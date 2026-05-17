clc; clear;

fs     = 48000;
fs_sdr = 960000;
decim  = fs_sdr / fs;
dev    = 5000;

MY_CALL = 'N0ACK';

PKT_SEC   = 0.8;
CHUNK_SEC = 0.2;
ACK_PKT_SEC = 1.0;
RX_GAIN_DB  = 50;
TX_GAIN_DB  = -3;

SAMPLES_PER_FRAME = round(CHUNK_SEC * fs_sdr);
if mod(SAMPLES_PER_FRAME, decim) ~= 0
    error('SamplesPerFrame must be divisible by decim (%d).', decim);
end

%% LPF (use coefficients + explicit state for streaming)
lpf = designfilt('lowpassfir', ...
    'PassbandFrequency',   3000, ...
    'StopbandFrequency',   8000, ...
    'PassbandRipple',      0.5,  ...
    'StopbandAttenuation', 40,   ...
    'SampleRate',          fs_sdr);
b_lpf = lpf.Coefficients;

%% Power gate (noise-relative with hysteresis)
START_RATIO = 2.0;   % ~ +3 dB
STOP_RATIO  = 1.3;   % ~ +1 dB
ALPHA       = 0.05;  % EMA smoothing while idle
HANG_SEC    = 0.8;
HANG_CHUNKS = ceil(HANG_SEC / CHUNK_SEC);

noise_power = 0;
inSignal = false;
hang = 0;

%% Rolling audio ring buffer + decode schedule
AUDIO_BUF_SEC   = 1.3;
DECODE_WIN_SEC  = 1.1;
DECODE_STEP_SEC = 0.4;

Nbuf  = round(AUDIO_BUF_SEC  * fs);
Nwin  = round(DECODE_WIN_SEC * fs);
Nstep = round(DECODE_STEP_SEC* fs);

audioBuf = zeros(Nbuf, 1);
w = 1;
filled = 0;
stepCount = 0;

%% Streaming demod/filter states
prevSample = 1 + 0j;
zi = zeros(length(b_lpf)-1, 1);

%% RX setup
gain_current = RX_GAIN_DB;
rx = mkRx(fs_sdr, SAMPLES_PER_FRAME, gain_current);

fprintf('==============================\n');
fprintf('RECEIVER ACTIVE — %s\n', MY_CALL);
fprintf('TDD ACK: %.1fs packets  Chunks: %.1fs\n', PKT_SEC, CHUNK_SEC);
fprintf('Will ACK every decoded message\n');
fprintf('==============================\n');

last_print = tic;

