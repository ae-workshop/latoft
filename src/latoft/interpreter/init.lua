local bytecodes = require("latoft.compiler.bytecodes")

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

local interpreter = {}

local STACK_MAX_SIZE = 255

local function select_all_iterator(code, entities, state, entity)
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
            if not es or not es[entity] then
                goto continue
            end
        end

        return entity
    end
end

interpreter.run = function(code, listeners)
    local code_size = #code
    local p = 1 -- code pointer

    local stack = {}
    local top = 0

    local iter_stack = {} -- iteration stack
    local iter_bottom = 0
    local iter_top = 0
    local jump_stack = {}
    local jump_top = 0
    local entity_stack = {}
    local entity_top = 0

    local entity_acc = 1
    local entities = {}
    local last_entity
    local collection = {}

    local event_listeners = {}
    local event_history = {}

    local registered_react_instructions = {}
    local env = {}
    
    local atom_map = {}
    for atom, label in pairs(code.atoms) do
        atom_map[label] = atom
    end


    local function complete()
    end

    local function terminate()
        error("terminate: "..INSTRUCTION_NAMES[code[p]])
    end
    
    local function jump(target_pos, recover_pos)
        jump_stack[jump_top + 1] = recover_pos
        jump_stack[jump_top + 2] = top
        jump_stack[jump_top + 3] = entity_top
        jump_top = jump_top + 4
        jump_stack[jump_top] = iter_bottom

        p = target_pos
        iter_bottom = iter_top
    end

    local function set_entity(id, atom)
        local es = entities[atom]
        if not es then
            es = {}
            entities[atom] = es
        end
        es[id] = true
    end
    env.set_entity = set_entity
    
    local function remove_entity(id, atom)
        local es = entities[atom]
        if es then
            es[id] = nil
        end
    end
    env.remove_entity = remove_entity

    local function entity_atom_iterator(entity_id, atom)
        local es
        while true do
            atom, es = next(entities, atom)
            if atom == nil then
                return nil
            end
            if es[entity_id] then
                return atom
            end
        end
    end

    local function entity_atoms(entity_id)
        return entity_atom_iterator, entity_id, nil
    end
    env.entity_atoms = entity_atoms

    local function set_event_listener(event, listener)
        local ls = event_listeners[event]
        if not ls then
            ls = {}
            event_listeners[event] = ls
        end
        ls[listener] = true
    end
    env.set_event_listener = set_event_listener
    
    local function remove_event_listener(event, listener)
        local ls = event_listeners[event]
        if ls then
            ls[listener] = nil
        end
    end
    env.remove_event_listener = remove_event_listener

    local function submit_unary_event(event, primary)
        print("event", code.atoms[event], primary)
        set_entity(primary, event)

        local h = event_history[event]
        if not h then
            h = {}
            event_history[event] = h
        end
        
        h[#h+1] = primary

        local ls = event_listeners[event]
        if ls then
            for l in pairs(ls) do
                if l(env, event, primary) then
                    ls[l] = nil
                end
            end
        end
    end
    env.submit_unary_event = submit_unary_event

    local function submit_action(event)
        local primary = stack[top]
        local secondary = stack[top - 1]
        local indirect = stack[top - 2]
        local peripheral = stack[top - 3]

        local passive_event = event + 1
        set_entity(primary, event)
        set_entity(secondary, passive_event)

        local h = event_history[event]
        if not h then
            h = {}
            event_history[event] = h
        end

        local top = #h
        h[top+1] = primary
        h[top+2] = secondary
        h[top+3] = indirect
        h[top+4] = peripheral

        local ls = event_listeners[event]
        if ls then
            for l in pairs(ls) do
                if l(env, event, primary, secondary, indirect, peripheral) then
                    ls[l] = nil
                end
            end
        end

        ls = event_listeners[passive_event]
        if ls then
            for l in pairs(ls) do
                if l(env, event, secondary, primary, indirect, peripheral) then
                    ls[l] = nil
                end
            end
        end
    end
    env.submit_action = submit_action

    local function check_action(event)
        local h = event_history[event]
        if not h then return false end

        local primary = stack[top]
        local secondary = stack[top - 1]
        local indirect = stack[top - 2]
        local peripheral = stack[top - 3]

        for i = 1, #h - 3, 4 do 
            if h[i] == primary
                and h[i + 1] == secondary
                and h[i + 2] == indirect
                and h[i + 3] == peripheral then
                return true
            end
        end
        return false
    end
    env.check_action = check_event

    if listeners then
        for label, listener in pairs(listeners) do
            local atom = atom_map[label]
            if not atom then
                error("unrecognized atom: "..atom)
            end
            event_listeners[atom] = {[listener] = true}
        end
    end

    local function ins_create(start_index, end_index, role)
        local id = entity_acc
        stack[top - role] = id
        entity_acc = entity_acc + 1

        for i = start_index, end_index do
            local atom = code[i]
            submit_unary_event(atom, id)
        end

        last_entity = id
        return true
    end

    local function ins_select_all(start_index, end_index, role)
        if start_index > end_index then
            return false
        end

        local fst_atom = code[start_index]
        local es = entities[fst_atom]
        if not es then return false end

        local state = {
            candidates = es,
            start_index = start_index + 1,
            end_index = end_index
        }

        local fst_entity =
            select_all_iterator(code, entities, state, nil)
        if not fst_entity then return false end

        iter_stack[iter_top + 1] = select_all_iterator
        iter_stack[iter_top + 2] = state
        iter_stack[iter_top + 3] = fst_entity
        iter_stack[iter_top + 4] = end_index + 1
        iter_stack[iter_top + 5] = top
        iter_top = iter_top + 6
        iter_stack[iter_top] = role

        stack[top - role] = fst_entity
        last_entity = fst_entity
        return true
    end

    local function ins_select_one(start_index, end_index, role)
        if start_index > end_index then
            return false
        end

        local fst_atom = code[start_index]
        local es = entities[fst_atom]
        if not es then return false end

        start_index = start_index + 1

        for entity in pairs(es) do
            local succ = true

            for i = start_index, end_index do
                local atom = code[i]
                local es = entity[atom]
                if not es then
                    succ = false
                    break
                end
            end

            if succ then
                code[top - role] = entity
                last_entity = entity
                return true
            end
        end

        return false
    end

    local function ins_react_all(start_index, end_index, role)
        if start_index > end_index then
            return false
        end

        ins_select_all(start_index, end_index, role)

        if registered_react_instructions[start_index] then
            return true
        end
        registered_react_instructions[start_index] = true

        local next_ins_pos = end_index + 1
        local atoms = {}

        local function listener(event, primary)
            for i = 1, #atoms do
                local atom = atoms[i]
                if atom ~= event then
                    local es = entities[atom]
                    if not es or not es[primary] then
                        return false
                    end
                end
            end
            jump(next_ins_pos, p)
            return false
        end

        for i = start_index, end_index do
            local atom = code[i]
            atoms[#atoms + 1] = atom
            set_event_listener(atom, listener)
        end
    end

    local function ins_react_one(start_index, end_index, role)
        if start_index > end_index then
            return false
        end

        local succ = ins_select_one(start_index, end_index, role)
        if succ then return true end

        if registered_react_instructions[start_index] then
            return false
        end
        registered_react_instructions[start_index] = true

        local next_ins_pos = end_index + 1
        local atoms = {}

        local function listener(event, primary)
            for i = 1, #atoms do
                local atom = atoms[i]
                if atom ~= event then
                    local es = entities[atom]
                    if not es or not es[primary] then
                        return false
                    end
                end
            end

            jump(next_ins_pos, p)

            for i = 1, #atoms do
                local atom = atoms[i]
                remove_event_listener(atom, listener)
            end

            return true
        end

        for i = start_index, end_index do
            local atom = code[i]
            atoms[#atoms + 1] = atom
            set_event_listener(atom, listener)
        end
    end

    local function ins_group(start_index, end_index, role)
        local group = {}

        if start_index > end_index then
            last_entity = group
            code[top - role] = group
            return true
        end

        local fst_atom = code[start_index]
        local es = entities[fst_atom]
        if not es then
            last_entity = group
            code[top - role] = group
            return true
        end

        start_index = start_index + 1

        for entity in pairs(es) do
            local succ = true

            for i = start_index, end_index do
                local atom = code[i]
                local es = entities[atom]
                if not es then
                    succ = false
                    break
                end
            end

            if succ then
                group[#group+1] = entity
            end
        end

        last_entity = group
        code[top - role] = group
        return true
    end

    while p <= code_size do
        local ins = code[p]
        local head = ins >> 4

        if head == 0 then
            if ins == INS_SCOPE then
                if top > STACK_MAX_SIZE then
                    error("stack overflow!")
                end
                stack[top + 1] = FAIL_ON_TERMINATED
                stack[top + 2] = 0
                stack[top + 3] = 0
                stack[top + 4] = 0
                top = top + 5
                stack[top] = 0
                p = p + 1
            elseif ins == INS_RETURN then
                top = top - 5
                p = p + 1
            elseif ins == INS_JUMP then
                jump(code[p + 1], p + 2)
            elseif ins == INS_RETRACE then
                local iterator
                local state
                local argument
                local value 

                while true do
                    if iter_top <= iter_bottom then
                        if jump_top ~= 0 then
                            p = jump_stack[jump_top - 3]
                            top = jump_stack[jump_top - 2]
                            entity_top = jump_stack[jump_top - 1]
                            iter_bottom = jump_stack[jump_top]
                            jump_top = jump_top - 4
                        else
                            p = p + 1
                        end
                        break
                    end

                    iterator = iter_stack[iter_top - 5]
                    state = iter_stack[iter_top - 4]
                    local arg_index = iter_top - 3
                    argument = iterator(code, entities, state, iter_stack[arg_index])

                    if argument ~= nil then
                        local retrace_pos = iter_stack[iter_top - 2]
                        local retrace_top = iter_stack[iter_top - 1]
                        local write_offset = iter_stack[iter_top]

                        p = retrace_pos
                        top = retrace_top
                        iter_stack[arg_index] = argument
                        stack[top - write_offset] = argument
                        break
                    end

                    iter_stack[iter_top - 4] = nil
                    iter_top = iter_top - 6
                end
            end
        elseif head == 1 then
            if ins == INS_SET_POLICY then
                stack[top - 4] = code[p + 1]
            end
            p = p + 2
        elseif head == 2 then
            local success

            local role = code[p + 1]
            local atom_count = code[p + 2]
            local start_index = p + 3
            local end_index = start_index + atom_count - 1

            p = end_index + 1

            if ins == INS_CREATE then
                success = ins_create(start_index, end_index, role)
            elseif ins == INS_CREATE_M then
                success = ins_create(start_index, end_index, role)
                if success then
                    entity_top = entity_top + 1
                    entity_stack[entity_top] = last_entity
                end
            elseif ins == INS_SELECT_ALL then
                success = ins_select_all(start_index, end_index, role)
            elseif ins == INS_SELECT_ALL_M then
                success = ins_select_all(start_index, end_index, role)
                if success then
                    entity_top = entity_top + 1
                    entity_stack[entity_top] = last_entity
                end
            elseif ins == INS_SELECT_ONE then
                success = ins_select_one(start_index, end_index, role)
            elseif ins == INS_SELECT_ONE_M then
                success = ins_select_one(start_index, end_index, role)
                if success then
                    entity_top = entity_top + 1
                    entity_stack[entity_top] = last_entity
                end
            elseif ins == INS_REACT_ALL then
            elseif ins == INS_REACT_ALL_M then
            elseif ins == INS_REACT_ONE then
            elseif ins == INS_REACT_ONE_M then
            elseif ins == INS_GROUP then
                success = ins_group(start_index, end_index, role)
            elseif ins == INS_GROUP_M then
                success = ins_group(start_index, end_index, role)
                if success then
                    entity_top = entity_top + 1
                    entity_stack[entity_top] = last_entity
                end
            end

            if not success then
                terminate()
            end
        elseif head == 3 then
            if ins == INS_REFER then
                -- TODO: REFER retracable
                local role = code[p + 1]
                local offset = code[p + 2]
                stack[top - role] = entity_stack[entity_top - offset]
            elseif ins == INS_REFLECT then
                -- TODO: REFLECT retracable
                local role = code[p + 1]
                local reflected_role = code[p + 2]
                stack[top - role] = stack[top - 5 - reflected_role]
            end
            p = p + 3
        elseif head == 4 then
        elseif head == 5 then
            if ins == INS_COLLECT then
                collection[#collection+1] = last_entity
            end
            p = p + 1
        elseif head == 6 then
            if ins == INS_DO then
                submit_action(code[p + 1])
            elseif ins == INS_FORK then
            elseif ins == INS_ASSERT then
                print(check_action(code[p + 1]))
            elseif ins == INS_TRY then
            elseif ins == INS_WAIT then
            end
            p = p + 2
        end
    end
end

return interpreter