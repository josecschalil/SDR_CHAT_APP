clc;
clear;

%% PARAMETERS
fs = 48000;
runs = 10;

% 50-character message (use char, NOT string)
msg = 'THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG12';

fprintf('===== LONG MESSAGE END-TO-END TEST =====\n');

all_pass = true;

for i = 1:runs

fprintf('\nRun %d:\n', i);

%% TX
frame = ax25_encode('N0CALL','APRS', msg);
audio = afsk_modulate(frame, fs);

%% RX
bits = afsk_demodulate(audio, fs);

try
    [src, dest, out] = ax25_decode(bits);
    
    %% VALIDATION
    
    % 1. Exact message match
    if strcmp(msg, out)
        fprintf('Message Match: PASS\n');
    else
        fprintf('Message Match: FAIL\n');
        all_pass = false;
    end
    
    % 2. Length check
    if length(msg) == length(out)
        fprintf('Length Check: PASS (%d chars)\n', length(out));
    else
        fprintf('Length Check: FAIL\n');
        all_pass = false;
    end
    
    % 3. Display output (optional)
    fprintf('Recovered: %s\n', out);
    
catch
    fprintf('Decoding FAILED\n');
    all_pass = false;
end

end

%% FINAL RESULT

fprintf('\n===== FINAL RESULT =====\n');

if all_pass
disp('ALL TESTS PASSED');
disp('0 BIT ERRORS ON CLEAN SIGNAL');
else
disp('ERRORS DETECTED');
disp('CHECK TIMING / FILTERING');
end
