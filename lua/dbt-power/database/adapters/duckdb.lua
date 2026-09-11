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

-- Apply `transform` only to the portions of `sql` that lie outside single-quoted
-- string literals (SQL escapes a literal quote inside a string as ''), so catalog
-- stripping never rewrites text that merely looks like a dotted identifier.
local function map_outside_string_literals(sql, transform)
  local parts = {}
  local i = 1
  local len = #sql

  while i <= len do
    local quote_start = sql:find("'", i, true)
    if not quote_start then
      table.insert(parts, transform(sql:sub(i)))
      break
    end

    table.insert(parts, transform(sql:sub(i, quote_start - 1)))

    -- Scan to the end of the literal, treating '' as an escaped quote
    local j = quote_start + 1
    while true do
      local next_quote = sql:find("'", j, true)
      if not next_quote then
        table.insert(parts, sql:sub(quote_start))
        i = len + 1
        break
      elseif sql:sub(next_quote + 1, next_quote + 1) == "'" then
        j = next_quote + 2
      else
        table.insert(parts, sql:sub(quote_start, next_quote))
        i = next_quote + 1
        break
      end
    end
  end

  return table.concat(parts)
end

-- Strip catalog prefixes from SQL (dbt adds catalog names that DuckDB doesn't recognize)
-- Converts: "catalog"."schema"."table" -> "schema"."table"
-- Converts: catalog.schema.table -> schema.table
function DuckDBAdapter:strip_catalog_prefix(sql)
  if not sql then
    return sql
  end

  return map_outside_string_literals(sql, function(chunk)
    -- Pattern: Remove quoted catalog prefix from three-part identifiers only
    -- Matches: "catalog"."schema"."table" -> "schema"."table"
    -- Does NOT match two-part identifiers like "schema"."table"
    chunk = chunk:gsub('"([^"]+)"%s*%.%s*("([^"]+)"%s*%.%s*"[^"]+")', '%2')

    -- Pattern 2: Remove unquoted catalog prefix: catalog.schema.table -> schema.table
    -- Only match three-part identifiers (preceded by whitespace or start of string)
    chunk = chunk:gsub("([%s%(,])([%w_]+)%.([%w_]+)%.([%w_]+)", "%1%3.%4")

    return chunk
  end)
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

  -- Strip catalog prefixes (dbt adds catalog names that DuckDB doesn't recognize)
  sql = self:strip_catalog_prefix(sql)

  -- Get database path
  local database_path = self.config.database_path or ":memory:"

  -- Use stdin to pass SQL (more reliable for complex queries than -c flag)
  -- The -csv flag ensures CSV output format
  Job:new({
    command = "duckdb",
    args = { database_path, "-csv" },
    writer = sql,  -- Send SQL via stdin
    on_exit = function(j, return_val)
      vim.schedule(function()
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
