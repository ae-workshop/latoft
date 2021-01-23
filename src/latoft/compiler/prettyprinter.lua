local bytecodes = require("latoft.compiler.bytecodes")

local concat = table.concat

local SCOPE_POLICY_NAMES = bytecodes.SCOPE_POLICY_NAMES
local INSTRUCTION_NAMES = bytecodes.INSTRUCTION_NAMES

local prettyprinter = {}

local function arg(code, index)
    local arg = code[index]
    if not arg then
        error("invalid instruction")
    end
    return arg
end

local function no_arg_formatter(code, index)
    return nil
end

local function one_number_formatter(code, index)
    return {tostring(arg(code, index))}
end

local function two_number_formatter(code, index)
    return {
        tostring(arg(code, index)),
        tostring(arg(code, index + 1)),
    }
end

local function atom_formatter(code, index)
    return {code.atoms[arg(code, index)]}
end

local function entity_formatter(code, index)
    local args = {}
    local role = arg(code, index)
    local count = arg(code, index+1)
    index = index + 1

    args[#args+1] = tostring(role)
    args[#args+1] = tostring(count)
    for i = 1, count do
        args[#args+1] = code.atoms[arg(code, index + i)]
    end

    return args
end

local INS = bytecodes.INSTRUCTIONS
local ARGUMENT_FORMATTERS = {
    [INS.SCOPE]        = no_arg_formatter,
    [INS.RETURN]       = no_arg_formatter,
    [INS.RETRACE]      = no_arg_formatter,
    [INS.JUMP]         = one_number_formatter,

    [INS.SET_POLICY]   = function(res, code, index)
        return {SCOPE_POLICY_NAMES[code[index]]}
    end,

    [INS.CREATE]       = entity_formatter,
    [INS.CREATE_M]     = entity_formatter,
    [INS.SELECT_ALL]   = entity_formatter,
    [INS.SELECT_ALL_M] = entity_formatter,
    [INS.SELECT_ONE]   = entity_formatter,
    [INS.SELECT_ONE_M] = entity_formatter,
    [INS.REACT_ALL]    = entity_formatter,
    [INS.REACT_ALL_M]  = entity_formatter,
    [INS.REACT_ONE]    = entity_formatter,
    [INS.REACT_ONE_M]  = entity_formatter,
    [INS.GROUP]        = entity_formatter,
    [INS.GROUP_M]      = entity_formatter,

    [INS.REFER]        = two_number_formatter,
    [INS.REFLECT]      = one_number_formatter,

    [INS.GUARD]        = no_arg_formatter,
    [INS.DESCRIBE]     = no_arg_formatter,
    [INS.WRITE]        = no_arg_formatter,
    [INS.RETRACT]      = no_arg_formatter,

    [INS.COLLECT]      = no_arg_formatter,

    [INS.DO]           = atom_formatter,
    [INS.FORK]         = atom_formatter,
    [INS.ASSERT]       = atom_formatter,
    [INS.TRY]          = atom_formatter,
    [INS.WAIT]         = atom_formatter
}

prettyprinter.format = function(code, atoms)
    local r = {}
    local index = 1

    while index <= #code do
        local ins = code[index]
        local ins_name = INSTRUCTION_NAMES[ins]
        if not ins_name then
            error("invalid instruction: "..ins.." [#"..index.."]\n"..concat(r))
        end

        r[#r+1] = ins_name
        index = index + 1

        local arg_formatter = ARGUMENT_FORMATTERS[ins]
        local success, args = pcall(arg_formatter, code, index)
        if not success then
            error("invalid instruction: "..ins.." [#"..index.."]\n"..concat(r))
        end
        if args then
            for i = 1, #args do
                r[#r+1] = " "
                r[#r+1] = args[i]
            end
            index = index + #args
        end

        r[#r+1] = "\n"
    end

    r[#r] = nil
    return concat(r)
end

return prettyprinter