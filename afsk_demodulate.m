function bitstream = afsk_demodulate(audio, fs)
%AFSK_DEMODULATE Demodulate 1200 baud Bell-202 AFSK into NRZI bits.
%
% The demodulator intentionally returns the best NRZI bit candidate rather
% than decoded AX.25 fields. AX.25/FCS validation stays in ax25_decode.

audio = audio(:).';
audio = audio - mean(audio);
audio = audio / (max(abs(audio)) + 1e-6);

Rb = 1200;
Ns = round(fs / Rb);

f_mark  = 1200;
f_space = 2200;

t = (0:length(audio)-1) / fs;
mark_osc  = exp(-1j * 2 * pi * f_mark * t);
space_osc = exp(-1j * 2 * pi * f_space * t);

mark_pwr  = abs(filter(ones(1, Ns)/Ns, 1, audio .* mark_osc));
space_pwr = abs(filter(ones(1, Ns)/Ns, 1, audio .* space_osc));

raw_bits = mark_pwr > space_pwr;

best_bits  = [];
best_score = -inf;

% Real SDR links can invert IQ/audio polarity. That swaps mark and space,
% so try both polarities before giving up.
for invert = [false true]
    if invert
        candidate_raw = ~raw_bits;
    else
        candidate_raw = raw_bits;
    end

    for offset = 1:Ns
        bits = candidate_raw(offset : Ns : end);

        try
            ax25_decode(bits);
            bitstream = bits;
            return;
        catch
            score = flag_correlation_score(bits);
        end

        if score > best_score
            best_score = score;
            best_bits = bits;
        end
    end
end

if isempty(best_bits)
    best_bits = raw_bits(1 : Ns : end);
end

bitstream = best_bits;
end

function score = flag_correlation_score(nrzi_bits)
bits = nrzi_decode(nrzi_bits(:).');
flag = [0 1 1 1 1 1 1 0];
score = 0;

for k = 1:(length(bits) - length(flag) + 1)
    score = score + sum(bits(k:k+length(flag)-1) == flag);
end
end
