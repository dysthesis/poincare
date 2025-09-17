local M = {}
function M.normalise_reference(ref)
  if type(ref) == 'table' then
    ref = ref[1]
  end
  if type(ref) ~= 'string' then
    return nil
  end
  ref = (ref:gsub('^%s+', ''):gsub('%s+$', ''))

  if ref:match('^doi:%s*10%.%d+/.+') or ref:match('^10%.%d+/.+') then
    local doi = ref:gsub('^doi:%s*', '')
    return 'https://doi.org/' .. doi
  end
  if ref:match('^arXiv:%s*%S+') then
    local id = ref:match('^arXiv:%s*(%S+)')
    return 'https://arxiv.org/abs/' .. id
  end

  if ref:match('^https?://') then
    return ref
  end
  return ref
end

function M.open_reference(bufnr)
  local fm = require('utils.frontmatter')
  local val, err = fm.get('reference', { bufnr = bufnr })
  if err or val == nil then
    vim.notify("No front-matter key 'reference' found", vim.log.levels.WARN)
    return
  end
  local target = M.normalise_reference(val)
  if not target then
    vim.notify("'reference' is not a string or list of strings", vim.log.levels.ERROR)
    return
  end

  if vim.system then
    vim.system({ 'xdg-open', target }, { detach = true })
  elseif vim.ui and vim.ui.open then
    pcall(vim.ui.open, target)
  else
    vim.fn.jobstart({ 'xdg-open', target }, { detach = true })
  end
end

return M
