-- Utility functions for dbt project detection

local M = {}

-- Find dbt project root directory
function M.find_dbt_project(start_path)
  start_path = start_path or vim.fn.expand("%:p:h")

  -- Look for dbt_project.yml
  local current = start_path
  local max_depth = 10
  local depth = 0

  while depth < max_depth do
    local dbt_project_file = current .. "/dbt_project.yml"

    if vim.fn.filereadable(dbt_project_file) == 1 then
      return current
    end

    -- Move up one directory
    local parent = vim.fn.fnamemodify(current, ":h")
    if parent == current then
      -- Reached root
      break
    end

    current = parent
    depth = depth + 1
  end

  return nil
end

-- Check if current file is in a dbt project
function M.is_in_dbt_project()
  return M.find_dbt_project() ~= nil
end

-- Get dbt project name
function M.get_project_name(project_root)
  project_root = project_root or M.find_dbt_project()
  if not project_root then
    return nil
  end

  local dbt_project_file = project_root .. "/dbt_project.yml"
  local file = io.open(dbt_project_file, "r")
  if not file then
    return nil
  end

  -- Simple YAML parsing for project name
  for line in file:lines() do
    local name = line:match("^name:%s*([%w_-]+)")
    if name then
      file:close()
      return name
    end
  end

  file:close()
  return nil
end

-- Get models directory
function M.get_models_dir(project_root)
  project_root = project_root or M.find_dbt_project()
  if not project_root then
    return nil
  end

  return project_root .. "/models"
end

-- Check if dbt CLI is available
function M.check_dbt_cli(cli_command)
  cli_command = cli_command or "dbt"
  return vim.fn.executable(cli_command) == 1
end

return M