while true

    data = double(rx());
    data = data(:);
    power = mean(abs(data).^2);

    if noise_power == 0
        noise_power = max(power, 1e-12);
    end

    if ~inSignal && hang == 0
        noise_power = (1-ALPHA)*noise_power + ALPHA*power;
        noise_power = max(noise_power, 1e-12);
    end

    if ~inSignal && power > noise_power * START_RATIO
        inSignal = true;
        hang = 0;
    elseif inSignal && power < noise_power * STOP_RATIO
        inSignal = false;
        hang = HANG_CHUNKS;
    elseif ~inSignal && hang > 0
        hang = hang - 1;
    end

    active = inSignal || hang > 0;

    if toc(last_print) > 1.0
        if active
            fprintf('Power: %.3g  noise: %.3g  (active)  Gain: %d dB\n', power, noise_power, gain_current);
        else
            fprintf('Power: %.3g  noise: %.3g  (idle)\n', power, noise_power);
        end
        last_print = tic;
    end

    % FM demod (streaming)
    d = [prevSample; data(1:end-1)];
    fm = angle(data .* conj(d));
    prevSample = data(end);
    fm = fm * (fs_sdr / (2*pi*dev));

    % LPF with state
    [fm_f, zi] = filter(b_lpf, 1, fm, zi);

    % Decimate to audio
    audioChunk = fm_f(1:decim:end);

    % Push into ring
    n = numel(audioChunk);
    idx = w + (0:n-1);
    idx = mod(idx-1, Nbuf) + 1;
    audioBuf(idx) = audioChunk;
    w = mod(w-1+n, Nbuf) + 1;
    filled = min(Nbuf, filled + n);

    % Decode scheduler
    stepCount = stepCount + n;
    if stepCount < Nstep || filled < Nwin
        continue;
    end
    stepCount = 0;

    start = w - Nwin;
    ridx = start + (0:Nwin-1);
    ridx = mod(ridx-1, Nbuf) + 1;
    winAudio = audioBuf(ridx);

    winAudio = winAudio - mean(winAudio);
    winAudio = winAudio / (max(abs(winAudio)) + 1e-6);

    bits = afsk_demodulate(winAudio, fs);
    if isempty(bits)
        continue;
    end

    try
        [src, dest, msg] = ax25_decode(bits);

        fprintf('\n==============================\n');
        fprintf('  MESSAGE RECEIVED\n');
        fprintf('  FROM : %s\n', src);
        fprintf('  TO   : %s\n', dest);
        fprintf('  MSG  : %s\n', msg);
        fprintf('==============================\n\n');

        packet_id = extractPacketId(msg);
        if isempty(packet_id)
            fprintf('Message has no packet ID; ACK skipped to avoid false acknowledgement.\n');
            continue;
        end

        fprintf('Sending ACK %s to %s...\n', packet_id, src);

        % Stop RX for half-duplex, transmit ACK burst, then restart RX
        release(rx);
        pause(0.05);

        ack_iq_padded = buildAckIQ(MY_CALL, src, packet_id, fs, fs_sdr, dev, ACK_PKT_SEC);

        tx = sdrtx('Pluto');
        tx.CenterFrequency    = 433e6;
        tx.BasebandSampleRate = fs_sdr;
        tx.Gain               = TX_GAIN_DB;
        transmitRepeat(tx, ack_iq_padded);
        pause(ACK_PKT_SEC + 0.1);
        release(tx);
        pause(0.05);

        % Restart RX + reset streaming state/buffers
        rx = mkRx(fs_sdr, SAMPLES_PER_FRAME, gain_current);
        prevSample = 1 + 0j;
        zi = zeros(length(b_lpf)-1, 1);
        audioBuf(:) = 0;
        w = 1; filled = 0; stepCount = 0;
        inSignal = false; hang = 0;
        noise_power = 0;

        fprintf('ACK sent — resuming receive\n\n');
    catch e
        fprintf('decode failed: %s\n', e.message);
    end
end

%% Local helpers
function rx = mkRx(fs_sdr, samplesPerFrame, gain_db)
rx = sdrrx('Pluto');
rx.CenterFrequency    = 433e6;
rx.BasebandSampleRate = fs_sdr;
rx.SamplesPerFrame    = samplesPerFrame;
rx.GainSource         = 'Manual';
rx.Gain               = gain_db;
end

function tx_iq_padded = buildAckIQ(my_call, dest_call, packet_id, fs, fs_sdr, dev, pkt_sec)
ack_text  = sprintf('ACK=%s', packet_id);
ack_frame = ax25_encode(my_call, dest_call, ack_text);
ack_audio = afsk_modulate(ack_frame, fs);
ack_up    = resample(ack_audio, fs_sdr, fs);
ack_up    = ack_up / (max(abs(ack_up)) + 1e-6);
ack_phase = 2*pi*dev * cumsum(ack_up) / fs_sdr;
ack_iq    = exp(1j * ack_phase);

total_s = round(pkt_sec * fs_sdr);
gap = zeros(round(0.06 * fs_sdr), 1);
preamble = exp(1j * zeros(round(0.06 * fs_sdr), 1));
one_ack = [preamble; ack_iq(:); gap];
total_s = max(total_s, length(one_ack) + round(0.08 * fs_sdr));
repeat_count = max(1, floor(total_s / length(one_ack)));
ack_pad = repmat(one_ack, repeat_count, 1);
if length(ack_pad) > total_s
    tx_iq_padded = ack_pad(1:total_s);
else
    tx_iq_padded = [ack_pad; zeros(total_s-length(ack_pad),1)];
end
end

function packet_id = extractPacketId(msg)
packet_id = '';
tok = regexp(char(msg), '^ID=([0-9A-Fa-f]+);', 'tokens', 'once');
if ~isempty(tok)
    packet_id = upper(tok{1});
end
end
