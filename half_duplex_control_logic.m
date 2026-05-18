function out = half_duplex_control_logic(op, varargin)
%HALF_DUPLEX_CONTROL_LOGIC Hardware-free helpers for GUI control arbitration.
switch upper(char(op))
    case 'INITIAL_OWNER'
        out = initialOwner(varargin{1}, varargin{2});
    case 'CONTROL_ACTION'
        out = controlAction(varargin{1});
    case 'CONTROL_FIELD'
        out = controlField(varargin{1}, varargin{2});
    case 'APPLY_CONTROL'
        out = applyControl(varargin{:});
    otherwise
        error('Unknown half-duplex control operation: %s', char(op));
end
end

function owner = initialOwner(local_call, remote_call)
local_call = char(local_call);
remote_call = char(remote_call);
if length(local_call) < length(remote_call)
    owner = local_call;
elseif length(remote_call) < length(local_call)
    owner = remote_call;
else
    calls = sort({local_call, remote_call});
    owner = calls{1};
end
end

function action = controlAction(msg)
action = '';
tok = regexp(char(msg), '^ID=[0-9A-Fa-f]+;CTRL=(REQ|OFFER|ACCEPT|REJECT|COMMIT|STATE)(;.*)?$', 'tokens', 'once');
if ~isempty(tok)
    action = tok{1};
end
end

function value = controlField(msg, name)
value = '';
parts = strsplit(char(msg), ';');
prefix = [upper(char(name)) '='];
for k = 1:numel(parts)
    part = char(parts{k});
    if startsWith(part, prefix)
        value = extractAfter(part, strlength(prefix));
        value = char(value);
        return;
    end
end
end

function state = applyControl(state, action, src, packet_id, is_duplicate, local_call)
if is_duplicate
    return;
end

switch char(action)
    case 'REQ'
        state.lastRequestFrom = char(src);
    case 'OFFER'
        state.pendingIncomingOfferId = char(packet_id);
        state.pendingIncomingOfferFrom = char(src);
    case 'ACCEPT'
        if ~isempty(state.pendingControlOfferId)
            state.pendingCommitTxnId = state.pendingControlOfferId;
            state.pendingCommitOwner = char(src);
        end
    case 'REJECT'
        if ~isempty(state.pendingControlOfferId)
            state.pendingControlOfferId = '';
            state.controlOwnerCall = char(local_call);
            state.hasTxControl = true;
        end
    case {'COMMIT', 'STATE'}
        owner = state.commitOwner;
        if ~isempty(owner)
            state.controlOwnerCall = char(owner);
            state.hasTxControl = strcmp(state.controlOwnerCall, char(local_call));
            state.pendingControlOfferId = '';
            state.pendingIncomingOfferId = '';
            state.pendingIncomingOfferFrom = '';
        end
end
end
