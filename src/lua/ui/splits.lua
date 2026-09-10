local M = {}

local resize_step = 3

local directions = {
  h = "L",
  j = "D",
  k = "U",
  l = "R",
}

local nested = false

local function tmux(args)
  if not vim.env.TMUX then
    return
  end

  vim.fn.jobstart(vim.list_extend({ "tmux" }, args), { detach = true })
end

local function at_edge(direction)
  return vim.fn.winnr() == vim.fn.winnr(direction)
end

local function position(start, finish)
  if at_edge(start) then
    return "start"
  end

  if at_edge(finish) then
    return "last"
  end

  return "middle"
end

local function resize(command, sign, amount)
  vim.cmd(("%s %s%d"):format(command, sign, amount))
end

local function resize_horizontal(direction, amount)
  -- No vertical separator exists inside Neovim.
  if at_edge("h") and at_edge("l") then
    tmux({
      "resize-pane",
      "-" .. directions[direction],
      tostring(amount),
    })
    return
  end

  local pos = position("h", "l")

  local sign
  if pos == "last" then
    sign = direction == "l" and "-" or "+"
  else
    sign = direction == "l" and "+" or "-"
  end

  local before = vim.api.nvim_win_get_position(0)[2]

  resize("vertical resize", sign, amount)

  if pos ~= "middle" then
    return
  end

  local after = vim.api.nvim_win_get_position(0)[2]

  local correction
  if sign == "-" and after > before then
    correction = "+"
  elseif sign == "+" and after < before then
    correction = "-"
  end

  if not correction then
    return
  end

  -- Neovim moved the wrong separator. Undo the change
  -- and apply it through the window to the right.
  resize("vertical resize", correction, amount)

  vim.cmd("wincmd l")
  resize("vertical resize", correction, amount)
  vim.cmd("wincmd h")
end

local function resize_vertical(direction, amount)
  -- No horizontal separator exists inside Neovim.
  if at_edge("k") and at_edge("j") then
    tmux({
      "resize-pane",
      "-" .. directions[direction],
      tostring(amount),
    })
    return
  end

  local pos = position("k", "j")

  local sign
  if pos == "last" then
    sign = direction == "j" and "-" or "+"
  else
    sign = direction == "j" and "+" or "-"
  end

  local before = vim.api.nvim_win_get_position(0)[1]

  resize("resize", sign, amount)

  if pos ~= "middle" then
    return
  end

  local after = vim.api.nvim_win_get_position(0)[1]

  -- Neovim has a slightly awkward bottom-edge case when
  -- resizing stacked middle windows.
  if at_edge("j") then
    local inverse = sign == "+" and "-" or "+"

    resize("resize", inverse, amount)

    vim.cmd("wincmd j")
    resize("resize", inverse, amount)

    return
  end

  local correction
  if sign == "-" and after > before then
    correction = "+"
  elseif sign == "+" and after < before then
    correction = "-"
  end

  if not correction then
    return
  end

  resize("resize", correction, amount)

  vim.cmd("wincmd k")
  resize("resize", correction, amount)
  vim.cmd("wincmd j")
end

function M.move(direction)
  local current = vim.api.nvim_get_current_win()

  vim.cmd("wincmd " .. direction)

  if vim.api.nvim_get_current_win() == current then
    tmux({
      "select-pane",
      "-" .. directions[direction],
    })
  end
end

function M.resize(direction, amount)
  amount = (amount or resize_step) * vim.v.count1

  if direction == "h" or direction == "l" then
    resize_horizontal(direction, amount)
  else
    resize_vertical(direction, amount)
  end
end

local function setup_tmux()
  local pane = vim.env.TMUX_PANE

  if not pane then
    return
  end

  -- Preserve @pane-is-vim when this Neovim is nested
  -- inside another Neovim instance.
  local value = vim.fn.system({
    "tmux",
    "show-options",
    "-pqvt",
    pane,
    "@pane-is-vim",
  })

  nested = tonumber(vim.trim(value)) == 1

  if not nested then
    tmux({
      "set-option",
      "-pt",
      pane,
      "@pane-is-vim",
      "1",
    })
  end

  vim.api.nvim_create_autocmd("VimSuspend", {
    callback = function()
      if not nested then
        tmux({
          "set-option",
          "-pt",
          pane,
          "@pane-is-vim",
          "0",
        })
      end
    end,
  })

  vim.api.nvim_create_autocmd("VimResume", {
    callback = function()
      if not nested then
        tmux({
          "set-option",
          "-pt",
          pane,
          "@pane-is-vim",
          "1",
        })
      end
    end,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      if not nested then
        tmux({
          "set-option",
          "-pt",
          pane,
          "@pane-is-vim",
          "0",
        })
      end
    end,
  })
end

function M.setup()
  setup_tmux()

  for _, direction in ipairs({ "h", "j", "k", "l" }) do
    local direction = direction

    vim.keymap.set("n", "<C-" .. direction .. ">", function()
      M.move(direction)
    end)

    vim.keymap.set("n", "<M-" .. direction .. ">", function()
      M.resize(direction)
    end)
  end
end

return M
