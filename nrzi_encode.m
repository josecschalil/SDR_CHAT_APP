function nrzi_bits = nrzi_encode(bits)
% NRZI Encoding
% Input:
%   bits        - binary input array (0/1)
%
% Output:
%   nrzi_bits   - NRZI encoded output

% Ensure row vector
bits = bits(:).';

% Preallocate
nrzi_bits = zeros(size(bits));

% Initial state = 1
current = 1;

for i = 1:length(bits)
    if bits(i) == 0
        % Toggle on 0
        current = ~current;
    end
    
    % Output current state
    nrzi_bits(i) = current;
end

end