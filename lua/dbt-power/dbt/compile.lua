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

-- Show compiled SQL for visual selection in split window
function M.show_compiled_sql_for_selection()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Try to get visual selection using marks
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  local selected_sql = nil

  if start_pos[2] ~= 0 and end_pos[2] ~= 0 then
    -- Marks are available
    local start_line = start_pos[2] - 1  -- 0-indexed
    local end_line = end_pos[2]
    local start_col = start_pos[3] - 1
    local end_col = end_pos[3]

    -- Get selected lines
    local selected_lines = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line, false)
    if #selected_lines > 0 then
      -- Handle multi-line selection
      if #selected_lines == 1 then
        -- Single line: extract from start_col to end_col
        selected_sql = selected_lines[1]:sub(start_col + 1, end_col)
      else
        -- Multi-line: first line from start_col, last line to end_col
        selected_lines[1] = selected_lines[1]:sub(start_col + 1)
        selected_lines[#selected_lines] = selected_lines[#selected_lines]:sub(1, end_col)
        selected_sql = table.concat(selected_lines, "\n")
      end
    end
  end

  -- Fallback: try to get selection from unnamed register
  if not selected_sql or vim.trim(selected_sql) == "" then
    vim.cmd("noautocmd normal! \"vy\"")
    selected_sql = vim.fn.getreg('"')
  end

  if not selected_sql or vim.trim(selected_sql) == "" then
    vim.notify("[dbt-power] No selection found. Use visual mode (v) to select SQL", vim.log.levels.WARN)
    return
  end

  -- Show loading indicator
  vim.notify("[dbt-power] Compiling selection...", vim.log.levels.INFO)

  -- Trim the selected SQL and ensure it's clean
  selected_sql = vim.trim(selected_sql)

  -- Remove trailing semicolon if present
  selected_sql = selected_sql:gsub("%s*;%s*$", "")

  -- Wrap with CTE to ensure proper SQL structure (for Jinja2 expansion)
  selected_sql = "WITH cte AS (\n  " .. selected_sql .. "\n)\nSELECT * FROM cte"

  -- Create a temporary ad-hoc model from the selection
  local project_root = require("dbt-power.utils.project").find_dbt_project()
  if not project_root then
    vim.notify("[dbt-power] Could not find dbt project root", vim.log.levels.ERROR)
    return
  end

  -- Create adhoc directory if it doesn't exist
  local adhoc_dir = project_root .. "/models/adhoc"
  local stat = vim.fn.getfperm(adhoc_dir)
  if stat == "" then
    vim.fn.mkdir(adhoc_dir, "p")
  end

  -- Generate filename with timestamp for uniqueness
  local timestamp = os.date("%Y%m%d_%H%M%S")
  local micro = math.floor(vim.loop.hrtime() / 1000) % 1000
  local model_name = "adhoc_selection_" .. timestamp .. "_" .. string.format("%03d", micro)
  local model_path = adhoc_dir .. "/" .. model_name .. ".sql"

  -- Write the selected SQL to the temporary model
  local file = io.open(model_path, "w")
  if not file then
    vim.notify("[dbt-power] Failed to create temporary model file", vim.log.levels.ERROR)
    return
  end

  local final_content = string.format("-- Temporary ad-hoc model from visual selection\n-- %s\n\n%s\n", os.date("%Y-%m-%d %H:%M:%S"), selected_sql)
  file:write(final_content)
  file:close()

  -- Store model name for later execution from preview buffer
  M.preview_model_name = model_name

  -- Compile the ad-hoc model
  M.compile_model(model_name, function(result)
    if result.error then
      -- Show error with full details
      M.show_error_details("Compilation failed for selection", result.error)
      -- Clean up the temporary file on error
      os.remove(model_path)
      return
    end

    if not result.compiled_sql then
      -- File not found after successful compile
      M.show_error_details(
        "Compilation succeeded but compiled SQL file not found for selection",
        "Searched paths:\n" .. (result.search_paths or "No paths recorded")
      )
      os.remove(model_path)
      return
    end

    -- Create or update preview window
    M.show_in_split(result.compiled_sql)

    -- Clean up the temporary file after showing
    vim.schedule(function()
      os.remove(model_path)
    end)
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

  -- Strategy: Try to find by model_name first (most reliable), then fallback to current buffer path
  if model_name then
    -- Try path 1: Find by exact model name in target/compiled
    local search_cmd = string.format(
      "find %s/target/compiled -name '%s.sql' -type f 2>/dev/null | sort -r | head -1",
      project_root,
      vim.fn.shellescape(model_name)
    )
    local result = vim.fn.system(search_cmd)
    if result and vim.trim(result) ~= "" then
      local found_path = vim.trim(result)
      table.insert(search_paths, found_path)
      local file = io.open(found_path, "r")
      if file then
        local content = file:read("*a")
        file:close()
        return {
          compiled_sql = content,
          search_paths = table.concat(search_paths, "\n"),
        }
      end
    end
  end

  -- Fallback: Try path based on source file location (current buffer)
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

  -- Last resort: Glob search in target/compiled
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
