-- Databricks database adapter
-- Primary strategy: Use dbt show (databricks-sql-cli is rarely used)

local BaseAdapter = require("dbt-power.database.adapter").BaseAdapter

local M = {}

local DatabricksAdapter = setmetatable({}, { __index = BaseAdapter })
DatabricksAdapter.__index = DatabricksAdapter

function DatabricksAdapter:new(config)
  local instance = BaseAdapter.new(self, config)
  instance.name = "databricks"
  -- Databricks SQL CLI exists but is not commonly used
  -- Most users rely on dbt show or API access
  instance.cli_command = "databricks-sql-cli"
  instance.config = config or {}
  instance:is_cli_available()
  return instance
end

-- Get connection arguments (if CLI is used)
function DatabricksAdapter:get_connection_args()
  -- databricks-sql-cli configuration is complex and varies
  -- Return empty args - this is primarily a placeholder
  return {}
end

-- Execute SQL via dbt show (primary method for Databricks)
-- Override the base execute_sql to always use dbt show
function DatabricksAdapter:execute_sql(sql, callback)
  vim.notify(
    "[dbt-power] Databricks adapter uses dbt show for execution",
    vim.log.levels.INFO
  )

  -- Databricks adapter primarily uses dbt show
  -- Direct CLI execution is not commonly supported
  -- The fallback mechanism in execute_via_adapter will handle this
  callback({
    error = "Databricks adapter requires dbt show fallback - this will be handled by the caller",
  })
end

-- Parse output (not typically used, as we rely on dbt show)
function DatabricksAdapter:parse_output(output)
  return { columns = {}, rows = {} }
end

-- Validate Databricks-specific configuration
function DatabricksAdapter:validate_config()
  -- Databricks typically uses dbt show, so minimal config validation
  vim.notify(
    "[dbt-power] Databricks adapter will use dbt show for query execution",
    vim.log.levels.INFO
  )
  return true, nil
end

M.DatabricksAdapter = DatabricksAdapter

return M
