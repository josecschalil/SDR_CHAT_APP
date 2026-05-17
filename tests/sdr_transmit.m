function sdr_transmit(audio, fs, carrier_freq)

% SDR TRANSMIT USING ADALM-PLUTO
% audio         : baseband AFSK signal
% fs            : audio sample rate (e.g., 48000)
% carrier_freq  : RF frequency (e.g., 433e6)

%% PARAMETERS

fs_sdr = 480000;        % Pluto SDR sample rate (must be higher than fs)
freq_dev = 3000;        % FM deviation (Hz)

%% NORMALIZE AUDIO
audio = audio(:);
audio = audio / max(abs(audio) + 1e-6);

%% UPSAMPLE AUDIO TO SDR RATE

interp_factor = fs_sdr / fs;

if mod(interp_factor,1) ~= 0
error('fs_sdr must be integer multiple of fs');
end

audio_up = interp(audio, interp_factor);

%% FM MODULATION

% Integrate signal for FM
phase = 2*pi*freq_dev * cumsum(audio_up) / fs_sdr;

% Generate complex FM signal
tx_signal = exp(1j * phase);

%% CREATE SDR TRANSMITTER

tx = sdrtx('Pluto');

tx.CenterFrequency = carrier_freq;   % e.g., 433e6
tx.BasebandSampleRate = fs_sdr;
tx.Gain = 0;                         % 0 dBm

%% TRANSMIT

disp('Transmitting...');
transmitRepeat(tx, tx_signal);

pause(5);   % transmit for 5 seconds

%% CLEANUP
release(tx);
disp('Transmission stopped');

end
