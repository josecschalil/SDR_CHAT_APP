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
app.defaultTxGain = -1;
app.defaultRxGain = 50;

app.rx = [];
app.connected = false;
app.receiving = false;
app.sessionActive = false;
app.stopTx = false;
app.txBusy = false;
app.rxState = [];
app.receivedPacketIds = containers.Map('KeyType', 'char', 'ValueType', 'logical');
app.hasTxControl = false;
app.controlOwnerCall = '';
app.pendingControlOfferId = '';
app.pendingControlRequestId = '';
app.pendingIncomingOfferId = '';
app.pendingIncomingOfferFrom = '';
app.pendingCommitTxnId = '';
app.pendingCommitOwner = '';
app.pendingStateOwner = '';
app.controlSeq = 0;
app.lastControlSeq = 0;

if mod(round(app.chunkSec * app.fs_sdr), app.decim) ~= 0
    error('SamplesPerFrame must be divisible by decim (%d).', app.decim);
end
app.samplesPerFrame = round(app.chunkSec * app.fs_sdr);
app.b_lpf = buildLowpass(app.fs_sdr);

buildUi();
refreshRadios();
setStatus('Disconnected', [0.55 0.12 0.12]);
updateControlUi();
logLine('GUI ready. Select a Pluto, connect, then start a half-duplex session.');

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
        app.statusLabel = uilabel(top, 'Text', 'Disconnected', 'FontWeight', 'bold');
        app.statusLabel.Layout.Column = [6 8];

        localLabel = uilabel(top, 'Text', 'Local Call');
        localLabel.Layout.Row = 2;
        localLabel.Layout.Column = 1;
        remoteLabel = uilabel(top, 'Text', 'Remote Call');
        remoteLabel.Layout.Row = 2;
        remoteLabel.Layout.Column = 2;
        txGainLabel = uilabel(top, 'Text', 'TX Gain');
        txGainLabel.Layout.Row = 2;
        txGainLabel.Layout.Column = 3;
        rxGainLabel = uilabel(top, 'Text', 'RX Gain');
        rxGainLabel.Layout.Row = 2;
        rxGainLabel.Layout.Column = 4;
        controlLabel = uilabel(top, 'Text', 'Control');
        controlLabel.Layout.Row = 2;
        controlLabel.Layout.Column = 5;

        app.localCallField = uieditfield(top, 'text', 'Value', 'N0CALL');
        app.localCallField.Layout.Row = 3;
        app.localCallField.Layout.Column = 1;
        app.remoteCallField = uieditfield(top, 'text', 'Value', 'N0ACK');
        app.remoteCallField.Layout.Row = 3;
        app.remoteCallField.Layout.Column = 2;
        app.txGainField = uieditfield(top, 'numeric', 'Value', app.defaultTxGain, 'Limits', [-89.75 0]);
        app.txGainField.Layout.Row = 3;
        app.txGainField.Layout.Column = 3;
        app.rxGainField = uieditfield(top, 'numeric', 'Value', app.defaultRxGain, 'Limits', [0 73]);
        app.rxGainField.Layout.Row = 3;
        app.rxGainField.Layout.Column = 4;
        app.controlLabel = uilabel(top, 'Text', 'No session', 'FontWeight', 'bold');
        app.controlLabel.Layout.Row = 3;
        app.controlLabel.Layout.Column = [5 8];

        middle = uigridlayout(root, [2 2]);
        middle.RowHeight = {104, '1x'};
        middle.ColumnWidth = {'1x', '1x'};
        middle.ColumnSpacing = 10;

        app.msgPanel = uipanel(middle, 'Title', 'Message');
        app.msgPanel.Layout.Row = 1;
        app.msgPanel.Layout.Column = [1 2];
        msgGrid = uigridlayout(app.msgPanel, [2 8]);
        msgGrid.RowHeight = {32, 32};
        msgGrid.ColumnWidth = {'1x', 110, 110, 120, 120, 120, 90, 90};
        app.messageField = uieditfield(msgGrid, 'text', 'Value', 'HELLO hII SDR');
        app.messageField.Layout.Row = 1;
        app.messageField.Layout.Column = [1 8];
        app.startButton = uibutton(msgGrid, 'Text', 'Start Session', 'ButtonPushedFcn', @(~,~) startAction());
        app.startButton.Layout.Row = 2;
        app.startButton.Layout.Column = 1;
        app.stopButton = uibutton(msgGrid, 'Text', 'Stop', 'Enable', 'off', 'ButtonPushedFcn', @(~,~) stopAction());
        app.stopButton.Layout.Row = 2;
        app.stopButton.Layout.Column = 2;
        app.sendButton = uibutton(msgGrid, 'Text', 'Send Message', 'Enable', 'off', 'ButtonPushedFcn', @(~,~) sendChatMessage());
        app.sendButton.Layout.Row = 2;
        app.sendButton.Layout.Column = 3;
        app.releaseButton = uibutton(msgGrid, 'Text', 'Release Control', 'Enable', 'off', 'ButtonPushedFcn', @(~,~) releaseControl());
        app.releaseButton.Layout.Row = 2;
        app.releaseButton.Layout.Column = 4;
        app.requestButton = uibutton(msgGrid, 'Text', 'Request Control', 'Enable', 'off', 'ButtonPushedFcn', @(~,~) requestControl());
        app.requestButton.Layout.Row = 2;
        app.requestButton.Layout.Column = 5;
        app.acceptButton = uibutton(msgGrid, 'Text', 'Accept Control', 'Enable', 'off', 'ButtonPushedFcn', @(~,~) acceptControl());
        app.acceptButton.Layout.Row = 2;
        app.acceptButton.Layout.Column = 6;
        app.rejectButton = uibutton(msgGrid, 'Text', 'Reject', 'Enable', 'off', 'ButtonPushedFcn', @(~,~) rejectControl());
        app.rejectButton.Layout.Row = 2;
        app.rejectButton.Layout.Column = 7;
        app.clearButton = uibutton(msgGrid, 'Text', 'Clear', 'ButtonPushedFcn', @(~,~) clearDisplays());
        app.clearButton.Layout.Row = 2;
        app.clearButton.Layout.Column = 8;

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
            setStatus(['Connected: ' radioId], [0.08 0.38 0.16]);
            updateControlUi();
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
        setStatus('Disconnected', [0.55 0.12 0.12]);
        updateControlUi();
        logLine('Disconnected.');
    end

    function startAction()
        if ~app.connected
            logLine('Connect to a Pluto before starting.');
            return;
        end

        startSession();
    end

    function stopAction()
        app.stopTx = true;
        app.sessionActive = false;
        app.txBusy = false;
        stopReceiveMode();
        resetControlState();
        updateControlUi();
    end

    function clearDisplays()
        app.sentArea.Value = {''};
        app.recvArea.Value = {''};
        app.logArea.Value = {''};
        app.receivedPacketIds = containers.Map('KeyType', 'char', 'ValueType', 'logical');
    end

    function startSession()
        if app.receiving
            return;
        end

        radioId = selectedRadioId();
        try
            app.stopTx = false;
            app.sessionActive = true;
            app.receivedPacketIds = containers.Map('KeyType', 'char', 'ValueType', 'logical');
            myCall = normalizeCall(app.localCallField.Value);
            remoteCall = normalizeCall(app.remoteCallField.Value);
            app.controlOwnerCall = initialControlOwner(myCall, remoteCall);
            app.hasTxControl = strcmp(app.controlOwnerCall, myCall);
            app.pendingControlOfferId = '';
            app.pendingControlRequestId = '';
            app.pendingIncomingOfferId = '';
            app.pendingIncomingOfferFrom = '';
            app.pendingCommitTxnId = '';
            app.pendingCommitOwner = '';
            app.pendingStateOwner = '';
            app.controlSeq = 0;
            app.lastControlSeq = 0;
            app.rx = mkRx(radioId, app.fs_sdr, app.samplesPerFrame, app.rxGainField.Value, app.centerFrequency);
            app.rxState = initRxState(app.fs, app.b_lpf, app.chunkSec);
            app.receiving = true;
            setSessionStatus();
            updateControlUi();
            logLine('==============================');
            logLine(sprintf('HALF-DUPLEX SESSION ACTIVE - %s', myCall));
            logLine(sprintf('Remote call: %s', remoteCall));
            logLine(sprintf('Initial transmit control: %s', app.controlOwnerCall));
            logLine(sprintf('TDD ACK: %.1fs packets  Chunks: %.1fs', app.pktSec, app.chunkSec));
            logLine('Will ACK every decoded message and control frame');
            logLine('==============================');

            receiveLoop();
        catch e
            app.receiving = false;
            app.sessionActive = false;
            setStatus('Receive start failed', [0.55 0.12 0.12]);
            updateControlUi();
            logLine(['Receive start failed: ' e.message]);
            stopReceiveMode();
        end
    end

    function sendChatMessage()
        if ~app.sessionActive
            logLine('Start a session before sending.');
            return;
        end
        if ~app.hasTxControl
            logLine(sprintf('Cannot send message: transmit control belongs to %s.', app.controlOwnerCall));
            return;
        end

        remoteCall = normalizeCall(app.remoteCallField.Value);
        msg = char(app.messageField.Value);
        packetId = newPacketId();
        payload = sprintf('ID=%s;%s', packetId, msg);
        sentText = sprintf('%s  TO=%s  ID=%s  %s', timestamp(), remoteCall, packetId, msg);
        ackReceived = sendPayloadWithAck(payload, packetId, sentText, 'message');
        if ackReceived
            setSessionStatus();
        end
    end

    function requestControl()
        if ~app.sessionActive || app.hasTxControl
            return;
        end

        packetId = newPacketId();
        app.pendingControlRequestId = packetId;
        sendControlPayloadBestEffort('REQ', packetId, '', '');
        app.pendingControlRequestId = '';
        logLine('Transmit control request sent without ACK wait.');
        updateControlUi();
    end

    function releaseControl()
        if ~app.sessionActive || ~app.hasTxControl
            return;
        end

        packetId = newPacketId();
        app.pendingControlOfferId = packetId;
        ackReceived = sendControlPayload('OFFER', packetId, packetId, '');
        if ackReceived
            logLine('Control release offer delivered; waiting for accept or reject.');
        else
            app.pendingControlOfferId = '';
        end
        updateControlUi();
    end

    function acceptControl()
        if ~app.sessionActive || isempty(app.pendingIncomingOfferId)
            return;
        end

        packetId = newPacketId();
        offerId = app.pendingIncomingOfferId;
        ackReceived = sendControlPayload('ACCEPT', packetId, offerId, '');
        if ackReceived
            app.pendingIncomingOfferId = '';
            app.pendingIncomingOfferFrom = '';
            appendArea(app.recvArea, sprintf('%s  CONTROL ACCEPTED - waiting for commit', timestamp()));
            setSessionStatus();
        end
        updateControlUi();
    end

    function rejectControl()
        if ~app.sessionActive || isempty(app.pendingIncomingOfferId)
            return;
        end

        packetId = newPacketId();
        offerId = app.pendingIncomingOfferId;
        ackReceived = sendControlPayload('REJECT', packetId, offerId, '');
        if ackReceived
            app.pendingIncomingOfferId = '';
            app.pendingIncomingOfferFrom = '';
            appendArea(app.recvArea, sprintf('%s  CONTROL REJECTED - %s keeps transmit control', timestamp(), app.controlOwnerCall));
            setSessionStatus();
        end
        updateControlUi();
    end

    function ackReceived = sendControlPayload(action, packetId, txnId, ownerCall)
        payload = buildControlPayload(action, packetId, txnId, ownerCall);
        remoteCall = normalizeCall(app.remoteCallField.Value);
        sentText = sprintf('%s  CONTROL TO=%s  ID=%s  CTRL=%s', timestamp(), remoteCall, packetId, action);
        ackReceived = sendPayloadWithAck(payload, packetId, sentText, ['control ' action]);
    end

    function sendControlPayloadBestEffort(action, packetId, txnId, ownerCall)
        payload = buildControlPayload(action, packetId, txnId, ownerCall);
        remoteCall = normalizeCall(app.remoteCallField.Value);
        sentText = sprintf('%s  CONTROL TO=%s  ID=%s  CTRL=%s  NOACK', timestamp(), remoteCall, packetId, action);
        sendPayloadBestEffort(payload, sentText, ['control ' action]);
    end

    function payload = buildControlPayload(action, packetId, txnId, ownerCall)
        app.controlSeq = app.controlSeq + 1;
        payload = sprintf('ID=%s;CTRL=%s;SEQ=%d', packetId, action, app.controlSeq);
        if ~isempty(txnId)
            payload = sprintf('%s;TXN=%s', payload, txnId);
        end
        if ~isempty(ownerCall)
            payload = sprintf('%s;OWNER=%s', payload, ownerCall);
        end
    end

    function ackReceived = sendPayloadWithAck(payload, packetId, sentText, label)
        ackReceived = false;
        if app.txBusy
            logLine('Transmit already in progress.');
            return;
        end

        app.txBusy = true;
        updateControlUi();
        radioId = selectedRadioId();
        myCall = normalizeCall(app.localCallField.Value);
        remoteCall = normalizeCall(app.remoteCallField.Value);
        wasReceiving = app.receiving;
        try
            txFinal = buildMessageIQ(myCall, remoteCall, payload);
        catch e
            logLine(['Frame build failed: ' e.message]);
            app.txBusy = false;
            updateControlUi();
            return;
        end

        suspendSessionRx();
        appendArea(app.sentArea, sentText);
        logLine(sprintf('TX %s started. ID=%s, ACK expected from %s.', label, packetId, remoteCall));

        tStart = tic;
        try
            while toc(tStart) < app.timeoutSec && ~ackReceived && ~app.stopTx
                txGain = app.txGainField.Value;
                tx = mkTx(radioId, app.fs_sdr, txGain, app.centerFrequency);
                logLine(sprintf('TX burst using gain %.1f dB.', txGain));
                transmitRepeat(tx, txFinal);
                pause(app.pktSec + 0.05);
                release(tx);

                listenSec = min(app.ackListenSec, max(0, app.timeoutSec - toc(tStart)));
                if listenSec < app.chunkSec
                    break;
                end

                rxAck = mkRx(radioId, app.fs_sdr, app.samplesPerFrame, app.rxGainField.Value, app.centerFrequency);
                [ackReceived, ackSrc, ~, ackDebug] = listenForAckRolling(rxAck, app.b_lpf, app.fs, app.fs_sdr, app.dev, app.decim, ...
                    myCall, remoteCall, packetId, listenSec, app.chunkSec);
                release(rxAck);

                if ackReceived
                    appendArea(app.recvArea, sprintf('%s  ACK FROM=%s  ACK=%s', timestamp(), ackSrc, packetId));
                    logLine(sprintf('ACK received from %s for ID=%s after %.1f s.', ackSrc, packetId, toc(tStart)));
                else
                    for dbgIdx = 1:numel(ackDebug)
                        logLine(ackDebug{dbgIdx});
                    end
                    logLine(sprintf('No ACK yet for ID=%s. Elapsed %.1f s.', packetId, toc(tStart)));
                    pause(0.2 + 0.2*rand);
                end
                drawnow limitrate;
            end
        catch e
            logLine(['Transmit/ACK failed: ' e.message]);
        end

        if ackReceived
            setStatus('Frame acknowledged', [0.08 0.38 0.16]);
        elseif app.stopTx
            setStatus('Stopped', [0.45 0.32 0.05]);
            logLine('TX stopped by user.');
        else
            setStatus('ACK timeout', [0.55 0.12 0.12]);
            logLine(sprintf('TX timed out after %.0f seconds.', app.timeoutSec));
        end

        if wasReceiving && app.sessionActive && ~app.stopTx
            resumeSessionRx();
        end
        app.txBusy = false;
        updateControlUi();
    end

    function sendPayloadBestEffort(payload, sentText, label)
        if app.txBusy
            logLine('Transmit already in progress.');
            return;
        end

        app.txBusy = true;
        updateControlUi();
        radioId = selectedRadioId();
        myCall = normalizeCall(app.localCallField.Value);
        remoteCall = normalizeCall(app.remoteCallField.Value);
        wasReceiving = app.receiving;
        try
            txFinal = buildMessageIQ(myCall, remoteCall, payload);
        catch e
            logLine(['Frame build failed: ' e.message]);
            app.txBusy = false;
            updateControlUi();
            return;
        end

        suspendSessionRx();
        appendArea(app.sentArea, sentText);
        try
            tx = mkTx(radioId, app.fs_sdr, app.txGainField.Value, app.centerFrequency);
            logLine(sprintf('TX %s once without ACK wait.', label));
            transmitRepeat(tx, txFinal);
            pause(app.pktSec + 0.05);
            release(tx);
        catch e
            logLine(['Best-effort transmit failed: ' e.message]);
        end

        if wasReceiving && app.sessionActive && ~app.stopTx
            resumeSessionRx();
        end
        app.txBusy = false;
        updateControlUi();
    end

    function stopReceiveMode()
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

    function receiveLoop()
        while app.receiving && ~app.stopTx && ~isempty(app.rx)
            data = double(app.rx());
            [app.rxState, decoded, src, dest, msg, power, noisePower, active, decodeError] = processRxChunk(app.rxState, data, ...
                app.b_lpf, app.fs, app.fs_sdr, app.dev, app.decim);

            if toc(app.rxState.lastPrint) > 1.0
                if active
                    logLine(sprintf('Power: %.3g  noise: %.3g  (active)  Gain: %d dB', power, noisePower, round(app.rxGainField.Value)));
                else
                    logLine(sprintf('Power: %.3g  noise: %.3g  (idle)', power, noisePower));
                end
                app.rxState.lastPrint = tic;
            end

            if decoded
                [packetId, isDuplicate] = rememberReceivedPacket(msg);
                controlAction = extractControlAction(msg);
                if startsWith(char(msg), 'ACK=')
                    logLine(sprintf('ACK frame heard outside active wait: FROM=%s TO=%s MSG=%s', src, dest, msg));
                    drawnow limitrate;
                    continue;
                end

                logLine('==============================');
                if isDuplicate
                    logLine('  DUPLICATE FRAME RECEIVED');
                else
                    if isempty(controlAction)
                        logLine('  MESSAGE RECEIVED');
                    else
                        logLine('  CONTROL FRAME RECEIVED');
                    end
                end
                logLine(sprintf('  FROM : %s', src));
                logLine(sprintf('  TO   : %s', dest));
                logLine(sprintf('  MSG  : %s', msg));
                if isDuplicate
                    logLine(sprintf('  ID   : %s already displayed; resending ACK only', packetId));
                end
                logLine('==============================');
                if isempty(controlAction)
                    if ~isDuplicate
                        appendArea(app.recvArea, sprintf('%s  FROM=%s  TO=%s  %s', timestamp(), src, dest, msg));
                    end
                else
                    handleControlFrame(controlAction, src, packetId, msg, isDuplicate);
                end
                if app.sessionActive
                    sendAckForMessage(src, dest, msg);
                    sendPendingCommit();
                    sendPendingState();
                elseif ~isDuplicate && isempty(controlAction)
                    appendArea(app.recvArea, sprintf('%s  FROM=%s  TO=%s  %s', timestamp(), src, dest, msg));
                end
            elseif ~isempty(decodeError)
                logLine(['decode failed: ' decodeError]);
            end

            drawnow limitrate;
        end

        if app.receiving
            stopReceiveMode();
        end
    end

    function [packetId, isDuplicate] = rememberReceivedPacket(msg)
        packetId = extractPacketId(msg);
        isDuplicate = false;
        if isempty(packetId)
            return;
        end

        isDuplicate = isKey(app.receivedPacketIds, packetId);
        if ~isDuplicate
            app.receivedPacketIds(packetId) = true;
        end
    end

    function handleControlFrame(action, src, packetId, msg, isDuplicate)
        if isDuplicate
            logLine(sprintf('Duplicate CTRL=%s ignored for state; ACK will be resent.', action));
            return;
        end

        myCall = normalizeCall(app.localCallField.Value);
        txnId = extractControlField(msg, 'TXN');
        seqText = extractControlField(msg, 'SEQ');
        seqValue = str2double(seqText);
        if ~isnan(seqValue) && seqValue <= app.lastControlSeq && ~strcmp(action, 'COMMIT')
            logLine(sprintf('Stale CTRL=%s ignored. SEQ %.0f <= %.0f.', action, seqValue, app.lastControlSeq));
            return;
        end
        if ~isnan(seqValue)
            app.lastControlSeq = seqValue;
        end

        switch action
            case 'REQ'
                appendArea(app.recvArea, sprintf('%s  CONTROL REQUEST FROM=%s  requesting transmit control', timestamp(), src));
                logLine(sprintf('%s requested transmit control. Release control if you want to hand over.', src));

            case 'OFFER'
                app.pendingIncomingOfferId = packetId;
                app.pendingIncomingOfferFrom = src;
                appendArea(app.recvArea, sprintf('%s  CONTROL OFFER FROM=%s  accept or reject transmit control', timestamp(), src));
                logLine(sprintf('%s offered transmit control. Accept or reject the offer.', src));

            case 'ACCEPT'
                if ~isempty(app.pendingControlOfferId) && (isempty(txnId) || strcmp(txnId, app.pendingControlOfferId))
                    app.pendingCommitTxnId = app.pendingControlOfferId;
                    app.pendingCommitOwner = src;
                    appendArea(app.recvArea, sprintf('%s  CONTROL ACCEPTED BY=%s  transmit control transferred', timestamp(), src));
                    logLine(sprintf('%s accepted transmit control. Sending commit after ACK.', src));
                else
                    logLine(sprintf('CTRL=ACCEPT from %s had no pending local offer.', src));
                end

            case 'REJECT'
                if ~isempty(app.pendingControlOfferId) && (isempty(txnId) || strcmp(txnId, app.pendingControlOfferId))
                    app.pendingControlOfferId = '';
                    app.controlOwnerCall = myCall;
                    app.hasTxControl = true;
                    appendArea(app.recvArea, sprintf('%s  CONTROL REJECTED BY=%s  you keep transmit control', timestamp(), src));
                    logLine(sprintf('%s rejected transmit control.', src));
                else
                    logLine(sprintf('CTRL=REJECT from %s had no pending local offer.', src));
                end

            case 'COMMIT'
                ownerCall = extractControlField(msg, 'OWNER');
                if isempty(ownerCall)
                    ownerCall = src;
                end
                applyCommittedOwner(ownerCall);
                app.pendingIncomingOfferId = '';
                app.pendingIncomingOfferFrom = '';
                app.pendingControlOfferId = '';
                if app.hasTxControl
                    app.pendingStateOwner = ownerCall;
                end
                appendArea(app.recvArea, sprintf('%s  CONTROL COMMIT OWNER=%s', timestamp(), ownerCall));
                logLine(sprintf('Committed transmit control owner: %s.', ownerCall));

            case 'STATE'
                ownerCall = extractControlField(msg, 'OWNER');
                if ~isempty(ownerCall)
                    applyCommittedOwner(ownerCall);
                    appendArea(app.recvArea, sprintf('%s  CONTROL STATE OWNER=%s', timestamp(), ownerCall));
                    logLine(sprintf('Control state synchronized. Owner: %s.', ownerCall));
                end
        end

        setSessionStatus();
        updateControlUi();
    end

    function sendPendingCommit()
        if isempty(app.pendingCommitTxnId)
            return;
        end

        txnId = app.pendingCommitTxnId;
        ownerCall = app.pendingCommitOwner;
        app.pendingCommitTxnId = '';
        app.pendingCommitOwner = '';
        packetId = newPacketId();
        ackReceived = sendControlPayload('COMMIT', packetId, txnId, ownerCall);
        app.pendingControlOfferId = '';
        applyCommittedOwner(ownerCall);
        if ackReceived
            appendArea(app.recvArea, sprintf('%s  CONTROL COMMITTED - %s has transmit control', timestamp(), ownerCall));
            setSessionStatus();
        else
            app.pendingCommitTxnId = txnId;
            app.pendingCommitOwner = ownerCall;
            logLine('Commit was not acknowledged; local owner was updated and commit will be retried on the next received frame.');
        end
        updateControlUi();
    end

    function sendPendingState()
        if isempty(app.pendingStateOwner)
            return;
        end

        ownerCall = app.pendingStateOwner;
        app.pendingStateOwner = '';
        packetId = newPacketId();
        sendControlPayloadBestEffort('STATE', packetId, '', ownerCall);
        logLine(sprintf('Control state announced without ACK wait. Owner=%s.', ownerCall));
    end

    function applyCommittedOwner(ownerCall)
        myCall = normalizeCall(app.localCallField.Value);
        app.controlOwnerCall = normalizeCall(ownerCall);
        app.hasTxControl = strcmp(app.controlOwnerCall, myCall);
    end

    function sendAckForMessage(src, dest, msg)
        packetId = extractPacketId(msg);
        if isempty(packetId)
            logLine('Message has no packet ID; ACK skipped to avoid false acknowledgement.');
            return;
        end

        radioId = selectedRadioId();
        configuredCall = normalizeCall(app.localCallField.Value);
        ackSourceCall = configuredCall;
        if ~isempty(dest) && ~strcmp(dest, configuredCall)
            ackSourceCall = normalizeCall(dest);
            logLine(sprintf('ACK source adjusted from Local Call %s to packet destination %s.', configuredCall, ackSourceCall));
        end
        ackIq = buildAckIQ(ackSourceCall, src, packetId, app.fs, app.fs_sdr, app.dev, app.ackPktSec);

        try
            logLine(sprintf('Sending ACK %s to %s...', packetId, src));
            release(app.rx);
            pause(0.05);
            tx = mkTx(radioId, app.fs_sdr, app.txGainField.Value, app.centerFrequency);
            transmitRepeat(tx, ackIq);
            pause(app.ackPktSec + 0.1);
            release(tx);

            appendArea(app.sentArea, sprintf('%s  ACK TO=%s  ACK=%s', timestamp(), src, packetId));

            app.rx = mkRx(radioId, app.fs_sdr, app.samplesPerFrame, app.rxGainField.Value, app.centerFrequency);
            app.rxState = initRxState(app.fs, app.b_lpf, app.chunkSec);
            logLine('ACK sent - resuming receive');
        catch e
            logLine(['ACK transmit failed: ' e.message]);
            if app.sessionActive && isempty(app.rx)
                try
                    resumeSessionRx();
                catch resumeError
                    logLine(['RX resume failed: ' resumeError.message]);
                end
            end
        end
    end

    function suspendSessionRx()
        if ~isempty(app.rx)
            try
                release(app.rx);
            catch
            end
        end
        app.rx = [];
    end

    function resumeSessionRx()
        radioId = selectedRadioId();
        app.rx = mkRx(radioId, app.fs_sdr, app.samplesPerFrame, app.rxGainField.Value, app.centerFrequency);
        app.rxState = initRxState(app.fs, app.b_lpf, app.chunkSec);
        app.receiving = true;
        logLine('RX resumed');
    end

    function resetControlState()
        app.hasTxControl = false;
        app.controlOwnerCall = '';
        app.pendingControlOfferId = '';
        app.pendingControlRequestId = '';
        app.pendingIncomingOfferId = '';
        app.pendingIncomingOfferFrom = '';
        app.pendingCommitTxnId = '';
        app.pendingCommitOwner = '';
        app.pendingStateOwner = '';
    end

    function setSessionStatus()
        if ~app.sessionActive
            return;
        end

        if app.hasTxControl
            setStatus('Session active - you can transmit', [0.08 0.38 0.16]);
        else
            setStatus(['Session active - listening to ' app.controlOwnerCall], [0.1 0.28 0.58]);
        end
    end

    function updateControlUi()
        if ~isfield(app, 'startButton')
            return;
        end

        app.startButton.Enable = onOff(app.connected && ~app.sessionActive && ~app.txBusy);
        app.stopButton.Enable = onOff(app.sessionActive || app.receiving || app.txBusy);
        app.messageField.Enable = onOff(app.sessionActive && app.hasTxControl && ~app.txBusy);
        app.sendButton.Enable = onOff(app.sessionActive && app.hasTxControl && ~app.txBusy);
        app.releaseButton.Enable = onOff(app.sessionActive && app.hasTxControl && ~app.txBusy && isempty(app.pendingControlOfferId));
        app.requestButton.Enable = onOff(app.sessionActive && ~app.hasTxControl && ~app.txBusy);
        app.acceptButton.Enable = onOff(app.sessionActive && ~app.txBusy && ~isempty(app.pendingIncomingOfferId));
        app.rejectButton.Enable = onOff(app.sessionActive && ~app.txBusy && ~isempty(app.pendingIncomingOfferId));

        if app.sessionActive
            if app.hasTxControl
                app.msgPanel.Title = 'Message - Transmit Control';
                app.controlLabel.Text = 'You have transmit control';
                app.controlLabel.FontColor = [0.08 0.38 0.16];
            else
                app.msgPanel.Title = 'Message - Listening';
                app.controlLabel.Text = ['Control: ' app.controlOwnerCall];
                app.controlLabel.FontColor = [0.1 0.28 0.58];
            end
        else
            app.msgPanel.Title = 'Message';
            app.controlLabel.Text = 'No session';
            app.controlLabel.FontColor = [0.2 0.2 0.2];
        end
        drawnow limitrate;
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

