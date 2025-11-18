-- Compile dbt models and show preview

local M = {}
local Job = require("plenary.job")

M.config = {}
M.auto_compile_enabled = false
M.preview_bufnr = nil
M.preview_winid = nil
M.preview_model_name = nil  -- Store model name for execution from preview buffer

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

  -- Store model name for later execution from preview buffer
  M.preview_model_name = model_name

  vim.notify("[dbt-power] Compiling " .. model_name .. "...", vim.log.levels.INFO)

  M.compile_model(model_name, function(result)
    if result.error then
      -- Show error with full details
      M.show_error_details("Compilation failed for model: " .. model_name, result.error)
      return
    end

    if not result.compiled_sql then
      -- File not found after successful compile
      M.show_error_details(
        "Compilation succeeded but compiled SQL file not found",
        "Searched paths:\n" .. (result.search_paths or "No paths recorded")
      )
      return
    end

    -- Create or update preview window
    M.show_in_split(result.compiled_sql)
  end)
end

-- Compile dbt model
function M.compile_model(model_name, callback)
  local project_root = require("dbt-power.utils.project").find_dbt_project()
  if not project_root then
    callback({ error = "Could not find dbt project root" })
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
          -- Combine stdout and stderr for full error context
          local stderr = table.concat(j:stderr_result(), "\n")
          local stdout = table.concat(j:result(), "\n")
          local full_error = stderr
          if stdout ~= "" then
            full_error = stdout .. "\n" .. stderr
          end

          callback({
            error = full_error,
            model_name = model_name,
            project_root = project_root,
          })
          return
        end

        -- Read compiled SQL
        local result = M.read_compiled_sql(project_root, model_name)
        callback(result)
      end)
    end,
  }):start()
end

-- Read compiled SQL from target directory
function M.read_compiled_sql(project_root, model_name)
  local search_paths = {}

  -- Try path 1: Relative path based on source file location
  local relative_path = vim.fn.expand("%:.")
  local compiled_path = string.format("%s/target/compiled/%s", project_root, relative_path)
  table.insert(search_paths, compiled_path)

  local file = io.open(compiled_path, "r")
  if file then
    local content = file:read("*a")
    file:close()
    return {
      compiled_sql = content,
      search_paths = table.concat(search_paths, "\n"),
    }
  end

  -- Try path 2: Glob search in target/compiled
  local filename = vim.fn.expand("%:t")
  local glob_pattern = project_root .. "/target/compiled/**/" .. filename
  local alt_path = vim.fn.glob(glob_pattern)
  if alt_path ~= "" then
    table.insert(search_paths, alt_path)
    file = io.open(alt_path, "r")
    if file then
      local content = file:read("*a")
      file:close()
      return {
        compiled_sql = content,
        search_paths = table.concat(search_paths, "\n"),
      }
    end
  end

  -- File not found
  return {
    error = nil,
    compiled_sql = nil,
    search_paths = table.concat(search_paths, "\n") .. "\n\nTried to find: " .. filename,
  }
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

-- Show detailed error information
function M.show_error_details(title, error_msg)
  -- Show as notification first
  vim.notify(title, vim.log.levels.ERROR, {
    title = "dbt-power Compile Error",
    timeout = 0,  -- Don't auto-dismiss
  })

  -- Open quickfix list with error details
  local qf_entries = {}
  local lines = vim.split(error_msg or "", "\n")

  for i, line in ipairs(lines) do
    if vim.trim(line) ~= "" then
      table.insert(qf_entries, {
        text = line,
        lnum = i,
        col = 1,
      })
    end
  end

  if #qf_entries > 0 then
    vim.fn.setqflist(qf_entries)
    -- Auto-open quickfix window
    vim.cmd("copen")
  end
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
