local kind_icons = {
  -- LLM Provider icons
  claude = '󰋦',
  openai = '󱢆',
  codestral = '󱎥',
  gemini = '',
  Groq = '',
  Openrouter = '󱂇',
  Ollama = '󰳆',
  ['Llama.cpp'] = '󰳆',
  Deepseek = '',
}
require('lz.n').load {
  'minuet-ai.nvim',
  after = function()
    require('minuet').setup {
      provider = 'openai_fim_compatible',
      virtualtext = {
        auto_trigger_ft = { '*' },
        keymap = {
          -- accept whole completion
          accept = '<M-l>',
          -- accept one line
          accept_line = '<M-;>',
          prev = '<M-k>',
          -- Cycle to next completion item, or manually invoke completion
          next = '<M-j>',
          dismiss = '<M-e>',
        },
        show_on_completion_menu = true,
      },
      n_completions = 1, -- recommend for local model for resource saving
      -- I recommend beginning with a small context window size and incrementally
      -- expanding it, depending on your local computing power. A context window
      -- of 512, serves as an good starting point to estimate your computing
      -- power. Once you have a reliable estimate of your local computing power,
      -- you should adjust the context window to a larger value.
      context_window = 512,
      provider_options = {
        openai_fim_compatible = {
          -- For Windows users, TERM may not be present in environment variables.
          -- Consider using APPDATA instead.
          api_key = 'TERM',
          name = 'Ollama',
          end_point = 'http://localhost:11434/v1/completions',
          model = 'qwen2.5-coder:7b',
          optional = {
            max_tokens = 128,
            top_p = 0.9,
          },
        },
      },
    }
  end,
}
