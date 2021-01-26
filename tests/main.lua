package.path = package.path..";src/?.lua;src/?/init.lua;"

local object = require("latoft.auxiliary.object")
local compiler = require("latoft.compiler")
local prettyprinter = require("latoft.compiler.prettyprinter")
local interpreter = require("latoft.runtime.interpreter")

local phrases = compiler.parse(
    [[Id 'Soclates latede idus 'Humanus.
      U 'Humanus coesade.
      E 'Soclates me'coesade.]])

local code = compiler.compile_phrases(phrases)
print(prettyprinter.format(code))
print(object.show(code.atoms))

local late_id = code.atoms["late"]

interpreter.run(code, function(env, event, control, p, s, i, pe)
    if event == late_id then
        for target, mark in env.targets(i) do
            env.set_entity(p, target, mark)
        end
    end
    return true
end)