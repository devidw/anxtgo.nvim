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

-- ---------------------------------------------------------------------------
-- stats helpers
-- ---------------------------------------------------------------------------

-- Derive the score/streak stats from an ordered list of "+"/"-" signs (newest
-- first). Pure, so it serves both the section total and each month's slice.
local function stats_from_signs(signs)
    local pos, neg = 0, 0
    for _, s in ipairs(signs) do
        if s == "+" then
            pos = pos + 1
        else
            neg = neg + 1
        end
    end

    -- current streak: consecutive same-polarity entries from the newest (first)
    -- entry, signed by that polarity
    local cur = 0
    if #signs > 0 then
        local head = signs[1]
        local n = 0
        for i = 1, #signs do
            if signs[i] == head then
                n = n + 1
            else
                break
            end
        end
        cur = (head == "+") and n or -n
    end

    -- longest run of consecutive positive entries anywhere
    local longest, run = 0, 0
    for i = 1, #signs do
        if signs[i] == "+" then
            run = run + 1
            if run > longest then
                longest = run
            end
        else
            run = 0
        end
    end

    return {
        posCount = pos,
        negCount = neg,
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
    local count = st.posCount + st.negCount
    local pct = round((count == 0 and 0 or st.posCount / count) * 100)
    -- "✓" marks the positive share when there is any positivity
    local pctStr = st.posCount > 0 and ("✓" .. pct .. "%") or (pct .. "%")
    return {
        label = label,
        pct = pctStr,
        pos = st.posCount,
        neg = st.negCount,
        record = st.longestPos,
        streak = streak,
    }
end

-- Format a group of rows into aligned strings: label, positive %, the "+"/"-"
-- totals, and the record ("★" + longest positive run) are each padded to the
-- widest value in the group and separated by two spaces. The current streak
-- (↑/↓ + length), when present, is appended.
local function render_group(rows)
    local labelW, pctW, posW, negW, recW = 0, 0, 0, 0, 0
    for _, r in ipairs(rows) do
        labelW = math.max(labelW, dwidth(r.label))
        pctW = math.max(pctW, dwidth(r.pct))
        posW = math.max(posW, #tostring(r.pos))
        negW = math.max(negW, #tostring(r.neg))
        recW = math.max(recW, #tostring(r.record))
    end

    local out = {}
    for _, r in ipairs(rows) do
        local line = lpad(r.label, labelW)
            .. "  " .. lpad(r.pct, pctW)
            .. "  +" .. lpad(tostring(r.pos), posW)
            .. "  -" .. lpad(tostring(r.neg), negW)
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
-- Section
-- ---------------------------------------------------------------------------

local Section = {}
Section.__index = Section
M.Section = Section

function Section.new(content)
    return setmetatable({
        content = content,
        rank = nil,
        posCount = 0,
        negCount = 0,
        curStreak = 0,
        longestPos = 0,
        months = {},
    }, Section)
end

function Section:name()
    local lines = split(self.content, "\n")
    local title = lines[1]

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
    -- everything after the first "===" separator
    local logs = split(self.content, "===")[2] or ""

    -- collect the polarity of every log line in order, and bucket the dated
    -- ones by "YY-MM" so we can break the score down per month
    local signs = {}
    local monthOrder = {}
    local monthSigns = {}
    for _, raw in ipairs(split(logs, "\n")) do
        local line = trim(raw)
        if #line > 0 then
            local first = line:sub(1, 1)
            if first == "+" or first == "-" then
                signs[#signs + 1] = first
                -- bucket by "24-01" from the first YY-MM-DD date anywhere in the
                -- line, so "+ [[24-01-31]] ..." parses too, not just a prefix
                local month = line:match("(%d%d%-%d%d)%-%d%d")
                if month then
                    if not monthSigns[month] then
                        monthSigns[month] = {}
                        monthOrder[#monthOrder + 1] = month
                    end
                    local ms = monthSigns[month]
                    ms[#ms + 1] = first
                end
            end
        end
    end

    local total = stats_from_signs(signs)
    self.posCount = total.posCount
    self.negCount = total.negCount
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

-- Scan a list of lines and return every `{{{ ... }}}` section together with the
-- 1-based line number of its opening `{{{` marker. Content mirrors the text a
-- Section expects: everything between the markers (the title lives on the
-- opening line right after `{{{`).
function M.parse_sections(lines)
    local sections = {}
    local content, startLine = nil, nil

    for i, line in ipairs(lines) do
        local open = line:find("{{{", 1, true)
        local close = line:find("}}}", 1, true)

        if content then
            if close then
                content[#content + 1] = line:sub(1, close - 1)
                sections[#sections + 1] = {
                    line = startLine,
                    content = table.concat(content, "\n"),
                }
                content, startLine = nil, nil
            else
                content[#content + 1] = line
            end
        elseif open then
            startLine = i
            if close and close > open then
                sections[#sections + 1] = {
                    line = startLine,
                    content = line:sub(open + 3, close - 1),
                }
                startLine = nil
            else
                content = { line:sub(open + 3) }
            end
        end
    end

    return sections
end

-- Compute the inlay for each section: the 1-based line of its title marker and
-- the stats lines (total + per month) to render above it. Special sections are
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

-- align the virtual stats under the section name (past the "{{{ " marker)
local INDENT = string.rep(" ", 4)

-- Recompute and re-render the inlaid stats for a buffer, replacing any marks
-- from a previous run. Cheap and synchronous; callers schedule it off the main
-- path (see M.rank) so opening/ranking never blocks.
function M.render(bufnr)
    bufnr = (bufnr and bufnr ~= 0) and bufnr or vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_loaded(bufnr) then
        return
    end

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

    for _, inlay in ipairs(M.compute(lines)) do
        local virt = {}
        for _, text in ipairs(inlay.lines) do
            virt[#virt + 1] = { { INDENT .. text, "AnxtgoStats" } }
        end

        -- virt_lines attached to a line inside a closed marker fold are hidden.
        -- The "{{{" line is the fold's first line, so anchor the block to the
        -- line above it (outside the fold) and render below that line — this
        -- keeps the stats visible whether or not the section is folded. Only a
        -- section starting on line 1 has no room above and falls back to above.
        local row = inlay.line - 1 -- 0-based title row
        if row > 0 then
            vim.api.nvim_buf_set_extmark(bufnr, ns, row - 1, 0, {
                virt_lines = virt,
                virt_lines_above = false,
            })
        else
            vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
                virt_lines = virt,
                virt_lines_above = true,
            })
        end
    end
end

-- Async entry point: compute + render on the next event-loop tick so it never
-- blocks the caller (document open, :AnxtgoRank).
function M.rank(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    vim.schedule(function()
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
            M.rank(args.buf)
        end,
    })
end

return M
