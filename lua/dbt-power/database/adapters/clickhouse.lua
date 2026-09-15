-- ClickHouse database adapter
-- Executes queries using clickhouse-client CLI

local BaseAdapter = require("dbt-power.database.adapter").BaseAdapter
local Job = require("plenary.job")

local M = {}

local ClickHouseAdapter = setmetatable({}, { __index = BaseAdapter })
ClickHouseAdapter.__index = ClickHouseAdapter

function ClickHouseAdapter:new(config)
  local instance = BaseAdapter.new(self, config)
  instance.name = "clickhouse"
  instance.cli_command = "clickhouse-client"
  instance.config = config or {}
  instance:is_cli_available()
  return instance
end

-- Get connection arguments for clickhouse-client CLI
function ClickHouseAdapter:get_connection_args()
  local args = {}

  if self.config.host then
    table.insert(args, "--host")
    table.insert(args, self.config.host)
  end

  if self.config.port then
    table.insert(args, "--port")
    table.insert(args, tostring(self.config.port))
  end

  if self.config.user then
    table.insert(args, "--user")
    table.insert(args, self.config.user)
  end

  if self.config.password then
    table.insert(args, "--password")
    table.insert(args, self.config.password)
  end

  -- dbt-clickhouse uses the dbt "schema" as the ClickHouse database name
  if self.config.database then
    table.insert(args, "--database")
    table.insert(args, self.config.database)
  end

  if self.config.secure then
    table.insert(args, "--secure")
  end

  return args
end

-- Execute SQL using clickhouse-client CLI
function ClickHouseAdapter:execute_sql(sql, callback)
  -- Check if CLI is available
  if not self:is_cli_available() then
    vim.notify(
      "[dbt-power] clickhouse-client CLI not found. Please install the ClickHouse client or it will fallback to dbt show",
      vim.log.levels.WARN
    )
    callback({ error = "clickhouse-client CLI not available" })
    return
  end

  -- Remove trailing semicolon and whitespace
  sql = vim.trim(sql)
  sql = sql:gsub("%s*;%s*$", "")

  local args = self:get_connection_args()
  table.insert(args, "--format")
  table.insert(args, "CSVWithNames")

  -- Use stdin to pass SQL (more reliable for complex queries than --query)
  Job:new({
    command = "clickhouse-client",
    args = args,
    writer = sql, -- Send SQL via stdin
    on_exit = function(j, return_val)
      vim.schedule(function()
        if return_val ~= 0 then
          local stderr = table.concat(j:stderr_result(), "\n")
          local stdout = table.concat(j:result(), "\n")
          local full_output = stderr
          if stdout ~= "" then
            full_output = stdout .. "\n" .. stderr
          end
          callback({ error = "clickhouse-client query failed:\n" .. full_output })
          return
        end

        -- Parse results from clickhouse-client CSV output
        local stdout = table.concat(j:result(), "\n")
        local parsed = self:parse_output(stdout)

        callback(parsed)
      end)
    end,
  }):start()
end

-- Parse ClickHouse CSVWithNames output
function ClickHouseAdapter:parse_output(output)
  if not output or output == "" then
    return { columns = {}, rows = {} }
  end

  -- Reuse CSV parser from execute module
  local execute = require("dbt-power.dbt.execute")
  return execute.parse_csv_results(output)
end

-- Validate ClickHouse-specific configuration
function ClickHouseAdapter:validate_config()
  -- host/port default to localhost:9000, so no hard requirements
  return true, nil
end

M.ClickHouseAdapter = ClickHouseAdapter

return M
