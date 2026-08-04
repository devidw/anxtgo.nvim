-- Pure-lua test suite for the anxtgo ranker.
-- Run with:  lua5.4 lua/anxtgo/test.lua   (from the repo root)
-- or:        ./test.sh

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

-- compare an upsert result (a line list) against an expected document
local function eq_doc(actual, expected, msg)
    local a, e = table.concat(actual, "\n"), table.concat(to_lines(expected), "\n")
    if a == e then
        passed = passed + 1
    else
        failed = failed + 1
        io.write(("FAIL: %s\n--- expected ---\n%s\n--- actual ---\n%s\n---\n"):format(
            msg or "", e, a))
    end
end

-- --------------------------------------------------------------------------
-- Section.name
-- --------------------------------------------------------------------------
eq(Section.new("Meta\n\nplaceholder\n"):name(), "Meta", "name: plain title")
eq(Section.new("   0  50% | abc\n\nbody"):name(), "abc", "name: managed title takes part after | ")
eq(Section.new(" Some Title \n\nbody"):name(), "Some Title", "name: trims plain title")

-- the >2 parts case returns trim(parts[1]), which is "a"
eq(Section.new("a | b | c\nbody"):name(), "a", "name: >2 pipe parts -> first segment")

-- --------------------------------------------------------------------------
-- isSpecial
-- --------------------------------------------------------------------------
ok(Section.new("Meta\nx"):isSpecial(), "isSpecial: Meta")
ok(Section.new("Archive\nx"):isSpecial(), "isSpecial: Archive")
ok(Section.new("X\nx"):isSpecial(), "isSpecial: X")
ok(not Section.new("abc\nx"):isSpecial(), "isSpecial: ranked is not special")

-- --------------------------------------------------------------------------
-- computeRank / counts / shares
-- --------------------------------------------------------------------------
local s = Section.new("x\n\nnotes\n\n### ?\n\n- a\n+ b\n+ c\n")
s:computeRank()
eq(s.negCount, 1, "computeRank: neg count")
eq(s.posCount, 2, "computeRank: pos count")
eq(s.rank, 1, "computeRank: rank = pos - neg")
eq(s:count(), 3, "count")
ok(math.abs(s:posShare() - 2 / 3) < 1e-9, "posShare")
ok(math.abs(s:negShare() - 1 / 3) < 1e-9, "negShare")

-- lines not starting with +/- are ignored
local s2 = Section.new("y\n\n### ?\n\nsome note\n+ done\n- not done\nmidline + ignore\n")
s2:computeRank()
eq(s2.posCount, 1, "computeRank: ignores non +/- lines (pos)")
eq(s2.negCount, 1, "computeRank: ignores non +/- lines (neg)")

-- a bare "- bullet" in the notes is prose, not a log: only dated markers count
-- outside of a managed month heading
local s3 = Section.new("z\n\n- just a note bullet\n+ another one\n\n### 24-01\n\n+ 24-01-02: x\n")
s3:computeRank()
eq(s3:count(), 1, "computeRank: undated notes bullets are not logs")
eq(s3.posCount, 1, "computeRank: only the dated log counts")

-- a dated marker anywhere in the section counts, heading or no heading
local s4 = Section.new("z\n\n+ 24-01-02: filed under nothing\n")
s4:computeRank()
eq(s4.posCount, 1, "computeRank: dated log outside any month heading counts")

-- streaks: current streak counts from the most recent (first) log line and is
-- signed; longest positive is the longest run of consecutive + anywhere
local st = Section.new("s\n\n### ?\n\n+ a\n+ b\n+ c\n- d\n+ e\n")
st:computeRank()
eq(st.curStreak, 3, "curStreak: leading +++ -> +3")
eq(st.longestPos, 3, "longestPos: best run of + is 3")

local stn = Section.new("s\n\n### ?\n\n- a\n- b\n+ c\n+ d\n+ e\n+ f\n")
stn:computeRank()
eq(stn.curStreak, -2, "curStreak: leading -- -> -2")
eq(stn.longestPos, 4, "longestPos: trailing run of 4 +")

local ste = Section.new("s\n\n")
ste:computeRank()
eq(ste.curStreak, 0, "curStreak: no entries -> 0")
eq(ste.longestPos, 0, "longestPos: no entries -> 0")

