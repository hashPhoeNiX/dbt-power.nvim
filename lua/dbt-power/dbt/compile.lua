-- Compile dbt models and show preview

local M = {}
local Job = require("plenary.job")

M.config = {}
M.auto_compile_enabled = false
M.preview_bufnr = nil
M.preview_winid = nil

function M.setup(config)
  M.config = config or {}
end

-- Show compiled SQL in split window
function M.show_compiled_sql()
  local model_name = M.get_model_name()
  if not model_name then
    vim.notify("[dbt-power] Not in a dbt model", vim.log.levels.WARN)
    return
  end

  vim.notify("[dbt-power] Compiling " .. model_name .. "...", vim.log.levels.INFO)

  M.compile_model(model_name, function(compiled_sql)
    if not compiled_sql then
      vim.notify("[dbt-power] Failed to compile model", vim.log.levels.ERROR)
      return
    end

    -- Create or update preview window
    M.show_in_split(compiled_sql)
  end)
end

-- Compile dbt model
function M.compile_model(model_name, callback)
  local project_root = require("dbt-power.utils.project").find_dbt_project()
  if not project_root then
    callback(nil)
    return
  end

  local cmd = {
    M.config.dbt_cloud_cli or "dbt",
    "compile",
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
          local error_msg = table.concat(j:stderr_result(), "\n")
          vim.notify("[dbt-power] Compile error: " .. error_msg, vim.log.levels.ERROR)
          callback(nil)
          return
        end

        -- Read compiled SQL
        local compiled_sql = M.read_compiled_sql(project_root)
        callback(compiled_sql)
      end)
    end,
  }):start()
end

-- Read compiled SQL from target directory
function M.read_compiled_sql(project_root)
  local relative_path = vim.fn.expand("%:.")
  local compiled_path = string.format("%s/target/compiled/%s", project_root, relative_path)

  -- Try to read compiled file
  local file = io.open(compiled_path, "r")
  if not file then
    -- Try alternative path (without project name)
    local model_name = vim.fn.expand("%:t")
    local alt_path = vim.fn.glob(project_root .. "/target/compiled/**/" .. model_name)
    if alt_path ~= "" then
      file = io.open(alt_path, "r")
    end
  end

  if not file then
    return nil
  end

  local content = file:read("*all")
  file:close()
  return content
end

-- Show content in split window
function M.show_in_split(content)
  -- Check if preview window already exists
  if M.preview_winid and vim.api.nvim_win_is_valid(M.preview_winid) then
    -- Update existing window
    local bufnr = vim.api.nvim_win_get_buf(M.preview_winid)
    M.set_buffer_content(bufnr, content)
    return
  end

  -- Create new split
  local split_cmd
  if M.config.preview.split_position == "below" then
    split_cmd = "botright split"
  else
    split_cmd = "vertical botright split"
  end

  vim.cmd(split_cmd)

  -- Create buffer
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, bufnr)

  -- Set buffer options
  vim.bo[bufnr].filetype = "sql"
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false

  -- Set buffer name
  vim.api.nvim_buf_set_name(bufnr, "[dbt-power] Compiled SQL")

  -- Set content
  M.set_buffer_content(bufnr, content)

  -- Store window ID
  M.preview_winid = vim.api.nvim_get_current_win()
  M.preview_bufnr = bufnr

  -- Set window size
  if M.config.preview.split_position == "below" then
    vim.cmd("resize " .. (M.config.preview.split_size or 20))
  else
    vim.cmd("vertical resize " .. (M.config.preview.split_size or 80))
  end

  -- Return to original window
  vim.cmd("wincmd p")
end

-- Set buffer content
function M.set_buffer_content(bufnr, content)
  local lines = vim.split(content, "\n")

  -- Make buffer modifiable temporarily
  vim.bo[bufnr].modifiable = true

  -- Set lines
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  -- Make readonly
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].modified = false
end

-- Toggle auto-compile mode
function M.toggle_auto_compile()
  M.auto_compile_enabled = not M.auto_compile_enabled

  if M.auto_compile_enabled then
    M.setup_auto_compile()
    vim.notify("[dbt-power] Auto-compile enabled", vim.log.levels.INFO)
  else
    M.teardown_auto_compile()
    vim.notify("[dbt-power] Auto-compile disabled", vim.log.levels.INFO)
  end
end

-- Setup auto-compile on text change
function M.setup_auto_compile()
  local group = vim.api.nvim_create_augroup("DbtPowerAutoCompile", { clear = true })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    buffer = 0,
    callback = function()
      -- Debounce
      if M.auto_compile_timer then
        M.auto_compile_timer:stop()
      end

      M.auto_compile_timer = vim.defer_fn(function()
        M.show_compiled_sql()
      end, 1000) -- 1 second debounce
    end,
  })
end

-- Teardown auto-compile
function M.teardown_auto_compile()
  if M.auto_compile_timer then
    M.auto_compile_timer:stop()
    M.auto_compile_timer = nil
  end

  vim.api.nvim_del_augroup_by_name("DbtPowerAutoCompile")
end

-- Get model name from current file
function M.get_model_name()
  local filepath = vim.fn.expand("%:p")
  if not filepath:match("%.sql$") then
    return nil
  end

  return vim.fn.expand("%:t:r")
end

return M
