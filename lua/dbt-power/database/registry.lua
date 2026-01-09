-- Adapter registry for managing and selecting database adapters
-- Handles adapter registration, detection, and instantiation

local M = {}

-- Registry of available adapters
local adapters = {}

-- Cache for detected adapters (project_root -> adapter instance)
local adapter_cache = {}
local cache_timestamp = {}
local CACHE_TTL = 300 -- 5 minutes in seconds

-- Register an adapter class
-- @param adapter_class table: Adapter class that extends BaseAdapter
function M.register_adapter(adapter_class)
  local instance = adapter_class:new()
  if not instance.name then
    vim.notify(
      "[dbt-power] Cannot register adapter without name",
      vim.log.levels.ERROR
    )
    return false
  end

  adapters[instance.name] = adapter_class
  return true
end

-- Get adapter by name
-- @param adapter_name string: Name of adapter (e.g., "snowflake", "postgres")
-- @param config table: Plugin configuration
-- @return table|nil: Adapter instance or nil if not found
function M.get_adapter(adapter_name, config)
  if not adapter_name then
    return nil
  end

  local adapter_class = adapters[adapter_name]
  if not adapter_class then
    vim.notify(
      string.format("[dbt-power] Unknown adapter: %s", adapter_name),
      vim.log.levels.WARN
    )
    return nil
  end

  -- Get adapter-specific config
  local adapter_config = {}
  if config and config.database then
    adapter_config = config.database[adapter_name] or {}
  end

  -- Create adapter instance
  local adapter = adapter_class:new(adapter_config)

  return adapter
end

-- Detect adapter type from dbt profiles and return appropriate adapter
-- @param project_root string: Path to dbt project root
-- @param user_config table: Plugin configuration
-- @param force_refresh boolean: Force cache refresh
-- @return table|nil: Adapter instance or nil if detection failed
function M.detect_and_get_adapter(project_root, user_config, force_refresh)
  if not project_root then
    return nil
  end

  -- Debug: Check manual adapter config
  local has_config = user_config ~= nil
  local has_db_config = has_config and user_config.database ~= nil
  local has_adapter = has_db_config and user_config.database.adapter ~= nil
  local adapter_value = has_adapter and user_config.database.adapter or "nil"

  vim.notify(
    string.format(
      "[dbt-power] Registry Debug:\n" ..
      "  Config: %s\n" ..
      "  Database config: %s\n" ..
      "  Adapter setting: %s",
      has_config and "yes" or "no",
      has_db_config and "yes" or "no",
      adapter_value
    ),
    vim.log.levels.INFO
  )

  -- Check if user manually specified adapter in config
  if user_config and user_config.database and user_config.database.adapter then
    local adapter_name = user_config.database.adapter
    local adapter = M.get_adapter(adapter_name, user_config)

    if adapter then
      vim.notify(
        string.format("[dbt-power] Using manually specified adapter: %s", adapter_name),
        vim.log.levels.INFO
      )
    else
      vim.notify(
        string.format("[dbt-power] Failed to get adapter: %s", adapter_name),
        vim.log.levels.ERROR
      )
    end

    return adapter
  end

  -- Check cache
  local now = os.time()
  if not force_refresh and adapter_cache[project_root] then
    local cached_time = cache_timestamp[project_root] or 0
    if (now - cached_time) < CACHE_TTL then
      return adapter_cache[project_root]
    end
  end

  -- Auto-detect from profiles.yml (silent mode since we handle warnings here)
  local profiles = require("dbt-power.database.profiles")
  local adapter_type = profiles.detect_adapter_type(project_root, true)

  if not adapter_type then
    -- Show our own warning (profiles.lua won't show its warning in silent mode)
    vim.notify(
      "[dbt-power] Could not detect database adapter. Please manually specify in config:\n" ..
      "  database = { adapter = 'snowflake' }  -- or 'postgres', 'bigquery', etc.",
      vim.log.levels.WARN
    )
    return nil
  end

  -- Get adapter instance
  local adapter = M.get_adapter(adapter_type, user_config)

  -- Cache the adapter
  if adapter then
    adapter_cache[project_root] = adapter
    cache_timestamp[project_root] = now
  end

  return adapter
end

-- Clear adapter cache for a project (or all projects)
-- @param project_root string|nil: Project to clear cache for, or nil for all
function M.clear_cache(project_root)
  if project_root then
    adapter_cache[project_root] = nil
    cache_timestamp[project_root] = nil
  else
    adapter_cache = {}
    cache_timestamp = {}
  end
end

-- Initialize registry with built-in adapters
function M.init()
  -- Clear existing adapters (useful for reloading)
  adapters = {}

  -- Register built-in adapters
  local ok, snowflake = pcall(require, "dbt-power.database.adapters.snowflake")
  if ok then
    M.register_adapter(snowflake.SnowflakeAdapter)
  end

  local ok, postgres = pcall(require, "dbt-power.database.adapters.postgres")
  if ok then
    M.register_adapter(postgres.PostgresAdapter)
  end

  local ok, duckdb = pcall(require, "dbt-power.database.adapters.duckdb")
  if ok then
    M.register_adapter(duckdb.DuckDBAdapter)
  end

  local ok, bigquery = pcall(require, "dbt-power.database.adapters.bigquery")
  if ok then
    M.register_adapter(bigquery.BigQueryAdapter)
  end

  local ok, redshift = pcall(require, "dbt-power.database.adapters.redshift")
  if ok then
    M.register_adapter(redshift.RedshiftAdapter)
  end

  local ok, databricks = pcall(require, "dbt-power.database.adapters.databricks")
  if ok then
    M.register_adapter(databricks.DatabricksAdapter)
  end
end

-- Get list of registered adapter names
-- @return table: Array of adapter names
function M.get_registered_adapters()
  local names = {}
  for name, _ in pairs(adapters) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

return M
