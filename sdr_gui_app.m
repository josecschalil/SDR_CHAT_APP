function sdr_gui_app
%SDR_GUI_APP GUI wrapper for the existing Pluto SDR TDD message/ACK flow.
%
% Run with:
%   sdr_gui_app

app = struct();

app.fs = 48000;
app.fs_sdr = 960000;
app.decim = app.fs_sdr / app.fs;
app.dev = 5000;
app.centerFrequency = 433e6;
app.pktSec = 1.4;
app.ackPktSec = 1.0;
app.chunkSec = 0.2;
app.ackListenSec = 2.8;
app.timeoutSec = 60;

app.rx = [];
app.rxTimer = [];
app.connected = false;
app.receiving = false;
app.stopTx = false;
app.rxState = [];

if mod(round(app.chunkSec * app.fs_sdr), app.decim) ~= 0
    error('SamplesPerFrame must be divisible by decim (%d).', app.decim);
end
app.samplesPerFrame = round(app.chunkSec * app.fs_sdr);
app.b_lpf = buildLowpass(app.fs_sdr);

buildUi();
refreshRadios();
setStatus('Disconnected', [0.55 0.12 0.12]);
logLine('GUI ready. Select a Pluto, connect, then choose Transmit or Receive.');

    function buildUi()
        app.fig = uifigure('Name', 'Pluto SDR TDD Messenger', ...
            'Position', [100 100 1120 720], ...
            'CloseRequestFcn', @onClose);

        root = uigridlayout(app.fig, [3 1]);
        root.RowHeight = {150, '1x', 170};
        root.ColumnWidth = {'1x'};
        root.Padding = [12 12 12 12];
        root.RowSpacing = 10;

        top = uigridlayout(root, [3 8]);
        top.RowHeight = {32, 32, 42};
        top.ColumnWidth = {110, 150, 95, 150, 95, 150, 95, '1x'};
        top.ColumnSpacing = 8;

        uilabel(top, 'Text', 'Pluto');
        app.radioDropDown = uidropdown(top, 'Items', {'usb:0'}, 'Value', 'usb:0');
        app.radioDropDown.Layout.Column = 2;
        app.refreshButton = uibutton(top, 'Text', 'Refresh', 'ButtonPushedFcn', @(~,~) refreshRadios());
        app.refreshButton.Layout.Column = 3;
        app.connectButton = uibutton(top, 'Text', 'Connect', 'ButtonPushedFcn', @(~,~) connectRadio());
        app.connectButton.Layout.Column = 4;
        app.disconnectButton = uibutton(top, 'Text', 'Disconnect', 'Enable', 'off', 'ButtonPushedFcn', @(~,~) disconnectRadio());
        app.disconnectButton.Layout.Column = 5;
        app.autoGainButton = uibutton(top, 'Text', 'Link Gain', 'Enable', 'off', 'ButtonPushedFcn', @(~,~) linkAutoGain());
        app.autoGainButton.Layout.Column = 6;
        app.statusLabel = uilabel(top, 'Text', 'Disconnected', 'FontWeight', 'bold');
        app.statusLabel.Layout.Column = [7 8];

        uilabel(top, 'Text', 'Local Call');
        uilabel(top, 'Text', 'Remote Call');
        uilabel(top, 'Text', 'TX Gain');
        uilabel(top, 'Text', 'RX Gain');
        app.modeGroup = uibuttongroup(top, 'Title', 'Mode');
        app.modeGroup.Layout.Row = [2 3];
        app.modeGroup.Layout.Column = 8;
        uiradiobutton(app.modeGroup, 'Text', 'Transmit', 'Position', [12 36 90 22], 'Value', true);
        uiradiobutton(app.modeGroup, 'Text', 'Receive', 'Position', [112 36 90 22]);

        app.localCallField = uieditfield(top, 'text', 'Value', 'N0CALL');
        app.localCallField.Layout.Row = 3;
        app.localCallField.Layout.Column = 1;
        app.remoteCallField = uieditfield(top, 'text', 'Value', 'N0ACK');
        app.remoteCallField.Layout.Row = 3;
        app.remoteCallField.Layout.Column = 2;
        app.txGainField = uieditfield(top, 'numeric', 'Value', -3, 'Limits', [-89.75 0]);
        app.txGainField.Layout.Row = 3;
        app.txGainField.Layout.Column = 3;
        app.rxGainField = uieditfield(top, 'numeric', 'Value', 50, 'Limits', [0 73]);
        app.rxGainField.Layout.Row = 3;
        app.rxGainField.Layout.Column = 4;

        middle = uigridlayout(root, [2 2]);
        middle.RowHeight = {72, '1x'};
        middle.ColumnWidth = {'1x', '1x'};
        middle.ColumnSpacing = 10;

        msgPanel = uipanel(middle, 'Title', 'Message');
        msgPanel.Layout.Row = 1;
        msgPanel.Layout.Column = [1 2];
        msgGrid = uigridlayout(msgPanel, [1 4]);
        msgGrid.ColumnWidth = {'1x', 100, 100, 100, 100};
        app.messageField = uieditfield(msgGrid, 'text', 'Value', 'HELLO hII SDR');
        app.startButton = uibutton(msgGrid, 'Text', 'Start', 'ButtonPushedFcn', @(~,~) startAction());
        app.stopButton = uibutton(msgGrid, 'Text', 'Stop', 'Enable', 'off', 'ButtonPushedFcn', @(~,~) stopAction());
        app.clearButton = uibutton(msgGrid, 'Text', 'Clear', 'ButtonPushedFcn', @(~,~) clearDisplays());
        app.calTxButton = uibutton(msgGrid, 'Text', 'Cal TX', 'Enable', 'off', 'ButtonPushedFcn', @(~,~) calibrationTransmit());

        sentPanel = uipanel(middle, 'Title', 'Sent Messages');
        sentPanel.Layout.Row = 2;
        sentPanel.Layout.Column = 1;
        sentGrid = uigridlayout(sentPanel, [1 1]);
        sentGrid.Padding = [8 8 8 8];
        app.sentArea = uitextarea(sentGrid, 'Editable', 'off');

        recvPanel = uipanel(middle, 'Title', 'Received Messages');
        recvPanel.Layout.Row = 2;
        recvPanel.Layout.Column = 2;
        recvGrid = uigridlayout(recvPanel, [1 1]);
        recvGrid.Padding = [8 8 8 8];
        app.recvArea = uitextarea(recvGrid, 'Editable', 'off');

        logPanel = uipanel(root, 'Title', 'Log');
        logGrid = uigridlayout(logPanel, [1 1]);
        logGrid.Padding = [8 8 8 8];
        app.logArea = uitextarea(logGrid, 'Editable', 'off');
    end

    function refreshRadios()
        items = discoverPlutos();
        app.radioDropDown.Items = items;
        app.radioDropDown.Value = items{1};
        logLine(sprintf('Radio list refreshed: %s', strjoin(items, ', ')));
    end

    function connectRadio()
        radioId = selectedRadioId();
        try
            rx = mkRx(radioId, app.fs_sdr, app.samplesPerFrame, app.rxGainField.Value, app.centerFrequency);
            release(rx);
            app.connected = true;
            app.connectButton.Enable = 'off';
            app.disconnectButton.Enable = 'on';
            app.autoGainButton.Enable = 'on';
            app.calTxButton.Enable = 'on';
            setStatus(['Connected: ' radioId], [0.08 0.38 0.16]);
            logLine(['Connected to ' radioId]);
        catch e
            app.connected = false;
            setStatus('Connection failed', [0.55 0.12 0.12]);
            logLine(['Connect failed: ' e.message]);
        end
    end

    function disconnectRadio()
        stopAction();
        app.connected = false;
        app.connectButton.Enable = 'on';
        app.disconnectButton.Enable = 'off';
        app.autoGainButton.Enable = 'off';
        app.calTxButton.Enable = 'off';
        setStatus('Disconnected', [0.55 0.12 0.12]);
        logLine('Disconnected.');
    end

    function linkAutoGain()
        if ~app.connected
            logLine('Connect to a Pluto before running link gain.');
            return;
        end
        if app.receiving
            logLine('Stop receive mode before running link gain.');
            return;
        end

        app.stopTx = false;
        setStatus('Link gain running', [0.1 0.28 0.58]);
        app.autoGainButton.Enable = 'off';
        app.startButton.Enable = 'off';
        app.calTxButton.Enable = 'off';
        app.stopButton.Enable = 'on';
        drawnow;

        radioId = selectedRadioId();
        remoteCall = normalizeCall(app.remoteCallField.Value);
        candidateGains = [30 35 40 45 50 55 60];
        bestGain = app.rxGainField.Value;
        bestDecodeScore = -inf;
        bestFallbackScore = inf;

        logLine(sprintf('Link gain: start Cal TX on remote station %s.', remoteCall));

        for g = candidateGains
            if app.stopTx
                break;
            end
            try
                rx = mkRx(radioId, app.fs_sdr, app.samplesPerFrame, g, app.centerFrequency);
                state = initRxState(app.fs, app.b_lpf, app.chunkSec);
                powers = [];
                peaks = [];
                decodedCount = 0;
                tGain = tic;

                while toc(tGain) < 2.0
                    data = double(rx());
                    powers(end+1) = mean(abs(data(:)).^2); %#ok<AGROW>
                    peaks(end+1) = max(abs(data(:))); %#ok<AGROW>
                    [state, decoded, src, ~, msg] = processRxChunk(state, data, ...
                        app.b_lpf, app.fs, app.fs_sdr, app.dev, app.decim);

                    if decoded && strcmp(src, remoteCall) && contains(msg, 'CAL=')
                        decodedCount = decodedCount + 1;
                    end
                    drawnow limitrate;
                end
                release(rx);

                p = median(powers);
                peak = median(peaks);

                saturated = peak > 0.85 || p > 5e-2;
                decodeScore = decodedCount - 5 * saturated;
                fallbackScore = abs(log10(max(p, 1e-12)) - log10(2e-3)) + 10 * saturated;

                logLine(sprintf('Link gain trial RX=%d dB, decodes=%d, power=%.3g, peak=%.3g.', g, decodedCount, p, peak));
                if decodeScore > bestDecodeScore || ...
                        (decodeScore == bestDecodeScore && fallbackScore < bestFallbackScore)
                    bestDecodeScore = decodeScore;
                    bestFallbackScore = fallbackScore;
                    bestGain = g;
                end
            catch e
                logLine(sprintf('Link gain trial RX=%d dB failed: %s', g, e.message));
            end
        end

        app.rxGainField.Value = bestGain;
        app.txGainField.Value = -3;
        app.autoGainButton.Enable = 'on';
        app.startButton.Enable = 'on';
        app.calTxButton.Enable = 'on';
        app.stopButton.Enable = 'off';
        setStatus('Link gain complete', [0.08 0.38 0.16]);
        if bestDecodeScore > 0
            logLine(sprintf('Link gain selected RX=%d dB using decoded calibration packets.', bestGain));
        else
            logLine(sprintf('Link gain selected RX=%d dB from signal level only; no calibration packet decoded.', bestGain));
        end
    end

    function calibrationTransmit()
        if ~app.connected
            logLine('Connect to a Pluto before calibration TX.');
            return;
        end
        if app.receiving
            logLine('Stop receive mode before calibration TX.');
            return;
        end

        app.stopTx = false;
        app.startButton.Enable = 'off';
        app.autoGainButton.Enable = 'off';
        app.calTxButton.Enable = 'off';
        app.stopButton.Enable = 'on';
        setStatus('Calibration TX', [0.1 0.28 0.58]);

        radioId = selectedRadioId();
        myCall = normalizeCall(app.localCallField.Value);
        remoteCall = normalizeCall(app.remoteCallField.Value);
        calMsg = sprintf('CAL=%s', myCall);
        calIq = buildMessageIQ(myCall, remoteCall, calMsg);
        tStart = tic;

        logLine(sprintf('Calibration TX started from %s to %s. Stop after remote Link Gain finishes.', myCall, remoteCall));
        while toc(tStart) < 45 && ~app.stopTx
            try
                tx = mkTx(radioId, app.fs_sdr, app.txGainField.Value, app.centerFrequency);
                transmitRepeat(tx, calIq);
                pause(app.pktSec + 0.05);
                release(tx);
                logLine(sprintf('Calibration burst sent at TX gain %.1f dB.', app.txGainField.Value));
            catch e
                logLine(['Calibration TX failed: ' e.message]);
                break;
            end
            drawnow limitrate;
            pause(0.15);
        end

        if app.stopTx
            logLine('Calibration TX stopped by user.');
            setStatus('Stopped', [0.45 0.32 0.05]);
        else
            logLine('Calibration TX finished after 45 seconds.');
            setStatus('Calibration TX finished', [0.08 0.38 0.16]);
        end

        app.startButton.Enable = 'on';
        app.autoGainButton.Enable = 'on';
        app.calTxButton.Enable = 'on';
        app.stopButton.Enable = 'off';
    end

    function startAction()
        if ~app.connected
            logLine('Connect to a Pluto before starting.');
            return;
        end

        if strcmp(app.modeGroup.SelectedObject.Text, 'Transmit')
            sendMessageWithAck();
        else
            startReceiveMode();
        end
    end

    function stopAction()
        app.stopTx = true;
        stopReceiveMode();
        app.startButton.Enable = 'on';
        app.stopButton.Enable = 'off';
    end

    function clearDisplays()
        app.sentArea.Value = {};
        app.recvArea.Value = {};
        app.logArea.Value = {};
    end

    function sendMessageWithAck()
        app.stopTx = false;
        app.startButton.Enable = 'off';
        app.stopButton.Enable = 'on';
        setStatus('Transmitting', [0.1 0.28 0.58]);

        radioId = selectedRadioId();
        myCall = normalizeCall(app.localCallField.Value);
        remoteCall = normalizeCall(app.remoteCallField.Value);
        msg = char(app.messageField.Value);
        packetId = upper(dec2hex(randi([0 65535]), 4));
        txMsg = sprintf('ID=%s;%s', packetId, msg);

        txFinal = buildMessageIQ(myCall, remoteCall, txMsg);
        appendArea(app.sentArea, sprintf('%s  TO=%s  ID=%s  %s', timestamp(), remoteCall, packetId, msg));
        logLine(sprintf('TX started. ID=%s, ACK expected from %s.', packetId, remoteCall));

        ackReceived = false;
        tStart = tic;
        txGainSchedule = buildTxGainSchedule(app.txGainField.Value);
        retryCount = 0;

        while toc(tStart) < app.timeoutSec && ~ackReceived && ~app.stopTx
            retryCount = retryCount + 1;
            txGain = txGainSchedule(min(retryCount, numel(txGainSchedule)));
            try
                tx = mkTx(radioId, app.fs_sdr, txGain, app.centerFrequency);
                logLine(sprintf('TX burst using gain %.1f dB.', txGain));
                transmitRepeat(tx, txFinal);
                pause(app.pktSec + 0.05);
                release(tx);
            catch e
                logLine(['Transmit failed: ' e.message]);
                break;
            end

            listenSec = min(app.ackListenSec, max(0, app.timeoutSec - toc(tStart)));
            if listenSec < app.chunkSec
                break;
            end

            try
                rx = mkRx(radioId, app.fs_sdr, app.samplesPerFrame, app.rxGainField.Value, app.centerFrequency);
                [ackReceived, ackSrc, ackMsg] = listenForAckRolling(rx, app.b_lpf, app.fs, app.fs_sdr, app.dev, app.decim, ...
                    myCall, remoteCall, packetId, listenSec, app.chunkSec);
                release(rx);
            catch e
                logLine(['ACK listen failed: ' e.message]);
                break;
            end

            if ackReceived
                appendArea(app.recvArea, sprintf('%s  ACK FROM=%s  %s', timestamp(), ackSrc, ackMsg));
                logLine(sprintf('ACK received for ID=%s after %.1f s.', packetId, toc(tStart)));
            else
                logLine(sprintf('No ACK yet for ID=%s. Elapsed %.1f s.', packetId, toc(tStart)));
                if retryCount < numel(txGainSchedule)
                    app.txGainField.Value = txGainSchedule(retryCount + 1);
                    logLine(sprintf('Auto TX gain step: next retry %.1f dB.', app.txGainField.Value));
                end
                pause(0.2 + 0.2*rand);
            end
            drawnow limitrate;
        end

        if ackReceived
            setStatus('Message acknowledged', [0.08 0.38 0.16]);
        elseif app.stopTx
            setStatus('Stopped', [0.45 0.32 0.05]);
            logLine('TX stopped by user.');
        else
            setStatus('ACK timeout', [0.55 0.12 0.12]);
            logLine(sprintf('TX timed out after %.0f seconds.', app.timeoutSec));
        end

        app.startButton.Enable = 'on';
        app.stopButton.Enable = 'off';
    end

    function startReceiveMode()
        if app.receiving
            return;
        end

        radioId = selectedRadioId();
        try
            app.rx = mkRx(radioId, app.fs_sdr, app.samplesPerFrame, app.rxGainField.Value, app.centerFrequency);
            app.rxState = initRxState(app.fs, app.b_lpf, app.chunkSec);
            app.receiving = true;
            app.startButton.Enable = 'off';
            app.stopButton.Enable = 'on';
            setStatus('Receiving', [0.08 0.38 0.16]);
            logLine('Receive mode started.');

            app.rxTimer = timer('ExecutionMode', 'fixedSpacing', ...
                'Period', app.chunkSec, ...
                'BusyMode', 'drop', ...
                'TimerFcn', @(~,~) receiveOneChunk());
            start(app.rxTimer);
        catch e
            app.receiving = false;
            setStatus('Receive start failed', [0.55 0.12 0.12]);
            logLine(['Receive start failed: ' e.message]);
        end
    end

    function stopReceiveMode()
        if ~isempty(app.rxTimer) && isvalid(app.rxTimer)
            stop(app.rxTimer);
            delete(app.rxTimer);
        end
        app.rxTimer = [];

        if ~isempty(app.rx)
            try
                release(app.rx);
            catch
            end
        end
        app.rx = [];

        if app.receiving
            logLine('Receive mode stopped.');
        end
        app.receiving = false;
    end

    function receiveOneChunk()
        if ~app.receiving || isempty(app.rx)
            return;
        end

        try
            data = double(app.rx());
            [app.rxState, decoded, src, dest, msg, power, noisePower, active] = processRxChunk(app.rxState, data, ...
                app.b_lpf, app.fs, app.fs_sdr, app.dev, app.decim);

            if toc(app.rxState.lastPrint) > 1.0
                if active
                    logLine(sprintf('Power %.3g, noise %.3g, active.', power, noisePower));
                else
                    logLine(sprintf('Power %.3g, noise %.3g, idle.', power, noisePower));
                end
                app.rxState.lastPrint = tic;
            end

            if decoded
                appendArea(app.recvArea, sprintf('%s  FROM=%s  TO=%s  %s', timestamp(), src, dest, msg));
                logLine(sprintf('Decoded message from %s.', src));
                sendAckForMessage(src, msg);
            end
        catch e
            logLine(['Receive loop error: ' e.message]);
        end
    end

    function sendAckForMessage(src, msg)
        packetId = extractPacketId(msg);
        if isempty(packetId)
            logLine('Message has no packet ID; ACK skipped.');
            return;
        end

        radioId = selectedRadioId();
        myCall = normalizeCall(app.localCallField.Value);
        ackIq = buildAckIQ(myCall, src, packetId, app.fs, app.fs_sdr, app.dev, app.ackPktSec);

        try
            release(app.rx);
            pause(0.05);
            tx = mkTx(radioId, app.fs_sdr, app.txGainField.Value, app.centerFrequency);
            transmitRepeat(tx, ackIq);
            pause(app.ackPktSec + 0.1);
            release(tx);

            appendArea(app.sentArea, sprintf('%s  ACK TO=%s  ACK=%s', timestamp(), src, packetId));
            logLine(sprintf('ACK sent to %s for ID=%s.', src, packetId));

            app.rx = mkRx(radioId, app.fs_sdr, app.samplesPerFrame, app.rxGainField.Value, app.centerFrequency);
            app.rxState = initRxState(app.fs, app.b_lpf, app.chunkSec);
        catch e
            logLine(['ACK transmit failed: ' e.message]);
        end
    end

    function onClose(~, ~)
        stopAction();
        delete(app.fig);
    end

    function radioId = selectedRadioId()
        value = char(app.radioDropDown.Value);
        token = regexp(value, '\(([^()]+)\)$', 'tokens', 'once');
        if isempty(token)
            radioId = value;
        else
            radioId = token{1};
        end
    end

    function setStatus(text, color)
        app.statusLabel.Text = text;
        app.statusLabel.FontColor = color;
        drawnow limitrate;
    end

    function logLine(text)
        appendArea(app.logArea, sprintf('%s  %s', timestamp(), text));
    end

    function appendArea(area, text)
        current = area.Value;
        if ischar(current)
            current = cellstr(current);
        end
        current{end+1, 1} = text;
        if numel(current) > 300
            current = current(end-299:end);
        end
        area.Value = current;
        drawnow limitrate;
    end
