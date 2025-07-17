require('lz.n').load {
  'avante.nvim',
  after = function()
    require('img-clip').setup {
      -- recommended settings
      default = {
        embed_image_as_base64 = false,
        prompt_for_file_name = false,
        drag_and_drop = {
          insert_mode = true,
        },
        -- required for Windows users
        use_absolute_path = true,
      },
    }
    require('render-markdown').setup {
      file_types = { 'markdown', 'Avante' },
    }
    require('avante').setup {
      provider = 'ollama',
      providers = {
        ollama = {
          max_tokens = 4096,
          endpoint = 'http://localhost:11434',
          model = 'deepseek-r1:14b',
          temperature = 0.75,
          api_key_name = '',
          disable_tools = true,
        },

        behaviour = {
          auto_suggestions = false, -- Experimental stage
          auto_set_highlight_group = true,
          auto_set_keymaps = true,
          auto_apply_diff_after_generation = false,
          support_paste_from_clipboard = true,
        },
        windows = {
          ask = {
            floating = true, -- Open the 'AvanteAsk' prompt in a floating window
          },
        },
      },
    }
  end,
}
