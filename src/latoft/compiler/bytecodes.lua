local bytecodes = {}

bytecodes.SCOPE_POLICIES = {
    FAIL_ON_COMPLETED  = 0x01,
    FAIL_ON_TERMINATED = 0x02
}

bytecodes.INSTRUCTIONS = {
    SCOPE        = 0x00,
    RETURN       = 0x01,
    RETRACE      = 0x02,
    JUMP         = 0x03,

    SET_POLICY   = 0x10,

    CREATE       = 0x20,
    CREATE_M     = 0x21,
    SELECT_ALL   = 0x22,
    SELECT_ALL_M = 0x23,
    SELECT_ONE   = 0x24,
    SELECT_ONE_M = 0x25,
    REACT_ALL    = 0x26,
    REACT_ALL_M  = 0x27,
    REACT_ONE    = 0x28,
    REACT_ONE_M  = 0x29,
    GROUP        = 0x2A,
    GROUP_M      = 0x2B,

    REFER        = 0x30,
    REFLECT      = 0x31,

    GUARD        = 0x40,
    DESCRIBE     = 0x41,
    WRITE        = 0x42,
    RETRACT      = 0x43,

    COLLECT      = 0x50,

    DO           = 0x60,
    FORK         = 0x61,
    ASSERT       = 0x62,
    TRY          = 0x63
}

local SCOPE_POLICY_NAMES = {}
for k, v in pairs(bytecodes.SCOPE_POLICIES) do
    SCOPE_POLICY_NAMES[v] = k
end
bytecodes.SCOPE_POLICY_NAMES = SCOPE_POLICY_NAMES

local INSTRUCTION_NAMES = {}
for k, v in pairs(bytecodes.INSTRUCTIONS) do
    INSTRUCTION_NAMES[v] = k
end
bytecodes.INSTRUCTION_NAMES = INSTRUCTION_NAMES

return bytecodes