end

function items = discoverPlutos()
items = {'usb:0'};

try
    if exist('findPlutoRadio', 'file') == 2
        radios = findPlutoRadio;
        if ~isempty(radios)
            found = {};
            for k = 1:numel(radios)
                radioId = readStructField(radios(k), {'RadioID', 'RadioId', 'URI', 'IPAddress'}, sprintf('usb:%d', k-1));
                serial = readStructField(radios(k), {'SerialNum', 'SerialNumber'}, '');
                if isempty(serial)
                    found{end+1} = radioId; %#ok<AGROW>
                else
                    found{end+1} = sprintf('%s (%s)', serial, radioId); %#ok<AGROW>
                end
            end
            items = found;
            return;
        end
    end
catch
end

try
    if exist('sdrinfo', 'file') == 2
        info = sdrinfo('Pluto');
        radioId = readStructField(info, {'RadioID', 'RadioId', 'URI', 'IPAddress'}, 'usb:0');
        items = {radioId};
    end
catch
end
end

function value = readStructField(s, names, fallback)
value = fallback;
for k = 1:numel(names)
    hasName = (isstruct(s) && isfield(s, names{k})) || (isobject(s) && isprop(s, names{k}));
    if hasName
        raw = s.(names{k});
        if isstring(raw) || ischar(raw)
            value = char(raw);
            return;
        end
    end
