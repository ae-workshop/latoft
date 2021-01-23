local tokenizer = require("latoft.compiler.tokenizer")
local parser = require("latoft.compiler.parser")
local assembler = require("latoft.compiler.assembler")

local compiler = {}

compiler.parse = function(source, source_path)
    local text = tokenizer.read(source, source_path)
    return parser.read(text)
end

compiler.parse_file = function(source, source_path)
    local text = tokenizer.read_file(source, source_path)
    return parser.read(text)
end

compiler.compile = function(source, source_path)
    local text = tokenizer.read(source, source_path)
    local phrases = parser.read(text)
    return assembler.build(phrases)
end

compiler.compile_file = function(file_path)
    local text = tokenizer.read_file(file_path)
    local phrases = parser.read(text)
    return assembler.build(phrases)
end

compiler.compile_phrases = function(phrases)
    return assembler.build(phrases)
end

return compiler