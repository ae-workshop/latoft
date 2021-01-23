local bytecodes = require("latoft.compiler.bytecodes")

local unpack = table.unpack

local SCOPE_POLICIES = bytecodes.SCOPE_POLICIES
local INSTRUCTIONS = bytecodes.INSTRUCTIONS

local FAIL_ON_COMPLETED  = SCOPE_POLICIES.FAIL_ON_COMPLETED
local FAIL_ON_TERMINATED = SCOPE_POLICIES.FAIL_ON_TERMINATED

local INS_SCOPE        = INSTRUCTIONS.SCOPE
local INS_RETURN       = INSTRUCTIONS.RETURN
local INS_RETRACE      = INSTRUCTIONS.RETRACE
local INS_JUMP         = INSTRUCTIONS.JUMP

local INS_SET_POLICY   = INSTRUCTIONS.SET_POLICY

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

local ARTICAL_INSTRUCTION_MAP = {
    ["ae"] = INS_GROUP,
    ["u"]  = INS_SELECT_ALL,
    ["lu"] = INS_REACT_ALL,
    ["o"]  = INS_SELECT_ONE,
    ["lo"] = INS_REACT_ONE,
    ["id"] = INS_CREATE,
}

local GRAMMATICAL_PREFIX_INSTRUCTION_MAP = {
    ["e"]  = INS_FORK,
    ["te"] = INS_DO,
    ["me"] = INS_ASSERT,
    ["ji"] = INS_TRY,
    ["se"] = INS_WAIT
}

local assembler = {}

