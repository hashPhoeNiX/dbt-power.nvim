-- Redshift database adapter
-- Executes queries using psql CLI (Redshift uses PostgreSQL wire protocol)

local PostgresAdapter = require("dbt-power.database.adapters.postgres").PostgresAdapter

local M = {}

-- Redshift adapter extends PostgreSQL adapter since they use the same protocol
local RedshiftAdapter = setmetatable({}, { __index = PostgresAdapter })
RedshiftAdapter.__index = RedshiftAdapter

function RedshiftAdapter:new(config)
  local instance = PostgresAdapter.new(self, config)
  instance.name = "redshift"
  -- Still uses psql CLI
  instance.cli_command = "psql"

  -- Set default port to 5439 if not specified (Redshift default)
  if not instance.config.port then
    instance.config.port = 5439
  end

  instance:is_cli_available()
  return instance
end

-- Validate Redshift-specific configuration
-- Inherits most validation from PostgreSQL adapter
function RedshiftAdapter:validate_config()
  -- Call parent validation
  local valid, err = PostgresAdapter.validate_config(self)
  if not valid then
    return valid, err
  end

  -- Redshift-specific validation could go here if needed
  return true, nil
end

M.RedshiftAdapter = RedshiftAdapter

return M
