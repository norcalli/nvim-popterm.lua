local nvim = require 'popterm.nvim'
local api = vim.api

local M = {}
local terminals = {}
local pop_win = -1

local config = {
	label_timeout = 5e2;
	label_colors = { ctermfg = White; ctermbg = Red; guifg = "#eee"; guibg = "#a00000" };
	label_format = "POPTERM %d";
	window_width = 0.9;
	window_height = 0.5;
}

local namespace = api.nvim_create_namespace('')
-- local namespace_clear_command = string.format("autocmd InsertCharPre <buffer> ++once lua vim.api.nvim_buf_clear_namespace(0, %d, 0, -1)", namespace)

function M._enforce_popterm_constraints()
	local curbuf = api.nvim_get_current_buf()
	local curwin = api.nvim_get_current_win()
	if curwin == pop_win and not buf_is_popterm(curbuf) then
		api.nvim_win_close(pop_win, false)
		nvim.ex.vsplit()
		api.nvim_set_current_buf(curbuf)
	end
end

local function init()
	do
		local res = {}
		for k, v in pairs(config.label_colors) do
			table.insert(res, k.."="..v)
		end
		nvim.ex.highlight("PopTermLabel ", res)
	end

	nvim.ex.augroup("PopTerm")
	nvim.ex.autocmd_()
	nvim.ex.autocmd("BufEnter * lua require'popterm'._enforce_popterm_constraints()")
	nvim.ex.augroup("END")
end

init()

local function buf_is_popterm(bufnr)
	for _, term in pairs(terminals) do
		if term.bufnr == bufnr then
			return true
		end
	end
	return false
end

local function find_current_terminal()
	local curbufnr = api.nvim_get_current_buf()
	for i, term in pairs(terminals) do
		if term.bufnr == curbufnr then
			return i, term
		end
	end
end

local function flash_label(bufnr, label)
	assert(type(label) == 'string')
	api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
	local label_line = math.max(api.nvim_buf_line_count(bufnr) - 2, 0)
	api.nvim_buf_set_virtual_text(bufnr, namespace, label_line, {{label, 'PopTermLabel'}}, {})

	local timer = vim.loop.new_timer()
	timer:start(config.label_timeout, 0, vim.schedule_wrap(function()
		api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
		timer:close()
	end))
end

local function close_popwin()
	if pop_win ~= -1 then
		api.nvim_win_close(pop_win, false)
		pop_win = -1
	end
end

local function terminal_is_alive(i)
	return terminals[i] and api.nvim_buf_is_loaded(terminals[i].bufnr)
end

local function find_live_terminals()
	local res = {}
	for i in pairs(terminals) do
		if terminal_is_alive(i) then
			table.insert(res, i)
		end
	end
	return res
end

function IS_POPTERM()
	return buf_is_popterm(api.nvim_get_current_buf())
end

-- Swap the current popterm (if any) with the one at position i.
function POPTERM_SWAP(i)
	assert(type(i) == 'number')
	local current_popterm_index = find_current_terminal()
	if current_popterm_index and current_popterm_index ~= i then
		terminals[i], terminals[current_popterm_index] = terminals[current_popterm_index], terminals[i]
		flash_label(api.nvim_get_current_buf(), string.format(config.label_format, i))
	end
end

function POPTERM_HIDE()
	close_popwin()
end

function POPTERM(i)
	assert(type(i) == 'number', "need an index for POPTERM")
	local terminal = terminals[i]
	if not terminal then
		terminal = { bufnr = -1; }
		terminals[i] = terminal
	end
	terminal.last_used_time = os.clock()

	local curbufnr = api.nvim_get_current_buf()
	-- Hide the current terminal
	if curbufnr == terminal.bufnr then
		-- TODO focus last win?
		-- TODO save layout on close and restore for each terminal?
		close_popwin()
	else
		-- Create/switch the window if it's closed.

		if api.nvim_win_is_valid(pop_win) then
			api.nvim_set_current_win(pop_win)
		end

		local new_term = false
		-- Create the buffer if it was closed.
		if not api.nvim_buf_is_loaded(terminal.bufnr) then
			terminal.bufnr = api.nvim_create_buf(true, false)
			assert(terminal.bufnr ~= 0, "Failed to create a buffer")
			new_term = true
		end

		-- If the window is already a terminal window, then just switch buffers.
		if buf_is_popterm(api.nvim_get_current_buf()) then
			api.nvim_set_current_buf(terminal.bufnr)
		else
			local uis = api.nvim_list_uis()

			local opts = {
				relative = 'editor';
				width = config.window_width;
				height = config.window_height;
				anchor = 'NW';
				style = 'minimal';
				focusable = false;
			}
			if 0 < opts.width and opts.width <= 1 then
				opts.width = math.floor(uis[1].width * opts.width)
			end
			if 0 < opts.height and opts.height <= 1 then
				opts.height = math.floor(uis[1].height * opts.height)
			end
			opts.col = (uis[1].width - opts.width) / 2
			opts.row = (uis[1].height - opts.height) / 2
			-- api.nvim_win_set_option(win, 'winfixheight', true)
			pop_win = api.nvim_open_win(terminal.bufnr, true, opts)
		end

		if new_term then
			nvim.fn.termopen(nvim.o.shell)
		end
		vim.schedule(nvim.ex.startinsert)

		local label = string.format(config.label_format, i)
		flash_label(terminal.bufnr, label)
		-- nvim.command(namespace_clear_command)
	end
