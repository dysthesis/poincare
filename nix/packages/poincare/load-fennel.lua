-- Check if hotpot.nvim is installed
if pcall(require, 'hotpot') then
  -- hotpot.nvim is found! We can continue normally.
  require('hotpot').setup {
    build = {
      { verbose = true },
      { 'init.fnl', true },
    },
    clean = true,
  }
  require('init') -- load the fennel entrypoint once Hotpot is ready
else
  -- hotpot.nvim is not installed, error...
  vim.notify('Failed to load hotpot.nvim!', vim.log.levels.ERROR)
end
