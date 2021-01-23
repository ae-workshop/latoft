local byte = string.byte
local char = string.char
local sub = string.sub
local gsub = string.gsub
local lower = string.lower
local unpack = table.unpack
local concat = table.concat

local tokenizer = {}

local BYTE_COMMA        = byte(",")
local BYTE_FULL_STOP    = byte(".")
local BYTE_LIST_START   = byte("[")
local BYTE_LIST_END     = byte("]")
local BYTE_STRING_START = byte("\"")
local BYTE_STRING_END   = byte("\"")

local RESERVED_CHARACTERS = {
    [BYTE_COMMA]        = true,
    [BYTE_FULL_STOP]    = true,
    [BYTE_LIST_START]   = true,
    [BYTE_LIST_END]     = true,
    [BYTE_STRING_START] = true,
    [BYTE_STRING_END]   = true,
    [0]                 = true
}

local BYTE_ESCAPE = byte("\\")

local RAW_ESCAPE_TABLE = {
    a = "\a", b = "\b", f = "\f", n = "\n",
    r = "\r", t = "\t", v = "\v",
    ["\\"] = "\\", ["0"] = "\0", [" "] = " ",
    ["\""] = "\"",
    ["["] = "[", ["]"] = "]"
}

local RAW_UNESCAPE_TABLE = {}
for k, v in pairs(RAW_ESCAPE_TABLE) do
    RAW_UNESCAPE_TABLE[v] = "\\"..k
end

local ESCAPE_TABLE = {}
for k, v in pairs(RAW_ESCAPE_TABLE) do
    ESCAPE_TABLE[byte(k)] = byte(v)
end

local BYTE_SPACE = byte(" ")
local BYTE_TAB   = byte("\t")
local BYTE_LF    = byte("\n")

local WHITE_CHARACTERS = {
    [BYTE_SPACE] = true,
    [BYTE_TAB]   = true,
    [BYTE_LF]    = true
}

local BYTE_A = byte("a")
local BYTE_O = byte("o")
local BYTE_U = byte("u")
local BYTE_E = byte("e")
local BYTE_I = byte("i")

local VOWELS = {
    [BYTE_A] = true,
    [BYTE_O] = true,
    [BYTE_U] = true,
    [BYTE_E] = true,
    [BYTE_I] = true
}

local ACCENT_VOWELS= {
    -- Á á
    [193] = BYTE_A,
    [225] = BYTE_A,
    -- Ó ó
    [211] = BYTE_O,
    [243] = BYTE_O,
    -- Ú ú
    [218] = BYTE_U,
    [250] = BYTE_U,
    -- É é
    [201] = BYTE_E,
    [233] = BYTE_E,
    -- Í í
    [205] = BYTE_I,
    [237] = BYTE_I
}

local BYTE_ACCENT_MARK = byte("'")
local BYTE_PROPER_NOUN_MARK = byte("'")

local PRONOUNS = {
    ["na"]  = "1s",
    ["nei"] = "1p",
    ["le"]  = "2s",
    ["lui"] = "2p",
    ["mo"]  = "3s",
    ["meu"] = "3p"
}

local DEFINITIVE_ARTICALS = {
    ["e"]  = {"this", 1},
    ["di"] = {"these", 1},
    ["a"]  = {"that", 1},
    ["do"] = {"those", 1}
}

local ARTICALS = {
    ["e"]  = {"this", 1},
    ["di"] = {"these", 1},
    ["a"]  = {"that", 1},
    ["do"] = {"those", 1},

    ["ae"] = {"all", 1},
    ["u"]  = {"each", 1},
    ["lu"] = {"each in all time", 1},
    ["o"]  = {"exist", 1},
    ["lo"] = {"exist in all time", 1},
    ["ei"] = {"no", 1},
    ["id"] = {"new", 1}
}

local ARTICAL_QUERY_POSTFIXES = {
    ["g"] = true,
    ["ag"] = true,
    ["ng"] = true,
    ["eng"] = true,
    ["gs"] = true,
    ["ugs"] = true,
    ["gt"] = true,
    ["agt"] = true
}

