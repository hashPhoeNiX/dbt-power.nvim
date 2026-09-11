-- BigQuery database adapter
-- Executes queries using bq CLI

local BaseAdapter = require("dbt-power.database.adapter").BaseAdapter
local Job = require("plenary.job")

local M = {}

local BigQueryAdapter = setmetatable({}, { __index = BaseAdapter })
BigQueryAdapter.__index = BigQueryAdapter

function BigQueryAdapter:new(config)
  local instance = BaseAdapter.new(self, config)
  instance.name = "bigquery"
  instance.cli_command = "bq"
  instance.config = config or {}
  instance:is_cli_available()
  return instance
end

-- Get connection arguments for bq CLI
function BigQueryAdapter:get_connection_args()
  local args = { "query" }

  -- Add format flag for CSV output
  table.insert(args, "--format=csv")

  -- Use standard SQL (not legacy)
  table.insert(args, "--use_legacy_sql=false")

  -- Add project ID if specified
  if self.config.project_id then
    table.insert(args, "--project_id=" .. self.config.project_id)
  end

  -- Add location if specified
  if self.config.location then
    table.insert(args, "--location=" .. self.config.location)
  end

  -- Add dataset if specified
  if self.config.dataset then
    table.insert(args, "--dataset_id=" .. self.config.dataset)
  end

  return args
end

-- Execute SQL using bq CLI
function BigQueryAdapter:execute_sql(sql, callback)
  -- Check if CLI is available
  if not self:is_cli_available() then
    vim.notify(
      "[dbt-power] bq CLI not found. Please install Google Cloud SDK or it will fallback to dbt show",
      vim.log.levels.WARN
    )
    callback({ error = "bq CLI not available" })
    return
  end

  -- Remove trailing semicolon and whitespace
  sql = vim.trim(sql)
  sql = sql:gsub("%s*;%s*$", "")

  -- Get connection arguments
  local args = self:get_connection_args()

  -- BigQuery bq query accepts SQL as final argument
  table.insert(args, sql)

  Job:new({
    command = "bq",
    args = args,
    on_exit = function(j, return_val)
      vim.schedule(function()
        if return_val ~= 0 then
          local stderr = table.concat(j:stderr_result(), "\n")
          local stdout = table.concat(j:result(), "\n")
          local full_output = stderr
          if stdout ~= "" then
            full_output = stdout .. "\n" .. stderr
          end
          callback({ error = "BigQuery query failed:\n" .. full_output })
          return
        end

        -- Parse results from bq CSV output
        local stdout = table.concat(j:result(), "\n")
        local parsed = self:parse_output(stdout)

        callback(parsed)
      end)
    end,
  }):start()
end

-- Parse BigQuery CSV output
function BigQueryAdapter:parse_output(output)
  if not output or output == "" then
    return { columns = {}, rows = {} }
  end

  -- Reuse CSV parser from execute module
  local execute = require("dbt-power.dbt.execute")
  return execute.parse_csv_results(output)
end

-- Validate BigQuery-specific configuration
function BigQueryAdapter:validate_config()
  -- project_id is recommended but not strictly required (can use default from gcloud config)
  if not self.config.project_id then
    vim.notify(
      "[dbt-power] BigQuery adapter: project_id not specified, using gcloud default",
      vim.log.levels.INFO
    )
  end
  return true, nil
end

M.BigQueryAdapter = BigQueryAdapter

return M
