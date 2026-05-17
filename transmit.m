clc; clear;

fs     = 48000;
fs_sdr = 960000;
decim  = fs_sdr / fs;
dev    = 5000;
msg    = 'HELLO hII SDR';
packet_id = upper(dec2hex(randi([0 65535]), 4));
tx_msg = sprintf('ID=%s;%s', packet_id, msg);

MY_CALL  = 'N0CALL';
DEST     = 'APRS';
ACK_CALL = 'N0ACK';

PKT_SEC        = 1.4;
CHUNK_SEC      = 0.2;
ACK_LISTEN_SEC = 2.8;
TIMEOUT_SEC    = 60;
TX_GAIN_DB     = -3;
RX_GAIN_DB     = 50;

SAMPLES_PER_FRAME = round(CHUNK_SEC * fs_sdr);
if mod(SAMPLES_PER_FRAME, decim) ~= 0
    error('SamplesPerFrame must be divisible by decim (%d).', decim);
end

%% Build TX frame (message burst)
frame    = ax25_encode(MY_CALL, DEST, tx_msg);
audio    = afsk_modulate(frame, fs);
audio_up = resample(audio, fs_sdr, fs);
audio_up = audio_up / (max(abs(audio_up)) + 1e-6);
phase     = 2*pi*dev * cumsum(audio_up) / fs_sdr;
tx_signal = exp(1j * phase);

%% Build a repeated burst. Repeating the same AX.25 frame gives the receiver
%% more chances to decode one clean copy during fades or symbol slips.
total_samples = round(PKT_SEC * fs_sdr);
gap = zeros(round(0.06 * fs_sdr), 1);
preamble = exp(1j * zeros(round(0.08 * fs_sdr), 1));
one_packet = [preamble; tx_signal(:); gap];
total_samples = max(total_samples, length(one_packet) + round(0.1 * fs_sdr));
repeat_count = max(1, floor(total_samples / length(one_packet)));
tx_padded = repmat(one_packet, repeat_count, 1);
tx_final = [tx_padded; zeros(max(0, total_samples - length(tx_padded)), 1)];
tx_final = tx_final(1:total_samples);
PKT_SEC = total_samples / fs_sdr;

%% RX DSP setup (for ACK)
lpf = designfilt('lowpassfir', ...
    'PassbandFrequency',   3000, ...
    'StopbandFrequency',   8000, ...
    'PassbandRipple',      0.5,  ...
    'StopbandAttenuation', 40,   ...
    'SampleRate',          fs_sdr);
b_lpf = lpf.Coefficients;

fprintf('==============================\n');
fprintf('TX: Sending "%s"\n', msg);
fprintf('Packet ID: %s\n', packet_id);
fprintf('TDD: %.1fs burst, %.1fs ACK listen\n', PKT_SEC, ACK_LISTEN_SEC);
fprintf('Chunks: %.1fs (%d samples)  Timeout: %.0fs\n', CHUNK_SEC, SAMPLES_PER_FRAME, TIMEOUT_SEC);
fprintf('==============================\n');

ack_received = false;
t_start      = tic;

while toc(t_start) < TIMEOUT_SEC && ~ack_received

    %% TX burst (true half-duplex: no RX while TX)
    tx = sdrtx('Pluto');
    tx.CenterFrequency    = 433e6;
    tx.BasebandSampleRate = fs_sdr;
    tx.Gain               = TX_GAIN_DB;

    transmitRepeat(tx, tx_final);
    pause(PKT_SEC + 0.05);
    release(tx);

    %% Listen for ACK
    time_left = TIMEOUT_SEC - toc(t_start);
    listen_sec = min(ACK_LISTEN_SEC, max(0, time_left));
    if listen_sec < CHUNK_SEC
        break;
    end

    rx = sdrrx('Pluto');
    rx.CenterFrequency    = 433e6;
    rx.BasebandSampleRate = fs_sdr;
    rx.SamplesPerFrame    = SAMPLES_PER_FRAME;
    rx.GainSource         = 'Manual';
    rx.Gain               = RX_GAIN_DB;

    [ack_received, ack_src, ack_msg] = listenForAckRolling(rx, b_lpf, fs, fs_sdr, dev, decim, ...
        MY_CALL, ACK_CALL, packet_id, listen_sec, CHUNK_SEC);
    release(rx);

    if ack_received
        fprintf('\n==============================\n');
        fprintf('  ACK RECEIVED FROM %s\n', ack_src);
        fprintf('  MSG : %s\n', ack_msg);
        fprintf('  TIME: %.1f sec\n', toc(t_start));
        fprintf('==============================\n');
        break;
    end

    fprintf('No ACK yet — elapsed: %.0fs\n', toc(t_start));
    pause(0.2 + 0.2*rand);
end

if ack_received
    fprintf('\nTX complete — message acknowledged.\n');
else
    fprintf('\nTX timed out after %.0f seconds — no ACK received.\n', TIMEOUT_SEC);
end

%% Local: rolling-audio ACK listener (post-FM)
function [ack_received, ack_src, ack_msg] = listenForAckRolling(rx, b_lpf, fs, fs_sdr, dev, decim, my_call, ack_call, packet_id, listen_sec, chunk_sec)

ack_received = false;
ack_src = '';
ack_msg = '';

% Ring buffer + decode schedule
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

% Streaming states
prevSample = 1 + 0j;
zi = zeros(length(b_lpf)-1, 1);

% Noise-relative power gate
START_RATIO = 2.0;   % ~ +3 dB
STOP_RATIO  = 1.3;   % ~ +1 dB
ALPHA       = 0.05;  % EMA smoothing while idle
HANG_SEC    = 0.8;
hang_chunks = ceil(HANG_SEC / chunk_sec);

noise_power = 0;
inSignal = false;
hang = 0;

t0 = tic;
while toc(t0) < listen_sec

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
        hang = hang_chunks;
    elseif ~inSignal && hang > 0
        hang = hang - 1;
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
        if strcmp(src, ack_call) && strcmp(dest, my_call) && contains(msg, ['ACK=' packet_id])
            ack_received = true;
            ack_src = src;
            ack_msg = msg;
            return;
        end
    catch
    end
end

end