end
end

function call = normalizeCall(value)
call = upper(strtrim(char(value)));
if isempty(call)
    call = 'N0CALL';
end
if length(call) > 6
    call = call(1:6);
end
end

function schedule = buildTxGainSchedule(startGain)
base = [startGain -10 -6 -3 0];
base = min(max(base, -89.75), 0);
schedule = [];
for k = 1:numel(base)
    if isempty(schedule) || all(abs(schedule - base(k)) > 1e-9)
        schedule(end+1) = base(k); %#ok<AGROW>
    end
end
schedule = sort(schedule, 'ascend');
startIdx = find(abs(schedule - min(max(startGain, -89.75), 0)) < 1e-9, 1);
if isempty(startIdx)
    startIdx = 1;
end
schedule = schedule(startIdx:end);
end

function b_lpf = buildLowpass(fs_sdr)
lpf = designfilt('lowpassfir', ...
    'PassbandFrequency',   3000, ...
    'StopbandFrequency',   8000, ...
    'PassbandRipple',      0.5,  ...
    'StopbandAttenuation', 40,   ...
    'SampleRate',          fs_sdr);
b_lpf = lpf.Coefficients;
end

function tx = mkTx(radioId, fs_sdr, gain_db, centerFrequency)
tx = sdrtx('Pluto');
if isprop(tx, 'RadioID')
    tx.RadioID = radioId;
