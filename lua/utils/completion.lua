-- From https://gist.github.com/MariaSolOs/2e44a86f569323c478e5a078d0cf98cc
---Utility for keymap creation.
---@param lhs string
---@param rhs string|function
---@param opts string|table
---@param mode? string|string[]
local function keymap(lhs, rhs, opts, mode)
  opts = type(opts) == 'string' and { desc = opts } or vim.tbl_extend('error', opts --[[@as table]], { buffer = bufnr })
  mode = mode or 'n'
  vim.keymap.set(mode, lhs, rhs, opts)
end

---For replacing certain <C-x>... keymaps.
---@param keys string
local function feedkeys(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'n', true)
end

---Is the completion menu open?
local function pumvisible()
  return tonumber(vim.fn.pumvisible()) ~= 0
end

return {
  setup = function(client, bufnr)
    local kind_icons = {
      '󰊄', -- Text
      '󰡱', -- Method
      '󰊕', -- Function
      '', -- Constructor
      '󰓽', -- Field
      '', -- Variable
      '󰠱', -- Class
      '', -- Interface
      '󰕳', -- Module
      '󰜢', -- Property
      '󰑭', -- Unit
      '󰎠', -- Value
      '', -- Enum
      '󰌋', -- Keyword
      '', -- Snippet
      '󰏘', -- Color
      '󰈚', -- File
      '', -- Reference
      '󰉋', -- Folder
      '󰗅', -- EnumMember
      '󰉒', -- Constant
      '󰙏', -- Struct
      '󰀫', -- Event
      '󰏺', -- Operator
      '󰰄', -- TypeParameter
    }

    for i, icon in ipairs(kind_icons) do
      vim.lsp.protocol.CompletionItemKind[i] = icon
    end

    -- Enable completion and configure keybindings.
    if client.supports_method('textDocument/completion') then
      vim.lsp.completion.enable(true, client.id, bufnr, { autotrigger = true })

      -- Use enter to accept completions.
      keymap('<cr>', function()
        return pumvisible() and '<C-y>' or '<cr>'
      end, { expr = true }, 'i')

      -- Use slash to dismiss the completion menu.
      keymap('/', function()
        return pumvisible() and '<C-e>' or '/'
      end, { expr = true }, 'i')

      vim.keymap.set('i', '<c-space>', '<c-x><c-o>', {
        buffer = bufnr,
        desc = 'omnicompletion',
      })

      vim.api.nvim_create_augroup('completion', { clear = false })
      vim.api.nvim_clear_autocmds { group = 'completion', buffer = bufnr }
      vim.api.nvim_create_autocmd('TextChangedI', {
        desc = 'auto-completion',
        group = 'completion',
        buffer = bufnr,
        callback = function()
          if vim.fn.pumvisible() ~= 0 then
            return
          end
          if vim.g.pum_timer then
            vim.fn.timer_stop(vim.g.pum_timer)
          end

          local current_line = vim.api.nvim_get_current_line()
          local cursor_position = vim.api.nvim_win_get_cursor(0)[2]
          local text_before_cursor = current_line:sub(1, cursor_position)
          local trigger_characters = table.concat(client.server_capabilities.completionProvider.triggerCharacters)
          local trigger_pattern = ('[%%w%s]$'):format(trigger_characters)
          if text_before_cursor:match(trigger_pattern) then
            vim.g.pum_timer = vim.fn.timer_start(300, function()
              if vim.api.nvim_get_mode().mode:match('^[^i]') then
                return
              end
              vim.api.nvim_feedkeys(vim.api.nvim_eval([["\<c-x>\<c-o>"]]), 'n', false)
            end)
          end
        end,
      })

      -- Use <C-n> to navigate to the next completion or:
      -- - Trigger LSP completion.
      -- - If there's no one, fallback to vanilla omnifunc.
      keymap('<C-n>', function()
        if pumvisible() then
          feedkeys('<C-n>')
        else
          if next(vim.lsp.get_clients { bufnr = 0 }) then
            vim.lsp.completion.trigger()
          else
            if vim.bo.omnifunc == '' then
              feedkeys('<C-x><C-n>')
            else
              feedkeys('<C-x><C-o>')
            end
          end
        end
      end, 'Trigger/select next completion', 'i')

      -- Buffer completions.
      keymap('<C-u>', '<C-x><C-n>', { desc = 'Buffer completions' }, 'i')

      -- Use <Tab> to accept a Copilot suggestion, navigate between snippet tabstops,
      -- or select the next completion.
      -- Do something similar with <S-Tab>.
      keymap('<Tab>', function()
        if pumvisible() then
          feedkeys('<C-n>')
        elseif vim.snippet.active { direction = 1 } then
          vim.snippet.jump(1)
        else
          feedkeys('<Tab>')
        end
      end, {}, { 'i', 's' })
      keymap('<S-Tab>', function()
        if pumvisible() then
          feedkeys('<C-p>')
        elseif vim.snippet.active { direction = -1 } then
          vim.snippet.jump(-1)
        else
          feedkeys('<S-Tab>')
        end
      end, {}, { 'i', 's' })

      -- Inside a snippet, use backspace to remove the placeholder.
      keymap('<BS>', '<C-o>s', {}, 's')
    end
  end,
}
