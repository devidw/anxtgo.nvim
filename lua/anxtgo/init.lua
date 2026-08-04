local M = {}

-- ---------------------------------------------------------------------------
-- string helpers
-- ---------------------------------------------------------------------------

-- trim leading/trailing whitespace (mirrors JS String.prototype.trim)
local function trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

-- split on a literal separator (mirrors JS String.prototype.split for a fixed
-- string). Always returns at least one element.
local function split(s, sep)
    local parts = {}
    local start = 1
    while true do
        local i, j = s:find(sep, start, true) -- plain find, no patterns
        if not i then
            parts[#parts + 1] = s:sub(start)
            break
        end
        parts[#parts + 1] = s:sub(start, i - 1)
        start = j + 1
    end
    return parts
end

-- round half up (mirrors JS Math.round for non-negative input)
local function round(x)
    return math.floor(x + 0.5)
end

-- copy `list` without its leading/trailing empty lines
local function trim_blanks(list, keep_leading)
    local first, last = 1, #list
    if not keep_leading then
        while first <= last and trim(list[first]) == "" do
            first = first + 1
        end
    end
    while last >= first and trim(list[last]) == "" do
        last = last - 1
    end
    local out = {}
    for i = first, last do
        out[#out + 1] = list[i]
    end
    return out
end

-- ---------------------------------------------------------------------------
-- stats helpers
-- ---------------------------------------------------------------------------

-- Derive the score/streak stats from an ordered list of "+"/"-" signs (newest
-- first). Pure, so it serves both the section total and each month's slice.
-- "*" days are excluded rather than scored, so they are transparent to every
-- stat: they score nothing and they neither extend nor break a streak.
local function stats_from_signs(signs)
    local pos, neg, neu = 0, 0, 0
    for _, s in ipairs(signs) do
        if s == "+" then
            pos = pos + 1
        elseif s == "-" then
            neg = neg + 1
        else
            neu = neu + 1
        end
    end

    -- current streak: consecutive same-polarity entries from the newest (first)
    -- scored entry, signed by that polarity
    local cur = 0
    local head = nil
    for _, s in ipairs(signs) do
        if s ~= "*" then
            head = s
            break
        end
    end
    if head then
        local n = 0
        for _, s in ipairs(signs) do
            if s == head then
                n = n + 1
            elseif s ~= "*" then
                break
            end
        end
        cur = (head == "+") and n or -n
    end

    -- longest run of consecutive positive entries anywhere
    local longest, run = 0, 0
    for _, s in ipairs(signs) do
        if s == "+" then
            run = run + 1
            if run > longest then
                longest = run
            end
        elseif s ~= "*" then
            run = 0
        end
    end

    return {
        posCount = pos,
        negCount = neg,
        neuCount = neu,
        rank = pos - neg,
        curStreak = cur,
        longestPos = longest,
    }
end

-- display width in terminal columns. Every glyph we emit (✓ ★ ↑ ↓ plus ascii)
-- is one column wide, so this is just the utf-8 codepoint count: bytes that are
-- not continuation bytes (0x80-0xBF).
local function dwidth(s)
    local n = 0
    for i = 1, #s do
        local b = s:byte(i)
        if b < 0x80 or b >= 0xC0 then
            n = n + 1
        end
    end
    return n
end

-- left-pad `s` with spaces to display width `w` (right-align)
local function lpad(s, w)
    local pad = w - dwidth(s)
    return pad > 0 and (string.rep(" ", pad) .. s) or s
end

-- the raw fields of one row, before column widths are known
local function row_fields(label, st, streak)
    -- excluded ("*") entries are left out of the share: it is positives over
    -- the days that were actually scored
    local count = st.posCount + st.negCount
    local pct = round((count == 0 and 0 or st.posCount / count) * 100)
    -- "✓" marks the positive share when there is any positivity
    local pctStr = st.posCount > 0 and ("✓" .. pct .. "%") or (pct .. "%")
    return {
        label = label,
        pct = pctStr,
        pos = st.posCount,
        neg = st.negCount,
        neu = st.neuCount or 0,
        record = st.longestPos,
        streak = streak,
    }
end

-- Format a group of rows into aligned strings: label, positive %, the "+"/"-"
-- totals, and the record ("★" + longest positive run) are each padded to the
-- widest value in the group and separated by two spaces. The excluded total
-- ("*") only gets a column when the group has any. The current streak
-- (↑/↓ + length), when present, is appended.
local function render_group(rows)
    local labelW, pctW, posW, negW, neuW, recW = 0, 0, 0, 0, 0, 0
    for _, r in ipairs(rows) do
        labelW = math.max(labelW, dwidth(r.label))
        pctW = math.max(pctW, dwidth(r.pct))
        posW = math.max(posW, #tostring(r.pos))
        negW = math.max(negW, #tostring(r.neg))
        neuW = math.max(neuW, #tostring(r.neu))
        recW = math.max(recW, #tostring(r.record))
    end

    local anyNeu = false
    for _, r in ipairs(rows) do
        anyNeu = anyNeu or r.neu > 0
    end

    local out = {}
    for _, r in ipairs(rows) do
        local line = lpad(r.label, labelW)
            .. "  " .. lpad(r.pct, pctW)
            .. "  +" .. lpad(tostring(r.pos), posW)
            .. "  -" .. lpad(tostring(r.neg), negW)
            .. (anyNeu and ("  *" .. lpad(tostring(r.neu), neuW)) or "")
            .. "  ★" .. lpad(tostring(r.record), recW)
        if r.streak ~= nil then
            -- ↑/↓ encode the direction, the count is the run length
            local arrow = r.streak < 0 and "↓" or "↑"
            line = line .. "  " .. arrow .. math.abs(r.streak)
        end
        out[#out + 1] = line
    end
    return out
end

-- ---------------------------------------------------------------------------
-- section body layout
-- ---------------------------------------------------------------------------

-- the "### YY-MM" (and "### ?") headings anxtgo owns: they are regenerated on
-- every rank, so nothing else may live on such a line
local UNDATED = "?"

local function month_label(heading)
    local h = trim(heading)
    if h == UNDATED or h:match("^%d%d%-%d%d$") then
        return h
    end
    return nil
end

-- Walk a section body and split it into free-form notes and ordered log
-- entries. A log line starts with "+"/"-", but only counts as a log when it
-- carries a YY-MM-DD date or sits under one of our managed month headings — so
-- an ordinary markdown bullet up in the notes stays a note. Managed headings
-- themselves are dropped; `upsert_section` regenerates them.
--
-- An entry may span several lines: everything indented below its marker line
-- belongs to it (blank lines included, as long as indented content follows) and
-- travels with it when the entry is refiled. Indentation wins over the marker
-- test, so an indented "- sub point" stays part of the entry above it instead
-- of becoming a log of its own.
local function scan(body)
    local notes, logs = {}, {}
    local managed = false
    local entry = nil -- the multi-line entry currently being extended
    local pending = {} -- blank lines held back until indented content follows

    for _, raw in ipairs(body) do
        local line = trim(raw)
        local heading = line:match("^###%s+(.*)$")

        if heading then
            entry, pending = nil, {}
            managed = month_label(heading) ~= nil
            if not managed then
                notes[#notes + 1] = raw
            end
        elseif line == "" then
            -- a blank line only stays inside the entry if the entry continues
            -- past it; otherwise it is just a separator and gets dropped
            if entry then
                pending[#pending + 1] = raw
            else
                notes[#notes + 1] = raw
            end
        elseif entry and raw:match("^%s") then
            for _, held in ipairs(pending) do
                entry.lines[#entry.lines + 1] = held
            end
            pending = {}
            entry.lines[#entry.lines + 1] = raw
        else
            entry, pending = nil, {}
            local sign = line:sub(1, 1)
            local date = line:match("%d%d%-%d%d%-%d%d")
            if (sign == "+" or sign == "-" or sign == "*") and (date or managed) then
                entry = { sign = sign, date = date, lines = { line } }
                logs[#logs + 1] = entry
            else
                notes[#notes + 1] = raw
            end
        end
    end

    return notes, logs
end

-- Rebuild a section body: the notes first, then one "### YY-MM" block per month
-- that has dated logs (newest month first, newest log first within it), and
-- finally a "### ?" block for logs without a date. This is the upsert — logs
-- filed under the wrong month, or not filed at all, land where they belong.
local function upsert_section(body)
    local notes, logs = scan(body)

    local order, buckets, undated = {}, {}, {}
    for i, log in ipairs(logs) do
        if log.date then
            local m = log.date:sub(1, 5)
            if not buckets[m] then
                buckets[m] = {}
                order[#order + 1] = m
            end
            local b = buckets[m]
            b[#b + 1] = { date = log.date, idx = i, lines = log.lines }
        else
            for _, line in ipairs(log.lines) do
                undated[#undated + 1] = line
            end
        end
    end

    -- months newest first (lexicographic on "YY-MM" is chronological)
    table.sort(order, function(a, b)
        return a > b
    end)

    local out = {}
    local function blank()
        if #out > 0 and out[#out] ~= "" then
            out[#out + 1] = ""
        end
    end
    local function block(label, lines)
        blank()
        out[#out + 1] = "### " .. label
        blank()
        for _, line in ipairs(lines) do
            out[#out + 1] = line
        end
    end

    for _, line in ipairs(trim_blanks(notes)) do
        out[#out + 1] = line
    end

    for _, m in ipairs(order) do
        local entries = buckets[m]
        -- newest log first; same-date logs keep the order they had (table.sort
        -- is not stable, so the original index breaks the tie)
        table.sort(entries, function(a, b)
            if a.date ~= b.date then
                return a.date > b.date
            end
            return a.idx < b.idx
        end)
        local lines = {}
        for _, e in ipairs(entries) do
            for _, line in ipairs(e.lines) do
                lines[#lines + 1] = line
            end
        end
        block(m, lines)
    end

    if #undated > 0 then
        block(UNDATED, undated)
    end

    return out
end

-- ---------------------------------------------------------------------------
-- Section
-- ---------------------------------------------------------------------------

local Section = {}
Section.__index = Section
M.Section = Section

-- `content` is the section title on the first line, followed by its body (the
-- lines between this "##" heading and the next one).
function Section.new(content)
    local lines = split(content, "\n")
    local body = {}
    for i = 2, #lines do
        body[#body + 1] = lines[i]
    end

    return setmetatable({
        content = content,
        title = lines[1] or "",
        body = body,
        rank = nil,
        posCount = 0,
        negCount = 0,
        neuCount = 0,
        curStreak = 0,
        longestPos = 0,
        months = {},
    }, Section)
end

function Section:name()
    local title = self.title

    if not title or title == "" then
        return nil
    end

    local parts = split(title, " | ")

    if #parts == 2 then
        return trim(parts[2])
    end

    return trim(parts[1])
end

function Section:isSpecial()
    local name = self:name()
    return name == "X" or name == "Meta" or name == "Archive"
end

function Section:count()
    return self.negCount + self.posCount
end

function Section:posShare()
    local c = self:count()
    if c == 0 then
        return 0
    end
    return self.posCount / c
end

function Section:negShare()
    local c = self:count()
    if c == 0 then
        return 0
    end
    return self.negCount / c
end

function Section:computeRank()
    -- collect the polarity of every log line in document order, and bucket the
    -- dated ones by "YY-MM" so we can break the score down per month. After an
    -- upsert the document order is newest first, which is what the streaks
    -- assume.
    local _, logs = scan(self.body)

    local signs = {}
    local monthOrder = {}
    local monthSigns = {}
    for _, log in ipairs(logs) do
        signs[#signs + 1] = log.sign
        if log.date then
            local month = log.date:sub(1, 5)
            if not monthSigns[month] then
                monthSigns[month] = {}
                monthOrder[#monthOrder + 1] = month
            end
            local ms = monthSigns[month]
            ms[#ms + 1] = log.sign
        end
    end

    local total = stats_from_signs(signs)
    self.posCount = total.posCount
    self.negCount = total.negCount
    self.neuCount = total.neuCount
    self.rank = total.rank
    self.curStreak = total.curStreak
    self.longestPos = total.longestPos

    -- months newest first (lexicographic on "YY-MM" is chronological)
    table.sort(monthOrder, function(a, b)
        return a > b
    end)
    self.months = {}
    for _, m in ipairs(monthOrder) do
        local st = stats_from_signs(monthSigns[m])
        st.month = m
        self.months[#self.months + 1] = st
    end
end

-- the managed stats block that gets inlaid as virtual lines: the "all" total
-- first, then one line per month that has dated logs (newest first). Every row
-- carries the positive %, the "+"/"-" totals and the record (longest positive
-- run). The current
-- streak is momentum-of-now, so it shows on exactly one row: the newest month
-- (or the total when there are no dated logs). Returns nil for special sections.
function Section:statsLines()
    if self:isSpecial() then
        return nil
    end

    if #self.months == 0 then
        return render_group({ row_fields("all", self, self.curStreak) })
    end

    local rows = { row_fields("all", self, nil) }
    for i, m in ipairs(self.months) do
        rows[#rows + 1] = row_fields(m.month, m, i == 1 and self.curStreak or nil)
    end
    return render_group(rows)
end

-- ---------------------------------------------------------------------------
-- core parsing (pure, no nvim dependency so it can be unit tested)
-- ---------------------------------------------------------------------------

-- Cut a list of lines into blocks: every "## " heading opens a section that
-- runs until the next "## " or "# " heading; anything outside a section (a
-- leading "# " title, frontmatter, ...) is kept verbatim as a raw block.
local function parse_blocks(lines)
    local blocks = {}
    local section, raw = nil, nil

    local function outside(line)
        section = nil
        if not raw then
            raw = { kind = "raw", lines = {} }
            blocks[#blocks + 1] = raw
        end
        raw.lines[#raw.lines + 1] = line
    end

    for i, line in ipairs(lines) do
        local hashes, rest = line:match("^(#+)%s+(.*)$")
        local level = hashes and #hashes or nil

        if level == 2 then
            raw = nil
            section = {
                kind = "section",
                line = i,
                heading = line,
                title = trim(rest),
                body = {},
            }
            blocks[#blocks + 1] = section
        elseif level == 1 then
            outside(line)
        elseif section then
            section.body[#section.body + 1] = line
        else
            outside(line)
        end
    end

    return blocks
end

-- Every "## " section together with the 1-based line number of its heading.
-- Content mirrors what a Section expects: the title on the first line, the body
-- below it.
function M.parse_sections(lines)
    local sections = {}
    for _, block in ipairs(parse_blocks(lines)) do
        if block.kind == "section" then
            sections[#sections + 1] = {
                line = block.line,
                content = block.title .. "\n" .. table.concat(block.body, "\n"),
            }
        end
    end
    return sections
end

-- Refile every log line into the "### YY-MM" month it belongs to, creating the
-- month headings that are missing and dropping the ones that ended up empty.
-- Special sections and anything outside a section are passed through. Returns
-- the rewritten lines.
function M.upsert(lines)
    local blocks = parse_blocks(lines)

    local has_section = false
    for _, block in ipairs(blocks) do
        has_section = has_section or block.kind == "section"
    end
    if not has_section then
        return lines
    end

    local out = {}
    local function push(chunk)
        if #chunk == 0 then
            return
        end
        if #out > 0 then
            out[#out + 1] = ""
        end
        for _, line in ipairs(chunk) do
            out[#out + 1] = line
        end
    end

    for _, block in ipairs(blocks) do
        if block.kind == "raw" then
            -- keep as-is, only its trailing blank lines are ours to normalize
            push(trim_blanks(block.lines, true))
        else
            local s = Section.new(block.title .. "\n" .. table.concat(block.body, "\n"))
            local chunk = { block.heading }
            local body = s:isSpecial() and trim_blanks(block.body) or upsert_section(block.body)
            if #body > 0 then
                chunk[#chunk + 1] = ""
                for _, line in ipairs(body) do
                    chunk[#chunk + 1] = line
                end
            end
            push(chunk)
        end
    end

    return out
end

-- Compute the inlay for each section: the 1-based line of its "##" heading and
-- the stats lines (total + per month) to render below it. Special sections are
-- skipped.
function M.compute(lines)
    local inlays = {}
    for _, sec in ipairs(M.parse_sections(lines)) do
        local s = Section.new(sec.content)
        if not s:isSpecial() then
            s:computeRank()
            inlays[#inlays + 1] = { line = sec.line, lines = s:statsLines() }
        end
    end
    return inlays
end

-- ---------------------------------------------------------------------------
-- nvim integration
-- ---------------------------------------------------------------------------

local ns = vim and vim.api.nvim_create_namespace("anxtgo")

-- align the virtual stats under the section name (past the "## " marker)
local INDENT = string.rep(" ", 3)

local function valid_buf(bufnr)
    bufnr = (bufnr and bufnr ~= 0) and bufnr or vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_loaded(bufnr) then
        return nil
    end
    return bufnr
end

-- Recompute and re-render the inlaid stats for a buffer, replacing any marks
-- from a previous run. Cheap and synchronous; callers schedule it off the main
-- path (see M.rank) so opening/ranking never blocks.
function M.render(bufnr)
    bufnr = valid_buf(bufnr)
    if not bufnr then
        return
    end

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

    for _, inlay in ipairs(M.compute(lines)) do
        local virt = {}
        for _, text in ipairs(inlay.lines) do
            virt[#virt + 1] = { { INDENT .. text, "AnxtgoStats" } }
        end

        -- below the "##" heading, i.e. inside the section's fold: folding the
        -- heading hides the stats along with the rest of the body, so a
        -- fully-collapsed file shows nothing but the headings.
        vim.api.nvim_buf_set_extmark(bufnr, ns, inlay.line - 1, 0, {
            virt_lines = virt,
            virt_lines_above = false,
        })
    end
end

-- Rewrite the buffer with every log line refiled under its month heading. No-op
-- when nothing moved, so an already-tidy file is never marked modified.
function M.reflow(bufnr)
    bufnr = valid_buf(bufnr)
    if not bufnr then
        return
    end

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local new = M.upsert(lines)

    if #new == #lines then
        local same = true
        for i = 1, #lines do
            if lines[i] ~= new[i] then
                same = false
                break
            end
        end
        if same then
            return
        end
    end

    local win = vim.api.nvim_get_current_win()
    local cursor = vim.api.nvim_win_get_buf(win) == bufnr and vim.api.nvim_win_get_cursor(win) or nil

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new)

    if cursor then
        vim.api.nvim_win_set_cursor(win, { math.min(cursor[1], #new), cursor[2] })
    end
end

-- Async entry point for :AnxtgoRank: refile the logs, then recompute the stats,
-- on the next event-loop tick so it never blocks the caller.
function M.rank(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    vim.schedule(function()
        M.reflow(bufnr)
        M.render(bufnr)
    end)
end

function M.setup(config)
    config = config or {}
    local pattern = config.pattern or { "*.md" }

    vim.api.nvim_set_hl(0, "AnxtgoStats", { link = "Comment", default = true })

    vim.api.nvim_create_user_command("AnxtgoRank", function()
        M.rank()
    end, {})

    local group = vim.api.nvim_create_augroup("anxtgo", { clear = true })
    vim.api.nvim_create_autocmd({ "BufReadPost" }, {
        group = group,
        pattern = pattern,
        callback = function(args)
            -- opening a file only shows the stats; the text is rewritten on an
            -- explicit :AnxtgoRank
            vim.schedule(function()
                M.render(args.buf)
            end)
        end,
    })
end

return M
