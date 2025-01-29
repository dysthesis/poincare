-- Formatter
require("lz.n").load({
	"conform.nvim",
	event = "BufWritePre",
	after = function()
		require("conform").setup({
			notify_on_error = false,
			format_on_save = function(bufnr)
				-- Disable "format_on_save lsp_fallback" for languages that don't
				-- have a well standardized coding style. You can add additional
				-- languages here or re-enable it for the disabled ones.
				local disable_filetypes = {}
				return {
					timeout_ms = 500,
					lsp_fallback = not disable_filetypes[vim.bo[bufnr].filetype],
				}
			end,
			format_after_save = {
				async = true,
			},
			formatters_by_ft = {
				lua = { "stylua" },
				markdown = { "markdownlint" },
				nix = { "alejandra" },
				c = { "clang-format" },
				rust = { "rustfmt" },
			},
		})
	end,
})
