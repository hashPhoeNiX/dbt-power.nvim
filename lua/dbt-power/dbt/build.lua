-- Build dbt models with dependency management
-- Supports building current model, upstream, downstream, or all dependencies
-- Displays full command output in a split buffer

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

  local cmd_str = table.concat(cmd, " ")

  Job:new({
    command = cmd[1],
    args = vim.list_slice(cmd, 2),
    cwd = project_root,
    on_exit = function(j, return_val)
      vim.schedule(function()
        local stderr = table.concat(j:stderr_result(), "\n")
        local stdout = table.concat(j:result(), "\n")
        local full_output = stdout
        if stderr ~= "" then
          full_output = stdout .. "\n" .. stderr
        end

        if return_val ~= 0 then
          vim.notify("[dbt-power] Build failed for model: " .. model_name, vim.log.levels.ERROR)
          M.show_build_output("Build Failed: " .. model_name, cmd_str, full_output)
          return
        end

        M.show_build_output("Build Successful: " .. model_name, cmd_str, full_output)
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

  local cmd = {
    M.config.dbt_cloud_cli or "dbt",
    "build",
    "--select",
    "+" .. model_name,
  }

  local cmd_str = table.concat(cmd, " ")

  Job:new({
    command = cmd[1],
    args = vim.list_slice(cmd, 2),
    cwd = project_root,
    on_exit = function(j, return_val)
      vim.schedule(function()
        local stderr = table.concat(j:stderr_result(), "\n")
        local stdout = table.concat(j:result(), "\n")
        local full_output = stdout
        if stderr ~= "" then
          full_output = stdout .. "\n" .. stderr
        end

        if return_val ~= 0 then
          vim.notify("[dbt-power] Build failed for upstream of: " .. model_name, vim.log.levels.ERROR)
          M.show_build_output("Build Failed (Upstream): " .. model_name, cmd_str, full_output)
          return
        end

        M.show_build_output("Build Successful (Upstream): " .. model_name, cmd_str, full_output)
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

  local cmd = {
    M.config.dbt_cloud_cli or "dbt",
    "build",
    "--select",
    model_name .. "+",
  }

  local cmd_str = table.concat(cmd, " ")

  Job:new({
    command = cmd[1],
    args = vim.list_slice(cmd, 2),
    cwd = project_root,
    on_exit = function(j, return_val)
      vim.schedule(function()
        local stderr = table.concat(j:stderr_result(), "\n")
        local stdout = table.concat(j:result(), "\n")
        local full_output = stdout
        if stderr ~= "" then
          full_output = stdout .. "\n" .. stderr
        end

        if return_val ~= 0 then
          vim.notify("[dbt-power] Build failed for downstream of: " .. model_name, vim.log.levels.ERROR)
          M.show_build_output("Build Failed (Downstream): " .. model_name, cmd_str, full_output)
          return
        end

        M.show_build_output("Build Successful (Downstream): " .. model_name, cmd_str, full_output)
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

  local cmd = {
    M.config.dbt_cloud_cli or "dbt",
    "build",
    "--select",
    "+" .. model_name .. "+",
  }

  local cmd_str = table.concat(cmd, " ")

  Job:new({
    command = cmd[1],
    args = vim.list_slice(cmd, 2),
    cwd = project_root,
    on_exit = function(j, return_val)
      vim.schedule(function()
        local stderr = table.concat(j:stderr_result(), "\n")
        local stdout = table.concat(j:result(), "\n")
        local full_output = stdout
        if stderr ~= "" then
          full_output = stdout .. "\n" .. stderr
        end

        if return_val ~= 0 then
          vim.notify("[dbt-power] Build failed for all dependencies of: " .. model_name, vim.log.levels.ERROR)
          M.show_build_output("Build Failed (All Dependencies): " .. model_name, cmd_str, full_output)
          return
        end

        M.show_build_output("Build Successful (All Dependencies): " .. model_name, cmd_str, full_output)
        vim.notify("[dbt-power] Successfully built all dependencies for: " .. model_name, vim.log.levels.INFO)
      end)
    end,
  }):start()
end

-- Show build output in a split buffer
function M.show_build_output(title, command, output)
  -- Create new buffer for output
  local buf = vim.api.nvim_create_buf(false, true)

  -- Format output
  local lines = {}

  -- Add title
  if title then
    table.insert(lines, "## " .. title)
    table.insert(lines, "")
  end

  -- Add command that was executed
  table.insert(lines, "**Command:**")
  table.insert(lines, "```bash")
  table.insert(lines, command)
  table.insert(lines, "```")
  table.insert(lines, "")

  -- Add separator
  table.insert(lines, "---")
  table.insert(lines, "")
  table.insert(lines, "**Output:**")
  table.insert(lines, "")

  -- Add the actual output
  if output and output ~= "" then
    for line in output:gmatch("[^\n]+") do
      table.insert(lines, line)
    end
  else
    table.insert(lines, "(No output)")
  end

  -- Set buffer content
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Make buffer read-only
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
  vim.api.nvim_buf_set_name(buf, "[dbt-power] Build Output")

  -- Open split at bottom
  vim.cmd("botright 30split")
  vim.api.nvim_set_current_buf(buf)

  -- Disable line wrapping for output visibility
  vim.api.nvim_set_option_value("wrap", false, { win = vim.api.nvim_get_current_win() })

  -- Add keymaps to close and navigate
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end, { buffer = buf, silent = true, desc = "Close build output" })

  vim.keymap.set("n", "<Esc>", function()
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end, { buffer = buf, silent = true, desc = "Close build output" })

  vim.keymap.set("n", "+", function()
    vim.cmd("resize +10")
  end, { buffer = buf, silent = true, desc = "Make output window taller" })

  vim.keymap.set("n", "-", function()
    vim.cmd("resize -10")
  end, { buffer = buf, silent = true, desc = "Make output window smaller" })

  -- Return to previous buffer
  vim.cmd("wincmd p")
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