end
tx.CenterFrequency = centerFrequency;
tx.BasebandSampleRate = fs_sdr;
tx.Gain = gain_db;
end

function rx = mkRx(radioId, fs_sdr, samplesPerFrame, gain_db, centerFrequency)
rx = sdrrx('Pluto');
if isprop(rx, 'RadioID')
    rx.RadioID = radioId;
end
rx.CenterFrequency = centerFrequency;
rx.BasebandSampleRate = fs_sdr;
rx.SamplesPerFrame = samplesPerFrame;
rx.GainSource = 'Manual';
rx.Gain = gain_db;
end

function tx_final = buildMessageIQ(src, dest, msg)
fs = 48000;
fs_sdr = 960000;
dev = 5000;
pkt_sec = 1.4;

frame = ax25_encode(src, dest, msg);
audio = afsk_modulate(frame, fs);
audio_up = resample(audio, fs_sdr, fs);
audio_up = audio_up / (max(abs(audio_up)) + 1e-6);
phase = 2*pi*dev * cumsum(audio_up) / fs_sdr;
tx_signal = exp(1j * phase);

total_samples = round(pkt_sec * fs_sdr);
gap = zeros(round(0.06 * fs_sdr), 1);
preamble = exp(1j * zeros(round(0.08 * fs_sdr), 1));
one_packet = [preamble; tx_signal(:); gap];
total_samples = max(total_samples, length(one_packet) + round(0.1 * fs_sdr));
repeat_count = max(1, floor(total_samples / length(one_packet)));
tx_padded = repmat(one_packet, repeat_count, 1);
tx_final = [tx_padded; zeros(max(0, total_samples - length(tx_padded)), 1)];
tx_final = tx_final(1:total_samples);
end

