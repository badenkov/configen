vim.g.mapleader = " "
vim.g.maplocalleader = ","
-- Settings
vim.opt.nu = true
vim.opt.tabstop = 2
vim.opt.softtabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true
vim.opt.smartindent = true
vim.opt.smartindent = false
vim.opt.wrap = false
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undodir = os.getenv("HOME") .. "/.vim/undodir"
vim.opt.undofile = true
vim.opt.hlsearch = false
vim.opt.incsearch = true
vim.opt.termguicolors = true
vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"
vim.opt.isfname:append("@-@")
vim.opt.updatetime = 50
vim.opt.clipboard = "unnamedplus"
vim.opt.spelllang = "en_us"
vim.opt.spell = true
vim.opt.timeoutlen = 300 -- Lower than default (1000) to quickly trigger which-key
vim.opt.wrap = true
vim.opt.linebreak = true
vim.opt.breakindent = true

vim.api.nvim_set_keymap("n", "j", "gj", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "k", "gk", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<Down>", "gj", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<Up>", "gk", { noremap = true, silent = true })

function ToggleDiagnosticVirtualText()
	local current = vim.diagnostic.config().virtual_lines
	vim.diagnostic.config({
		virtual_lines = not current,
	})
end

vim.diagnostic.config({
	underline = true,
	virtual_text = false,
	virtual_lines = false,
	signs = true,
})

vim.keymap.set("n", "<localleader>d", ToggleDiagnosticVirtualText, { noremap = true, silent = true })
vim.keymap.set("n", "<S-d>", vim.diagnostic.open_float, { noremap = true, silent = true })

--

local function k(mode, lhs, rhs, desc, options)
	local defaults = { noremap = true, silent = true }

	options = vim.tbl_deep_extend("force", defaults, options or {})
	options.desc = desc -- Add description

	vim.keymap.set(mode, lhs, rhs, options)
end

k("n", "<leader>w", function()
	if vim.bo.filetype == "" or vim.bo.filetype == "nofile" or vim.fn.expand("%") == "" then
	-- vim.cmd("saveas " .. vim.fn.input("Save as: "))
	else
		vim.cmd("write")
		vim.api.nvim_command("stopinsert")
	end
end, "Experiment")

k("n", "<leader>e", function()
	require("neo-tree.command").execute({ toggle = true, dir = vim.fn.getcwd() })
end, "Explorer NeoTree")
k("n", "<leader>o", function()
	if vim.bo.filetype == "neo-tree" then
		vim.cmd.wincmd("p")
	else
		vim.cmd.Neotree("reveal")
	end
end, "Reveal file in NeoTree")

k("n", "<leader><leader>", "<cmd>FzfLua files<cr>", "Find files")
k("n", "<leader>/", "<cmd>FzfLua live_grep<cr>", "Grep")
k("n", "<leader>,", "<cmd>FzfLua buffers<cr>", "Switch Buffer")

k("n", "<leader>gg", "<cmd>LazyGit<cr>", "LazyGit")

-- Movement between splits
k("n", "<C-h>", function()
	if vim.fn.winnr() == vim.fn.winnr("h") then
		vim.system({ "swaymsg", "focus", "left" })
	else
		require("smart-splits").move_cursor_left()
	end
end, "Move to left split")

k("n", "<C-j>", function()
	if vim.fn.winnr() == vim.fn.winnr("j") then
		vim.system({ "swaymsg", "focus", "down" })
	else
		require("smart-splits").move_cursor_down()
	end
end, "Move to below split")

k("n", "<C-k>", function()
	if vim.fn.winnr() == vim.fn.winnr("k") then
		vim.system({ "swaymsg", "focus", "up" })
	else
		require("smart-splits").move_cursor_up()
	end
end, "Move to up split")

k("n", "<C-l>", function()
	if vim.fn.winnr() == vim.fn.winnr("l") then
		vim.system({ "swaymsg", "focus", "right" })
	else
		require("smart-splits").move_cursor_right()
	end
end, "Move to right split")

