function audio = sdr_receive(duration, fs, carrier_freq)

% SDR RECEIVE USING ADALM-PLUTO
% duration      : capture time (seconds)
% fs            : desired audio sample rate (e.g., 48000)
% carrier_freq  : RF frequency (e.g., 433e6)

%% PARAMETERS

fs_sdr = 480000;      % SDR sample rate (must match TX)
freq_dev = 3000;      % FM deviation (Hz)

%% CREATE SDR RECEIVER

rx = sdrrx('Pluto');

rx.CenterFrequency = carrier_freq;
rx.BasebandSampleRate = fs_sdr;
rx.SamplesPerFrame = 4096;
rx.GainSource = 'Manual';
rx.Gain = 40;   % adjust based on signal strength

%% CAPTURE SIGNAL

disp('Receiving...');

num_frames = ceil(duration * fs_sdr / rx.SamplesPerFrame);

rx_signal = [];

for i = 1:num_frames
data = rx();
rx_signal = [rx_signal; data];
end

release(rx);
disp('Capture complete');

%% FM DEMODULATION

% Extract phase
rx_signal = double(rx_signal);

phase = unwrap(angle(rx_signal));

% Differentiate phase
fm_demod = diff(phase);

% Scale back to audio
fm_demod = fm_demod * fs_sdr / (2*pi*freq_dev);

%% LOW-PASS FILTER (REMOVE HIGH-FREQ NOISE)

audio_lp = filtfilt(ones(1,5)/5, 1, fm_demod);

%% DOWNSAMPLE TO AUDIO RATE

decim_factor = fs_sdr / fs;

if mod(decim_factor,1) ~= 0
error('fs_sdr must be integer multiple of fs');
end

audio = downsample(audio_lp, decim_factor);

%% NORMALIZE

audio = audio / max(abs(audio) + 1e-6);

end
