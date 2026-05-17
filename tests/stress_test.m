clc; clear;

disp("========== AX.25 STRESS TEST ==========")

pass_count = 0;
total_tests = 6;

%% ================= TEST 1 =================
disp("Test 1: Short message 'HI'")

try
    [s,d,m] = ax25_decode(ax25_encode("VU3ABC","VU3XYZ","HI"));

    assert(strcmp(s,"VU3ABC"), "Source mismatch");
    assert(strcmp(d,"VU3XYZ"), "Destination mismatch");
    assert(strcmp(m,"HI"), "Message mismatch");

    disp("✅ PASS")
    pass_count = pass_count + 1;

catch e
    disp("❌ FAIL")
    disp(e.message)
end

disp(" ")

%% ================= TEST 2 =================
disp("Test 2: Long message")

msg = "THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG12";

try
    [~,~,m] = ax25_decode(ax25_encode("VU3ABC","VU3XYZ",msg));

    assert(strcmp(m,msg), "Long message corrupted");

    disp("✅ PASS")
    pass_count = pass_count + 1;

catch e
    disp("❌ FAIL")
    disp(e.message)
end

disp(" ")

%% ================= TEST 3 =================
disp("Test 3: Alphanumeric 'TEST123'")

try
    [~,~,m] = ax25_decode(ax25_encode("VU3ABC","VU3XYZ","TEST123"));

    assert(strcmp(m,"TEST123"), "Digits corrupted");

    disp("✅ PASS")
    pass_count = pass_count + 1;

catch e
    disp("❌ FAIL")
    disp(e.message)
end

disp(" ")

%% ================= TEST 4 =================
disp("Test 4: Empty message")

try
    [~,~,m] = ax25_decode(ax25_encode("VU3ABC","VU3XYZ",""));

    assert(strcmp(m,""), "Empty message failed");

    disp("✅ PASS")
    pass_count = pass_count + 1;

catch e
    disp("❌ FAIL")
    disp(e.message)
end

disp(" ")

%% ================= TEST 5 =================
disp("Test 5: Bit stuffing verification")

try
    frame = ax25_encode("VU3ABC","VU3XYZ","HELLO");

    payload = frame(9:end-8); % remove flags

    % Find 5 consecutive ones
    idx = strfind(payload, [1 1 1 1 1]);

    valid = true;
    for i = 1:length(idx)
        if payload(idx(i)+5) ~= 0
            valid = false;
            break;
        end
    end

    assert(valid, "Bit stuffing missing after 5 ones");

    % Round-trip check
    [~,~,m] = ax25_decode(frame);
    assert(strcmp(m,"HELLO"), "Destuffing failed");

    disp("✅ PASS")
    pass_count = pass_count + 1;

catch e
    disp("❌ FAIL")
    disp(e.message)
end

disp(" ")

%% ================= TEST 6 =================
disp("Test 6: FCS error detection (bit flip)")

try
    frame = ax25_encode("VU3ABC","VU3XYZ","HELLO");

    % Flip a bit (avoid flags)
    frame(50) = 1 - frame(50);

    error_detected = false;

    try
        ax25_decode(frame);
    catch
        error_detected = true;
    end

    assert(error_detected, "FCS failed to detect error");

    disp("✅ PASS")
    pass_count = pass_count + 1;

catch e
    disp("❌ FAIL")
    disp(e.message)
end

disp(" ")

%% ================= FINAL RESULT =================

disp("====================================")
fprintf("PASSED: %d / %d tests\n", pass_count, total_tests);

if pass_count == total_tests
    disp("🎯 ALL TESTS PASSED — YOUR AX.25 STACK IS CORRECT")
else
    disp("⚠️ SOME TESTS FAILED — DEBUG REQUIRED")
end