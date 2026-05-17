function bits = nrzi_decode(nrzi_bits)

nrzi_bits = nrzi_bits(:).';

bits = zeros(size(nrzi_bits));

prev = 1;  % initial state MUST match encoder

for i = 1:length(nrzi_bits)
    
    if nrzi_bits(i) == prev
        bits(i) = 1;   % no transition
    else
        bits(i) = 0;   % transition
    end
    
    prev = nrzi_bits(i);
end

end