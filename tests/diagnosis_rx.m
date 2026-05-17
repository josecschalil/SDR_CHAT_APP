clc; clear;

fs     = 48000;
fs_sdr = 960000;
decim  = fs_sdr / fs;
dev    = 5000;

lpf = designfilt('lowpassfir', ...
    'PassbandFrequency',   3000, ...
    'StopbandFrequency',   8000, ...
    'PassbandRipple',      0.5,  ...
    'StopbandAttenuation', 40,   ...
    'SampleRate',          fs_sdr);

rx = sdrrx('Pluto');
rx.CenterFrequency    = 433e6;
rx.BasebandSampleRate = fs_sdr;
rx.SamplesPerFrame    = fs_sdr;
rx.GainSource         = 'Manual';
rx.Gain               = 20;

% Expected TX frame for comparison
frame_tx = ax25_encode('N0CALL', 'APRS', 'HELLO FROM SDR');
fprintf('Expected frame: %d bits\n\n', length(frame_tx));

best_ber   = inf;
best_frame = [];

fprintf('Capturing — make sure TX is running...\n');

for attempt = 1:20
    data  = rx();
    data  = double(data);
    power = mean(abs(data).^2);
    fprintf('Attempt %2d | Power: %.4f', attempt, power);

    if power < 1.0
        fprintf(' — no signal\n');
        continue;
    end

    % FM demod
    fm    = angle(data(2:end) .* conj(data(1:end-1)));
    fm    = [fm; fm(end)];
    fm    = fm * (fs_sdr / (2*pi*dev));
    fm_f  = filter(lpf, fm);
    audio = fm_f(1:decim:end);
    audio = audio - mean(audio);
    audio = audio / (max(abs(audio)) + 1e-6);

    bits_rx = afsk_demodulate(audio, fs);
    len     = min(length(bits_rx), length(frame_tx));
    errors  = sum(bits_rx(1:len) ~= frame_tx(1:len));
    ber     = errors / len;

    fprintf(' | Bits: %4d | Errors: %3d | BER: %.4f\n', len, errors, ber);

    if ber < best_ber
        best_ber   = ber;
        best_frame = bits_rx;
    end

    if ber == 0
        fprintf('\nPERFECT DECODE on attempt %d!\n', attempt);
        break;
    end
end

fprintf('\n=== BEST RESULT ===\n');
fprintf('BER: %.4f  (%d errors in %d bits)\n', best_ber, ...
    sum(best_frame(1:min(end,length(frame_tx))) ~= frame_tx(1:min(end,length(frame_tx)))), ...
    min(length(best_frame), length(frame_tx)));

m = find(best_frame(1:min(end,length(frame_tx))) ~= frame_tx(1:min(end,length(frame_tx))), 1);
if ~isempty(m)
    fprintf('First error at bit : %d\n', m);
    len = min(length(best_frame), length(frame_tx));
    fprintf('TX: %s\n', num2str(frame_tx(max(1,m-4):min(len,m+4))));
    fprintf('RX: %s\n', num2str(best_frame(max(1,m-4):min(len,m+4))));
end

release(rx);