-- Resizing splits
k("n", "<C-A-h>", function()
	require("smart-splits").resize_left()
end, "Resize split left")
k("n", "<C-A-j>", function()
	require("smart-splits").resize_down()
end, "Resize split down")
k("n", "<C-A-k>", function()
	require("smart-splits").resize_up()
end, "Resize split up")
k("n", "<C-A-l>", function()
	require("smart-splits").resize_right()
end, "Resize split right")

-- Swapping buffers with adjacent splits
k("n", "<A-S-h>", function()
	require("smart-splits").swap_buf_left()
end, "Swap with left")
k("n", "<A-S-j>", function()
	require("smart-splits").swap_buf_down()
end, "Swap with down")
k("n", "<A-S-k>", function()
	require("smart-splits").swap_buf_up()
end, "Swap with up")
k("n", "<A-S-l>", function()
	require("smart-splits").swap_buf_right()
end, "Swap with right")

k({ "n", "v" }, "<localleader>f", "<cmd>Format<cr>", "Format")

-- Flash plugin
vim.keymap.set("n", "<leader>ls", function()
	require("flash").jump()
end)
vim.keymap.set("n", "<leader>lt", function()
	require("flash").treesitter()
end)
vim.keymap.set("n", "<leader>lr", function()
	require("flash").treesitter_search()
end)

-- vim.keymap.set('i', '<c-space>', function()
--   vim.lsp.completion.get()
-- end)

-- Themes
vim.cmd("luafile " .. vim.fn.expand("$HOME/.local/current-theme/neovim/theme.lua"))
local fwatch = require("fwatch")
fwatch.watch(
	vim.fn.expand("$HOME/.local/neovim-reload-theme"),
	"luafile " .. vim.fn.expand("$HOME/.local/current-theme/neovim/theme.lua")
)

require("ibl").setup()

require("go").setup()

local elixir = require("elixir")
local elixirls = require("elixir.elixirls")

elixir.setup({
	nextls = { enable = true },
	elixirls = {
		enable = true,
		settings = elixirls.settings({
			dialyzerEnabled = false,
			enableTestLenses = false,
		}),
		on_attach = function(client, bufnr)
			vim.keymap.set("n", "<space>fp", ":ElixirFromPipe<cr>", { buffer = true, noremap = true })
			vim.keymap.set("n", "<space>tp", ":ElixirToPipe<cr>", { buffer = true, noremap = true })
			vim.keymap.set("v", "<space>em", ":ElixirExpandMacro<cr>", { buffer = true, noremap = true })
		end,
	},
	projectionist = {
		enable = true,
	},
})

require("conform").setup({
	formatters_by_ft = {
		-- ruby = { "rubyfmt", "rubocop" },
		-- ruby = { "rubyfmt" },
		-- ruby = { "standardrb" },
		ruby = { "rufo" },
		javascript = { "prettier", stop_after_first = true },
		javascriptreact = { "prettier", stop_after_first = true },
		typescript = { "prettier", stop_after_first = true },
		typescriptreact = { "prettier", stop_after_first = true },
		graphql = { "prettier", stop_after_first = true },
		json = { "prettier", stop_after_first = true },
		jsonc = { "prettier", stop_after_first = true },
		html = { "prettier", stop_after_first = true },
		css = { "prettier", stop_after_first = true },
		markdown = { "prettier", stop_after_first = true },
		go = { "goimports", "gofmt" },
		nix = { "alejandra" },
		lua = { "stylua", stop_after_first = true },
	},

	format_on_save = function(bufnr)
		-- Disable with a global or buffer-local variable
		if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
			return
		end
		return { timeout_ms = 500, lsp_format = "fallback" }
	end,
})

vim.g.disable_autoformat = false
vim.api.nvim_create_user_command("FormatDisable", function(args)
	if args.bang then
		-- FormatDisable! will disable formatting just for this buffer
		vim.b.disable_autoformat = true
	else
		vim.g.disable_autoformat = true
	end
end, {
	desc = "Disable autoformat-on-save",
	bang = true,
})

vim.api.nvim_create_user_command("FormatEnable", function()
	vim.b.disable_autoformat = false
	vim.g.disable_autoformat = false
end, {
	desc = "Re-enable autoformat-on-save",
})

