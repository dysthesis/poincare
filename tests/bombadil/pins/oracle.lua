local M = {}

local function project()
  return vim.fs.root(0, ".git") or vim.fn.getcwd()
end

local function state_file(root)
  local state_dir = vim.fs.joinpath(vim.fn.stdpath("state"), "pins")
  local hash = vim.fn.sha256(vim.fs.normalize(root))

  return vim.fs.joinpath(state_dir, hash .. ".json")
end

local function read_pins(root)
  local path = state_file(root)

  if vim.fn.filereadable(path) == 0 then
    return {}
  end

  local text = table.concat(vim.fn.readfile(path), "\n")
  local decoded = vim.json.decode(text)

  assert(type(decoded) == "table")

  return decoded
end

local last = {}

local function check_pins()
  local root = vim.fs.normalize(assert(project()))
  local path = state_file(root)
  local pins = read_pins(root)

  last = {
    buffer = vim.api.nvim_buf_get_name(0),
    root = root,
    state_file = path,
    pins = pins,
  }

  local prefix = root .. "/"

  for _, pin in ipairs(pins) do
    pin = vim.fs.normalize(pin)

    assert(
      pin == root or vim.startswith(pin, prefix),
      ("POINCARE_INVARIANT: pin %q outside project %q"):format(pin, root)
    )
  end
end

function M.setup()
  vim.api.nvim_create_user_command("PoincareCheck", function()
    local ok, err = pcall(check_pins)

    if not ok then
      last.error = tostring(err)

      vim.fn.writefile({
        vim.json.encode(last),
      }, "/tmp/poincare-bombadil/oracle-failure.json")

      vim.cmd("cquit 97")
    end
  end, {})
end

return M
