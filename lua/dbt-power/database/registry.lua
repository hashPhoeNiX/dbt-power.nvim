-- Adapter registry for managing and selecting database adapters
-- Handles adapter registration, detection, and instantiation

local M = {}

-- Registry of available adapters
local adapters = {}

-- Cache for detected adapters (project_root -> adapter instance)
local adapter_cache = {}
local cache_timestamp = {}
local CACHE_TTL = 300 -- 5 minutes in seconds

-- Manual adapter overrides (project_root -> adapter_name)
-- Takes precedence over auto-detection
local manual_adapters = {}

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

-- Normalize profile configuration to adapter-specific format
-- @param adapter_type string: Adapter type (e.g., "duckdb", "postgres")
-- @param profile_config table: Configuration from profiles.yml
-- @param project_root string: Project root directory (for making paths absolute)
-- @return table: Normalized configuration
function M.normalize_profile_config(adapter_type, profile_config, project_root)
  if not profile_config then
    return {}
  end

  local normalized = {}

  -- DuckDB adapter
  if adapter_type == "duckdb" then
    if profile_config.path then
      local db_path = profile_config.path
      -- Make path absolute if it's relative
      if not db_path:match("^/") and not db_path:match("^:memory:") and project_root then
        db_path = project_root .. "/" .. db_path
      end
      normalized.database_path = db_path
    end

  -- PostgreSQL/Redshift adapter
  elseif adapter_type == "postgres" or adapter_type == "redshift" then
    if profile_config.host then normalized.host = profile_config.host end
    if profile_config.port then normalized.port = tonumber(profile_config.port) end
    if profile_config.database or profile_config.dbname then
      normalized.database = profile_config.database or profile_config.dbname
    end
    if profile_config.user or profile_config.username then
      normalized.user = profile_config.user or profile_config.username
    end
    if profile_config.password then normalized.password = profile_config.password end
    if profile_config.schema then normalized.schema = profile_config.schema end

  -- BigQuery adapter
  elseif adapter_type == "bigquery" then
    if profile_config.project then normalized.project_id = profile_config.project end
    if profile_config.dataset then normalized.dataset = profile_config.dataset end
    if profile_config.location then normalized.location = profile_config.location end

  -- Snowflake adapter
  elseif adapter_type == "snowflake" then
    if profile_config.account then normalized.account = profile_config.account end
    if profile_config.user then normalized.user = profile_config.user end
    if profile_config.database then normalized.database = profile_config.database end
    if profile_config.schema then normalized.schema = profile_config.schema end
    if profile_config.warehouse then normalized.warehouse = profile_config.warehouse end
    if profile_config.role then normalized.role = profile_config.role end

  -- Databricks adapter
  elseif adapter_type == "databricks" then
    if profile_config.host then normalized.host = profile_config.host end
    if profile_config.http_path then normalized.http_path = profile_config.http_path end
    if profile_config.token then normalized.token = profile_config.token end
  end

  return normalized
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

-- Get adapter with specific configuration
-- @param adapter_name string: Name of adapter
-- @param adapter_config table: Adapter-specific configuration
-- @return table|nil: Adapter instance or nil if not found
function M.get_adapter_with_config(adapter_name, adapter_config)
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

  -- Create adapter instance with provided config
  local adapter = adapter_class:new(adapter_config or {})

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

  -- Priority 1: Check manual adapter override (set via :DbtSetAdapter command)
  local manual_adapter = M.get_manual_adapter(project_root)
  if manual_adapter then
    -- Extract config from profiles.yml if available (reuses profiles.lua's
    -- 5-minute cache instead of re-reading the file on every call)
    local profiles = require("dbt-power.database.profiles")
    local parsed_profiles = profiles.get_cached_profiles(project_root)
    local profile_config = {}

    if parsed_profiles then
      local profile_name = profiles.get_active_profile(project_root)
      if profile_name then
        profile_config = profiles.extract_adapter_config(parsed_profiles, profile_name) or {}
      end
    end

    -- Normalize and merge config (profiles.yml overrides user defaults)
    local normalized_config = M.normalize_profile_config(manual_adapter, profile_config, project_root)
    local user_adapter_config = (user_config and user_config.database and user_config.database[manual_adapter]) or {}
    local merged_config = vim.tbl_deep_extend("force",
      user_adapter_config,    -- Start with user defaults
      normalized_config or {} -- Override with profiles.yml values
    )

    return M.get_adapter_with_config(manual_adapter, merged_config)
  end

  -- Priority 2: Check if user manually specified adapter in config
  if user_config and user_config.database and user_config.database.adapter then
    local adapter_name = user_config.database.adapter
    local adapter = M.get_adapter(adapter_name, user_config)
    return adapter
  end

  -- Priority 3: Check cache
  local now = os.time()
  if not force_refresh and adapter_cache[project_root] then
    local cached_time = cache_timestamp[project_root] or 0
    if (now - cached_time) < CACHE_TTL then
      return adapter_cache[project_root]
    end
  end

  -- Priority 4: Auto-detect from profiles.yml (silent mode since we handle warnings here)
  local profiles = require("dbt-power.database.profiles")
  local adapter_type = profiles.detect_adapter_type(project_root, true)

  if not adapter_type then
    -- Check if this might be dbt Cloud CLI
    local home = vim.fn.expand("~")
    local dbt_cloud_path = home .. "/.dbt/dbt_cloud.yml"
    local file = io.open(dbt_cloud_path, "r")

    if file then
      file:close()
      vim.notify(
        "[dbt-power] dbt Cloud CLI detected. Auto-detection not available.\n" ..
        "Use :DbtSetAdapter to manually select your database adapter.",
        vim.log.levels.WARN
      )
    else
      vim.notify(
        "[dbt-power] Could not detect database adapter from profiles.yml.\n" ..
        "Use :DbtSetAdapter to manually select your adapter.",
        vim.log.levels.WARN
      )
    end
    return nil
  end

  -- Extract adapter configuration from profiles.yml
  local profiles_path = profiles.get_profiles_path(project_root)
  local profile_config = {}

  if profiles_path then
    local parsed_profiles = profiles.parse_profiles_yml(profiles_path)
    local profile_name = profiles.get_active_profile(project_root)
    if parsed_profiles and profile_name then
      profile_config = profiles.extract_adapter_config(parsed_profiles, profile_name) or {}
    end
  end

  -- Normalize profile config to adapter format
  local normalized_config = M.normalize_profile_config(adapter_type, profile_config, project_root)

  -- Merge configs: profiles.yml values override user config defaults
  -- This allows auto-detection to work even when user has default values
  local user_adapter_config = (user_config and user_config.database and user_config.database[adapter_type]) or {}
  local merged_config = vim.tbl_deep_extend("force",
    user_adapter_config,    -- Start with user defaults
    normalized_config or {} -- Override with profiles.yml values
  )

  -- Get adapter instance with merged config
  local adapter = M.get_adapter_with_config(adapter_type, merged_config)

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

-- Manually set adapter for a project (overrides auto-detection)
-- @param project_root string: Project root directory
-- @param adapter_name string: Adapter name to use
function M.set_manual_adapter(project_root, adapter_name)
  manual_adapters[project_root] = adapter_name
end

-- Clear manual adapter override for a project
-- @param project_root string: Project root directory
function M.clear_manual_adapter(project_root)
  manual_adapters[project_root] = nil
end

-- Get manual adapter override for a project
-- @param project_root string: Project root directory
-- @return string|nil: Manually set adapter name or nil
function M.get_manual_adapter(project_root)
  return manual_adapters[project_root]
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