vim.api.nvim_create_user_command("Format", function(args)
	local range = nil
	if args.count ~= -1 then
		local end_line = vim.api.nvim_buf_get_lines(0, args.line2 - 1, args.line2, true)[1]
		range = {
			start = { args.line1, 0 },
			["end"] = { args.line2, end_line:len() },
		}
	end
	require("conform").format({ async = true, lsp_format = "fallback", range = range })
end, { range = true })

require("Comment").setup({
	pre_hook = require("ts_context_commentstring.integrations.comment_nvim").create_pre_hook(),
})

local function get_name_without_extension(path)
	return path:match("(.+)%..+$") or path -- Extracts filename without extension
end

require("neo-tree").setup({
	close_if_last_window = false, -- Close Neo-tree if it is the last window left in the tab
	popup_border_style = "rounded",
	enable_git_status = true,
	enable_diagnostics = true,
	open_files_do_not_replace_types = { "terminal", "trouble", "qf" }, -- when opening files, do not use windows containing these filetypes or buftypes
	open_files_using_relative_paths = false,
	sort_case_insensitive = false, -- used when sorting files and directories in the tree
	-- sort_function = function (a, b)
	--   return a.path:lower() < b.path:lower()
	-- end,
	-- sort_function = function (a,b)
	--       if a.type == b.type then
	--           return a.path > b.path
	--       else
	--           return a.type > b.type
	--       end
	--   end , -- this sorts files and directories descendantly
	default_component_configs = {
		container = {
			enable_character_fade = true,
		},
		indent = {
			indent_size = 2,
			padding = 1, -- extra padding on left hand side
			-- indent guides
			with_markers = true,
			indent_marker = "│",
			last_indent_marker = "└",
			highlight = "NeoTreeIndentMarker",
			-- expander config, needed for nesting files
			with_expanders = nil, -- if nil and file nesting is enabled, will enable expanders
			expander_collapsed = "",
			expander_expanded = "",
			expander_highlight = "NeoTreeExpander",
		},
		icon = {
			folder_closed = "",
			folder_open = "",
			folder_empty = "󰜌",
			provider = function(icon, node, state) -- default icon provider utilizes nvim-web-devicons if available
				if node.type == "file" or node.type == "terminal" then
					local success, web_devicons = pcall(require, "nvim-web-devicons")
					local name = node.type == "terminal" and "terminal" or node.name
					if success then
						local devicon, hl = web_devicons.get_icon(name)
						icon.text = devicon or icon.text
						icon.highlight = hl or icon.highlight
					end
				end
			end,
			-- The next two settings are only a fallback, if you use nvim-web-devicons and configure default icons there
			-- then these will never be used.
			default = "*",
			highlight = "NeoTreeFileIcon",
		},
		modified = {
			symbol = "[+]",
			highlight = "NeoTreeModified",
		},
		name = {
			trailing_slash = false,
			use_git_status_colors = true,
			highlight = "NeoTreeFileName",
		},
		git_status = {
			symbols = {
				-- Change type
				added = "", -- or "✚", but this is redundant info if you use git_status_colors on the name
				modified = "", -- or "", but this is redundant info if you use git_status_colors on the name
				deleted = "✖", -- this can only be used in the git_status source
				renamed = "󰁕", -- this can only be used in the git_status source
				-- Status type
				untracked = "",
				ignored = "",
				unstaged = "󰄱",
				staged = "",
				conflict = "",
			},
		},
		-- If you don't want to use these columns, you can set `enabled = false` for each of them individually
		file_size = {
			enabled = true,
			width = 12, -- width of the column
			required_width = 64, -- min width of window required to show this column
		},
		type = {
			enabled = true,
			width = 10, -- width of the column
			required_width = 122, -- min width of window required to show this column
		},
		last_modified = {
			enabled = true,
			width = 20, -- width of the column
			required_width = 88, -- min width of window required to show this column
		},
		created = {
			enabled = true,
			width = 20, -- width of the column
			required_width = 110, -- min width of window required to show this column
		},
		symlink_target = {
			enabled = false,
		},
	},
	-- A list of functions, each representing a global custom command
	-- that will be available in all sources (if not overridden in `opts[source_name].commands`)
	-- see `:h neo-tree-custom-commands-global`
	commands = {},
	window = {
		position = "left",
		width = 40,
		mapping_options = {
			noremap = true,
			nowait = true,
		},
		mappings = {
			["<space>"] = {
				"toggle_node",
				nowait = false, -- disable `nowait` if you have existing combos starting with this char that you want to use
			},
			["<2-LeftMouse>"] = "open",
			["<cr>"] = "open",
			["<esc>"] = "cancel", -- close preview or floating neo-tree window
			["P"] = { "toggle_preview", config = { use_float = true, use_image_nvim = true } },
			-- Read `# Preview Mode` for more information
			["l"] = "focus_preview",
			["S"] = "open_split",
			["s"] = "open_vsplit",
			-- ["S"] = "split_with_window_picker",
			-- ["s"] = "vsplit_with_window_picker",
			["t"] = "open_tabnew",
			-- ["<cr>"] = "open_drop",
			-- ["t"] = "open_tab_drop",
			["w"] = "open_with_window_picker",
			--["P"] = "toggle_preview", -- enter preview mode, which shows the current node without focusing
			["C"] = "close_node",
			-- ['C'] = 'close_all_subnodes',
			["z"] = "close_all_nodes",
			--["Z"] = "expand_all_nodes",
			["a"] = {
				"add",
				-- this command supports BASH style brace expansion ("x{a,b,c}" -> xa,xb,xc). see `:h neo-tree-file-actions` for details
				-- some commands may take optional config options, see `:h neo-tree-mappings` for details
				config = {
					show_path = "none", -- "none", "relative", "absolute"
				},
			},
			["A"] = "add_directory", -- also accepts the optional config.show_path option like "add". this also supports BASH style brace expansion.
			["d"] = "delete",
			["r"] = "rename",
			["b"] = "rename_basename",
			["y"] = "copy_to_clipboard",
			["x"] = "cut_to_clipboard",
			["p"] = "paste_from_clipboard",
			["c"] = "copy", -- takes text input for destination, also accepts the optional config.show_path option like "add":
			-- ["c"] = {
			--  "copy",
			--  config = {
			--    show_path = "none" -- "none", "relative", "absolute"
			--  }
			--}
			["m"] = "move", -- takes text input for destination, also accepts the optional config.show_path option like "add".
			["q"] = "close_window",
			["R"] = "refresh",
			["?"] = "show_help",
			["<"] = "prev_source",
			[">"] = "next_source",
			["i"] = "show_file_details",
			-- ["i"] = {
			--   "show_file_details",
			--   -- format strings of the timestamps shown for date created and last modified (see `:h os.date()`)
			--   -- both options accept a string or a function that takes in the date in seconds and returns a string to display
			--   -- config = {
			--   --   created_format = "%Y-%m-%d %I:%M %p",
			--   --   modified_format = "relative", -- equivalent to the line below
			--   --   modified_format = function(seconds) return require('neo-tree.utils').relative_date(seconds) end
			--   -- }
			-- },
		},
	},
	nesting_rules = {},
	filesystem = {
		filtered_items = {
			visible = false, -- when true, they will just be displayed differently than normal items
			hide_dotfiles = true,
			hide_gitignored = true,
			hide_hidden = true, -- only works on Windows for hidden files/directories
			hide_by_name = {
				--"node_modules"
			},
			hide_by_pattern = { -- uses glob style patterns
				--"*.meta",
				--"*/src/*/tsconfig.json",
			},
			always_show = { -- remains visible even if other settings would normally hide it
				--".gitignored",
			},
			always_show_by_pattern = { -- uses glob style patterns
				--".env*",
			},
			never_show = { -- remains hidden even if visible is toggled to true, this overrides always_show
				--".DS_Store",
				--"thumbs.db"
			},
			never_show_by_pattern = { -- uses glob style patterns
				--".null-ls_*",
			},
		},
		follow_current_file = {
			enabled = false, -- This will find and focus the file in the active buffer every time
			--               -- the current file is changed while the tree is open.
			leave_dirs_open = false, -- `false` closes auto expanded dirs, such as with `:Neotree reveal`
		},
		group_empty_dirs = false, -- when true, empty folders will be grouped together
		hijack_netrw_behavior = "open_default", -- netrw disabled, opening a directory opens neo-tree
		-- in whatever position is specified in window.position
		-- "open_current",  -- netrw disabled, opening a directory opens within the
		-- window like netrw would, regardless of window.position
		-- "disabled",    -- netrw left alone, neo-tree does not handle opening dirs
		use_libuv_file_watcher = false, -- This will use the OS level file watchers to detect changes
		-- instead of relying on nvim autocmd events.
		window = {
			mappings = {
				["<bs>"] = "navigate_up",
				["."] = "set_root",
				["H"] = "toggle_hidden",
				["/"] = "fuzzy_finder",
				["D"] = "fuzzy_finder_directory",
				["#"] = "fuzzy_sorter", -- fuzzy sorting using the fzy algorithm
				-- ["D"] = "fuzzy_sorter_directory",
				["f"] = "filter_on_submit",
				["<c-x>"] = "clear_filter",
				["[g"] = "prev_git_modified",
				["]g"] = "next_git_modified",
				["o"] = { "show_help", nowait = false, config = { title = "Order by", prefix_key = "o" } },
				["oc"] = { "order_by_created", nowait = false },
				["od"] = { "order_by_diagnostics", nowait = false },
				["og"] = { "order_by_git_status", nowait = false },
				["om"] = { "order_by_modified", nowait = false },
				["on"] = { "order_by_name", nowait = false },
				["os"] = { "order_by_size", nowait = false },
				["ot"] = { "order_by_type", nowait = false },
				-- ['<key>'] = function(state) ... end,
			},
			fuzzy_finder_mappings = { -- define keymaps for filter popup window in fuzzy_finder_mode
				["<down>"] = "move_cursor_down",
				["<C-n>"] = "move_cursor_down",
				["<up>"] = "move_cursor_up",
				["<C-p>"] = "move_cursor_up",
				["<esc>"] = "close",
				-- ['<key>'] = function(state, scroll_padding) ... end,
			},
		},

		commands = {}, -- Add a custom command or override a global one using the same function name
	},
	buffers = {
		follow_current_file = {
			enabled = true, -- This will find and focus the file in the active buffer every time
			--              -- the current file is changed while the tree is open.
			leave_dirs_open = false, -- `false` closes auto expanded dirs, such as with `:Neotree reveal`
		},
		group_empty_dirs = true, -- when true, empty folders will be grouped together
		show_unloaded = true,
		window = {
			mappings = {
				["bd"] = "buffer_delete",
				["<bs>"] = "navigate_up",
				["."] = "set_root",
				["o"] = { "show_help", nowait = false, config = { title = "Order by", prefix_key = "o" } },
				["oc"] = { "order_by_created", nowait = false },
				["od"] = { "order_by_diagnostics", nowait = false },
				["om"] = { "order_by_modified", nowait = false },
				["on"] = { "order_by_name", nowait = false },
				["os"] = { "order_by_size", nowait = false },
				["ot"] = { "order_by_type", nowait = false },
			},
		},
	},
	git_status = {
		window = {
			position = "float",
			mappings = {
				["A"] = "git_add_all",
				["gu"] = "git_unstage_file",
				["ga"] = "git_add_file",
				["gr"] = "git_revert_file",
				["gc"] = "git_commit",
				["gp"] = "git_push",
				["gg"] = "git_commit_and_push",
				["o"] = { "show_help", nowait = false, config = { title = "Order by", prefix_key = "o" } },
				["oc"] = { "order_by_created", nowait = false },
				["od"] = { "order_by_diagnostics", nowait = false },
				["om"] = { "order_by_modified", nowait = false },
				["on"] = { "order_by_name", nowait = false },
				["os"] = { "order_by_size", nowait = false },
				["ot"] = { "order_by_type", nowait = false },
			},
		},
	},
})
require("window-picker").setup({
	filter_rules = {
		include_current_win = false,
		autoselect_one = true,
		-- filter using buffer options
		bo = {
			-- if the file type is one of following, the window will be ignored
			filetype = { "neo-tree", "neo-tree-popup", "notify" },
			-- if the buffer type is one of following, the window will be ignored
			buftype = { "terminal", "quickfix" },
		},
	},
})

