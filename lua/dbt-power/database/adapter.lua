-- Base adapter interface for database-specific implementations
-- All adapters should extend this base class and implement required methods

local M = {}

-- Base Adapter class
local BaseAdapter = {}
BaseAdapter.__index = BaseAdapter

function BaseAdapter:new(config)
  local instance = setmetatable({}, self)
  instance.name = nil -- e.g., "snowflake", "postgres", "bigquery"
  instance.cli_command = nil -- e.g., "snowsql", "psql", "bq"
  instance.cli_available = false
  instance.config = config or {}
  return instance
end

-- Check if the CLI tool is available in PATH
function BaseAdapter:is_cli_available()
  if not self.cli_command then
    return false
  end

  local handle = io.popen("command -v " .. self.cli_command .. " 2>/dev/null")
  if not handle then
    return false
  end

  local result = handle:read("*a")
  handle:close()

  self.cli_available = result ~= ""
  return self.cli_available
end

-- Execute SQL query and call callback with results
-- Must be implemented by subclasses
-- @param sql string: The SQL query to execute
-- @param callback function: Called with results in format { columns, rows, error }
function BaseAdapter:execute_sql(sql, callback)
  error("execute_sql must be implemented by adapter: " .. (self.name or "unknown"))
end

-- Get connection arguments for CLI command
-- Must be implemented by subclasses
-- @return table: Array of CLI arguments
function BaseAdapter:get_connection_args()
  error("get_connection_args must be implemented by adapter: " .. (self.name or "unknown"))
end

-- Parse CLI output into normalized format
-- Must be implemented by subclasses
-- @param raw_output string: Raw output from CLI
-- @return table: { columns = {...}, rows = {{...}}, error = nil }
function BaseAdapter:parse_output(raw_output)
  error("parse_output must be implemented by adapter: " .. (self.name or "unknown"))
end

-- Wrap SQL with LIMIT clause (optional, can be overridden)
-- @param sql string: The SQL query
-- @param limit number: Row limit
-- @return string: Wrapped SQL
function BaseAdapter:wrap_with_limit(sql, limit)
  -- Remove trailing semicolon and whitespace
  sql = vim.trim(sql)
  sql = sql:gsub("%s*;%s*$", "")

  -- Wrap with limit
  return string.format("SELECT * FROM (%s) AS query LIMIT %d", sql, limit)
end

-- Validate adapter-specific configuration (optional)
-- @return boolean, string: success, error_message
function BaseAdapter:validate_config()
  return true, nil
end

-- Execute SQL via direct CLI (common implementation)
-- Subclasses can override for custom behavior
function BaseAdapter:execute_via_cli(sql, callback)
  local Job = require("plenary.job")

  -- Create temp SQL file for execution
  local temp_file = vim.fn.tempname() .. ".sql"
  local file = io.open(temp_file, "w")
  if not file then
    callback({ error = string.format("Could not create temp SQL file at %s", temp_file) })
    return
  end

  file:write(sql)
  file:close()

  -- Get connection arguments from adapter
  local connection_args = self:get_connection_args()
  local args = vim.list_extend(connection_args, { temp_file })

  -- Cleanup function to ensure temp file is always removed
  local function cleanup()
    pcall(os.remove, temp_file)
  end

  Job:new({
    command = self.cli_command,
    args = args,
    on_exit = function(j, return_val)
      vim.schedule(function()
        -- Always clean up temp file
        cleanup()

        if return_val ~= 0 then
          local stderr = table.concat(j:stderr_result(), "\n")
          local stdout = table.concat(j:result(), "\n")
          local full_output = stderr
          if stdout ~= "" then
            full_output = stdout .. "\n" .. stderr
          end
          callback({
            error = string.format("%s query failed:\n%s", self.name, full_output),
          })
          return
        end

        -- Parse results using adapter's parser
        local stdout = table.concat(j:result(), "\n")
        local parsed = self:parse_output(stdout)

        callback(parsed)
      end)
    end,
  }):start()
end

-- Execute SQL via dbt show (universal fallback)
-- Available to all adapters as a fallback mechanism
function BaseAdapter:execute_via_dbt_show(sql, callback, project_root, model_name)
  local Job = require("plenary.job")
  local compile = require("dbt-power.dbt.compile")

  -- We need to compile the SQL as a temporary model first
  -- Then use dbt show to execute it
  -- This is a universal approach that works for all adapters

  -- For now, we'll require the caller to pass project_root and model_name
  -- In the future, we could make this smarter
  if not project_root or not model_name then
    callback({
      error = "dbt show fallback requires project_root and model_name parameters",
    })
    return
  end

  local dbt_cmd = compile.config.dbt_cloud_cli or "dbt"
  local limit = self.config.direct_query and self.config.direct_query.max_rows or 100

  Job:new({
    command = dbt_cmd,
    args = { "show", "--select", model_name, "--limit", tostring(limit) },
    cwd = project_root,
    on_exit = function(j, return_val)
      vim.schedule(function()
        if return_val ~= 0 then
          local stderr = table.concat(j:stderr_result(), "\n")
          callback({ error = "dbt show failed:\n" .. stderr })
          return
        end

        -- Parse dbt show output
        local stdout = table.concat(j:result(), "\n")
        local execute = require("dbt-power.dbt.execute")
        local parsed = execute.parse_dbt_show_results(stdout)

        callback(parsed)
      end)
    end,
  }):start()
end

-- Determine if we should fallback to dbt show based on error
function BaseAdapter:should_fallback_to_dbt_show(error_message)
  -- CLI not found or connection errors should fallback
  if error_message:match("not found") or error_message:match("command not found") then
    return true
  end
  if error_message:match("connection") or error_message:match("Connection") then
    return true
  end
  return false
end

M.BaseAdapter = BaseAdapter

return M