-- empty share guard (no log lines -> no div by zero crash)
local sz = Section.new("z\n\n### ?\n\n")
sz:computeRank()
eq(sz:posShare(), 0, "posShare: zero when no entries")
eq(sz:statsLines()[1], "all  0%  +0  -0  ★0  ↑0", "statsLines: zero-entry renders 0% / ★0")
eq(#sz:statsLines(), 1, "statsLines: no dated logs -> only the total line")

-- --------------------------------------------------------------------------
-- statsLines: each row carries %, the +/- totals and the record (★); undated
-- logs -> no months, so the current streak lives on the "all" row as a fallback
-- --------------------------------------------------------------------------
local r = Section.new("abc\n\nnotes\n\n### ?\n\n+ a\n- b\n")
r:computeRank()
eq(r:statsLines()[1], "all  ✓50%  +1  -1  ★1  ↑1", "statsLines: undated total row w/ streak")
eq(#r:statsLines(), 1, "statsLines: undated logs contribute no month rows")

-- special sections have no stats lines
eq(Section.new("Meta\n\nplaceholder\n\n"):statsLines(), nil, "statsLines: special -> nil")

local neg = Section.new("q\n\n### ?\n\n- a\n- b\n- c\n")
neg:computeRank()
eq(neg:statsLines()[1], "all  0%  +0  -3  ★0  ↓3", "statsLines: all-negative total row")

-- --------------------------------------------------------------------------
-- statsLines: per-month breakdown (newest month first, after the total). the
-- current streak shows only on the newest month row, not "all" or older months.
-- --------------------------------------------------------------------------
local mo = Section.new("m\n\n### 24-02\n\n+ 24-02-05: x\n\n### 24-01\n\n- 24-01-10: y\n+ 24-01-02: z\n")
mo:computeRank()
local ml = mo:statsLines()
eq(#ml, 3, "statsLines: total + 2 months")
eq(ml[1], "  all   ✓67%  +2  -1  ★1", "statsLines: total row has no streak")
eq(ml[2], "24-02  ✓100%  +1  -0  ★1  ↑1", "statsLines: newest month carries the streak")
eq(ml[3], "24-01   ✓50%  +1  -1  ★1", "statsLines: older month has no streak")

-- columns are padded to the widest value in the group (✓100% sets the width)
local star1 = ml[1]:find("★", 1, true)
eq(ml[2]:find("★", 1, true), star1, "statsLines: ★ column aligned across rows")
eq(ml[3]:find("★", 1, true), star1, "statsLines: ★ column aligned across rows")

-- the date is matched anywhere in the line, not just as a prefix
local mb = Section.new("b\n\n+ [[23-12-01]] abc\n- see 23-11-30 note\n")
mb:computeRank()
local mbl = mb:statsLines()
eq(mbl[2], "23-12  ✓100%  +1  -0  ★1  ↑1", "statsLines: date inside [[ ]] is bucketed")
eq(mbl[3], "23-11     0%  +0  -1  ★0", "statsLines: mid-line date is bucketed")

-- --------------------------------------------------------------------------
-- "*" entries: excluded days, counted as entries but scored as zero and
-- transparent to both streaks
-- --------------------------------------------------------------------------
local nu = Section.new("n\n\n### ?\n\n+ a\n* b\n- c\n")
nu:computeRank()
eq(nu.posCount, 1, "neutral: pos count unaffected")
eq(nu.negCount, 1, "neutral: neg count unaffected")
eq(nu.neuCount, 1, "neutral: counted separately")
eq(nu.rank, 0, "neutral: scores zero")
eq(nu:count(), 2, "neutral: left out of the scored count")
ok(math.abs(nu:posShare() - 0.5) < 1e-9, "neutral: left out of the share")

local nus = Section.new("n\n\n### ?\n\n* a\n+ b\n+ c\n- d\n")
nus:computeRank()
eq(nus.curStreak, 2, "neutral: a leading * does not start or break the streak")

local nur = Section.new("n\n\n### ?\n\n+ a\n* b\n+ c\n- d\n")
nur:computeRank()
eq(nur.longestPos, 2, "neutral: the record runs straight through a *")
eq(nur.curStreak, 2, "neutral: the current streak runs straight through a *")

local nuo = Section.new("n\n\n### ?\n\n* a\n* b\n")
nuo:computeRank()
eq(nuo.curStreak, 0, "neutral: nothing but * -> no streak")
eq(nuo:statsLines()[1], "all  0%  +0  -0  *2  ★0  ↑0", "neutral: all-excluded row")

-- the "*" column only shows up when the group has any
local nun = Section.new("n\n\n### ?\n\n+ a\n")
nun:computeRank()
eq(nun:statsLines()[1], "all  ✓100%  +1  -0  ★1  ↑1", "neutral: no * column without excluded days")

local num = Section.new(table.concat({
    "m", "",
    "### 24-02", "",
    "* 24-02-10: travelling, did not apply",
    "+ 24-02-05: x", "",
    "### 24-01", "",
    "- 24-01-10: y",
    "+ 24-01-02: z",
}, "\n"))
num:computeRank()
local nml = num:statsLines()
eq(nml[1], "  all   ✓67%  +2  -1  *1  ★1", "neutral: total row carries the * count")
eq(nml[2], "24-02  ✓100%  +1  -0  *1  ★1  ↑1", "neutral: month row with an excluded day")
eq(nml[3], "24-01   ✓50%  +1  -1  *0  ★1", "neutral: months without any pad the * column")

-- a "*" bullet in the notes is prose, same as "-"
local nub = Section.new("n\n\n* just a bullet\n\n### 24-01\n\n+ 24-01-02: x\n")
nub:computeRank()
eq(nub:count(), 1, "neutral: undated * in the notes is not an entry")

-- --------------------------------------------------------------------------
-- parse_sections: captures line numbers and content
-- --------------------------------------------------------------------------
local secs = anxtgo.parse_sections(to_lines("## a\n\nx\n\n## b\n\ny"))
eq(#secs, 2, "parse_sections: count")
eq(secs[1].line, 1, "parse_sections: first at line 1")
eq(Section.new(secs[1].content):name(), "a", "parse_sections: first name")
eq(secs[2].line, 5, "parse_sections: second at line 5")
eq(Section.new(secs[2].content):name(), "b", "parse_sections: second name")

-- content before the first "##", and any "#" title, is outside every section
local outer = anxtgo.parse_sections(to_lines("# doc\n\nintro\n\n## solo\n\nbody"))
eq(#outer, 1, "parse_sections: h1 does not open a section")
eq(outer[1].line, 5, "parse_sections: line number of the h2")
eq(Section.new(outer[1].content):name(), "solo", "parse_sections: h2 name")

-- "###" month headings stay inside their section
local nested = anxtgo.parse_sections(to_lines("## a\n\n### 24-01\n\n+ 24-01-01: x\n\n## b\n"))
eq(#nested, 2, "parse_sections: h3 does not split a section")
ok(nested[1].content:find("### 24-01", 1, true) ~= nil,
    "parse_sections: body keeps the month heading")

-- --------------------------------------------------------------------------
-- compute: inlays for ranked sections only, keyed by line number
-- --------------------------------------------------------------------------
local doc = table.concat({
    "## Meta",  -- line 1, special -> skipped
    "",
    "m",
    "",
    "## high",  -- line 5, rank +3
    "",
    "### 24-01",
    "",
    "+ 24-01-03: a",
    "+ 24-01-02: b",
    "+ 24-01-01: c",
}, "\n")

local inlays = anxtgo.compute(to_lines(doc))
eq(#inlays, 1, "compute: skips special sections")
eq(inlays[1].line, 5, "compute: inlay anchored to the heading line")
eq(inlays[1].lines[1], "  all  ✓100%  +3  -0  ★3", "compute: inlay total stats")
eq(inlays[1].lines[2], "24-01  ✓100%  +3  -0  ★3  ↑3", "compute: inlay month stats")

-- --------------------------------------------------------------------------
-- upsert: logs are refiled under the month they are dated with
-- --------------------------------------------------------------------------

-- everything under the section root -> all months are created
eq_doc(anxtgo.upsert(to_lines([[
## abc

notes

+ 24-01-03: a
- 24-02-15: b
]])), [[
## abc

notes

### 24-02

- 24-02-15: b

### 24-01

+ 24-01-03: a]], "upsert: creates the missing month headings")

-- filed under the wrong month -> moved to the right one, empty months dropped
eq_doc(anxtgo.upsert(to_lines([[
## abc

### 24-05

+ 24-01-03: a

### 23-09
]])), [[
## abc

### 24-01

+ 24-01-03: a]], "upsert: refiles a misplaced log and drops the empty month")

-- within a month the newest log comes first; same-date logs keep their order
eq_doc(anxtgo.upsert(to_lines([[
## abc

+ 24-01-02: older
+ 24-01-09: newest
- 24-01-02: same day as the first
]])), [[
## abc

### 24-01

+ 24-01-09: newest
+ 24-01-02: older
- 24-01-02: same day as the first]], "upsert: sorts newest first, stable on ties")

-- undated markers under a month heading end up in "### ?", at the bottom
eq_doc(anxtgo.upsert(to_lines([[
## abc

- a note bullet, not a log

### 24-01

+ 24-01-02: dated
- undated
]])), [[
## abc

- a note bullet, not a log

### 24-01

+ 24-01-02: dated

### ?

- undated]], "upsert: undated logs go to ### ?, notes bullets stay notes")

-- special sections and out-of-section content are passed through
eq_doc(anxtgo.upsert(to_lines([[
# journal

## Meta

+ 24-01-02: not a log here

## abc

+ 24-01-02: a
]])), [[
# journal

## Meta

+ 24-01-02: not a log here

## abc

### 24-01

+ 24-01-02: a]], "upsert: special sections are left alone")

-- "*" entries are refiled by date like any other
eq_doc(anxtgo.upsert(to_lines([[
## abc

* 24-03-01: was away, does not apply
  and a continuation line
+ 24-01-02: a
]])), [[
## abc

### 24-03

* 24-03-01: was away, does not apply
  and a continuation line

### 24-01

+ 24-01-02: a]], "upsert: excluded entries get their month too")

-- indented lines below a marker are part of that entry and travel with it
eq_doc(anxtgo.upsert(to_lines([[
## abc

+ 24-01-02: first line
  continues here
  and here
- 24-03-04: next marker
]])), [[
## abc

### 24-03

- 24-03-04: next marker

### 24-01

+ 24-01-02: first line
  continues here
  and here]], "upsert: indented continuation lines follow their marker")

-- an indented bullet is part of the entry above it, not a log of its own
eq_doc(anxtgo.upsert(to_lines([[
## abc

### 24-01

+ 24-01-02: did the thing
  - sub point a
  - sub point b

    still the same entry

- 24-01-01: earlier
]])), [[
## abc

### 24-01

+ 24-01-02: did the thing
  - sub point a
  - sub point b

    still the same entry
- 24-01-01: earlier]], "upsert: indented bullets stay inside the entry")

local multi = Section.new("m\n\n### 24-01\n\n+ 24-01-02: a\n  - sub\n  - sub\n- 24-01-01: b\n")
multi:computeRank()
eq(multi:count(), 2, "computeRank: continuation lines are not counted as logs")
eq(multi.posCount, 1, "computeRank: multi-line entry counts once")

-- a document without any "##" section is returned untouched
local plain = to_lines("just some text\n\n- a bullet\n")
eq_doc(anxtgo.upsert(plain), table.concat(plain, "\n"), "upsert: no sections -> unchanged")

-- --------------------------------------------------------------------------
-- upsert + compute on the real sample.md
-- --------------------------------------------------------------------------
local sf = io.open(dir .. "../../sample.md", "r")
if sf then
    local sample = sf:read("*a")
    sf:close()
    local sample_lines = to_lines(sample)

    local sample_inlays = anxtgo.compute(sample_lines)
    eq(#sample_inlays, 2, "sample: two ranked sections (abc, def)")
    eq(sample_inlays[1].lines[1], "  all   ✓50%  +1  -1  *1  ★1", "sample: abc total")
    eq(sample_inlays[1].lines[2], "24-02     0%  +0  -1  *1  ★0  ↓1", "sample: abc newest month")
    eq(sample_inlays[2].lines[1], "  all   ✓67%  +2  -1  ★2", "sample: def total")
    eq(#sample_inlays[2].lines, 3, "sample: def has total + 2 month rows")

    -- the sample is already tidy: upserting it only strips the trailing blank
    local once = anxtgo.upsert(sample_lines)
    eq(table.concat(once, "\n"), table.concat(sample_lines, "\n"):gsub("%s+$", ""),
        "sample: already grouped, upsert is a no-op")
    eq(table.concat(anxtgo.upsert(once), "\n"), table.concat(once, "\n"),
        "sample: upsert is idempotent")
end

-- --------------------------------------------------------------------------
io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
