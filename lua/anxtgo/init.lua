local M = {}

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
    local current_file_path = vim.api.nvim_buf_get_name(0)
    local cmd = "deno run --allow-all " .. M.get_plugin_directory() .. "ranker.ts " .. current_file_path .. " " ..
                    current_file_path .. ".bak"
    -- print(cmd)
    local out = vim.fn.system(cmd)
    -- print(out)
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