function state = initRxState(fs, b_lpf, chunk_sec)
AUDIO_BUF_SEC = 1.3;
DECODE_WIN_SEC = 1.1;
DECODE_STEP_SEC = 0.4;

state.Nbuf = round(AUDIO_BUF_SEC * fs);
state.Nwin = round(DECODE_WIN_SEC * fs);
state.Nstep = round(DECODE_STEP_SEC * fs);
state.audioBuf = zeros(state.Nbuf, 1);
state.w = 1;
state.filled = 0;
state.stepCount = 0;
state.prevSample = 1 + 0j;
state.zi = zeros(length(b_lpf)-1, 1);
state.START_RATIO = 2.0;
state.STOP_RATIO = 1.3;
state.ALPHA = 0.05;
state.hangChunks = ceil(0.8 / chunk_sec);
state.noisePower = 0;
state.inSignal = false;
state.hang = 0;
state.lastPrint = tic;
end

function [state, decoded, src, dest, msg, power, noisePower, active] = processRxChunk(state, data, b_lpf, fs, fs_sdr, dev, decim)
decoded = false;
src = '';
dest = '';
msg = '';

data = double(data(:));
power = mean(abs(data).^2);

if state.noisePower == 0
    state.noisePower = max(power, 1e-12);
end

if ~state.inSignal && state.hang == 0
    state.noisePower = (1-state.ALPHA)*state.noisePower + state.ALPHA*power;
    state.noisePower = max(state.noisePower, 1e-12);
