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
		"Saghen/blink.cmp",
		build = "cargo build --locked --release --target-dir target",
		version = "*",
	},
	"Saghen/blink.compat", -- compatibility layer
	"rafamadriz/friendly-snippets",

	{ "nvim-treesitter/nvim-treesitter", build = ":TSUpdate" }, -- tree sitter integration
	"neovim/nvim-lspconfig", -- configurations for LSPs
	"j-hui/fidget.nvim",
	"nvimdev/lspsaga.nvim",
	"stevearc/conform.nvim",

	-- Language extensions
	"p00f/clangd_extensions.nvim",

	"kdheepak/monochrome.nvim", -- a theme
	"echasnovski/mini.pick", -- a fuzzy finder
	"echasnovski/mini.surround", -- add a surround motion
	"nvim-neorocks/lz.n", -- a lazy loader
	"NeogitOrg/neogit", -- a git ui
	"sindrets/diffview.nvim", -- a nice diff viewing ui
	"lewis6991/gitsigns.nvim", -- some nice git integration
	"stevearc/oil.nvim",
	{ "ThePrimeagen/harpoon", branch = "harpoon2" },

	"altermo/ultimate-autopair.nvim",

	-- common dependencies
	"nvim-lua/plenary.nvim",
	"nvim-tree/nvim-web-devicons",
}

-- Call helper function
bootstrap_paq(plugins)

-- Configure the plugins
require("plugins.monochrome-nvim")
require("plugins.mini-pick")
require("plugins.neogit")
require("plugins.gitsigns")
require("plugins.blink")
require("plugins.lspconfig")
require("plugins.ultimate-autopair")
require("plugins.conform")
require("plugins.harpoon")

-- for _, plugin in ipairs(plugins) do
-- 	local formatted = 'plugins.' .. plugin:match('/(.*)'):gsub('%.', '-') or ''
-- 	-- Load the configuration only if it exists
-- 	local ok, config = pcall(require, formatted)
-- 	if not ok then
-- 		return
-- 	end
-- done
