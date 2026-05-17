clc; clear;

fprintf('===== SOFTWARE TDD ACK TEST =====\n');

fs     = 48000;
fs_sdr = 960000;
dev    = 5000;
snr_db = Inf;   % Use Inf for deterministic protocol confirmation.
runs   = 20;

tx_call  = 'N0CALL';
rx_call  = 'N0ACK';
dest     = 'APRS';
user_msg = 'HELLO SDR';

pass_count = 0;

for k = 1:runs
    packet_id = upper(dec2hex(randi([0 65535]), 4));
    tx_msg = sprintf('ID=%s;%s', packet_id, user_msg);

    tx_iq = buildPacketIQ(tx_call, dest, tx_msg, fs, fs_sdr, dev);
    tx_iq = applyChannel(tx_iq, snr_db, fs_sdr);

    rx_audio = recoverAudio(tx_iq, fs, fs_sdr, dev);
    rx_bits = afsk_demodulate(rx_audio, fs);

    try
        [src, ~, decoded_msg] = ax25_decode(rx_bits);
        rx_packet_id = extractPacketId(decoded_msg);

        if ~strcmp(src, tx_call) || ~strcmp(rx_packet_id, packet_id)
            error('RX decoded wrong source or packet ID');
        end

        ack_msg = sprintf('ACK=%s', rx_packet_id);
        ack_iq = buildPacketIQ(rx_call, tx_call, ack_msg, fs, fs_sdr, dev);
        ack_iq = applyChannel(ack_iq, snr_db, fs_sdr);

        ack_audio = recoverAudio(ack_iq, fs, fs_sdr, dev);
        ack_bits = afsk_demodulate(ack_audio, fs);
        [ack_src, ack_dest, decoded_ack] = ax25_decode(ack_bits);

        ack_ok = strcmp(ack_src, rx_call) && ...
                 strcmp(ack_dest, tx_call) && ...
                 contains(decoded_ack, ['ACK=' packet_id]);

        if ack_ok
            pass_count = pass_count + 1;
            fprintf('Run %02d: PASS  ID=%s\n', k, packet_id);
        else
            fprintf('Run %02d: FAIL  ACK mismatch for ID=%s\n', k, packet_id);
        end
    catch e
        fprintf('Run %02d: FAIL  ID=%s  %s\n', k, packet_id, e.message);
    end
end

fprintf('\n===== RESULT =====\n');
fprintf('Passed: %d / %d\n', pass_count, runs);

if pass_count == runs
    disp('SOFTWARE TDD ACK PATH PASSED');
else
    error('Software TDD ACK path failed');
end

function iq = buildPacketIQ(src, dest, msg, fs, fs_sdr, dev)
frame = ax25_encode(src, dest, msg);
audio = afsk_modulate(frame, fs);
audio_up = resample(audio, fs_sdr, fs);
audio_up = audio_up / (max(abs(audio_up)) + 1e-6);
phase = 2*pi*dev * cumsum(audio_up) / fs_sdr;
iq = exp(1j * phase);
end

function iq_out = applyChannel(iq_in, snr_db, fs_sdr)
iq_out = iq_in(:);
guard = round(0.08 * fs_sdr);
shift = randi([0 round(0.01 * fs_sdr)]);
iq_out = [zeros(guard + shift, 1); iq_out; zeros(guard, 1)];

signal_power = mean(abs(iq_in(:)).^2);
if isfinite(snr_db)
    noise_power = signal_power / (10^(snr_db/10));
    noise = sqrt(noise_power/2) * (randn(size(iq_out)) + 1j*randn(size(iq_out)));
    iq_out = iq_out + noise;
end
end

function audio = recoverAudio(iq, fs, fs_sdr, dev)
decim = fs_sdr / fs;
if mod(decim, 1) ~= 0
    error('fs_sdr must be an integer multiple of fs');
end

iq = double(iq(:));
d = [1 + 0j; iq(1:end-1)];
fm = angle(iq .* conj(d));
fm = fm * (fs_sdr / (2*pi*dev));

lpf = designfilt('lowpassfir', ...
    'PassbandFrequency',   3000, ...
    'StopbandFrequency',   8000, ...
    'PassbandRipple',      0.5,  ...
    'StopbandAttenuation', 40,   ...
    'SampleRate',          fs_sdr);

fm_f = filter(lpf, fm);
audio = fm_f(1:decim:end);
audio = audio - mean(audio);
audio = audio / (max(abs(audio)) + 1e-6);
end

function packet_id = extractPacketId(msg)
packet_id = '';
tok = regexp(char(msg), '^ID=([0-9A-Fa-f]+);', 'tokens', 'once');
if ~isempty(tok)
    packet_id = upper(tok{1});
end
end