require("which-key")
require("smart-splits").setup()
require("neotest").setup({
	adapters = {
		require("neotest-minitest")({}),
	},
})

require("nvim-treesitter.configs").setup({
	-- indent = {
	--   enable = false,
	-- },
	highlight = {
		enable = true,
		-- https://gitlab.com/theoreichel/tree-sitter-slim/-/issues/1
		-- пока не решится, надеюсь поможет
		disable = { "slim" },
	},
})

require("lualine").setup()

local MiniIcons = require("mini.icons")
MiniIcons.setup()
MiniIcons.mock_nvim_web_devicons()
MiniIcons.mock_nvim_web_devicons()

require("mini.bufremove").setup()
require("mini.surround").setup()
require("mini.move").setup()
-- require('mini.indentscope').setup({
--   delay = 0,
--   animation = require('mini.indentscope').gen_animation.none()
-- })
--
-- LSP

vim.lsp.enable({ "ts_ls", "nil_ls", "graphql", "cssls", "html", "lua_ls" })
vim.lsp.inlay_hint.enable()

-- local lspconfig = require('lspconfig')

-- Configure gopls.
-- lspconfig.gopls.setup({})
-- lspconfig.nil_ls.setup({})
-- lspconfig.ts_ls.setup({})

-- Use LspAttach autocommand to only map the following keys
-- after the language server attaches to the current buffer
vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("UserLspConfig", {}),
	callback = function(ev)
		-- Enable completion triggered by <c-x><c-o>
		vim.bo[ev.buf].omnifunc = "v:lua.vim.lsp.omnifunc"

		-- Buffer local mappings.
		-- See `:help vim.lsp.*` for documentation on any of the below functions
		local opts = { buffer = ev.buf }
		vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
		vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
		vim.keymap.set("n", "gy", vim.lsp.buf.type_definition, opts)

		-- Пожалуй положусь на conform.nvim в вопросе форматирования
		-- vim.keymap.set('n', '<space>f', function()
		--   vim.lsp.buf.format { async = true }
		-- end, opts)

		local client = vim.lsp.get_client_by_id(ev.data.client_id)
		if client:supports_method("textDocument/completion") then
			vim.lsp.completion.enable(true, client.id, ev.buf, { autotrigger = false })
		end
	end,
})

