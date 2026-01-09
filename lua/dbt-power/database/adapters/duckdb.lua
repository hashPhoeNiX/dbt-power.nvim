-- DuckDB database adapter
-- Executes queries using duckdb CLI

local BaseAdapter = require("dbt-power.database.adapter").BaseAdapter
local Job = require("plenary.job")

local M = {}

local DuckDBAdapter = setmetatable({}, { __index = BaseAdapter })
DuckDBAdapter.__index = DuckDBAdapter

function DuckDBAdapter:new(config)
  local instance = BaseAdapter.new(self, config)
  instance.name = "duckdb"
  instance.cli_command = "duckdb"
  instance.config = config or {}
  instance:is_cli_available()
  return instance
end

-- Get connection arguments for duckdb CLI
function DuckDBAdapter:get_connection_args()
  local database_path = self.config.database_path or ":memory:"
  return { database_path }
end

-- Execute SQL using duckdb CLI
function DuckDBAdapter:execute_sql(sql, callback)
  -- Check if CLI is available
  if not self:is_cli_available() then
    vim.notify(
      "[dbt-power] duckdb CLI not found. Please install DuckDB or it will fallback to dbt show",
      vim.log.levels.WARN
    )
    callback({ error = "duckdb CLI not available" })
    return
  end

  -- Remove trailing semicolon and whitespace
  sql = vim.trim(sql)
  sql = sql:gsub("%s*;%s*$", "")

  -- Get database path
  local database_path = self.config.database_path or ":memory:"

  -- DuckDB can execute SQL directly via -c flag or from stdin
  -- We'll use a temp file approach for consistency
  local temp_file = vim.fn.tempname() .. ".sql"
  local file = io.open(temp_file, "w")
  if not file then
    callback({ error = string.format("Could not create temp SQL file at %s", temp_file) })
    return
  end

  -- Add DuckDB-specific formatting commands
  -- .mode csv for CSV output
  file:write(".mode csv\n")
  file:write(sql)
  file:close()

  -- Cleanup function to ensure temp file is always removed
  local function cleanup()
    pcall(os.remove, temp_file)
  end

  Job:new({
    command = "duckdb",
    args = { database_path, "-init", temp_file },
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
          callback({ error = "duckdb query failed:\n" .. full_output })
          return
        end

        -- Parse results from duckdb output
        local stdout = table.concat(j:result(), "\n")
        local parsed = self:parse_output(stdout)

        callback(parsed)
      end)
    end,
  }):start()
end

-- Parse duckdb CSV output
function DuckDBAdapter:parse_output(output)
  if not output or output == "" then
    return { columns = {}, rows = {} }
  end

  -- Reuse CSV parser from execute module
  local execute = require("dbt-power.dbt.execute")
  return execute.parse_csv_results(output)
end

-- Validate DuckDB-specific configuration
function DuckDBAdapter:validate_config()
  -- database_path is optional (defaults to :memory:)
  return true, nil
end

M.DuckDBAdapter = DuckDBAdapter

return M
