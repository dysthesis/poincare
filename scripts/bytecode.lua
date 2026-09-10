local bit = require("bit")
local jit = require("jit")
local jutil = require("jit.util")
local vmdef = require("jit.vmdef")
local vim = assert(rawget(_G, "vim"))

local opcode_width = 6
local opcode_bits = 8
local jump_mode = 13
local jump_bias = 0x7fff
if #vmdef.bcnames == 0 or #vmdef.bcnames % opcode_width ~= 0 then
  error("incompatible LuaJIT bcnames width")
end
local opcode_count = #vmdef.bcnames / opcode_width
if opcode_count > 2 ^ opcode_bits then
  error("LuaJIT opcode table exceeds instruction encoding")
end
local opcode_names = {}
local seen_opcodes = {}
for opcode_id = 0, opcode_count - 1 do
  local chunk = vmdef.bcnames:sub(
    opcode_id * opcode_width + 1,
    (opcode_id + 1) * opcode_width
  )
  local name = chunk:match("^(%S+)%s*$")
  if not name or seen_opcodes[name] then
    error("incompatible LuaJIT opcode table")
  end
  seen_opcodes[name] = true
  opcode_names[#opcode_names + 1] = name
end

local manifest_path = _G.arg[1]
local manifest_file, open_error = io.open(manifest_path, "rb")
if not manifest_file then
  error(open_error)
end
local manifest = vim.json.decode(manifest_file:read("*a"))
manifest_file:close()

local function json_info(fn)
  local info = jutil.funcinfo(fn)
  local result = {}
  for key, value in pairs(info) do
    if type(value) == "string" or type(value) == "number" or type(value) == "boolean" then
      result[key] = value
    end
  end
  return result
end

local function prototype(fn, id, parent_id, gcconst_index)
  local info = json_info(fn)
  local instructions = {}
  for pc = 1, info.bytecodes - 1 do
    local instruction, mode = jutil.funcbc(fn, pc)
    local opcode_id = bit.band(instruction, 0xff)
    local word = instruction < 0 and instruction + 2 ^ 32 or instruction
    local item = {
      pc = pc,
      opcode = opcode_names[opcode_id + 1],
      opcode_id = opcode_id,
      word = word,
      mode = mode,
      line = jutil.funcinfo(fn, pc).currentline or vim.NIL,
    }
    if bit.band(bit.rshift(mode, 7), 15) == jump_mode then
      local operand = bit.band(bit.rshift(instruction, 16), 0xffff)
      item.target = pc + operand - jump_bias
    end
    instructions[#instructions + 1] = item
  end

  return {
    id = id,
    parent_id = parent_id == nil and vim.NIL or parent_id,
    gcconst_index = gcconst_index == nil and vim.NIL or gcconst_index,
    info = info,
    instructions = instructions,
  }
end

local function prototypes(fn, result, parent_id, gcconst_index)
  local info = jutil.funcinfo(fn)
  local id = #result
  result[#result + 1] = prototype(fn, id, parent_id, gcconst_index)
  for index = 1, info.gcconsts do
    local constant = jutil.funck(fn, -index)
    if type(constant) == "proto" then
      prototypes(constant, result, id, index)
    end
  end
end

local function hex(value)
  return (value:gsub(".", function(byte)
    return string.format("%02x", string.byte(byte))
  end))
end

local sources = {}
for _, source in ipairs(manifest.sources) do
  local item = { id = source.id }
  local ok, result, detail = pcall(function()
    local chunk, load_error = loadfile(source.path)
    if not chunk then
      return nil, load_error
    end
    local found = {}
    prototypes(chunk, found)
    return found, hex(string.dump(chunk))
  end)
  if ok and result then
    item.prototypes = result
    item.bytecode_dump = detail
  else
    item.error = tostring(ok and detail or result)
  end
  sources[#sources + 1] = item
end

io.write(vim.json.encode({
  runtime = { version = jit.version, arch = jit.arch, os = jit.os },
  vm = {
    opcode_width = opcode_width,
    opcode_bits = opcode_bits,
    jump_mode = jump_mode,
    jump_bias = jump_bias,
    opcodes = opcode_names,
  },
  sources = sources,
}))
