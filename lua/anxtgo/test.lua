-- Pure-lua test suite for the anxtgo ranker.
-- Run with:  lua5.4 lua/anxtgo/test.lua   (from the repo root)
-- or:        just test

local dir = (arg[0] or ""):match("(.*/)") or "./"
local anxtgo = dofile(dir .. "init.lua")
local Section = anxtgo.Section

-- --------------------------------------------------------------------------
-- tiny test harness
-- --------------------------------------------------------------------------
local passed, failed = 0, 0

local function eq(actual, expected, msg)
    if actual == expected then
        passed = passed + 1
    else
        failed = failed + 1
        io.write(("FAIL: %s\n  expected: %q\n  actual:   %q\n"):format(
            msg or "", tostring(expected), tostring(actual)))
    end
end

local function ok(cond, msg)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        io.write(("FAIL: %s\n"):format(msg or ""))
    end
end

-- --------------------------------------------------------------------------
-- Section.name
-- --------------------------------------------------------------------------
eq(Section.new("Meta\n\nplaceholder\n").name and Section.new("Meta\n\nx"):name(),
    "Meta", "name: plain title")
eq(Section.new("   0  50% | abc\n\nbody"):name(), "abc", "name: managed title takes part after | ")
eq(Section.new(" Some Title \n\nbody"):name(), "Some Title", "name: trims plain title")
eq(Section.new("a | b | c\n\nbody"):name(), "a | b | c"
    and Section.new("a | b | c\n\nbody"):name(), "a | b | c", "name: 3 parts falls back to whole-first")

-- the >2 parts case actually returns trim(parts[1]) where parts[1] is "a"
eq(Section.new("a | b | c\nbody"):name(), "a", "name: >2 pipe parts -> first segment")

-- --------------------------------------------------------------------------
-- isSpecial
-- --------------------------------------------------------------------------
ok(Section.new("Meta\nx"):isSpecial(), "isSpecial: Meta")
ok(Section.new("Archive\nx"):isSpecial(), "isSpecial: Archive")
ok(Section.new("X\nx"):isSpecial(), "isSpecial: X")
ok(not Section.new("  0  50% | abc\nx"):isSpecial(), "isSpecial: ranked is not special")

-- --------------------------------------------------------------------------
-- computeRank / counts / shares
-- --------------------------------------------------------------------------
local s = Section.new("t | x\n\nnotes\n\n===\n\n- a\n+ b\n+ c\n\n")
s:computeRank()
eq(s.negCount, 1, "computeRank: neg count")
eq(s.posCount, 2, "computeRank: pos count")
eq(s.rank, 1, "computeRank: rank = pos - neg")
eq(s:count(), 3, "count")
ok(math.abs(s:posShare() - 2 / 3) < 1e-9, "posShare")
ok(math.abs(s:negShare() - 1 / 3) < 1e-9, "negShare")

-- lines not starting with +/- are ignored
local s2 = Section.new("t | y\n\n===\n\nsome note\n+ done\n- not done\nmidline + ignore\n")
s2:computeRank()
eq(s2.posCount, 1, "computeRank: ignores non +/- lines (pos)")
eq(s2.negCount, 1, "computeRank: ignores non +/- lines (neg)")

-- empty share guard (no log lines -> no div by zero crash)
local s3 = Section.new("t | z\n\n===\n\n\n")
s3:computeRank()
eq(s3:posShare(), 0, "posShare: zero when no entries")
eq(s3:toString(), "{{{   0   0% | z\n\n===\n\n}}}", "toString: zero-entry section renders 0 / 0%")

-- --------------------------------------------------------------------------
-- toString formatting (3-wide rank and percent, leading spaces)
-- --------------------------------------------------------------------------
local r = Section.new("old | abc\n\nnotes\n\n===\n\n+ a\n- b\n")
r:computeRank()
eq(r:toString(), "{{{   0  50% | abc\n\nnotes\n\n===\n\n+ a\n- b\n\n}}}",
    "toString: ranked section formatting")

