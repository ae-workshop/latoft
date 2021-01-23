package.path = package.path..";src/?.lua;src/?/init.lua;"

local object = require("latoft.auxiliary.object")
local compiler = require("latoft.compiler")
local prettyprinter = require("latoft.compiler.prettyprinter")
local interpreter = require("latoft.interpreter")

local phrases = compiler.parse(
    [[Id 'Soclates late idus 'Humanus.
      U 'Humanus casa.
      E 'Soclates mecása.]])
local code = compiler.compile_phrases(phrases)
print(prettyprinter.format(code))
print(object.show(code.atoms))

interpreter.run(code, {
    late = function(env, event, p, _, i, _)
        for atom in env.entity_atoms(i) do
            env.submit_unary_event(atom, p)
        end
    end
})

--[[
输出 =>

(rule 会死
  (select 人))
(add 人 苏格拉底)
(remove 人 苏格拉底)

(exist)
(all)
(no)

(select-1 conam)
(select-2 saeced)
(push)
(refer-1 1)
(select-2 conam)
(predicate limelafa)
(pop)

(push)
(select-1 conam)
(select-2 saeced)

(push)
(ref-1 1)
(select-2 conam)
(predicate limelafa)
(pop)

(predicate pola)
(pop-1)

(select-2 saeced limela)
(assert/2)
(assert/3)
]]