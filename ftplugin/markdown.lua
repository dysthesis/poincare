-- properly detect markdown
vim.g.conceallevel = 2
vim.cmd([[
augroup filetypedetect
  autocmd!
  " Set .md files to use markdown syntax
  autocmd BufNewFile,BufRead *.md set syntax=markdown
augroup END
]])

vim.api.nvim_create_autocmd("FileType", {
	group = vim.api.nvim_create_augroup("wrap_spell", { clear = true }),
	pattern = { "gitcommit", "markdown" },
	callback = function()
		vim.opt_local.textwidth = 80
		vim.opt_local.wrap = true
		vim.opt_local.spell = true
		vim.opt_local.tabstop = 2
		vim.opt_local.softtabstop = 2
		vim.opt_local.shiftwidth = 2
		vim.opt_local.expandtab = true
	end,
})
