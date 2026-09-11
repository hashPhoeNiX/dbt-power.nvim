-- Snowflake database adapter
-- Executes queries using snowsql CLI

local BaseAdapter = require("dbt-power.database.adapter").BaseAdapter
local Job = require("plenary.job")

local M = {}

local SnowflakeAdapter = setmetatable({}, { __index = BaseAdapter })
SnowflakeAdapter.__index = SnowflakeAdapter

function SnowflakeAdapter:new(config)
  local instance = BaseAdapter.new(self, config)
  instance.name = "snowflake"
  instance.cli_command = "snowsql"
  instance.config = config or {}

  -- Set default timeout values if not provided
  instance.config.login_timeout = instance.config.login_timeout or 30  -- seconds
  instance.config.connection_timeout = instance.config.connection_timeout or 30  -- seconds

  instance:is_cli_available()
  return instance
end

-- Add the -o login_timeout / -o network_timeout flags shared by get_connection_args
-- and execute_sql's own argument builder.
local function append_timeout_args(args, config)
  if config.login_timeout then
    table.insert(args, "-o")
    table.insert(args, string.format("login_timeout=%d", config.login_timeout))
  end

  if config.connection_timeout then
    table.insert(args, "-o")
    table.insert(args, string.format("network_timeout=%d", config.connection_timeout))
  end
end

-- Get connection arguments for snowsql CLI
function SnowflakeAdapter:get_connection_args()
  local connection_name = self.config.connection_name or "default"
  local args = { "-c", connection_name, "-f" }

  -- Add timeout options to prevent long connection hangs
  append_timeout_args(args, self.config)

  return args
end

-- Execute SQL using snowsql CLI
function SnowflakeAdapter:execute_sql(sql, callback)
  -- Check if CLI is available
  if not self:is_cli_available() then
    vim.notify(
      "[dbt-power] snowsql CLI not found. Please install snowsql or it will fallback to dbt show",
      vim.log.levels.WARN
    )
    -- Fallback would need to be handled by caller
    callback({ error = "snowsql CLI not available" })
    return
  end

  -- Remove trailing semicolon and whitespace
  sql = vim.trim(sql)
  sql = sql:gsub("%s*;%s*$", "")

  -- Create temp SQL file for execution
  local temp_file = vim.fn.tempname() .. ".sql"
  local file = io.open(temp_file, "w")
  if not file then
    callback({ error = string.format("Could not create temp SQL file at %s", temp_file) })
    return
  end

  file:write(sql)
  file:close()

  -- Execute via snowsql - uses connection from ~/.snowsql/config
  local connection_name = self.config.connection_name or "default"

  -- Cleanup function to ensure temp file is always removed
  local function cleanup()
    pcall(os.remove, temp_file)
  end

  -- Build snowsql command with timeout options
  local args = { "-c", connection_name, "-f", temp_file, "-o", "exit_on_error=true", "-o", "friendly=false" }

  -- Add login/network timeouts to prevent long connection hangs
  append_timeout_args(args, self.config)

  -- Enable debug logging by default to get detailed error messages
  -- Users can disable this by setting debug_on_error = false in config
  local enable_debug = self.config.debug_on_error ~= false  -- Default true
  if enable_debug then
    table.insert(args, "-o")
    table.insert(args, "log_level=DEBUG")
  end

  Job:new({
    command = "snowsql",
    args = args,
    on_exit = function(j, return_val)
      vim.schedule(function()
        -- Always clean up temp file, even on error
        cleanup()

        if return_val ~= 0 then
          local stderr = table.concat(j:stderr_result(), "\n")
          local stdout = table.concat(j:result(), "\n")
          local full_output = stderr
          if stdout ~= "" then
            full_output = stdout .. "\n" .. stderr
          end

          callback({ error = "snowsql query failed:\n" .. full_output })
          return
        end

        -- Parse tabular results from snowsql output
        local stdout = table.concat(j:result(), "\n")
        local parsed = self:parse_output(stdout)

        callback(parsed)
      end)
    end,
  }):start()
end

-- Parse snowsql output which comes in pipe-separated table format
function SnowflakeAdapter:parse_output(output)
  local columns = {}
  local rows = {}

  if not output or output == "" then
    return { columns = {}, rows = {} }
  end

  local lines = vim.split(output, "\n")

  -- Find the header row (first row with pipe separators, typically after connection messages)
  local header_idx = nil
  for i, line in ipairs(lines) do
    -- Look for a line with pipes that's not just separators
    if line:match("|") and not line:match("^[%s%-%+|]+$") then
      header_idx = i
      break
    end
  end

  if not header_idx then
    return { columns = {}, rows = {} }
  end

  -- Parse header row
  local header_line = lines[header_idx]
  for col in header_line:gmatch("|([^|]+)") do
    local trimmed = vim.trim(col)
    if trimmed ~= "" then
      table.insert(columns, trimmed)
    end
  end

  if #columns == 0 then
    return { columns = {}, rows = {} }
  end

  -- Parse data rows
  for i = header_idx + 1, #lines do
    local line = lines[i]

    -- Skip separator lines and empty lines
    if vim.trim(line) == "" or line:match("^[%s%-%+|]+$") then
      goto continue_snowsql_parse
    end

    -- Skip lines that don't look like data rows (no pipes)
    if not line:match("|") then
      goto continue_snowsql_parse
    end

    -- Parse row
    local row = {}
    for value in line:gmatch("|([^|]+)") do
      local trimmed = vim.trim(value)
      table.insert(row, trimmed)
    end

    -- Only add rows with correct number of columns
    if #row == #columns then
      table.insert(rows, row)
    end

    ::continue_snowsql_parse::
  end

  return {
    columns = columns,
    rows = rows,
  }
end

-- Validate Snowflake-specific configuration
function SnowflakeAdapter:validate_config()
  -- Connection name is optional (defaults to "default")
  -- Could add validation for ~/.snowsql/config existence here
  return true, nil
end

M.SnowflakeAdapter = SnowflakeAdapter

return M