local has_words_before = function()
	local line, col = table.unpack(vim.api.nvim_win_get_cursor(0))
	return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match("%s") == nil
end

local cmp = require("cmp")
cmp.setup({
	mapping = {
		["<Tab>"] = cmp.mapping(function(fallback)
			if cmp.visible() then
				cmp.select_next_item()
			-- elseif vim.fn["vsnip#available"](1) == 1 then
			--   feedkey("<Plug>(vsnip-expand-or-jump)", "")
			elseif has_words_before() then
				cmp.complete()
			else
				fallback() -- The fallback function sends a already mapped key. In this case, it's probably `<Tab>`.
			end
		end, { "i", "s" }),
		["<S-Tab>"] = cmp.mapping(function()
			if cmp.visible() then
				cmp.select_prev_item()
				-- elseif vim.fn["vsnip#jumpable"](-1) == 1 then
				--   feedkey("<Plug>(vsnip-jump-prev)", "")
			end
		end, { "i", "s" }),
	},
	sources = {
		{ name = "async_path" },
		{ name = "nvim_lsp" },
	},
})

require("codecompanion").setup({
	strategies = {
		chat = {
			adapter = "openrouter",
		},
		inline = {
			adapter = "openrouter",
		},
	},
	adapters = {
		openrouter = function()
			return require("codecompanion.adapters").extend("openai_compatible", {
				env = {
					url = "https://openrouter.ai/api",
					api_key = "OPENROUTER_API_KEY",
					chat_url = "/v1/chat/completions",
					models_endpoint = "/v1/models",
				},
				schema = {
					model = {
						default = "google/gemma-3-27b-it",
					},
				},
			})
		end,
		openrouter_claude = function()
			return require("codecompanion.adapters").extend("openai_compatible", {
				env = {
					url = "https://openrouter.ai/api",
					api_key = "OPENROUTER_API_KEY",
					chat_url = "/v1/chat/completions",
					models_endpoint = "/v1/models",
				},
				schema = {
					model = {
						default = "anthropic/claude-3.7-sonnet",
					},
				},
			})
		end,
	},
})
