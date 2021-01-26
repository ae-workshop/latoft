local bytecodes = require("latoft.compiler.bytecodes")

local coroutine_wrap = coroutine.rwap

local SCOPE_POLICY_NAMES = bytecodes.SCOPE_POLICY_NAMES
local INSTRUCTION_NAMES = bytecodes.INSTRUCTION_NAMES

local SCOPE_POLICIES = bytecodes.SCOPE_POLICIES
local INSTRUCTIONS = bytecodes.INSTRUCTIONS

local FAIL_ON_COMPLETED  = SCOPE_POLICIES.FAIL_ON_COMPLETED
local FAIL_ON_TERMINATED = SCOPE_POLICIES.FAIL_ON_TERMINATED

local INS_SCOPE        = INSTRUCTIONS.SCOPE
local INS_RETURN       = INSTRUCTIONS.RETURN
local INS_RETRACE      = INSTRUCTIONS.RETRACE

local INS_SET_POLICY   = INSTRUCTIONS.SET_POLICY
local INS_JUMP         = INSTRUCTIONS.JUMP

local INS_CREATE       = INSTRUCTIONS.CREATE
local INS_CREATE_M     = INSTRUCTIONS.CREATE_M
local INS_SELECT_ALL   = INSTRUCTIONS.SELECT_ALL
local INS_SELECT_ALL_M = INSTRUCTIONS.SELECT_ALL_M
local INS_SELECT_ONE   = INSTRUCTIONS.SELECT_ONE
local INS_SELECT_ONE_M = INSTRUCTIONS.SELECT_ONE_M
local INS_REACT_ALL    = INSTRUCTIONS.REACT_ALL
local INS_REACT_ALL_M  = INSTRUCTIONS.REACT_ALL_M
local INS_REACT_ONE    = INSTRUCTIONS.REACT_ONE
local INS_REACT_ONE_M  = INSTRUCTIONS.REACT_ONE_M
local INS_GROUP        = INSTRUCTIONS.GROUP
local INS_GROUP_M      = INSTRUCTIONS.GROUP_M

local INS_REFER        = INSTRUCTIONS.REFER
local INS_REFLECT      = INSTRUCTIONS.REFLECT

local INS_GUARD        = INSTRUCTIONS.GUARD
local INS_DESCRIBE     = INSTRUCTIONS.DESCRIBE
local INS_WRITE        = INSTRUCTIONS.WRITE
local INS_RETRACT      = INSTRUCTIONS.RETRACT

local INS_COLLECT      = INSTRUCTIONS.COLLECT

local INS_DO           = INSTRUCTIONS.DO
local INS_FORK         = INSTRUCTIONS.FORK
local INS_ASSERT       = INSTRUCTIONS.ASSERT
local INS_TRY          = INSTRUCTIONS.TRY
local INS_WAIT         = INSTRUCTIONS.WAIT

local FLOW_CONTINUE   = 0
local FLOW_COMPLETED  = 1
local FLOW_TERMINATED = 2

local EMPTY_TABLE = setmetatable({}, {
    __newindex = "readonly table"
})

local interpreter = {}

local STACK_MAX_SIZE = 255