end

-- POPTERM_NEXT will, if:
-- - There are no popterms, create one at index 1.
-- - There are popterms and they are hidden, focus the most recently used one.
-- - We are in a popterm, find the next one in the ring and focus it.
function POPTERM_NEXT(start)
	start = start or find_current_terminal()
	-- TODO(ashkan): find the closest valid index as a starting point if it's not
	-- a terminal.
	local live_terminals = find_live_terminals()
	if not start then
		if #live_terminals == 0 then
			return POPTERM(1)
		elseif #live_terminals == 1 then
			return POPTERM(live_terminals[1])
		else
			-- Find the most recently used terminal.
			local mru_index, mru_time = live_terminals[1], terminals[live_terminals[1]].last_used_time
			for i = 2, #live_terminals do
				local index = live_terminals[i]
				local time = terminals[index].last_used_time
				if mru_time < time then
					mru_index, mru_time = index, time
				end
			end
			return POPTERM(mru_index)
		end
	end
	assert(terminal_is_alive(start), "Invalid starting point. Must be an active terminal")
	if #live_terminals == 1 then
		return flash_label(terminals[live_terminals[1]].bufnr, "No other terminals")
	end
	for i = 1, #live_terminals do
		if live_terminals[i] == start then
			return POPTERM(live_terminals[i%#live_terminals+1])
		end
	end
end

local mappings = {}
for i = 1, 9 do
	local key = ("<A-%d>"):format(i)
	local value = { ("<Cmd>lua POPTERM(%d)<CR>"):format(i); noremap = true; }
	mappings["n"..key] = value
	mappings["t"..key] = value
	mappings["i"..key] = value
end
local SHIFT_MAPPINGS = "!@#$%^&*("
for i = 1, 9 do
	-- TODO(ashkan): can this work on GUIs or nah?
	-- local key = ("<A-S-%d>"):format(i)
	local key = ("<A-%s>"):format(SHIFT_MAPPINGS:sub(i,i))
	local value = { ("<Cmd>lua POPTERM_SWAP(%d)<CR>"):format(i); noremap = true; }
	mappings["n"..key] = value
	mappings["t"..key] = value
	mappings["i"..key] = value
end
do
	local key = "<A-`>"
	local value = { "<Cmd>lua POPTERM_HIDE()<CR>"; noremap = true; }
	mappings["n"..key] = value
	mappings["t"..key] = value
	mappings["i"..key] = value
end
do
	local key = "<A-Tab>"
	local value = { "<Cmd>lua POPTERM_NEXT()<CR>"; noremap = true; }
	mappings["n"..key] = value
	mappings["t"..key] = value
	mappings["i"..key] = value
end

M.mappings = mappings

local valid_modes = {
	n = 'n'; v = 'v'; x = 'x'; i = 'i';
	o = 'o'; t = 't'; c = 'c'; s = 's';
	-- :map! and :map
	['!'] = '!'; [' '] = '';
}
local function nvim_apply_mappings(mappings, default_options)
	for key, options in pairs(mappings) do
		options = vim.tbl_extend("keep", options, default_options or {})
		local mode, mapping = key:match("^(.)(.+)$")
		if not mode then
			assert(false, "nvim_apply_mappings: invalid mode specified for keymapping "..key)
		end
		if not valid_modes[mode] then
			assert(false, "nvim_apply_mappings: invalid mode specified for keymapping. mode="..mode)
		end
		mode = valid_modes[mode]
		local rhs = options[1]
		-- Remove this because we're going to pass it straight to nvim_set_keymap
		options[1] = nil
		vim.api.nvim_set_keymap(mode, mapping, rhs, options)
	end
end

M.setup = function()
	nvim_apply_mappings(mappings)
end

return M

-- vim:noet ts=3 sw=3
