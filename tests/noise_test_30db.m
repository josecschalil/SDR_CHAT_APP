clc;
clear;

%% PARAMETERS
fs = 48000;
snr_db = 30;

% Test message (char array)
msg = 'THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG12';

fprintf('===== NOISE TEST (30 dB SNR) =====\n');

%% TX
frame = ax25_encode('N0CALL','APRS', msg);
audio = afsk_modulate(frame, fs);

%% ADD NOISE

use_awgn = true;   % set false if toolbox not available

if use_awgn
% Requires Communications Toolbox
audio_noisy = awgn(audio, snr_db, 'measured');
else
% Manual noise (no toolbox)
noise_amp = rms(audio) / (10^(snr_db/20));
audio_noisy = audio + noise_amp * randn(size(audio));
end

%% RX
bits = afsk_demodulate(audio_noisy, fs);

try
[src, dest, out] = ax25_decode(bits);

%% VALIDATION

fprintf('\nRecovered Message:\n%s\n', out);

% 1. Exact match
if strcmp(msg, out)
    disp('Message Match: PASS');
else
    disp('Message Match: FAIL');
end

% 2. Length check
if length(msg) == length(out)
    fprintf('Length Check: PASS (%d chars)\n', length(out));
else
    disp('Length Check: FAIL');
end


catch
disp('Decoding FAILED');
end

fprintf('\n===== EXPECTATION =====\n');
disp('At 30 dB SNR → SHOULD PASS with 0 errors');