interpreter.run = function(code, event_listener)
    local code_size = #code
    local p = 1 -- code pointer

    local scope_stack = {}
    local scope_top = 0
    local iter_stack = {}
    local iter_top = 0
    local iter_bottom = 0
    local jump_stack = {}
    local jump_top = 0
    local entity_stack = {}
    local entity_top = 0

    local entities = {}
    local events = {}
    local event_listeners = {}
    local target_cache = {}
    local collection = {}

    local atoms = code.atoms
    local atom_map = {}
    for label, atom in pairs(atoms) do
        atom_map[atom] = label
    end

    local env = {}

    local function set_entity(source, target, mark)
        local es = entities[target]
        if not es then
            es = {}
            entities[target] = es
        end
        es[source] = mark or true
        target_cache[source] = nil
    end

    local function remove_entity(source, target)
        local es = entities[target]
        if es then
            es[source] = nil
            target_cache[source] = nil
        end
    end

    local function get_mark(source, target)
        local es = entities[target]
        if es then
            return es[source]
        end
    end

    local function sources(target)
        return next, entities[target] or EMPTY_TABLE, nil
    end

    local function targets(source)
        local cache = target_cache[source]
        if not cache then
            cache = {}
            for target, es in pairs(entities) do
                local mark = es[source]
                if mark then
                    cache[target] = mark
                end
            end
        end
        return next, cache, nil
    end

    local function submit_event(event, control, primary, secondary, indirect, peripheral)
        local instances = events[event]
        if not instances then
            instances = {}
            events[event] = instances
        end

        instances[#instances+1] =
            {primary, secondary, indirect, peripheral}

        if primary then set_entity(primary, event) end
        if secondary then set_entity(secondary, event + 1) end

        return event_listener(env, event, control, primary, secondary, indirect, peripheral)
    end

    local function find_event(event, primary, secondary, indirect, peripheral)
        local instances = events[event]
        if not instances then return nil end

        local len = #instances
        local i = 0
        local v
        local e

        while true do
            ::continue::
            i = i + 1
            if i > len then break end

            e = instances[i]
            if primary then
                v = e[1]
                if v and v ~= primary then
                    goto continue
                end
            end
            if secondary then
                v = e[2]
                if v and v ~= secondary then
                    goto continue
                end
            end
            if indirect then
                v = e[3]
                if v and v ~= indirect then
                    goto continue
                end
            end
            if peripheral then
                v = e[4]
                if v and v ~= peripheral then
                    goto continue
                end
            end
            return e
        end
    end

    local function jump(target_pos)
        jump_stack[jump_top + 1] = p
        jump_stack[jump_top + 2] = scope_top
        jump_stack[jump_top + 3] = entity_top
        jump_top = jump_top + 4
        jump_stack[jump_top] = iter_bottom

        p = target_pos
        iter_bottom = iter_top
    end

    local function retrace()
        local iterator
        local state
        local argument
        local value 

        while true do
            if iter_top <= iter_bottom then
                if jump_top == 0 then
                    return false
                end

                p = jump_stack[jump_top - 3]
                scope_top = jump_stack[jump_top - 2]
                entity_top = jump_stack[jump_top - 1]
                iter_bottom = jump_stack[jump_top]
                jump_top = jump_top - 4
                return true
            end

            iterator = iter_stack[iter_top - 5]
            state = iter_stack[iter_top - 4]
            local arg_index = iter_top - 3
            argument = iterator(state, iter_stack[arg_index])

            if argument then
                local retrace_pos = iter_stack[iter_top - 2]
                local retrace_top = iter_stack[iter_top - 1]
                local write_offset = iter_stack[iter_top]

                p = retrace_pos
                scope_top = retrace_top
                iter_stack[arg_index] = argument
                scope_stack[scope_top - write_offset] = argument
                return true
            end

            iter_stack[iter_top - 4] = nil
            iter_top = iter_top - 6
        end
    end

    env.set_entity = set_entity
    env.remove_entity = remove_entity
    env.get_mark = get_mark
    env.sources = sources
    env.targets = targets
    env.submit_event = submit_event
    env.find_event = find_event
    env.jump = jump
    env.retrace = retrace

    local function ins_create(start_index, end_index, role)
        local entity = {}
        scope_stack[scope_top - role] = entity

        for i = start_index, end_index do
            local atom = code[i]
            local tag = atom & 3
            if tag == 0 then -- noun
                set_entity(entity, atom)
            elseif tag == 3 then -- active verb
                submit_event(atom, "do", entity)
            else -- tag == 4 -- passive verb
                submit_event(atom - 1, "do", nil, entity)
            end
        end

        return FLOW_CONTINUE, entity
    end

    local function select_all_iterator(state, entity)
        local candidates = state.candidates
        local start_index = state.start_index
        local end_index = state.end_index

        while true do
            ::continue::

            entity = next(candidates, entity)
            if not entity then
                return nil
            end

            for i = start_index, end_index do
                local atom = code[i]
                local es = entities[atom]
                if not es or not es[entity]  then
                    goto continue
                end
            end

            return entity
        end
    end

    local function ins_select_all(start_index, end_index, role)
        if start_index > end_index then
            return FLOW_COMPLETED
        end

        local atom = code[start_index]
        local candidates = entities[atom]

        if not candidates then
            return FLOW_COMPLETED
        end

        local state = {
            candidates = candidates,
            start_index = start_index + 1,
            end_index = end_index
        }

        local fst_entity =
            select_all_iterator(state, nil)
        if not fst_entity then
            return FLOW_COMPLETED
        end

        iter_stack[iter_top + 1] = select_all_iterator
        iter_stack[iter_top + 2] = state
        iter_stack[iter_top + 3] = fst_entity
        iter_stack[iter_top + 4] = end_index + 1
        iter_stack[iter_top + 5] = scope_top
        iter_top = iter_top + 6
        iter_stack[iter_top] = role

        scope_stack[scope_top - role] = fst_entity
        return FLOW_CONTINUE, fst_entity
    end

    local function ins_select_one(start_index, end_index, role)
        if start_index > end_index then
            return FLOW_TERMINATED
        end

        local atom = code[start_index]
        local es = entities[atom]
        if not es then
            return FLOW_TERMINATED
        end

        start_index = start_index + 1

        for entity in pairs(es) do
            local success = true

            for i = start_index, end_index do
                atom = code[i]
                es = entity[atom]
                if not es then
                    success = false
                    break
                end
            end

            if success then
                code[scope_top - role] = entity
                return FLOW_CONTINUE, entity
            end
        end

        return FLOW_TERMINATED
    end

    local function ins_react_all(start_index, end_index, role)
    end

    local function ins_react_one(start_index, end_index, role)
    end

    local function ins_group(start_index, end_index, role)
        local group = {}

        if start_index > end_index then
            code[scope_top - role] = group
            return FLOW_CONTINUE, group
        end

        local atom = code[start_index]
        local es = entities[fst_atom]

        if not es then
            code[scope_top - role] = group
            return FLOW_CONTINUE, group
        end

        start_index = start_index + 1

        for entity in pairs(es) do
            local success = true

            for i = start_index, end_index do
                atom = code[i]
                es = entities[atom]
                if not es then
                    success = false
                    break
                end
            end

            if success then
                group[#group+1] = entity
            end
        end

        code[scope_top - role] = group
        return FLOW_CONTINUE, group
    end

    while p <= code_size do
        local ins = code[p]
        local head = ins >> 4

        if head == 0 then
            if ins == INS_SCOPE then
                if scope_top > STACK_MAX_SIZE then
                    error("stack overflow!")
                end
                local return_pos = code[p + 1]
                p = p + 2
                scope_stack[scope_top + 1] = return_pos
                scope_stack[scope_top + 2] = FAIL_ON_TERMINATED
                scope_stack[scope_top + 3] = nil
                scope_stack[scope_top + 4] = nil
                scope_stack[scope_top + 5] = nil
                scope_top = scope_top + 6
                scope_stack[scope_top] = nil
            elseif ins == INS_RETURN then
                p = p + 1
                scope_top = scope_top - 6
            elseif ins == INS_JUMP then
                local target = code[p + 1]
                p = p + 2
                jump(target)
            elseif ins == INS_RETRACE then
                if not retrace() then
                    p = p + 1
                end
            end
        elseif head == 1 then
            p = p + 2
            if ins == INS_SET_POLICY then
                scope_stack[scope_top - 4] = code[p + 1]
            end
        elseif head == 2 then
            local result
            local entity

            local role = code[p + 1]
            local atom_count = code[p + 2]
            local start_index = p + 3
            local end_index = start_index + atom_count - 1

            p = end_index + 1

            if ins == INS_CREATE then
                result = ins_create(start_index, end_index, role)
            elseif ins == INS_CREATE_M then
                result, entity = ins_create(start_index, end_index, role)
                if result == FLOW_CONTINUE then
                    entity_top = entity_top + 1
                    entity_stack[entity_top] = entity
                end
            elseif ins == INS_SELECT_ALL then
                result = ins_select_all(start_index, end_index, role)
            elseif ins == INS_SELECT_ALL_M then
                result, entity = ins_select_all(start_index, end_index, role)
                if result == FLOW_CONTINUE then
                    entity_top = entity_top + 1
                    entity_stack[entity_top] = entity
                end
            elseif ins == INS_SELECT_ONE then
                result = ins_select_one(start_index, end_index, role)
            elseif ins == INS_SELECT_ONE_M then
                result, entity = ins_select_one(start_index, end_index, role)
                if success then
                    entity_top = entity_top + 1
                    entity_stack[entity_top] = entity
                end
            elseif ins == INS_REACT_ALL then
            elseif ins == INS_REACT_ALL_M then
            elseif ins == INS_REACT_ONE then
            elseif ins == INS_REACT_ONE_M then
            elseif ins == INS_GROUP then
                result = ins_group(start_index, end_index, role)
            elseif ins == INS_GROUP_M then
                result, entity = ins_group(start_index, end_index, role)
                if result == FLOW_CONTINUE then
                    entity_top = entity_top + 1
                    entity_stack[entity_top] = entity
                end
            end

            if result == FLOW_TERMINATED then
                local scope_policy = scope_stack[scope_top - 4]
                if scope_policy == FAIL_ON_TERMINATED then
                    error("FAIL!")
                else
                    p = scope_stack[scope_top - 5]
                end
            elseif result == FLOW_COMPLETED then
                local scope_policy = scope_stack[scope_top - 4]
                if scope_policy == FAIL_ON_COMPLETED then
                    error("FAIL!")
                else
                    p = scope_stack[scope_top - 5]
                end
            end
        elseif head == 3 then
            if ins == INS_REFER then
                local role = code[p + 1]
                local offset = code[p + 2]
                scope_stack[scope_top - role] =
                    entity_stack[entity_top - offset]
            elseif ins == INS_REFLECT then
                local role = code[p + 1]
                local reflected_role = code[p + 2]
                scope_stack[scope_top - role] =
                    scope_stack[scope_top - 5 - reflected_role]
            end
            p = p + 3
        elseif head == 4 then
        elseif head == 5 then
            if ins == INS_COLLECT then
            end
            p = p + 1
        elseif head == 6 then
            local success
            local msg
            local event = code[p + 1]
            p = p + 2

            local p = scope_stack[scope_top]
            local s = scope_stack[scope_top - 1]
            local i = scope_stack[scope_top - 2]
            local pe = scope_stack[scope_top - 3]

            if ins == INS_DO then
                success, msg = submit_event(event, "do", p, s, i, pe)
            elseif ins == INS_FORK then
                success, msg = submit_event(event, "fork", p, s, i, pe)
            elseif ins == INS_ASSERT then
                success = find_event(event, p, s, i, pe)
                if not success then
                    msg = "false assert"
                end
            elseif ins == INS_TRY then
                success, msg = submit_event(event, "do", p, s, i, pe)
                success = true
            end

            local scope_policy = scope_stack[scope_top - 4]
            if scope_policy == FAIL_ON_TERMINATED then
                if not success then
                    error("FAIL: "..msg)
                end
            elseif scope_policy == FAIL_ON_COMPLETED then
                if success then
                    error("FAIL: "..msg)
                end
            end
        end
    end
end

return interpreter