function owner = initialControlOwner(local_call, remote_call)
owner = half_duplex_control_logic('INITIAL_OWNER', local_call, remote_call);
end

function value = onOff(tf)
if tf
    value = 'on';
else
    value = 'off';
end
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

function [state, decoded, src, dest, msg, power, noisePower, active, decodeError] = processRxChunk(state, data, b_lpf, fs, fs_sdr, dev, decim)
decoded = false;
src = '';
dest = '';
msg = '';
decodeError = '';

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
catch e
    decodeError = e.message;
end
end

function [ack_received, ack_src, ack_msg, ack_debug] = listenForAckRolling(rx, b_lpf, fs, fs_sdr, dev, decim, my_call, ack_call, packet_id, listen_sec, chunk_sec)
ack_received = false;
ack_src = '';
ack_msg = '';
ack_debug = {};

state = initRxState(fs, b_lpf, chunk_sec);
t0 = tic;

while toc(t0) < listen_sec
    data = double(rx());
    [state, decoded, src, dest, msg] = processRxChunk(state, data, b_lpf, fs, fs_sdr, dev, decim);
    if decoded && contains(msg, 'ACK=')
        if strcmp(src, ack_call) && strcmp(dest, my_call) && contains(msg, ['ACK=' packet_id])
            ack_received = true;
            ack_src = src;
            ack_msg = msg;
            return;
        end

        reason = {};
        if ~strcmp(src, ack_call)
            reason{end+1} = sprintf('source %s expected %s', src, ack_call); %#ok<AGROW>
        end
        if ~strcmp(dest, my_call)
            reason{end+1} = sprintf('dest %s expected %s', dest, my_call); %#ok<AGROW>
        end
        if ~contains(msg, ['ACK=' packet_id])
            reason{end+1} = sprintf('payload %s expected ACK=%s', msg, packet_id); %#ok<AGROW>
        end
        ack_debug{end+1} = sprintf('Ignored ACK candidate: FROM=%s TO=%s MSG=%s (%s)', ...
            src, dest, msg, strjoin(reason, '; ')); %#ok<AGROW>
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

function packet_id = newPacketId()
packet_id = upper(dec2hex(randi([0 65535]), 4));
end

function action = extractControlAction(msg)
action = half_duplex_control_logic('CONTROL_ACTION', msg);
end

function value = extractControlField(msg, name)
value = half_duplex_control_logic('CONTROL_FIELD', msg, name);
end

function value = timestamp()
value = char(datetime('now', 'Format', 'HH:mm:ss'));
end