local function conjugate_articals(articals)
    local conjugated = {}
    for art, desc in pairs(articals) do
        local last_byte = byte(art, #art)
        if VOWELS[last_byte] then
            conjugated[art.."n"] = {desc[1], 2, "n"}
            conjugated[art.."s"] = {desc[1], 3, "s"}
            conjugated[art.."t"] = {desc[1], 4, "t"}

            conjugated[art.."g"]  = {desc[1], 1, "g"}
            conjugated[art.."ng"] = {desc[1], 2, "ng"}
            conjugated[art.."gs"] = {desc[1], 3, "gs"}
            conjugated[art.."gt"] = {desc[1], 4, "gt"}
        else
            conjugated[art.."en"] = {desc[1], 2, "en"}
            conjugated[art.."us"] = {desc[1], 3, "us"}
            conjugated[art.."at"] = {desc[1], 4, "at"}

            conjugated[art.."ag"]  = {desc[1], 1, "ag"}
            conjugated[art.."eng"] = {desc[1], 2, "eng"}
            conjugated[art.."ugs"] = {desc[1], 3, "ugs"}
            conjugated[art.."agt"] = {desc[1], 4, "agt"}
        end
    end

    for art, desc in pairs(conjugated) do
        articals[art] = desc
    end
end

conjugate_articals(DEFINITIVE_ARTICALS)
conjugate_articals(ARTICALS)

local LEXICAL_ASPECT_MARKS = {
    ["a"]  = {"dynamic", "atelic", "durative"},
    ["ae"] = {"dynamic", "atelic", "punctual"},
    ["o"]  = {"dynamic", "telic", "durative"},
    ["oe"] = {"dynamic", "telic", "punctual"},
    ["e"]  = {"static", "atelic", "durative"},
    ["ei"] = {"static", "atelic", "punctual"},
    ["i"]  = {"static", "telic", "durative"},
    ["ie"] = {"static", "telic", "punctual"}
}

local GRAMMATICAL_ASPECT_MARKS = {
    ["e"]  = "empirical",
    ["a"]  = "predetermined",
    ["i"]  = "initial",
    ["o"]  = "progressive",
    ["u"]  = "perfective",
    ["uo"] = "satisfactory",
    ["ue"] = "continuous",
    ["iu"] = "repetitive"
}

local GRAMMATICAL_PREFIXES = {
    ["hi"] = "reason",
    ["va"] = "result",
    ["me"] = "condition",
    ["pu"] = "purpose",
    ["de"] = "theme",
    ["e"]  = "apposition",
    ["te"] = "adversative",
    ["vi"] = "synonym",
    ["se"] = "parrallel"
}

local LEXICAL_PREFIXES = {
    ["a"]    = "accomplished",
    ["ju"]   = "defective",
    ["bi"]   = "negative",
    ["ga"]   = "opposite",
    ["si"]   = "analogous",
    ["zu"]   = "posterior",
    ["gi"]   = "transcendental",
    ["cu"]   = "reflexive",
    ["cuta"] = "voluntary",
    ["pa"]   = "mutual",
    ["di"]   = "half",
    ["en"]   = "singular",
    ["mo"]   = "dual",
    ["sta"]  = "trial",
    ["mu"]   = "plural",
    ["na"]   = "repeat",
    ["ho"]   = "common",
    ["o"]    = "greator",
    ["li"]   = "smaller",
    ["so"]   = "orignal",
    ["lu"]   = "convergent",
    ["ca"]   = "separative",
    ["fla"]  = "transfering",
    ["la"]   = "forward",
    ["ce"]   = "backward"
}

local GRAMMATICAL_POSTFIXES = {
    -- predicative verb

    ["n"]   = {"predicative", "active", 1},
    ["s"]   = {"predicative", "active", 2},
    ["sai"] = {"predicative", "active", 2, "honorific"},
    [0]     = {"predicative", "active", 3},
    ["tai"] = {"predicative", "active", 3, "honorific"},

    ["ni"] = {"predicative", "passive", 1},
    ["si"] = {"predicative", "passive", 2},
    ["ti"] = {"predicative", "passive", 3},

    ["nu"] = {"predicative", "employment", 1},
    ["su"] = {"predicative", "employment", 2},
    ["tu"] = {"predicative", "employment", 3},

    -- infinitive verb

    ["ta"]  = {"adverbial", "active"},
    ["ten"] = {"adverbial", "passive"},
    ["tit"] = {"adverbial", "employment"},

    ["fa"]  = {"adjective", "active"},
    ["fen"] = {"adjective", "passive"},
    ["fit"] = {"adjective", "employment"},

    -- gerund

    ["nga"]  = {"gerund", "active"},
    ["ngen"] = {"gerund", "passive"},
    ["ngit"] = {"gerund", "employment"},

    -- semantic role

    ["nt"] = {"role", "agent"},
    ["fi"] = {"role", "patient"},
    ["m"]  = {"role", "experiencer"},
    ["d"]  = {"role", "scene"},
    ["ft"] = {"role", "measure"},
    ["vz"] = {"role", "outcome"},
    ["g"]  = {"role", "depletion"}
}

local NOUN_POSTFIXES = {
    ["nga"]  = {"gerund", "active"},
    ["ngen"] = {"gerund", "passive"},
    ["ngit"] = {"gerund", "employment"},

    ["nt"] = {"role", "agent"},
    ["fi"] = {"role", "patient"},
    ["m"]  = {"role", "experiencer"},
    ["d"]  = {"role", "scene"},
    ["ft"] = {"role", "measure"},
    ["vz"] = {"role", "outcome"},
    ["g"]  = {"role", "depletion"}
}

local function tokenizer_error(state, message)
    error(("[tokenizer] %s:%s:%s: %s"):format(
        state.source_path,
        state.line,
        state.column,
        message), 0)
end

local function assert_index_valid(source, state)
    if state.index > #source then
        tokenizer_error(state, "end of source")
    end
end

local function transform_source(str)
    local cs = {}
    for i, c in utf8.codes(str) do
        local vowel_byte = ACCENT_VOWELS[c]
        if vowel_byte then
            for j = #cs, 1, -1 do
                local pc = cs[j]
                if ESCAPE_TABLE[pc] then
                    break
                elseif VOWELS[pc] then
                    for k = #cs, j + 1, -1 do
                        cs[k+1] = cs[k]
                    end
                    cs[j+1] = BYTE_ACCENT_MARK
                    break
                end
            end
            cs[#cs+1] = vowel_byte
        else
            cs[#cs+1] = c
        end
    end
    return utf8.char(unpack(cs))
end

local function read_byte(source, state)
    local index = state.index
    local cb = byte(source, index)
    if cb == nil then return nil end

    if cb == BYTE_LF then
        state.line = state.line + 1
        state.column = 1
    else
        state.column = state.column + 1
    end

    state.index = index + 1
    return cb
end

local function try_byte(source, state, cb)
    local sb = byte(source, state.index)
    if sb ~= cb then
        return nil
    else
        return read_byte(source, state)
    end
end

local function close_with_byte(source, state, cb)
    local sb = byte(source, state.index)
    if sb == nil then
        tokenizer_error(state, ("end of source ('%s' expected)")
            :format(char(cb)))
    elseif sb ~= cb then
        return nil
    else
        return read_byte(source, state)
    end
end

local function skip_white(source, state)
    while true do
        local cb = byte(source, state.index)
        if cb == nil or not WHITE_CHARACTERS[cb] then
            return
        end
        read_byte(source, state)
    end
end

local function parse_numeric_escape(source, state)
    local cb1 = byte(source, index)
    local cb2 = byte(source, index + 1)
    local cb3 = byte(source, index + 2)

    error("TODO")
end

local function read_character_byte(source, state)
    local cb = read_byte(source, state)
    if cb == nil then return nil end

    if cb == BYTE_ESCAPE then
        local escape_head = read_byte(source, state)
        if escape_head == nil then
            tokenizer_error(state, "end of source (escape character expected)")
        end
        return ESCAPE_TABLE[escape_head]
            or parse_numeric_escape(source, state)
    end

    return cb
end

local function read_string(source, state)
    if not try_byte(source, state, BYTE_STRING_START) then
        return nil
    end

    local cs = {}
    while true do
        if close_with_byte(source, state, BYTE_STRING_END) then
            break
        end
        cs[#cs+1] = read_character_byte(source, state)
    end
    return char(unpack(cs))
end

local function read_list(source, state, element_reader)
    if not try_byte(source, state, BYTE_LIST_START) then
        return nil
    end

    local es = {}
    while true do
        if close_with_byte(source, state, BYTE_LIST_END) then
            break
        end
        es[#es+1] = element_reader(source, state)
    end
    return es
end

local function read_letters(source, state)
    local cs = {}

    while true do
        local cb = byte(source, state.index)
        if cb == nil or WHITE_CHARACTERS[cb] or RESERVED_CHARACTERS[cb] then
            break
        end
        cs[#cs+1] = cb
        read_byte(source, state)
    end

    return #cs > 0 and char(unpack(cs))
end

local function get_prefix(str, state)
    local cb
    local cs = {}
    local index = 1

    for index = 1, #str do
        cb = byte(str, index)
        if cb == BYTE_ACCENT_MARK then
            break
        end
        cs[index] = cb
    end

    if cb ~= BYTE_ACCENT_MARK or #cs == 0 then
        return nil
    end

    local prefix = char(unpack(cs))
    if not GRAMMATICAL_PREFIXES[prefix] then
        if not LEXICAL_PREFIXES[prefix] then
            tokenizer_error(state, "invalid prefix: "..prefix)
        end
        return nil
    end
    return prefix
end

local function get_postfix(str, state)
    local candidate
    local candidate_desc

    local acc = ""
    local prev_cb
    local cb

    for i = #str, 1, -1 do
        cb = byte(str, i)
        acc = char(cb)..acc

        local desc = GRAMMATICAL_POSTFIXES[acc]
        if desc and VOWELS[byte(str, i - 1)] then
            candidate = acc
            candidate_desc = desc
        end
    end

    return candidate, candidate_desc
end

local function deconstruct_stem(stem, state)
    local root_lhs = ""
    local root_rhs = ""
    local lexical_aspect = ""
    local grammatical_aspect = ""

    local cb
    local i = #stem

    if not VOWELS[byte(stem, i)] then
        tokenizer_error(state, "invalid stem: "..stem)
    end

    while i > 0 do
        cb = byte(stem, i)
        if not VOWELS[cb] then break end
        grammatical_aspect =
            char(cb)..grammatical_aspect
        i = i - 1
    end

    if #grammatical_aspect == 0 then
        tokenizer_error(state, "grammatical aspect required")
    elseif not GRAMMATICAL_ASPECT_MARKS[grammatical_aspect] then
        tokenizer_error(state, "invalid grammatical aspect: "
            ..grammatical_aspect)
    end

    while i > 0 do
        cb = byte(stem, i)
        if VOWELS[cb] then break end
        root_rhs = char(cb)..root_rhs
        i = i - 1
    end

    if #root_rhs == 0 then
        tokenizer_error(state, "root required")
    end

    while i > 0 do
        cb = byte(stem, i)
        if not VOWELS[cb] then break end
        lexical_aspect =
            char(cb)..lexical_aspect
        i = i - 1
    end

    if #lexical_aspect == 0 then
        tokenizer_error(state, "lexical aspect required")
    elseif not LEXICAL_ASPECT_MARKS[lexical_aspect] then
        tokenizer_error(state, "invalid lexical aspect: "
            ..lexical_aspect)
    end

    while i > 0 do
        cb = byte(stem, i)
        if VOWELS[cb] then break end
        root_lhs = char(cb)..root_lhs
        i = i - 1
    end

    if #root_lhs == 0 then
        tokenizer_error(state, "root required")
    end

    return sub(stem, 1, i)..root_lhs.."."..root_rhs..".",
        lexical_aspect, grammatical_aspect
end

local function read_word(source, state)
    local raw = read_letters(source, state)
    if not raw then return nil end

    local word_cache = state.word_cache
    local cache = word_cache[raw]
    if cache then
        return cache
    end

    local w = {
        metadata = {
            source_path = state.source_path,
            index = state.index,
            line = state.line,
            column = state.column
        }
    }

    if byte(raw, 1) == BYTE_PROPER_NOUN_MARK then
        w.type = "noun"
        w.subtype = "proper"
        w.raw = raw
        w.stem = sub(raw, 2)
        word_cache[raw] = w
        return w
    end

    raw = lower(raw)
    w.raw = raw
    word_cache[raw] = w

    if PRONOUNS[raw] then
        w.type = "noun"
        w.subtype = "pronoun"
        w.stem = raw
        return w
    end

    local art_desc = ARTICALS[raw]
    if art_desc then
        w.type = "artical"
        w.subtype = art_desc
        w.definiteness = DEFINITIVE_ARTICALS[raw]
            and "definitive" or "indefinitive"

        local postfix = art_desc[3]
        if postfix then
            w.postfix = postfix
            w.stem = sub(raw, 1, #raw - #postfix)
            w.is_query = ARTICAL_QUERY_POSTFIXES[postfix]
        else
            w.stem = raw
        end
        return w
    end

    local num = tonumber(raw)
    if num then
        w.type = "noun"
        w.subtype = "number"
        w.number = num
        return w
    end

    local prefix = get_prefix(raw, state)
    if prefix then
        w.prefix = prefix
        raw = sub(raw, #prefix + 2)
    end
    
    local postfix, desc = get_postfix(raw, state)
    if postfix then
        w.postfix = postfix
        raw = sub(raw, 1, #raw - #postfix)
        w.stem = raw
        w.subtype = desc

        if NOUN_POSTFIXES[postfix] then
            w.type = "noun"
        else
            w.type = "verb"
        end
    else
        w.type = "verb"
        w.stem = raw
        w.subtype = GRAMMATICAL_POSTFIXES[0]
    end

    local root, la, ga = deconstruct_stem(raw, state)
    w.root = root
    w.lexical_aspect = la
    w.grammatical_aspect = ga

    return w
end

local function read_sentence(source, state)
    local clause = {}
    local sentence = {
        type = "sentence",
        clause
    }

    while true do
        skip_white(source, state)

        if close_with_byte(source, state, BYTE_FULL_STOP) then
            break
        elseif close_with_byte(source, state, BYTE_COMMA) then
            if #clause ~= 0 then
                clause = {}
                sentence[#sentence+1] = clause
            end
        else
            clause[#clause+1] =
                read_word(source, state)
                or read_string(source, state)
                or read_list(source, state, read_sentence)
                or tokenizer_error(state,
                    "unrecorgnized character"..byte(source, state.index))
        end
    end

    if #sentence == 1 and #clause == 0 then
        return nil
    end

    return sentence
end

local function read_text(source, state)
    local text = {
        type = "text"
    }
    
    while true do
        skip_white(source, state)

        if state.index > #source then
            break
        end

        text[#text+1] = read_sentence(source, state)
    end

    return text
end

tokenizer.read = function(source, source_path)
    return read_text(transform_source(source), {
        index = 1,
        line = 1,
        column = 1,
        source_path = source_path or "[source]",
        word_cache = {}
    })
end

tokenizer.read_file = function(file_path)
    local src = io.open(file_path):read("*a")
    return tokenizer.read(src, file_path)
end

return tokenizer