-- Profile parser for detecting database adapter
-- Supports both dbt Core (profiles.yml) and dbt Cloud CLI
--
-- Searches for profiles.yml in this order:
-- 1. Project directory (e.g., ~/Projects/my-dbt-project/profiles.yml)
-- 2. DBT_PROFILES_DIR environment variable location
-- 3. Default ~/.dbt/profiles.yml

local M = {}

-- Cache for parsed profiles
local profiles_cache = nil
local cache_timestamp = 0
local CACHE_TTL = 300 -- 5 minutes in seconds

-- Get the path to profiles.yml by searching multiple locations
-- @param project_root string: dbt project root directory
-- @return string|nil: Path to profiles.yml or nil if not found
local function get_profiles_path(project_root)
  -- Priority 1: Check project directory (common for dbt Core projects)
  if project_root then
    local project_profiles = project_root .. "/profiles.yml"
    local file = io.open(project_profiles, "r")
    if file then
      file:close()
      return project_profiles
    end
  end

  -- Priority 2: Check DBT_PROFILES_DIR environment variable
  local profiles_dir = vim.fn.getenv("DBT_PROFILES_DIR")
  if profiles_dir and profiles_dir ~= vim.NIL and profiles_dir ~= "" then
    local env_profiles = profiles_dir .. "/profiles.yml"
    local file = io.open(env_profiles, "r")
    if file then
      file:close()
      return env_profiles
    end
  end

  -- Priority 3: Check default ~/.dbt/profiles.yml
  local home = vim.fn.expand("~")
  local default_profiles = home .. "/.dbt/profiles.yml"
  local file = io.open(default_profiles, "r")
  if file then
    file:close()
    return default_profiles
  end

  -- No profiles.yml found (might be dbt Cloud CLI)
  return nil
end

-- Simple YAML parser for extracting adapter type
-- Only handles basic YAML structure needed for profiles.yml
-- @param content string: YAML content
-- @return table: Parsed YAML as nested tables
local function parse_yaml_simple(content)
  local result = {}
  local current_section = result
  local section_stack = { result }
  local indent_stack = { 0 }

  for line in content:gmatch("[^\r\n]+") do
    -- Skip comments and empty lines
    if line:match("^%s*#") or line:match("^%s*$") then
      goto continue
    end

    -- Calculate indentation
    local indent = #line:match("^%s*")
    local trimmed = vim.trim(line)

    -- Parse key-value pair
    local key, value = trimmed:match("^([^:]+):%s*(.*)$")
    if key then
      key = vim.trim(key)
      value = vim.trim(value)

      -- Pop stack if indent decreased or stayed same (for sibling sections)
      while #indent_stack > 1 and indent <= indent_stack[#indent_stack] do
        table.remove(section_stack)
        table.remove(indent_stack)
      end

      current_section = section_stack[#section_stack]

      if value == "" or value == "{}" then
        -- This is a section header
        current_section[key] = {}
        table.insert(section_stack, current_section[key])
        table.insert(indent_stack, indent)
      else
        -- This is a key-value pair
        -- Remove quotes if present
        value = value:gsub("^['\"]", ""):gsub("['\"]$", "")
        current_section[key] = value
      end
    end

    ::continue::
  end

  return result
end

-- Parse profiles.yml file
-- @param profiles_path string: Path to profiles.yml
-- @return table|nil: Parsed profiles or nil if error
function M.parse_profiles_yml(profiles_path)
  local file = io.open(profiles_path, "r")
  if not file then
    return nil
  end

  local content = file:read("*a")
  file:close()

  if not content or content == "" then
    return nil
  end

  local ok, parsed = pcall(parse_yaml_simple, content)
  if not ok then
    return nil
  end

  return parsed
end

-- Get active profile name from environment or dbt_project.yml
-- @param project_root string: Path to dbt project root
-- @return string|nil: Profile name or nil
function M.get_active_profile(project_root)
  -- Check DBT_PROFILE environment variable first
  local env_profile = vim.fn.getenv("DBT_PROFILE")
  if env_profile and env_profile ~= vim.NIL and env_profile ~= "" then
    return env_profile
  end

  -- Read from dbt_project.yml
  local dbt_project_path = project_root .. "/dbt_project.yml"
  local file = io.open(dbt_project_path, "r")
  if not file then
    return nil
  end

  local content = file:read("*a")
  file:close()

  -- Simple extraction of profile name
  local profile_name = content:match("profile:%s*['\"]?([^'\"]+)['\"]?")
  return profile_name
end

-- Detect adapter type from profiles.yml
-- @param project_root string: Path to dbt project root
-- @param silent boolean: If true, suppress warnings about missing profiles
-- @return string|nil: Adapter type (e.g., "snowflake", "postgres") or nil
function M.detect_adapter_type(project_root, silent)
  -- Check cache
  local now = os.time()
  if profiles_cache and (now - cache_timestamp) < CACHE_TTL then
    -- Use cached profiles
    local profile_name = M.get_active_profile(project_root)
    if not profile_name then
      return nil
    end

    return M.extract_adapter_type(profiles_cache, profile_name)
  end

  -- Parse profiles.yml (searches project dir, env var, then ~/.dbt/)
  local profiles_path = get_profiles_path(project_root)
  if not profiles_path then
    -- No profiles.yml found (might be using dbt Cloud CLI)
    if not silent then
      -- Check if dbt_cloud.yml exists
      local home = vim.fn.expand("~")
      local dbt_cloud_path = home .. "/.dbt/dbt_cloud.yml"
      local file = io.open(dbt_cloud_path, "r")
      if file then
        file:close()
        vim.notify(
          "[dbt-power] dbt Cloud CLI detected. Please manually specify adapter in config:\n" ..
          "  database = { adapter = 'snowflake' }  -- or 'postgres', 'bigquery', etc.",
          vim.log.levels.WARN
        )
      end
    end
    return nil
  end

  local profiles = M.parse_profiles_yml(profiles_path)

  if not profiles then
    return nil
  end

  -- Cache the parsed profiles
  profiles_cache = profiles
  cache_timestamp = now

  -- Get active profile
  local profile_name = M.get_active_profile(project_root)
  if not profile_name then
    return nil
  end

  return M.extract_adapter_type(profiles, profile_name)
end

-- Extract adapter type from parsed profiles
-- @param profiles table: Parsed profiles.yml
-- @param profile_name string: Profile name to look up
-- @return string|nil: Adapter type or nil
function M.extract_adapter_type(profiles, profile_name)
  -- Navigate: profiles → [profile_name] → target → outputs → [target] → type
  if not profiles[profile_name] then
    return nil
  end

  local profile = profiles[profile_name]
  local target_name = profile.target
  if not target_name then
    return nil
  end

  local outputs = profile.outputs
  if not outputs then
    return nil
  end

  local target = outputs[target_name]
  if not target then
    return nil
  end

  local adapter_type = target.type
  return adapter_type
end

-- Clear profiles cache (useful for testing or manual refresh)
function M.clear_cache()
  profiles_cache = nil
  cache_timestamp = 0
end

-- Get cached adapter type (with optional force refresh)
-- @param project_root string: Path to dbt project root
-- @param force_refresh boolean: Force cache refresh
-- @return string|nil: Adapter type or nil
function M.get_cached_adapter_type(project_root, force_refresh)
  if force_refresh then
    M.clear_cache()
  end

  return M.detect_adapter_type(project_root)
end

return M
