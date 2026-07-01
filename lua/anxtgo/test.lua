-- Pure-lua test suite for the anxtgo ranker.
-- Run with:  lua5.4 lua/anxtgo/test.lua   (from the repo root)
-- or:        just test

local dir = (arg[0] or ""):match("(.*/)") or "./"
local anxtgo = dofile(dir .. "init.lua")
local Section = anxtgo.Section

-- split a string into a list of lines (test-side helper; the plugin works on
-- the buffer's line array directly)
local function to_lines(s)
    local lines = {}
    for line in (s .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line
    end
    return lines
end

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

-- streaks: current streak counts from the most recent (first) log line and is
-- signed; longest positive is the longest run of consecutive + anywhere
local st = Section.new("t | s\n\n===\n\n+ a\n+ b\n+ c\n- d\n+ e\n")
st:computeRank()
eq(st.curStreak, 3, "curStreak: leading +++ -> +3")
eq(st.longestPos, 3, "longestPos: best run of + is 3")

local stn = Section.new("t | s\n\n===\n\n- a\n- b\n+ c\n+ d\n+ e\n+ f\n")
stn:computeRank()
eq(stn.curStreak, -2, "curStreak: leading -- -> -2")
eq(stn.longestPos, 4, "longestPos: trailing run of 4 +")

local ste = Section.new("t | s\n\n===\n\n")
ste:computeRank()
eq(ste.curStreak, 0, "curStreak: no entries -> 0")
eq(ste.longestPos, 0, "longestPos: no entries -> 0")

-- empty share guard (no log lines -> no div by zero crash)
local s3 = Section.new("t | z\n\n===\n\n\n")
s3:computeRank()
eq(s3:posShare(), 0, "posShare: zero when no entries")
eq(s3:statsLines()[1], "all 0% ★0 ↑0", "statsLines: zero-entry renders 0% / ★0")
eq(#s3:statsLines(), 1, "statsLines: no dated logs -> only the total line")

-- --------------------------------------------------------------------------
-- statsLines: each row carries % and record (★); undated logs -> no months, so
-- the current streak lives on the "all" row as a fallback
-- --------------------------------------------------------------------------
local r = Section.new("old | abc\n\nnotes\n\n===\n\n+ a\n- b\n")
r:computeRank()
eq(r:statsLines()[1], "all ✓50% ★1 ↑1", "statsLines: undated total row w/ streak")
eq(#r:statsLines(), 1, "statsLines: undated logs contribute no month rows")

-- special sections have no stats lines
eq(Section.new("Meta\n\nplaceholder\n\n"):statsLines(), nil, "statsLines: special -> nil")

local neg = Section.new("t | q\n\n===\n\n- a\n- b\n- c\n")
neg:computeRank()
eq(neg:statsLines()[1], "all 0% ★0 ↓3", "statsLines: all-negative total row")

-- --------------------------------------------------------------------------
-- statsLines: per-month breakdown (newest month first, after the total). the
-- current streak shows only on the newest month row, not "all" or older months.
-- --------------------------------------------------------------------------
local mo = Section.new("t | m\n\n===\n\n+ 24-02-05: x\n- 24-01-10: y\n+ 24-01-02: z\n")
mo:computeRank()
local ml = mo:statsLines()
eq(#ml, 3, "statsLines: total + 2 months")
eq(ml[1], "  all  ✓67% ★1", "statsLines: total row has no streak")
eq(ml[2], "24-02 ✓100% ★1 ↑1", "statsLines: newest month carries the streak")
eq(ml[3], "24-01  ✓50% ★1", "statsLines: older month has no streak")

-- columns are padded to the widest value in the group (✓100% sets the width)
local star1 = ml[1]:find("★", 1, true)
eq(ml[2]:find("★", 1, true), star1, "statsLines: ★ column aligned across rows")
eq(ml[3]:find("★", 1, true), star1, "statsLines: ★ column aligned across rows")

-- the date is matched anywhere in the line, not just as a prefix
local mb = Section.new("t | b\n\n===\n\n+ [[23-12-01]] abc\n- see 23-11-30 note\n")
mb:computeRank()
local mbl = mb:statsLines()
eq(mbl[2], "23-12 ✓100% ★1 ↑1", "statsLines: date inside [[ ]] is bucketed")
eq(mbl[3], "23-11    0% ★0", "statsLines: mid-line date is bucketed")

-- --------------------------------------------------------------------------
-- parse_sections: captures line numbers and content
-- --------------------------------------------------------------------------
local secs = anxtgo.parse_sections(to_lines("{{{ a\nx }}}\n\n{{{ b\ny }}}"))
eq(#secs, 2, "parse_sections: count")
eq(secs[1].line, 1, "parse_sections: first at line 1")
eq(Section.new(secs[1].content):name(), "a", "parse_sections: first name")
eq(secs[2].line, 4, "parse_sections: second at line 4")
eq(Section.new(secs[2].content):name(), "b", "parse_sections: second name")

-- single-line section
local one = anxtgo.parse_sections(to_lines("intro\n{{{ solo }}}\nouter"))
eq(#one, 1, "parse_sections: single-line count")
eq(one[1].line, 2, "parse_sections: single-line line number")
eq(Section.new(one[1].content):name(), "solo", "parse_sections: single-line name")

-- --------------------------------------------------------------------------
-- compute: inlays for ranked sections only, keyed by line number
-- --------------------------------------------------------------------------
local doc = table.concat({
    "{{{ Meta",       -- line 1, special -> skipped
    "",
    "m",
    "",
    "}}}",
    "",
    "{{{ high",       -- line 7, rank +3
    "",
    "===",
    "",
    "+ a",
    "+ b",
    "+ c",
    "",
    "}}}",
}, "\n")

local inlays = anxtgo.compute(to_lines(doc))
eq(#inlays, 1, "compute: skips special sections")
eq(inlays[1].line, 7, "compute: inlay anchored to title line")
eq(inlays[1].lines[1], "all ✓100% ★3 ↑3", "compute: inlay total stats")

-- --------------------------------------------------------------------------
-- compute on the real sample.md
-- --------------------------------------------------------------------------
local sf = io.open(dir .. "../../sample.md", "r")
if sf then
    local sample = sf:read("*a")
    sf:close()
    local sample_inlays = anxtgo.compute(to_lines(sample))
    eq(#sample_inlays, 2, "sample: two ranked sections (abc, def)")
    eq(sample_inlays[1].lines[1], "  all  ✓50% ★1", "sample: abc total")
    eq(sample_inlays[2].lines[1], "  all  ✓67% ★2", "sample: def total")
    eq(#sample_inlays[2].lines, 3, "sample: def has total + 2 month rows")
end

-- --------------------------------------------------------------------------
io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