end

if ~state.inSignal && power > state.noisePower * state.START_RATIO
    state.inSignal = true;
    state.hang = 0;
elseif state.inSignal && power < state.noisePower * state.STOP_RATIO
    state.inSignal = false;
    state.hang = state.hangChunks;
elseif ~state.inSignal && state.hang > 0
    state.hang = state.hang - 1;
end
active = state.inSignal || state.hang > 0;
noisePower = state.noisePower;

d = [state.prevSample; data(1:end-1)];
fm = angle(data .* conj(d));
state.prevSample = data(end);
fm = fm * (fs_sdr / (2*pi*dev));

[fm_f, state.zi] = filter(b_lpf, 1, fm, state.zi);
audioChunk = fm_f(1:decim:end);

n = numel(audioChunk);
idx = state.w + (0:n-1);
idx = mod(idx-1, state.Nbuf) + 1;
state.audioBuf(idx) = audioChunk;
state.w = mod(state.w-1+n, state.Nbuf) + 1;
state.filled = min(state.Nbuf, state.filled + n);

state.stepCount = state.stepCount + n;
if state.stepCount < state.Nstep || state.filled < state.Nwin
    return;
end
state.stepCount = 0;

start = state.w - state.Nwin;
ridx = start + (0:state.Nwin-1);
ridx = mod(ridx-1, state.Nbuf) + 1;
winAudio = state.audioBuf(ridx);

