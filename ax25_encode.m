function frame = ax25_encode(src, dest, message)
% AX.25 Encoder
% Inputs:
%   src     - source callsign (e.g., 'N0CALL')
%   dest    - destination callsign (e.g., 'APRS')
%   message - text message (string)
%
% Output:
%   frame   - final bit stream (binary array)

%% 1. Encode addresses (shift ASCII left by 1)
addr = [];

addr = [addr encode_callsign(dest, 0)]; % destination (not last)
addr = [addr encode_callsign(src, 1)];  % source (last address → set end bit)

%% 2. Append CTRL and PID
CTRL = hex2dec('03');
PID  = hex2dec('F0');

message = char(message);   % FIX
payload = [addr CTRL PID uint8(message)];

%% 3. Compute CRC-CCITT (FCS)
fcs = crc_ccitt(payload);

% Append FCS (LSB first as per AX.25)
payload = [payload bitand(fcs,255) bitshift(fcs,-8)];

%% 4. Convert to bit stream (LSB first per byte)
bits = [];
for i = 1:length(payload)
    b = de2bi(payload(i), 8, 'right-msb'); % LSB first
    bits = [bits b];
end

%% 5. Bit stuffing (insert 0 after five consecutive 1s)
stuffed = [];
count = 0;

for i = 1:length(bits)
    stuffed = [stuffed bits(i)];
    
    if bits(i) == 1
        count = count + 1;
        if count == 5
            stuffed = [stuffed 0];
            count = 0;
        end
    else
        count = 0;
    end
end

%% 6. Add flags (0x7E = 01111110, LSB first → 0 1 1 1 1 1 1 0)

flag = [0 1 1 1 1 1 1 0];

frame_bits = [flag stuffed flag];

%% 7. NRZI Encoding (NEW STEP)
frame = nrzi_encode(frame_bits);

end


%% -------- Helper Functions --------

function addr = encode_callsign(call, isLast)

% ✅ FIX: convert string → char
call = char(call);

% Normalize
call = upper(call);

% Trim if longer than 6
if length(call) > 6
    call = call(1:6);
end

% Pad if shorter
call = [call repmat(' ', 1, 6-length(call))];

addr = zeros(1,7,'uint8');

% Encode characters
for i = 1:6
    addr(i) = bitshift(uint8(call(i)),1);
end

% SSID byte
ssid = uint8(0);
ssid = bitshift(ssid,1);

if isLast
    ssid = bitor(ssid,1);
end

addr(7) = ssid;

end


function fcs = crc_ccitt(data)
% CRC-CCITT (0x1021) initial value = 0xFFFF

poly = hex2dec('1021');
fcs = hex2dec('FFFF');

for i = 1:length(data)
    fcs = bitxor(fcs, bitshift(uint16(data(i)),8));
    
    for j = 1:8
        if bitand(fcs, hex2dec('8000'))
            fcs = bitxor(bitshift(fcs,1), poly);
        else
            fcs = bitshift(fcs,1);
        end
        fcs = bitand(fcs, hex2dec('FFFF')); % keep 16-bit
    end
end

% Final XOR
fcs = bitcmp(fcs, 'uint16');

end