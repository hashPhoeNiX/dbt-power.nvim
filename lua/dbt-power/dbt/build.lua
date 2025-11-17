-- Build dbt models with dependency management
-- Supports building current model, upstream, downstream, or all dependencies

local M = {}
local Job = require("plenary.job")

M.config = {}

function M.setup(config)
  M.config = config or {}
end

-- Build current model only
function M.build_current_model()
  local model_name = M.get_model_name()
  if not model_name then
    vim.notify("[dbt-power] Not in a dbt model file (.sql)", vim.log.levels.WARN)
    return
  end

  local project_root = require("dbt-power.utils.project").find_dbt_project()
  if not project_root then
    vim.notify("[dbt-power] Could not find dbt project root", vim.log.levels.ERROR)
    return
  end

  vim.notify("[dbt-power] Building model: " .. model_name .. "...", vim.log.levels.INFO)

  local cmd = {
    M.config.dbt_cloud_cli or "dbt",
    "build",
    "--select",
    model_name,
  }

  Job:new({
    command = cmd[1],
    args = vim.list_slice(cmd, 2),
    cwd = project_root,
    on_exit = function(j, return_val)
      vim.schedule(function()
        if return_val ~= 0 then
          local stderr = table.concat(j:stderr_result(), "\n")
          local stdout = table.concat(j:result(), "\n")
          local full_output = stderr
          if stdout ~= "" then
            full_output = stdout .. "\n" .. stderr
          end
          vim.notify("[dbt-power] Build failed for model: " .. model_name, vim.log.levels.ERROR)
          require("dbt-power.dbt.execute").show_error_details("dbt build failed", full_output)
          return
        end

        vim.notify("[dbt-power] Successfully built: " .. model_name, vim.log.levels.INFO)
      end)
    end,
  }):start()
end

-- Build upstream dependencies (source models that feed into this model)
function M.build_upstream()
  local model_name = M.get_model_name()
  if not model_name then
    vim.notify("[dbt-power] Not in a dbt model file (.sql)", vim.log.levels.WARN)
    return
  end

  local project_root = require("dbt-power.utils.project").find_dbt_project()
  if not project_root then
    vim.notify("[dbt-power] Could not find dbt project root", vim.log.levels.ERROR)
    return
  end

  vim.notify("[dbt-power] Building upstream dependencies for: " .. model_name .. "...", vim.log.levels.INFO)

  -- In dbt, +model_name selects the model and all its upstream dependencies
  local cmd = {
    M.config.dbt_cloud_cli or "dbt",
    "build",
    "--select",
    "+" .. model_name,
  }

  Job:new({
    command = cmd[1],
    args = vim.list_slice(cmd, 2),
    cwd = project_root,
    on_exit = function(j, return_val)
      vim.schedule(function()
        if return_val ~= 0 then
          local stderr = table.concat(j:stderr_result(), "\n")
          local stdout = table.concat(j:result(), "\n")
          local full_output = stderr
          if stdout ~= "" then
            full_output = stdout .. "\n" .. stderr
          end
          vim.notify("[dbt-power] Build failed for upstream of: " .. model_name, vim.log.levels.ERROR)
          require("dbt-power.dbt.execute").show_error_details("dbt build upstream failed", full_output)
          return
        end

        vim.notify("[dbt-power] Successfully built upstream dependencies for: " .. model_name, vim.log.levels.INFO)
      end)
    end,
  }):start()
end

-- Build downstream dependencies (models that depend on this model)
function M.build_downstream()
  local model_name = M.get_model_name()
  if not model_name then
    vim.notify("[dbt-power] Not in a dbt model file (.sql)", vim.log.levels.WARN)
    return
  end

  local project_root = require("dbt-power.utils.project").find_dbt_project()
  if not project_root then
    vim.notify("[dbt-power] Could not find dbt project root", vim.log.levels.ERROR)
    return
  end

  vim.notify("[dbt-power] Building downstream dependencies for: " .. model_name .. "...", vim.log.levels.INFO)

  -- In dbt, model_name+ selects the model and all its downstream dependencies
  local cmd = {
    M.config.dbt_cloud_cli or "dbt",
    "build",
    "--select",
    model_name .. "+",
  }

  Job:new({
    command = cmd[1],
    args = vim.list_slice(cmd, 2),
    cwd = project_root,
    on_exit = function(j, return_val)
      vim.schedule(function()
        if return_val ~= 0 then
          local stderr = table.concat(j:stderr_result(), "\n")
          local stdout = table.concat(j:result(), "\n")
          local full_output = stderr
          if stdout ~= "" then
            full_output = stdout .. "\n" .. stderr
          end
          vim.notify("[dbt-power] Build failed for downstream of: " .. model_name, vim.log.levels.ERROR)
          require("dbt-power.dbt.execute").show_error_details("dbt build downstream failed", full_output)
          return
        end

        vim.notify("[dbt-power] Successfully built downstream dependencies for: " .. model_name, vim.log.levels.INFO)
      end)
    end,
  }):start()
end

-- Build all dependencies (both upstream and downstream)
function M.build_all_dependencies()
  local model_name = M.get_model_name()
  if not model_name then
    vim.notify("[dbt-power] Not in a dbt model file (.sql)", vim.log.levels.WARN)
    return
  end

  local project_root = require("dbt-power.utils.project").find_dbt_project()
  if not project_root then
    vim.notify("[dbt-power] Could not find dbt project root", vim.log.levels.ERROR)
    return
  end

  vim.notify("[dbt-power] Building all dependencies for: " .. model_name .. "...", vim.log.levels.INFO)

  -- In dbt, +model_name+ selects the model and all its dependencies (both upstream and downstream)
  local cmd = {
    M.config.dbt_cloud_cli or "dbt",
    "build",
    "--select",
    "+" .. model_name .. "+",
  }

  Job:new({
    command = cmd[1],
    args = vim.list_slice(cmd, 2),
    cwd = project_root,
    on_exit = function(j, return_val)
      vim.schedule(function()
        if return_val ~= 0 then
          local stderr = table.concat(j:stderr_result(), "\n")
          local stdout = table.concat(j:result(), "\n")
          local full_output = stderr
          if stdout ~= "" then
            full_output = stdout .. "\n" .. stderr
          end
          vim.notify("[dbt-power] Build failed for all dependencies of: " .. model_name, vim.log.levels.ERROR)
          require("dbt-power.dbt.execute").show_error_details("dbt build all dependencies failed", full_output)
          return
        end

        vim.notify("[dbt-power] Successfully built all dependencies for: " .. model_name, vim.log.levels.INFO)
      end)
    end,
  }):start()
end

-- Get model name from filepath
function M.get_model_name()
  local filepath = vim.fn.expand("%:t:r") -- filename without extension
  if not filepath or filepath == "" then
    return nil
  end
  return filepath
end

return M
