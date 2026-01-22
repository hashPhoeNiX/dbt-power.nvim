-- Ad-hoc analysis creation for temporary testing
-- Creates temporary dbt analyses that can be executed and then deleted

local M = {}

-- Create a temporary ad-hoc dbt analysis
function M.create_adhoc_model()
  local project_root = require("dbt-power.utils.project").find_dbt_project()
  if not project_root then
    vim.notify("[dbt-power] Not in a dbt project", vim.log.levels.ERROR)
    return
  end

  -- Create adhoc directory if it doesn't exist
  local adhoc_dir = project_root .. "/analyses/adhoc"
  local stat = vim.fn.getfperm(adhoc_dir)
  if stat == "" then
    -- Directory doesn't exist, create it
    vim.fn.mkdir(adhoc_dir, "p")
  end

  -- Generate filename with timestamp
  local timestamp = os.date("%Y%m%d_%H%M%S")
  local model_name = "adhoc_" .. timestamp
  local model_path = adhoc_dir .. "/" .. model_name .. ".sql"

  -- Create the file
  local file = io.open(model_path, "w")
  if not file then
    vim.notify("[dbt-power] Failed to create ad-hoc analysis file", vim.log.levels.ERROR)
    return
  end

  -- Write template SQL
  file:write(string.format([[-- Ad-hoc temporary analysis
-- Created: %s
-- Delete this file when done testing

SELECT 1 AS test_column
]], os.date("%Y-%m-%d %H:%M:%S")))
  file:close()

  -- Open the file in new buffer
  vim.cmd("edit " .. model_path)

  vim.notify(
    "[dbt-power] Created ad-hoc analysis: " .. model_name .. "\n" ..
    "Location: analyses/adhoc/" .. model_name .. ".sql\n" ..
    "Execute with: <leader>dS (buffer) or <leader>ds (inline)\n" ..
    "Delete file when done testing",
    vim.log.levels.INFO
  )
end

-- List all ad-hoc analyses
function M.list_adhoc_models()
  local project_root = require("dbt-power.utils.project").find_dbt_project()
  if not project_root then
    vim.notify("[dbt-power] Not in a dbt project", vim.log.levels.ERROR)
    return
  end

  local adhoc_dir = project_root .. "/analyses/adhoc"
  local files = vim.fn.glob(adhoc_dir .. "/*.sql", false, true)

  if #files == 0 then
    vim.notify("[dbt-power] No ad-hoc analyses found", vim.log.levels.INFO)
    return
  end

  vim.notify("[dbt-power] Ad-hoc analyses:\n" .. table.concat(files, "\n"), vim.log.levels.INFO)
end

-- Clean up all ad-hoc analyses
function M.cleanup_adhoc_models()
  local project_root = require("dbt-power.utils.project").find_dbt_project()
  if not project_root then
    vim.notify("[dbt-power] Not in a dbt project", vim.log.levels.ERROR)
    return
  end

  local adhoc_dir = project_root .. "/analyses/adhoc"
  local files = vim.fn.glob(adhoc_dir .. "/*.sql", false, true)

  if #files == 0 then
    vim.notify("[dbt-power] No ad-hoc analyses to clean up", vim.log.levels.INFO)
    return
  end

  for _, file in ipairs(files) do
    os.remove(file)
  end

  vim.notify("[dbt-power] Cleaned up " .. #files .. " ad-hoc analyses", vim.log.levels.INFO)
end

return M
