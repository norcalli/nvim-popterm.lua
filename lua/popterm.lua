local nvim = require 'popterm.nvim'
local api = vim.api

local M = {}

local terminals = {}

local function buf_is_popterm(bufnr)
	for _, term in pairs(terminals) do
		if term.bufnr == bufnr then
			return true
		end
	end
	return false
end

local pop_win = -1

function IS_POPTERM()
	return buf_is_popterm(api.nvim_get_current_buf())
end

function M._enforce_popterm_constraints()
	local curbuf = api.nvim_get_current_buf()
	local curwin = api.nvim_get_current_win()
	if curwin == pop_win and not buf_is_popterm(curbuf) then
		api.nvim_win_close(pop_win, false)
		nvim.ex.vsplit()
		api.nvim_set_current_buf(curbuf)
	end
end

local config = {
	label_timeout = 5e2;
	label_colors = { ctermfg = White; ctermbg = Red; guifg = "#eee"; guibg = "#a00000" };
	label_format = "POPTERM %d";
	window_width = 0.9;
	window_height = 0.5;

}

local namespace = api.nvim_create_namespace('')
-- local namespace_clear_command = string.format("autocmd InsertCharPre <buffer> ++once lua vim.api.nvim_buf_clear_namespace(0, %d, 0, -1)", namespace)

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

function POPTERM(i)
	assert(type(i) == 'number', "need an index for POPTERM")
	local terminal = terminals[i]
	if not terminal then
		terminal = { bufnr = -1; }
		terminals[i] = terminal
	end

	local curbufnr = api.nvim_get_current_buf()
	-- Hide the current terminal
	if curbufnr == terminal.bufnr then
		-- TODO focus last win?
		-- TODO save layout on close and restore for each terminal?
		api.nvim_win_close(pop_win, false)
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
		api.nvim_buf_clear_namespace(terminal.bufnr, namespace, 0, -1)
		local label_line = math.max(api.nvim_buf_line_count(terminal.bufnr) - 2, 0)
		api.nvim_buf_set_virtual_text(terminal.bufnr, namespace, label_line, {{label, 'PopTermLabel'}}, {})

		local timer = vim.loop.new_timer()
		timer:start(config.label_timeout, 0, vim.schedule_wrap(function()
			api.nvim_buf_clear_namespace(terminal.bufnr, namespace, 0, -1)
			timer:close()
		end))

		-- nvim.command(namespace_clear_command)
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