local function emit(state, ...)
    local code = state.code
    local ins = {...}
    for i = 1, #ins do
        code[#code+1] = ins[i]
    end
end

local function entity_atom(state, phrase)
    local raw = phrase.raw
    local atoms = state.atoms
    local id = atoms[raw]

    if not id then
        local count = state.atom_count
        state.atom_count = count + 1
        id = count << 2
        atoms[raw] = id
    end

    return id
end

local function raw_action_atom(state, phrase)
    local stem = phrase.stem
    local atoms = state.atoms
    local id = atoms[stem]

    if not id then
        local count = state.atom_count
        state.atom_count = count + 1
        id = count << 2 + 3
        atoms[stem] = id
    end

    return id
end

local function action_atom(state, phrase)
    local id = raw_action_atom(state, phrase)
    if phrase.subtype[2] == "passive" then
        return id + 1
    end
    return id
end

local function register_entity(state, phrase)
    local entities = state.entities
    local phrase_art = phrase.artical

    local reference = {
        instruction_index = #state.code + 1,
        count = 0
    }
    entities[#entities+1] = {
        artical = phrase_art,
        noun = phrase.noun,
        reference = reference
    }

    local appositive_nouns = phrase.appositive_nouns
    if appositive_nouns then
        for i = 1, #appositive_nouns do
            local app_noun = appositive_nouns[i]
            entities[#entities+1] = {
                artical = phrase_art,
                noun = app_noun,
                reference = reference
            }
        end
    end
end

local function check_reference_valid(referred_artical, referring_artical)
    local referred_art = referred_artical.stem
    local referring_art = referring_artical.stem
    
    if referred_art == "ae" then
        -- plural
        return referring_art == "di"
            or referring_art == "do"
    else
        -- singular
        return referring_art == "e"
            or referring_art == "a"
    end
end

local function do_reference(state, entity, phrase)
    local code = state.code
    local reference = entity.reference
    local ref_count = reference.count
    reference.count = ref_count + 1

    local index

    if ref_count == 0 then
        local ins_index = reference.instruction_index
        code[ins_index] = code[ins_index] + 1

        index = state.refered_entity_count + 1
        state.refered_entity_count = index
        reference.index = index
    else
        index = reference.index
    end

    local role = phrase.artical.subtype[2]
    emit(state, INS_REFER, role - 1,
        state.refered_entity_count - index)
    return true
end

local function refer_entity(state, phrase)
    local entities = state.entities
    local phrase_art = phrase.artical
    local phrase_noun = phrase.noun
    
    if not phrase_noun then
        local last_entity = entities[#entities]
        if check_reference_valid(last_entity.artical, phrase_art) then
            return do_reference(state, last_entity, phrase)
        end
    end

    for i = #entities, 1, -1 do
        local entity = entities[i]
        if entity.noun and entity.noun.raw == phrase_noun.raw
            and check_reference_valid(entity.artical, phrase_art) then
            return do_reference(state, entity, phrase)
        end
    end

    return false
end

local build_predicate_phrase
local build_nonpredicate_phrase

local function build_noun_phrase(state, phrase)
    local atoms = {}

    local appositive_nouns = phrase.appositive_nouns
    if appositive_nouns then
        for i = 1, #appositive_nouns do
            atoms[#atoms+1] = entity_atom(state, appositive_nouns[i])
        end
    end

    local adjectives = phrase.adjectives
    if adjectives then
        for i = 1, #adjectives do
            atoms[#atoms+1] = action_atom(state, adjectives[i])
        end
    end

    if #atoms > 255 then
        error("atoms > 255")
    end

    local artical = phrase.artical
    local adjective_default_ins = INS_ASSERT

    if artical.definiteness == "definitive" then
        if not refer_entity(state, phrase) then
            error("invalid reference: "..phrase.noun.raw)
        end
        if #atoms > 0 then
            emit(state, INS_GUARD, #atoms, unpack(atoms))
        end
    else
        local noun = phrase.noun
        if noun then
            atoms[#atoms+1] = entity_atom(state, noun)
        end

        local instruction
        local stem = artical.stem
            
        if stem == "ei" then
            emit(state, INS_SET_POLICY, FAIL_ON_COMPLETED)
            instruction = INS_SELECT_ONE
        elseif artical.definiteness == "indefinitive" then
            instruction = ARTICAL_INSTRUCTION_MAP[stem]
            if stem == "id" then
                adjective_default_ins = INS_DO
            end
        end

        register_entity(state, phrase)
        local argument_num = artical.subtype[2]
        emit(state, instruction, argument_num - 1, #atoms, unpack(atoms))
    end

    local adjective_phrases = phrase.adjective_phrases
    if adjective_phrases then
        for i = 1, #adjective_phrases do
            build_nonpredicate_phrase(
                state, adjective_phrases[i], adjective_default_ins)
        end
    end

    if artical.is_query then
        emit(state, INS_COLLECT)
    end
end

local function raw_build_verb_phrase(state, instruction, phrase)
    local adverbial_phrases = phrase.adverbial_phrases
    if adverbial_phrases then
        for i = 1, #adverbial_phrases do
            build_nonpredicate_phrase(
                state, adverbial_phrases[i], INS_DO)
        end
    end

    local noun_phrases = phrase.noun_phrases
    if noun_phrases then
        for i = 1, #noun_phrases do
            build_noun_phrase(state, noun_phrases[i])
        end
    end

    emit(state, instruction,
        raw_action_atom(state, phrase.verb))
end

local function get_verb_instruction(phrase, default_instruction)
    local instruction
    local prefix = phrase.verb.prefix
    return not prefix
        and default_instruction
        or GRAMMATICAL_PREFIX_INSTRUCTION_MAP[prefix]
end

build_predicate_phrase = function(state, phrase)
    local ins = get_verb_instruction(phrase, INS_DO)
    if not ins then return end

    emit(state, INS_SCOPE)
    raw_build_verb_phrase(state, ins, phrase)
    emit(state, INS_RETURN)
end

build_nonpredicate_phrase = function(state, phrase, default_instruction)
    local ins = get_verb_instruction(phrase, default_instruction)
    if not ins then return end

    local reflective = true
    local noun_phrases = phrase.noun_phrases

    if noun_phrases then
        for i = 1, #noun_phrases do
            local noun = noun_phrases[i]
            if noun.artical.subtype[2] == 1 then
                reflective = false
                break
            end
        end
    end

    emit(state, INS_SCOPE)
    if reflective then
        emit(state, INS_REFLECT,
            phrase.verb.subtype[2] == "active" and 0 or 1)
    end
    raw_build_verb_phrase(state, ins, phrase)
    emit(state, INS_RETURN)
end

assembler.build = function(phrases)
    local state = {
        code = {},
        atoms = {},
        atom_count = 0,
        entities = {},
        refered_entity_count = 0
    }

    for i = 1, #phrases do
        build_predicate_phrase(state, phrases[i])
    end

    emit(state, INS_RETRACE)

    local code = state.code
    local atoms = {}
    for k, v in pairs(state.atoms) do
        atoms[v] = k
    end
    code.atoms = atoms

    return code
end

return assembler