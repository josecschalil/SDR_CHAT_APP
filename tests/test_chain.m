% paste_test.m — no SDR hardware needed
% Simulates the exact TX→RX chain in software to confirm it works
clc; clear;

fs     = 48000;
fs_sdr = 960000;
decim  = fs_sdr / fs;
dev    = 5000;

% Build signal exactly as TX does
frame    = ax25_encode('N0CALL', 'APRS', 'HELLO FROM SDR');
audio_tx = afsk_modulate(frame, fs);
audio_up = resample(audio_tx, fs_sdr, fs);
audio_up = audio_up / max(abs(audio_up));

% FM modulate
phase     = 2*pi*dev * cumsum(audio_up) / fs_sdr;
tx_signal = exp(1j * phase);

% FM demodulate — exactly as RX does
fm    = angle(tx_signal(2:end) .* conj(tx_signal(1:end-1)));
fm    = [fm; fm(end)];
fm    = fm * (fs_sdr / (2*pi*dev));

% LPF
lpf   = designfilt('lowpassfir', ...
    'PassbandFrequency',   3000, ...
    'StopbandFrequency',   8000, ...
    'PassbandRipple',      0.5,  ...
    'StopbandAttenuation', 40,   ...
    'SampleRate',          fs_sdr);
fm_f  = filter(lpf, fm);

% Decimate
audio_rx = fm_f(1:decim:end);
audio_rx = audio_rx - mean(audio_rx);
audio_rx = audio_rx / max(abs(audio_rx));

% Compare spectra
figure(1); clf;
subplot(2,1,1);
[p1,f1] = pwelch(audio_tx, 1024, 512, 4096, fs);
plot(f1, 10*log10(p1)); xlim([0 4000]); grid on;
xline(1200,'r--'); xline(2200,'r--');
title('TX audio spectrum (should have peaks at 1200 and 2200 Hz)');

subplot(2,1,2);
[p2,f2] = pwelch(audio_rx, 1024, 512, 4096, fs);
plot(f2, 10*log10(p2)); xlim([0 4000]); grid on;
xline(1200,'r--'); xline(2200,'r--');
title('RX recovered audio spectrum (should match TX exactly)');

% Decode
bits_rx = afsk_demodulate(audio_rx, fs);
len     = min(length(bits_rx), length(frame));
errors  = sum(bits_rx(1:len) ~= frame(1:len));
fprintf('Software loopback BER: %.4f (%d errors in %d bits)\n', errors/len, errors, len);

try
    [src, dest, msg] = ax25_decode(bits_rx);
    fprintf('DECODED: %s → %s : %s\n', src, dest, msg);
catch e
    fprintf('Decode failed: %s\n', e.message);
end