winAudio = winAudio - mean(winAudio);
winAudio = winAudio / (max(abs(winAudio)) + 1e-6);

bits = afsk_demodulate(winAudio, fs);
if isempty(bits)
    return;
end

try
    [src, dest, msg] = ax25_decode(bits);
    decoded = true;
catch
end
end

function [ack_received, ack_src, ack_msg] = listenForAckRolling(rx, b_lpf, fs, fs_sdr, dev, decim, my_call, ack_call, packet_id, listen_sec, chunk_sec)
ack_received = false;
ack_src = '';
ack_msg = '';

state = initRxState(fs, b_lpf, chunk_sec);
t0 = tic;

while toc(t0) < listen_sec
    data = double(rx());
    [state, decoded, src, dest, msg] = processRxChunk(state, data, b_lpf, fs, fs_sdr, dev, decim);
    if decoded && strcmp(src, ack_call) && strcmp(dest, my_call) && contains(msg, ['ACK=' packet_id])
        ack_received = true;
        ack_src = src;
        ack_msg = msg;
        return;
    end
end
end

function tx_iq_padded = buildAckIQ(my_call, dest_call, packet_id, fs, fs_sdr, dev, pkt_sec)
ack_text = sprintf('ACK=%s', packet_id);
ack_frame = ax25_encode(my_call, dest_call, ack_text);
ack_audio = afsk_modulate(ack_frame, fs);
ack_up = resample(ack_audio, fs_sdr, fs);
ack_up = ack_up / (max(abs(ack_up)) + 1e-6);
ack_phase = 2*pi*dev * cumsum(ack_up) / fs_sdr;
ack_iq = exp(1j * ack_phase);

total_s = round(pkt_sec * fs_sdr);
gap = zeros(round(0.06 * fs_sdr), 1);
preamble = exp(1j * zeros(round(0.06 * fs_sdr), 1));
one_ack = [preamble; ack_iq(:); gap];
total_s = max(total_s, length(one_ack) + round(0.08 * fs_sdr));
repeat_count = max(1, floor(total_s / length(one_ack)));
ack_pad = repmat(one_ack, repeat_count, 1);
if length(ack_pad) > total_s
    tx_iq_padded = ack_pad(1:total_s);
else
    tx_iq_padded = [ack_pad; zeros(total_s-length(ack_pad), 1)];
end
end

function packet_id = extractPacketId(msg)
packet_id = '';
tok = regexp(char(msg), '^ID=([0-9A-Fa-f]+);', 'tokens', 'once');
if ~isempty(tok)
    packet_id = upper(tok{1});
end
end

function value = timestamp()
value = char(datetime('now', 'Format', 'HH:mm:ss'));
end
