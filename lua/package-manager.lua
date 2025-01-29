-- Bootstrap the package manager
local function clone_paq()
    local path = vim.fn.stdpath("data") .. "/site/pack/paqs/start/paq-nvim"
    local is_installed = vim.fn.empty(vim.fn.glob(path)) == 0
    if not is_installed then
	vim.fn.system { "git", "clone", "--depth=1", "https://github.com/savq/paq-nvim.git", path }
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

local plugins = {
    "savq/paq-nvim",

    { 'nvim-treesitter/nvim-treesitter', build = ':TSUpdate' },

    "kdheepak/monochrome.nvim",
    "echasnovski/mini.pick",
    "nvim-neorocks/lz.n",
    "NeogitOrg/neogit",
    "sindrets/diffview.nvim",

    -- common dependencies
    "nvim-lua/plenary.nvim",
}

-- Call helper function
bootstrap_paq(plugins)

-- Configure the plugins
require('plugins.monochrome-nvim')
require('plugins.mini-pick')
require('plugins.neogit')

-- for _, plugin in ipairs(plugins) do
-- 	local formatted = "plugins." .. plugin:match("/(.*)"):gsub("%.", "-") or ""
-- 	-- Load the configuration only if it exists
-- 	local ok, config = pcall(require, formatted)
-- 	if not ok then
-- 		return
-- 	end
-- done
