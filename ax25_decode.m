function [src, dest, message] = ax25_decode(nrzi_bits)

%% 1 — NRZI decode
bitstream = nrzi_decode(nrzi_bits(:).');

%% 2 — Find flags using proper numeric search
flag      = [0 1 1 1 1 1 1 0];
flag_pos  = find_flags(bitstream, flag);

if length(flag_pos) < 2
    error('Not enough flags found (found %d)', length(flag_pos));
end

%% 3 — Try every consecutive flag pair as a frame candidate
for i = 1:length(flag_pos)-1
    frame_start = flag_pos(i)   + 8;   % skip opening flag
    frame_end   = flag_pos(i+1) - 1;   % up to but not including closing flag

    if frame_end <= frame_start
        continue;
    end

    payload_bits = bitstream(frame_start:frame_end);

    try
        [src, dest, message] = decode_payload(payload_bits);
        return;   % success — return immediately
    catch
        % try next candidate
    end
end

error('FCS check FAILED for all frame candidates');
end

%% ── PAYLOAD DECODER ─────────────────────────────────────────────────────────

function [src, dest, message] = decode_payload(payload_bits)

%% Remove bit stuffing
unstuffed = [];
ones_count = 0;
i = 1;
while i <= length(payload_bits)
    b = payload_bits(i);
    unstuffed(end+1) = b;
    if b == 1
        ones_count = ones_count + 1;
        if ones_count == 5
            i = i + 1;   % skip the stuffed 0
            ones_count = 0;
        end
    else
        ones_count = 0;
    end
    i = i + 1;
end

%% Bits → bytes (LSB first per AX.25)
num_bytes = floor(length(unstuffed) / 8);
if num_bytes < 18   % 7+7+1+1+0data+2fcs minimum
    error('Frame too short: %d bytes', num_bytes);
end

bytes = zeros(1, num_bytes, 'uint8');
for k = 1:num_bytes
    bytes(k) = uint8(bi2de(unstuffed((k-1)*8 + (1:8)), 'right-msb'));
end

%% FCS check
% AX.25: FCS is last 2 bytes, low byte first
data     = bytes(1:end-2);
recv_fcs = uint16(bytes(end-1)) + bitshift(uint16(bytes(end)), 8);
calc_fcs = crc_ccitt(data);

if recv_fcs ~= calc_fcs
    error('FCS mismatch: received 0x%04X, calculated 0x%04X', recv_fcs, calc_fcs);
end

%% Decode addresses (7 bytes each, chars are left-shifted by 1)
if length(data) < 16
    error('Data too short for address fields');
end
dest = decode_callsign(data(1:7));
src  = decode_callsign(data(8:14));

%% Extract INFO field (skip 14 addr + 1 CTRL + 1 PID = bytes 15,16)
message = char(data(17:end));
end

%% ── HELPERS ─────────────────────────────────────────────────────────────────

function idx = find_flags(bits, flag)
% Proper numeric flag search — strfind does NOT work on double arrays
    n   = length(flag);
    idx = [];
    for k = 1:(length(bits) - n + 1)
        if all(bits(k:k+n-1) == flag)
            idx(end+1) = k;
        end
    end
end

function callsign = decode_callsign(addr_bytes)
% Each character byte is left-shifted by 1 in AX.25 — shift right to recover
    chars    = char(bitshift(uint8(addr_bytes(1:6)), -1));
    callsign = strtrim(chars);
end

function fcs = crc_ccitt(data)
    poly = uint16(hex2dec('1021'));
    fcs  = uint16(hex2dec('FFFF'));
    for i = 1:length(data)
        fcs = bitxor(fcs, bitshift(uint16(data(i)), 8));
        for j = 1:8
            if bitand(fcs, uint16(hex2dec('8000')))
                fcs = bitxor(bitshift(fcs, 1), poly);
            else
                fcs = bitshift(fcs, 1);
            end
            fcs = bitand(fcs, uint16(hex2dec('FFFF')));
        end
    end
    fcs = bitxor(fcs, uint16(hex2dec('FFFF')));
end