-- special sections keep just their name as the title
local meta = Section.new("Meta\n\nplaceholder\n\n")
eq(meta:toString(), "{{{ Meta\n\nplaceholder\n\n}}}", "toString: special section")

-- negative rank widths
local neg = Section.new("t | q\n\n===\n\n- a\n- b\n- c\n")
neg:computeRank()
eq(neg:toString(), "{{{  -3   0% | q\n\n===\n\n- a\n- b\n- c\n\n}}}",
    "toString: negative rank padding")

-- --------------------------------------------------------------------------
-- get_sections
-- --------------------------------------------------------------------------
local secs = anxtgo.get_sections("{{{ a\nx }}}\n\n{{{ b\ny }}}")
eq(#secs, 2, "get_sections: count")
eq(secs[1]:name(), "a", "get_sections: first name")
eq(secs[2]:name(), "b", "get_sections: second name")

-- --------------------------------------------------------------------------
-- process: ordering (specials first, then ranked ascending) + reordering
-- --------------------------------------------------------------------------
local input = table.concat({
    "{{{ Meta\n\nm\n\n}}}",
    "{{{ old | high\n\n===\n\n+ a\n+ b\n+ c\n\n}}}", -- rank +3
    "{{{ old | low\n\n===\n\n- a\n- b\n\n}}}",       -- rank -2
    "{{{ old | mid\n\n===\n\n+ a\n- b\n\n}}}",       -- rank 0
}, "\n\n")

local out = anxtgo.process(input)
local order = {}
for cap in out:gmatch("{{{([^{}]+)}}}") do
    order[#order + 1] = Section.new(cap):name()
end
eq(table.concat(order, ","), "Meta,low,mid,high",
    "process: specials first then ranked ascending by score")

-- idempotency: processing an already-processed buffer is stable
eq(anxtgo.process(out), out, "process: idempotent")

-- --------------------------------------------------------------------------
-- process: vim modelines outside sections are preserved
-- --------------------------------------------------------------------------
local ml_input = table.concat({
    "<!-- vim: set foldmethod=marker: -->",
    "",
    "{{{ old | a\n\n===\n\n+ x\n\n}}}",
}, "\n")
local ml_out = anxtgo.process(ml_input)
ok(ml_out:find("<!-- vim: set foldmethod=marker: -->", 1, true) == 1,
    "process: leading modeline kept on top")
eq(anxtgo.process(ml_out), ml_out, "process: leading modeline idempotent")

-- trailing modeline stays at the bottom
local ft_input = "{{{ old | a\n\n===\n\n+ x\n\n}}}\n\n# vim: set ft=markdown :"
local ft_out = anxtgo.process(ft_input)
ok(ft_out:find("# vim: set ft=markdown :", 1, true) ~= nil,
    "process: trailing modeline kept")
ok(ft_out:sub(-#"# vim: set ft=markdown :") == "# vim: set ft=markdown :",
    "process: trailing modeline at bottom")
eq(anxtgo.process(ft_out), ft_out, "process: trailing modeline idempotent")

-- non-modeline stray text outside sections is still dropped
local stray = anxtgo.process("just a note\n\n{{{ old | a\n\n===\n\n+ x\n\n}}}")
ok(stray:find("just a note", 1, true) == nil,
    "process: non-modeline stray text still dropped")

-- --------------------------------------------------------------------------
-- process on the real sample.md
-- --------------------------------------------------------------------------
local sf = io.open(dir .. "../../sample.md", "r")
if sf then
    local sample = sf:read("*a")
    sf:close()
    local processed = anxtgo.process(sample)
    ok(processed:find("{{{ Meta", 1, true) ~= nil, "sample: keeps Meta")
    ok(processed:find("{{{ X", 1, true) ~= nil, "sample: keeps X")
    ok(processed:find("  0  50%% | abc") ~= nil, "sample: abc scored 0 / 50%")
    ok(processed:find("  1  67%% | def") ~= nil, "sample: def scored 1 / 67%")
    eq(anxtgo.process(processed), processed, "sample: process is idempotent")
end

-- --------------------------------------------------------------------------
io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
