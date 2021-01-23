local parser = {}

local function parser_error(state, message)
    local curr_word = state.current_clause[state.word_index]
    if not curr_word then
        error(("[parser] end of text: %s"):format(message), 0)
    end

    local metadata = curr_word.metadata
    error(("[parser] %s:%s:%s: %s"):format(
        metadata.source_path,
        metadata.line,
        metadata.column,
        message), 0)
end

local function next_sentence(state)
    local text = state.text
    local sentence_index = state.sentence_index

    sentence_index = sentence_index + 1
    local sentence = text[sentence_index]

    if sentence == nil then
        return false
    else
        state.current_sentence = sentence
        state.sentence_index = sentence_index
        state.current_clause = sentence[1]
        state.clause_index = 1
        state.word_index = 1
        return true
    end
end

local function next_clause(state)
    local sentence = state.current_sentence
    local clause_index = state.clause_index

    clause_index = clause_index + 1
    local clause = sentence[clause_index]

    if clause == nil then
        return false
    else
        state.current_clause = clause
        state.clause_index = clause_index
        state.word_index = 1
        return true
    end
end

local function push_position(state)
    local stack = state.stack
    stack[#stack+1] = {
        state.current_sentence,
        state.sentence_index,
        state.current_clause,
        state.clause_index,
        state.word_index
    }
end

local function pop_position(state)
    local stack = state.stack
    local p = stack[#stack]
    stack[#stack] = nil
    return p
end

local function recover_position(state)
    local p = pop_position(state)
    state.current_sentence = p[1]
    state.sentence_index = p[2]
    state.current_clause = p[3]
    state.clause_index = p[4]
    state.word_index = p[5]
end

local function is_clause_end(state)
    return state.word_index > #state.current_clause
end

local function read_many(state, reader)
    local list = {}
    while true do
        local result = reader(state)
        if result == nil then
            break
        end

        list[#list+1] = result

        if is_clause_end(state) then
            if not next_clause(state) then
                break
            end
        end
    end
    return #list > 0 and list or nil
end

local function read_many_in_single_clause(state, reader)
    local list = {}
    while true do
        local result = reader(state)
        if result == nil then
            break
        end

        list[#list+1] = result

        if is_clause_end(state) then
            break
        end
    end
    return #list > 0 and list or nil
end

local function read_word(state, predicate)
    local word_index = state.word_index
    local word = state.current_clause[word_index]
    if word == nil then
        return nil
    end
    if predicate(word) then
        state.word_index = word_index + 1
        return word
    end
end

local function read_noun(state)
    return read_word(state, function(w) return w.type == "noun" end)
end

local function read_artical(state)
    return read_word(state, function(w) return w.type == "artical" end)
end

local function read_verb(state, category)
    return read_word(state,
        function(w)
            return w.type == "verb"
                and w.subtype[1] == category
        end)
end

local function read_predicative(state)
    return read_verb(state, "predicative")
end

local function read_adjective(state)
    return read_verb(state, "adjective")
end

local function read_adverbial(state)
    return read_verb(state, "adverbial")
end

local read_predicative_phrase
local read_adjective_phrase
local read_adverbial_phrase

local function read_noun_phrase(state)
    push_position(state)

    local artical = read_artical(state)
    if artical == nil then
        recover_position(state)
        return nil
    end

    local adjectives = read_many(state, read_adjective)
    local noun = read_noun(state)

    local noun_phrases
    local appositive_nouns

    if noun then
        if noun.subtype[1] == "gerund" then
            noun_phrases = read_many_in_single_clause(state, read_noun_phrase)
        else
            appositive_nouns = read_many(state, read_noun)
        end
    end

    local adjective_phrases = read_many(state, read_adjective_phrase)

    pop_position(state)

    return {
        type = "noun_phrase",
        artical = artical,
        noun = noun,
        noun_phrases = noun_phrases,
        appositive_nouns = appositive_nouns,
        adjectives = adjectives,
        adjective_phrases = adjective_phrases
    }
end

local function combine_arrays(t1, t2)
    if t1 == nil then
        return t2
    elseif t2 == nil then
        return t1
    else
        for i = 1, #t2 do
            t1[#t1+1] = t2[i]
        end
        return t1
    end
end

read_predicative_phrase = function(state)
    push_position(state)

    local adverbial_phrases = read_many(state, read_adverbial_phrase)
    local noun_phrases = read_many(state, read_noun_phrase)
    local adverbials = read_many(state, read_adverbial)

    local verb = read_predicative(state)
    if verb == nil then
        recover_position(state)
        return nil
    end

    local noun_phrases_remain = read_many(state, read_noun_phrase)
    local adverbial_phrases_remain = read_many(state, read_adverbial_phrase)

    pop_position(state)

    return {
        type = "predicative_phrase",
        verb = verb,
        adverbials = adverbials,
        noun_phrases =
            combine_arrays(noun_phrases, noun_phrases_remain),
        adverbial_phrases =
            combine_arrays(adverbial_phrases, adverbial_phrases_remain)
    }
end

local function read_nonpredicative_phrase(state, type, verb_reader)
    push_position(state)

    local verb = verb_reader(state)
    if verb == nil then
        recover_position(state)
        return nil
    end

    local noun_phrases = read_many_in_single_clause(state, read_noun_phrase)
    local adverbial_phrases = read_many_in_single_clause(state, read_adverbial_phrase)

    pop_position(state)

    return {
        type = type,
        verb = verb,
        noun_phrases = noun_phrases,
        adverbials = adverbials,
        adverbial_phrases = adverbial_phrases
    }
end

read_adjective_phrase = function(state)
    return read_nonpredicative_phrase(state, "adjective_phrase", read_adjective)
end

read_adverbial_phrase = function(state)
    return read_nonpredicative_phrase(state, "adverbial_phrase", read_adverbial)
end

local function read_text(state)
    local result = {}

    while true do
        local phrases = read_many(state, read_predicative_phrase)
        if #phrases == 0 then
            parser_error(state, "predicative phrase required")
        end
        if not is_clause_end(state) then
            local ws = {}
            for i = state.word_index, #state.current_clause do
                local w = state.current_clause[i]
                if type(w) == "table" then
                    ws[#ws+1] = w.raw
                else
                    ws[#ws+1] = w
                end
                ws[#ws+1] = " "
            end
            parser_error(state, "unrecognized words found: "..table.concat(ws))
        end
        for i = 1, #phrases do
            result[#result+1] = phrases[i]
        end
        if not next_sentence(state) then
            break
        end
    end

    return result
end

parser.read = function(text)
    if #text == 0 then
        return {}
    end

    return read_text {
        text = text,
        current_sentence = text[1],
        sentence_index = 1,
        current_clause = text[1][1],
        clause_index = 1,
        word_index = 1,
        stack = {}
    }
end

return parser