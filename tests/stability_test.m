clc;
clear;

% PARAMETERS
fs = 48000;
N  = 50;
snr = 15;

success = 0;

fprintf('===== AX25 FULL SYSTEM TEST =====\n');

for i = 1:N


% Random message
msg = char(randi([65 90],1,20));

% Encode
frame = ax25_encode('N0CALL','APRS', msg);

% Modulate
audio = afsk_modulate(frame, fs);

% Add noise
audio = awgn(audio, snr, 'measured');

% Add timing shift
shift = randi([0 20]);
audio = [zeros(shift,1); audio];

% Demodulate
bits = afsk_demodulate(audio, fs);

% Decode
try
    [~,~,out] = ax25_decode(bits);
    
    if strcmp(msg, out)
        success = success + 1;
        fprintf('Trial %d: PASS\n', i);
    else
        fprintf('Trial %d: DATA MISMATCH\n', i);
    end
    
catch
    fprintf('Trial %d: FAIL\n', i);
end


end

% Result
success_rate = (success/N)*100;

fprintf('\n===== RESULT =====\n');
fprintf('Success Rate = %.2f%%\n', success_rate);

if success_rate > 90
disp('SYSTEM IS SDR READY');
elseif success_rate > 75
disp('MODERATE PERFORMANCE');
else
disp('SYSTEM NEEDS IMPROVEMENT');
end
