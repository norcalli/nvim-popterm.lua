local nvim = require 'nvim'

local M = {}

local terminals = {}

local function buf_is_terminal(bufnr)
	for _, term in ipairs(terminals) do
		if term.bufnr == bufnr then
			return true
		end
	end
	return false
end

local pop_win = -1

function IS_POPTERM()
	return buf_is_terminal(nvim.get_current_buf())
end

local namespace = nvim.create_namespace('')
nvim.ex.highlight("PopTermLabel ctermfg=White ctermbg=Red guifg=#eee guibg=#a00000")
-- local namespace_clear_command = string.format("autocmd InsertCharPre <buffer> ++once lua vim.api.nvim_buf_clear_namespace(0, %d, 0, -1)", namespace)

function POPTERM(i)
	assert(type(i) == 'number', "need an index for POPTERM")
	local terminal = terminals[i]
	if not terminal then
		terminal = { bufnr = -1; }
		terminals[i] = terminal
	end

	local term_buf = terminal.bufnr
	local curbufnr = nvim.get_current_buf()
	-- Hide the current terminal
	if curbufnr == term_buf then
		-- TODO focus last win?
		-- TODO save layout on close and restore?
		nvim.win_close(0, false)
	else
		-- Create/switch the window if it's closed.

		if nvim.win_is_valid(pop_win) then
			nvim.set_current_win(pop_win)
		end

		local new_term = false
		-- Create the buffer if it was closed.
		if not nvim.buf_is_loaded(term_buf) then
			term_buf = nvim.create_buf(false, false)
			assert(term_buf ~= 0, "Failed to create a buffer")
			terminal.bufnr = term_buf
			new_term = true
		end

		-- If the window is already a terminal window, then just switch buffers.
		if buf_is_terminal(nvim.get_current_buf()) then
			nvim.set_current_buf(term_buf)
		else
			-- nvim.ex.autocmd("WinLeave", ("<buffer=%d>"):format(buf), lua_callback_cmd(function()
			-- 	nvim.win_close(win, true)
			-- end))
			local uis = nvim.list_uis()

			local opts = {
				relative = 'editor';
				width = 0.9;
				height = 0.5;
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
			-- nvim.win_set_option(win, 'winfixheight', true)
			pop_win = nvim.open_win(term_buf, true, opts)
		end

		if new_term then
			nvim.fn.termopen(nvim.o.shell)
		end
		vim.schedule(nvim.ex.startinsert)

		local label = string.format("POPTERM %d", i)
		nvim.buf_clear_namespace(term_buf, namespace, 0, -1)
		local label_line = math.max(nvim.buf_line_count(term_buf) - 2, 0)
		nvim.buf_set_virtual_text(term_buf, namespace, label_line, {{label, 'PopTermLabel'}}, {})

		-- nvim.buf_attach(term_buf, false, {
		-- 	on_lines = function()
		-- 		nvim.buf_clear_namespace(term_buf, namespace, 0, -1)
		-- 		return true
		-- 	end;
		-- })

		local timer = vim.loop.new_timer()
		timer:start(500, 0, vim.schedule_wrap(function()
			nvim.buf_clear_namespace(term_buf, namespace, 0, -1)
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
