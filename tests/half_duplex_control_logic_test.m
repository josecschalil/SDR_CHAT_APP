fprintf('===== HALF-DUPLEX CONTROL LOGIC TEST =====\n');

owner = half_duplex_control_logic('INITIAL_OWNER', 'N0A', 'N0CALL');
assert(strcmp(owner, 'N0A'), 'Shorter callsign should get initial control');

owner = half_duplex_control_logic('INITIAL_OWNER', 'N0B', 'N0A');
assert(strcmp(owner, 'N0A'), 'Equal-length callsigns should use lexicographic tie-break');

action = half_duplex_control_logic('CONTROL_ACTION', 'ID=1A2B;CTRL=REQ');
assert(strcmp(action, 'REQ'), 'CTRL=REQ should parse');

action = half_duplex_control_logic('CONTROL_ACTION', 'ID=1A2C;CTRL=COMMIT;SEQ=3;TXN=1003;OWNER=N0ACK');
assert(strcmp(action, 'COMMIT'), 'CTRL=COMMIT should parse with fields');

owner = half_duplex_control_logic('CONTROL_FIELD', 'ID=1A2C;CTRL=COMMIT;SEQ=3;TXN=1003;OWNER=N0ACK', 'OWNER');
assert(strcmp(owner, 'N0ACK'), 'OWNER field should parse');

action = half_duplex_control_logic('CONTROL_ACTION', 'ID=1A2B;HELLO');
assert(isempty(action), 'Normal messages should not parse as control frames');

state = baseState('N0CALL');
state = half_duplex_control_logic('APPLY_CONTROL', state, 'REQ', 'N0ACK', '1001', false, 'N0CALL');
assert(strcmp(state.lastRequestFrom, 'N0ACK'), 'REQ should record requester without changing owner');
assert(state.hasTxControl, 'REQ must not transfer control');

state = baseState('N0ACK');
state = half_duplex_control_logic('APPLY_CONTROL', state, 'OFFER', 'N0CALL', '1002', false, 'N0ACK');
assert(strcmp(state.pendingIncomingOfferId, '1002'), 'OFFER should create pending incoming offer');
assert(strcmp(state.controlOwnerCall, 'N0ACK'), 'OFFER must not change committed owner');
assert(~state.hasTxControl, 'OFFER should leave listener without control until commit is received');

state = baseState('N0CALL');
state.pendingControlOfferId = '1003';
state = half_duplex_control_logic('APPLY_CONTROL', state, 'ACCEPT', 'N0ACK', '1004', false, 'N0CALL');
assert(strcmp(state.pendingCommitTxnId, '1003'), 'ACCEPT should schedule a commit for the original offer');
assert(strcmp(state.controlOwnerCall, 'N0CALL'), 'ACCEPT must not change committed owner before COMMIT');
assert(state.hasTxControl, 'Sender should keep control until COMMIT is sent');

state.commitOwner = 'N0ACK';
state = half_duplex_control_logic('APPLY_CONTROL', state, 'COMMIT', 'N0CALL', '1008', false, 'N0CALL');
assert(strcmp(state.controlOwnerCall, 'N0ACK'), 'COMMIT should transfer committed owner');
assert(~state.hasTxControl, 'Original transmitter should lose control after COMMIT');

state = baseState('N0CALL');
state.pendingControlOfferId = '1005';
state = half_duplex_control_logic('APPLY_CONTROL', state, 'REJECT', 'N0ACK', '1006', false, 'N0CALL');
assert(strcmp(state.controlOwnerCall, 'N0CALL'), 'REJECT should keep local control');
assert(state.hasTxControl, 'Sender should keep control after REJECT');

stateBefore = state;
state = half_duplex_control_logic('APPLY_CONTROL', state, 'ACCEPT', 'N0ACK', '1007', true, 'N0CALL');
assert(isequal(state, stateBefore), 'Duplicate control frames must not change state');

disp('HALF-DUPLEX CONTROL LOGIC PASSED');

function state = baseState(owner)
state = struct();
state.hasTxControl = strcmp(owner, 'N0CALL');
state.controlOwnerCall = owner;
state.pendingControlOfferId = '';
state.pendingIncomingOfferId = '';
state.pendingIncomingOfferFrom = '';
state.lastRequestFrom = '';
state.pendingCommitTxnId = '';
state.pendingCommitOwner = '';
state.commitOwner = '';
end
