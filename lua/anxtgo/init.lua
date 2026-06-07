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

-- detect a vim/vi/ex modeline, e.g. "<!-- vim: set foldmethod=marker: -->".
-- the marker may be at the start of the line or preceded by whitespace.
local function is_modeline(line)
    return line:match("^vim?:") ~= nil
        or line:match("[ \t]vim?:") ~= nil
        or line:match("^ex:") ~= nil
        or line:match("[ \t]ex:") ~= nil
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

    for _, raw in ipairs(split(logs, "\n")) do
        local line = trim(raw)
        if #line > 0 then
            local first = line:sub(1, 1)
            if first == "-" then
                self.negCount = self.negCount + 1
            elseif first == "+" then
                self.posCount = self.posCount + 1
            end
        end
    end

    self.rank = self.posCount - self.negCount
end

function Section:toString()
    local lines = split(self.content, "\n")
    table.remove(lines, 1) -- drop the title line

    local newTitle
    if self:isSpecial() then
        newTitle = self:name()
    else
        newTitle = string.format(
            "%3d %3d%% | %s",
            self.rank,
            round(self:posShare() * 100),
            self:name()
        )
    end

    local body = trim(table.concat(lines, "\n"))
    return "{{{ " .. newTitle .. "\n\n" .. body .. "\n\n}}}"
end

-- ---------------------------------------------------------------------------
-- core processing (pure, no nvim dependency so it can be unit tested)
-- ---------------------------------------------------------------------------

-- extract all `{{{ ... }}}` sections (content may not contain braces)
function M.get_sections(input)
    local sections = {}
    for cap in input:gmatch("{{{([^{}]+)}}}") do
        sections[#sections + 1] = Section.new(cap)
    end
    return sections
end

-- transform the whole buffer text: rank, reorder, and re-render
function M.process(input)
    local sections = M.get_sections(input)

    local specials = {}
    local ranked = {}

    for _, s in ipairs(sections) do
        if s:isSpecial() then
            specials[#specials + 1] = s
        else
            ranked[#ranked + 1] = s
        end
    end

    for _, s in ipairs(ranked) do
        s:computeRank()
    end

    -- sort by rank ascending; keep original order for ties (stable)
    for i, s in ipairs(ranked) do
        s._idx = i
    end
    table.sort(ranked, function(a, b)
        if a.rank == b.rank then
            return a._idx < b._idx
        end
        return a.rank < b.rank
    end)

    local out = {}
    for _, s in ipairs(specials) do
        out[#out + 1] = s:toString()
    end
    for _, s in ipairs(ranked) do
        out[#out + 1] = s:toString()
    end

    local body = table.concat(out, "\n\n")

    -- preserve vim modelines that live outside the {{{ }}} sections: those
    -- before the first section stay on top, those after the last stay at the
    -- bottom. Everything else outside sections is still discarded.
    local lines = split(input, "\n")
    local firstIdx, lastIdx
    for i, ln in ipairs(lines) do
        if ln:find("{{{", 1, true) then
            firstIdx = firstIdx or i
        end
        if ln:find("}}}", 1, true) then
            lastIdx = i
        end
    end

    local headers, footers = {}, {}
    if firstIdx then
        for i = 1, firstIdx - 1 do
            if is_modeline(lines[i]) then
                headers[#headers + 1] = lines[i]
            end
        end
    end
    if lastIdx then
        for i = lastIdx + 1, #lines do
            if is_modeline(lines[i]) then
                footers[#footers + 1] = lines[i]
            end
        end
    end

    if #headers > 0 then
        body = table.concat(headers, "\n") .. "\n\n" .. body
    end
    if #footers > 0 then
        body = body .. "\n\n" .. table.concat(footers, "\n")
    end

    return body
end

-- ---------------------------------------------------------------------------
-- nvim integration
-- ---------------------------------------------------------------------------

function M.get_plugin_directory()
    local info = debug.getinfo(1, 'S')
    local plugin_path = info.source:sub(2)
    plugin_path = plugin_path:match("(.*/)")
    return plugin_path
end

function M.insert(text)
    local line, col = unpack(vim.api.nvim_win_get_cursor(0))
    vim.api.nvim_buf_set_text(0, line - 1, col, line - 1, col, {text})
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', true)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('a', true, false, true), 'n', false)
end

function M.line(prefix)
    return prefix .. " " .. os.date("%y-%m-%d") .. ": "
end

function M.pos()
    return M.insert(M.line("+"))
end

function M.neg()
    return M.insert(M.line("-"))
end

function M.rank()
    local path = vim.api.nvim_buf_get_name(0)

    local f = assert(io.open(path, "r"))
    local contents = f:read("*a")
    f:close()

    -- backup
    local bak = assert(io.open(path .. ".bak", "w"))
    bak:write(contents)
    bak:close()

    local out = M.process(contents)

    local w = assert(io.open(path, "w"))
    w:write(out)
    w:close()

    vim.cmd("e")
    -- todo any way to do it without forcing, reload, it will collapse currently
    -- opened fold
end

function M.setup(config)
    vim.api.nvim_create_user_command("AnxtgoPositive", M.pos, {})
    vim.api.nvim_create_user_command("AnxtgoNegative", M.neg, {})
    vim.api.nvim_create_user_command("AnxtgoRank", M.rank, {})
end

return M
