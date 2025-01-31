-- Bootstrap the package manager
local function clone_paq()
	local path = vim.fn.stdpath("data") .. "/site/pack/paqs/start/paq-nvim"
	local is_installed = vim.fn.empty(vim.fn.glob(path)) == 0
	if not is_installed then
		vim.fn.system({ "git", "clone", "--depth=1", "https://github.com/savq/paq-nvim.git", path })
		return true
	end
end

local function bootstrap_paq(packages)
	local first_install = clone_paq()
	vim.cmd.packadd("paq-nvim")
	local paq = require("paq")
	if first_install then
		vim.notify("Installing plugins... If prompted, hit Enter to continue.")
	end

	-- Read and install packages
	paq(packages)
	paq.install()
end

-- Add plugins here
local plugins = {
	"savq/paq-nvim", -- the package manager itself

	-- Completion
	{ -- supposedly faster than nvim-cmp
		"saghen/blink.cmp",
		build = "cargo build --locked --release --target-dir target",
		version = "*",
	},
	"saghen/blink.compat", -- compatibility layer
	"rafamadriz/friendly-snippets",

	{ "nvim-treesitter/nvim-treesitter", build = ":TSUpdate" }, -- tree sitter integration
	"neovim/nvim-lspconfig", -- configurations for LSPs
	"stevearc/conform.nvim",

	-- Language extensions
	"p00f/clangd_extensions.nvim",
	"saecki/crates.nvim", -- rust crates
	"mrcjkb/rustaceanvim", -- rust stuff

	-- Notetaking
	"zk-org/zk-nvim",

	-- Themes
	"slugbyte/lackluster.nvim",

	"echasnovski/mini.pick", -- a fuzzy finder
	"echasnovski/mini.surround", -- add a surround motion
	"echasnovski/mini.icons", -- icons library
	"echasnovski/mini.ai", -- more a/i textobjects
	"nvim-neorocks/lz.n", -- a lazy loader
	"NeogitOrg/neogit", -- a git ui
	"sindrets/diffview.nvim", -- a nice diff viewing ui
	"lewis6991/gitsigns.nvim", -- some nice git integration
	"stevearc/oil.nvim",

	"altermo/ultimate-autopair.nvim",
	"christoomey/vim-tmux-navigator",
}

-- Call helper function
bootstrap_paq(plugins)

vim.g.codelldb_path = "~/.local/share/codelldb"

-- Load plugin configurations, if they exist
for _, plugin in ipairs(plugins) do
	local name = ""
	if type(plugin) == "table" then
		name = plugin[1]
	else
		name = plugin
	end
	name = name:match(".*/(.*)"):gsub("%.", "-") or ""

	local formatted = "plugins." .. name
	-- Load the configuration only if it exists
	local ok, _ = pcall(require, formatted)
end
