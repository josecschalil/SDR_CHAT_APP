function audio = afsk_modulate(bitstream, fs)

bitstream = bitstream(:).';

Rb = 1200;
Ns = round(fs / Rb);

f_mark = 1200;
f_space = 2200;

audio = zeros(1, length(bitstream) * Ns);

phase = 0;

for i = 1:length(bitstream)
    
    if bitstream(i) == 1
        f = f_mark;
    else
        f = f_space;
    end
    
    t = (0:Ns-1)/fs;
    
    samples = sin(2*pi*f*t + phase);
    
    % Update phase (continuous)
    phase = mod(phase + 2*pi*f*(Ns/fs), 2*pi);
    
    audio((i-1)*Ns + (1:Ns)) = samples;
end

audio = audio / (max(abs(audio)) + 1e-6);

% Column vector
audio = audio(:);

end
