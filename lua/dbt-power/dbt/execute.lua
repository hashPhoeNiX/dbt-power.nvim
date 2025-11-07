-- Execute dbt models and show results inline

local M = {}
local Job = require("plenary.job")
local inline_results = require("dbt-power.ui.inline_results")

M.config = {}

function M.setup(config)
  M.config = config or {}
end

-- Execute current model using Power User approach (compile → wrap → execute)
-- PRIMARY METHOD: Matches dbt Power User VS Code extension
function M.execute_and_show_inline()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1

  -- Clear previous results at this line
  inline_results.clear_at_line(bufnr, cursor_line)

  -- Show loading indicator
  vim.notify("[dbt-power] Executing query (Power User mode)...", vim.log.levels.INFO)

  -- Check if we're in a dbt model file
  local filepath = vim.fn.expand("%:p")

  if filepath:match("%.sql$") then
    -- This is a dbt model - use Power User approach
    M.execute_dbt_model_power_user(function(results)
      if results.error then
        vim.notify("[dbt-power] Error: " .. results.error, vim.log.levels.ERROR)
        return
      end

      inline_results.display_query_results(bufnr, cursor_line, results)
      vim.notify(
        string.format("[dbt-power] Executed successfully (%d rows)", #results.rows),
        vim.log.levels.INFO
      )
    end)
  else
    -- Not in a model file - show message
    vim.notify("[dbt-power] Not in a dbt model file (.sql)", vim.log.levels.WARN)
  end
end

-- Execute current model with results in buffer (BUFFER OUTPUT METHOD)
-- Display results in a split window instead of inline
function M.execute_with_dbt_show_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local filepath = vim.fn.expand("%:p")

  local model_name = nil

  -- Check if we're in a dbt model file
  if filepath:match("%.sql$") then
    model_name = M.get_model_name()
  else
    -- Check if we're in the preview buffer and use stored model name
    local compile = require("dbt-power.dbt.compile")
    if compile.preview_model_name and compile.preview_bufnr == bufnr then
      model_name = compile.preview_model_name
    end
  end

  if not model_name then
    vim.notify("[dbt-power] Not in a dbt model file (.sql) or preview buffer", vim.log.levels.WARN)
    return
  end

  local project_root = require("dbt-power.utils.project").find_dbt_project()
  if not project_root then
    vim.notify("[dbt-power] Could not find dbt project root", vim.log.levels.ERROR)
    return
  end

  -- Show loading indicator
  local buffer_output = require("dbt-power.ui.buffer_output")
  buffer_output.show_loading("[dbt-power] Executing " .. model_name .. "...")

  -- Use dbt show approach
  M.execute_with_dbt_show(project_root, model_name, function(results)
    if results.error then
      buffer_output.clear_loading()
      M.show_error_details("dbt show execution failed for model: " .. model_name, results.error)
      return
    end

    -- Display in buffer instead of inline
    buffer_output.show_results_in_buffer(results, "Model: " .. model_name)

    vim.notify(
      string.format("[dbt-power] Executed successfully (%d rows)", #results.rows),
      vim.log.levels.INFO
    )
  end)
end

-- Execute current model using dbt show (ALTERNATIVE METHOD)
-- Use different keymap for this (e.g., <leader>ds)
function M.execute_with_dbt_show_command()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1

  -- Clear previous results at this line
  inline_results.clear_at_line(bufnr, cursor_line)

  local filepath = vim.fn.expand("%:p")
  local model_name = nil

  -- Check if we're in a dbt model file
  if filepath:match("%.sql$") then
    model_name = M.get_model_name()
  else
    -- Check if we're in the preview buffer and use stored model name
    local compile = require("dbt-power.dbt.compile")
    if compile.preview_model_name and compile.preview_bufnr == bufnr then
      model_name = compile.preview_model_name
    end
  end

  if not model_name then
    vim.notify("[dbt-power] Not in a dbt model file (.sql) or preview buffer", vim.log.levels.WARN)
    return
  end

  local project_root = require("dbt-power.utils.project").find_dbt_project()
  if not project_root then
    vim.notify("[dbt-power] Could not find dbt project root", vim.log.levels.ERROR)
    return
  end

  -- Show loading indicator
  vim.notify("[dbt-power] Executing " .. model_name .. "...", vim.log.levels.INFO, {
    timeout = 0,  -- Don't auto-dismiss while waiting
  })

  -- Use dbt show approach
  M.execute_with_dbt_show(project_root, model_name, function(results)
    if results.error then
      M.show_error_details("dbt show execution failed for model: " .. model_name, results.error)
      return
    end

    inline_results.display_query_results(bufnr, cursor_line, results)
    vim.notify(
      string.format("[dbt-power] Executed successfully (%d rows)", #results.rows),
      vim.log.levels.INFO
    )
  end)
end

-- Execute visual selection by creating a temporary ad-hoc model
function M.execute_selection()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Get visual selection using marks (more reliable)
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  if start_pos[2] == 0 or end_pos[2] == 0 then
    vim.notify("[dbt-power] No selection found. Use visual mode (v) to select SQL", vim.log.levels.WARN)
    return
  end

  local start_line = start_pos[2] - 1  -- 0-indexed
  local end_line = end_pos[2]
  local start_col = start_pos[3] - 1
  local end_col = end_pos[3]

  -- Get selected lines
  local selected_lines = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line, false)
  if #selected_lines == 0 then
    vim.notify("[dbt-power] Could not retrieve selected text", vim.log.levels.WARN)
    return
  end

  -- Handle multi-line selection
  local selected_sql
  if #selected_lines == 1 then
    -- Single line: extract from start_col to end_col
    selected_sql = selected_lines[1]:sub(start_col + 1, end_col)
  else
    -- Multi-line: first line from start_col, last line to end_col
    selected_lines[1] = selected_lines[1]:sub(start_col + 1)
    selected_lines[#selected_lines] = selected_lines[#selected_lines]:sub(1, end_col)
    selected_sql = table.concat(selected_lines, "\n")
  end

  if vim.trim(selected_sql) == "" then
    vim.notify("[dbt-power] Selection is empty", vim.log.levels.WARN)
    return
  end

  local cursor_line = start_line

  -- Clear previous results
  inline_results.clear_at_line(bufnr, cursor_line)

  -- Show loading indicator
  vim.notify("[dbt-power] Executing selection...", vim.log.levels.INFO)

  -- Add LIMIT if not present
  local sql_upper = selected_sql:upper()
  if not sql_upper:match("LIMIT") then
    local limit = M.config.inline_results.max_rows or 500
    selected_sql = M.wrap_with_limit(selected_sql, limit)
  end

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

  file:write(string.format("-- Temporary ad-hoc model from visual selection\n-- %s\n\n%s\n", os.date("%Y-%m-%d %H:%M:%S"), selected_sql))
  file:close()

  -- Execute the ad-hoc model using dbt show
  M.execute_with_dbt_show(project_root, model_name, function(results)
    if results.error then
      M.show_error_details("dbt show execution failed for selection", results.error)
      -- Clean up the temporary file on error
      os.remove(model_path)
      return
    end

    -- Display results inline
    inline_results.display_query_results(bufnr, cursor_line, results)
    vim.notify(
      string.format("[dbt-power] Selection executed successfully (%d rows)", #results.rows),
      vim.log.levels.INFO
    )

    -- Clean up the temporary file after execution
    vim.schedule(function()
      os.remove(model_path)
    end)
  end)
end

-- Execute dbt model using Power User approach (compile → wrap → execute)
-- STEP 1: Compile → STEP 2: Wrap → STEP 3: Execute
function M.execute_dbt_model_power_user(callback)
  local project_root = require("dbt-power.utils.project").find_dbt_project()
  if not project_root then
    callback({ error = "Not in a dbt project" })
    return
  end

  -- Get model name from current file
  local model_name = M.get_model_name()
  if not model_name then
    callback({ error = "Could not determine model name from filename" })
    return
  end

  -- STEP 1: Compile the model (same as Power User)
  M.compile_dbt_model(project_root, model_name, function(compiled_sql)
    if not compiled_sql then
      -- Fallback to dbt show if compile fails
      vim.notify("[dbt-power] Compile failed, trying dbt show as fallback", vim.log.levels.WARN)
      M.execute_with_dbt_show(project_root, model_name, callback)
      return
    end

    -- STEP 2: Wrap with LIMIT clause (same as Power User)
    local limit = M.config.inline_results.max_rows or 500
    local wrapped_sql = M.wrap_with_limit(compiled_sql, limit)

    -- STEP 3: Execute wrapped SQL via vim-dadbod
    -- This is where results come from the database
    M.execute_wrapped_sql(project_root, wrapped_sql, callback)
  end)
end

-- STEP 1: Compile dbt model using dbt compile command
function M.compile_dbt_model(project_root, model_name, callback)
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
          local stderr = table.concat(j:stderr_result(), "\n")
          local stdout = table.concat(j:result(), "\n")
          local full_output = stderr
          if stdout ~= "" then
            full_output = stdout .. "\n" .. stderr
          end
          M.show_error_details("dbt compile failed for model: " .. model_name, full_output)
          callback(nil)
          return
        end

        -- Read compiled SQL from target/compiled/
        local compiled_sql = M.read_compiled_sql(project_root, model_name)
        callback(compiled_sql)
      end)
    end,
  }):start()
end

-- Read compiled SQL from target directory
function M.read_compiled_sql(project_root, model_name)
  -- Try to find compiled file using model name
  local relative_path = vim.fn.expand("%:.")  -- Current file relative path
  local compiled_path = project_root .. "/target/compiled/" .. relative_path:gsub("%.sql$", ".sql")

  -- Try reading from expected path
  local file = io.open(compiled_path, "r")
  if file then
    local content = file:read("*a")
    file:close()
    return content
  end

  -- Fallback: Search for compiled file by model name
  local search_cmd = string.format(
    "find %s/target/compiled -name '%s.sql' -type f 2>/dev/null | head -1",
    project_root,
    model_name
  )
  local result = vim.fn.system(search_cmd)
  if result and result ~= "" then
    local found_path = vim.trim(result)
    file = io.open(found_path, "r")
    if file then
      local content = file:read("*a")
      file:close()
      return content
    end
  end

  return nil
end

-- STEP 2: Wrap SQL with LIMIT clause (same as Power User)
function M.wrap_with_limit(sql, limit)
  -- Remove trailing semicolon and whitespace
  sql = sql:gsub("%s*;%s*$", "")

  -- Wrap with LIMIT clause (Power User pattern)
  -- SELECT * FROM (<sql>) AS query LIMIT <limit>
  return string.format(
    "SELECT * FROM (\n%s\n) AS query LIMIT %d",
    sql,
    limit
  )
end

-- STEP 3: Execute wrapped SQL against database via vim-dadbod
function M.execute_wrapped_sql(project_root, wrapped_sql, callback)
  -- Try to execute using vim-dadbod if available
  local ok, dadbod = pcall(require, "dadbod")

  if ok then
    -- vim-dadbod available, use it to execute query
    M.execute_via_dadbod(wrapped_sql, callback)
  else
    -- Fallback: Try using dbt show as alternate execution method
    vim.notify("[dbt-power] vim-dadbod not available, using dbt show as fallback", vim.log.levels.WARN)
    -- For now, show a message about what would be executed
    vim.notify("[dbt-power] Would execute: " .. wrapped_sql:sub(1, 50) .. "...", vim.log.levels.INFO)
    callback({
      error = "Database connection not configured. Use <leader>db to configure via DBUI"
    })
  end
end

-- Execute SQL using vim-dadbod database interface
function M.execute_via_dadbod(sql, callback)
  -- vim-dadbod requires an active database connection
  -- Check if a database is configured
  local db = vim.g.db or vim.g.dbs and vim.g.dbs[vim.g.db_ui_default_connection]

  if not db then
    callback({ error = "No database connection configured. Use :DBUIToggle to configure." })
    return
  end

  -- Create temp SQL file for execution
  local temp_file = vim.fn.tempname() .. ".sql"
  local output_file = vim.fn.tempname() .. ".csv"

  local file = io.open(temp_file, "w")
  if not file then
    callback({ error = "Could not create temp SQL file" })
    return
  end

  file:write(sql)
  file:close()

  -- Use dadbod to execute the query and save results to CSV
  local cmd = string.format(
    'DB %s < "%s" > "%s" 2>&1',
    db,
    temp_file,
    output_file
  )

  Job:new({
    command = "sh",
    args = { "-c", cmd },
    on_exit = function(j, return_val)
      vim.schedule(function()
        -- Clean up temp files
        os.remove(temp_file)

        if return_val ~= 0 then
          local stderr = table.concat(j:stderr_result(), "\n")
          local stdout = table.concat(j:result(), "\n")
          os.remove(output_file)
          local full_output = stderr
          if stdout ~= "" then
            full_output = stdout .. "\n" .. stderr
          end
          callback({ error = "Database query failed:\n" .. full_output })
          return
        end

        -- Read and parse results
        local output = io.open(output_file, "r")
        if not output then
          callback({ error = "Could not read query results" })
          return
        end

        local results = output:read("*a")
        output:close()
        os.remove(output_file)

        -- Parse CSV results
        local parsed = M.parse_csv_results(results)
        callback(parsed)
      end)
    end,
  }):start()
end

-- Parse CSV results from query output
function M.parse_csv_results(csv_content)
  local lines = vim.split(csv_content, "\n")
  local columns = {}
  local rows = {}

  if #lines == 0 then
    return { columns = {}, rows = {} }
  end

  -- First line is header (comma-separated)
  local header_line = vim.trim(lines[1])
  if header_line ~= "" then
    for col in header_line:gmatch("[^,]+") do
      table.insert(columns, vim.trim(col))
    end
  end

  -- Parse data rows
  for i = 2, #lines do
    local line = vim.trim(lines[i])
    if line ~= "" then
      local row = {}
      for value in line:gmatch("[^,]+") do
        table.insert(row, vim.trim(value))
      end
      if #row == #columns then
        table.insert(rows, row)
      end
    end
  end

  return {
    columns = columns,
    rows = rows,
  }
end

-- FALLBACK METHOD: Use dbt show if compile/execute approach fails
function M.execute_with_dbt_show(project_root, model_name, callback)
  vim.notify("[dbt-power] Executing with dbt show command", vim.log.levels.INFO)

  local limit = M.config.inline_results and M.config.inline_results.max_rows or 500

  local cmd = {
    M.config.dbt_cloud_cli or "dbt",
    "show",
    "--select",
    model_name,
    "--limit",
    tostring(limit),
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
          callback({ error = full_output })
          return
        end

        -- Parse results from dbt show output
        -- Combine stdout and stderr since dbt Cloud CLI might write to both
        local stdout = table.concat(j:result(), "\n")
        local stderr = table.concat(j:stderr_result(), "\n")
        local full_output = stdout
        if stderr ~= "" then
          full_output = stdout .. "\n" .. stderr
        end

        -- FIRST: Check if output contains a dbt error (before trying to parse as table)
        if full_output:match("Encountered an error:") then
          -- Extract error section between "Encountered an error:" and "Invocation has finished"
          local error_section = ""
          local lines = vim.split(full_output, "\n")
          local in_error = false
          for _, line in ipairs(lines) do
            if line:match("Encountered an error:") then
              in_error = true
            end
            if in_error then
              error_section = error_section .. line .. "\n"
              if line:match("Invocation has finished") then
                break
              end
            end
          end
          callback({ error = error_section })
          return
        end

        -- SECOND: Parse as table results
        local results = M.parse_dbt_show_results(full_output)

        if not results.columns or #results.columns == 0 then
          -- No error found and no columns parsed - show debug message
          local debug_msg = "Parser could not find columns in dbt show output.\n\n"
          debug_msg = debug_msg .. "Total output length: " .. #full_output .. " chars\n\n"
          debug_msg = debug_msg .. "Raw output (first 1500 chars):\n"
          debug_msg = debug_msg .. full_output:sub(1, 1500)
          if #full_output > 1500 then
            debug_msg = debug_msg .. "\n... (truncated)\n\nCheck :messages for debug info"
          end
          callback({ error = debug_msg })
          return
        end

        callback(results)
      end)
    end,
  }):start()
end

-- Parse dbt show output
-- dbt show returns output in pipe-separated format with borders:
-- ┏━━━━━━━━━━┳━━━━━━━━━━━┓
-- ┃ column1  ┃ column2   ┃
-- ┡━━━━━━━━━━╇━━━━━━━━━━━┩
-- │ value1   │ value2    │
-- └──────────┴───────────┘
function M.parse_dbt_show_results(output)
  local columns = {}
  local rows = {}

  -- Debug: check if output is empty
  if not output or output == "" then
    return { columns = {}, rows = {} }
  end

  -- First pass: find and parse header line
  local lines = vim.split(output, "\n")

  -- Skip dbt Cloud CLI logging lines at the beginning
  -- Look for lines that contain actual table content (pipes or box drawing chars)
  local table_start_idx = 1
  for i, line in ipairs(lines) do
    -- Skip logging lines (Sending, Created, Waiting, Streaming, Running, Downloading, Invocation)
    if line:match("^[A-Za-z]") and not line:match("[┃│┏┓┐└┘├┤┼─┬┴┳┲┪┨┦|%-+%s]") then
      table_start_idx = i + 1
    elseif line:match("[┃│|]") then
      -- Found start of table
      table_start_idx = i
      break
    end
  end

  local header_idx = nil
  local use_box_chars = false

  for i = table_start_idx, #lines do
    local line = lines[i]
    if line:match("┃") or line:match("|") then
      -- Check if this looks like a header row (not separator)
      if not line:match("^[%s%┏%┳%━]+$") and not line:match("^[%s%-%+]+$") then
        header_idx = i
        use_box_chars = line:match("┃") ~= nil
        break
      end
    end
  end

  if not header_idx then
    return { columns = {}, rows = {} }
  end

  -- Parse header row
  local header_line = lines[header_idx]
  local pipe_pattern
  if use_box_chars then
    pipe_pattern = "┃"
    -- Use direct pattern for box-drawing character
    for col in header_line:gmatch("┃([^┃]+)") do
      local trimmed = vim.trim(col)
      -- Skip the "..." truncation marker
      if trimmed ~= "..." then
        table.insert(columns, trimmed)
      end
    end
  else
    pipe_pattern = "|"
    -- Use direct pattern for pipe
    for col in header_line:gmatch("|([^|]+)") do
      local trimmed = vim.trim(col)
      -- Skip the "..." truncation marker
      if trimmed ~= "..." then
        table.insert(columns, trimmed)
      end
    end
  end

  if #columns == 0 then
    return { columns = {}, rows = {} }
  end

  -- Second pass: parse data rows, handling multiline values
  -- Strategy: Accumulate lines and try to parse until we get the right number of columns
  local current_row_lines = {}

  for i = header_idx + 1, #lines do
    -- Make sure we're still in the table section
    if i > header_idx + 1000 then
      break  -- Safety check to avoid parsing too far
    end
    local line = lines[i]

    -- Skip completely empty lines
    if vim.trim(line) == "" then
      goto continue_row_parse
    end

    -- Skip separator lines
    if vim.trim(line):match("^[┌┐└┘├┤┼─┬┴│%s]+$") or
       vim.trim(line):match("^[%s%-%+|]+$") then
      goto continue_row_parse
    end

    -- Add line to current row
    table.insert(current_row_lines, line)

    -- Try to parse accumulated lines into columns
    local full_line = table.concat(current_row_lines, " "):gsub("%s+", " ")
    local row = {}

    -- Parse the accumulated lines - handle both box-drawing and pipe characters
    if use_box_chars then
      for value in full_line:gmatch("│([^│]+)") do
        local trimmed = vim.trim(value)
        -- Skip "..." truncation markers
        if trimmed ~= "..." then
          table.insert(row, trimmed)
        end
      end
    else
      for value in full_line:gmatch("|([^|]+)") do
        local trimmed = vim.trim(value)
        -- Skip "..." truncation markers
        if trimmed ~= "..." then
          table.insert(row, trimmed)
        end
      end
    end

    -- If we now have the right number of columns, this row is complete
    if #row == #columns then
      table.insert(rows, row)
      current_row_lines = {}
    end

    ::continue_row_parse::
  end

  return {
    columns = columns,
    rows = rows,
  }
end

-- Get model name from filepath
function M.get_model_name()
  local filepath = vim.fn.expand("%:t:r") -- filename without extension
  if not filepath or filepath == "" then
    return nil
  end
  return filepath
end

-- Show error details in a popup or buffer
-- Extracts key error information and displays it prominently
function M.show_error_details(title, error_output)
  -- Parse error output to extract key information
  local lines = vim.split(error_output, "\n")

  -- Special handling for dbt Cloud CLI output: extract error between "Encountered an error:" and "Invocation has finished"
  local error_lines = {}
  local in_error_section = false
  local found_dbt_error = false

  for i, line in ipairs(lines) do
    -- Check for dbt Cloud error section
    if line:match("Encountered an error:") then
      found_dbt_error = true
      in_error_section = true
      table.insert(error_lines, line)
    elseif in_error_section and line:match("Invocation has finished") then
      -- End of error section
      break
    elseif in_error_section then
      if vim.trim(line) ~= "" then
        table.insert(error_lines, vim.trim(line))
      end
    end
  end

  -- If we didn't find a dbt Cloud error section, look for general error patterns
  if not found_dbt_error then
    for _, line in ipairs(lines) do
      if line:match("Error") or line:match("ERROR") or line:match("error") then
        if vim.trim(line) ~= "" then
          table.insert(error_lines, vim.trim(line))
        end
        -- Collect up to 15 error-related lines
        if #error_lines >= 15 then
          break
        end
      end
    end
  end

  -- If still no error lines found, show the first non-empty lines
  if #error_lines == 0 then
    for i = 1, math.min(10, #lines) do
      if vim.trim(lines[i]) ~= "" then
        table.insert(error_lines, vim.trim(lines[i]))
      end
    end
  end

  -- Format error message with context
  local error_message = title .. "\n\n" .. table.concat(error_lines, "\n")

  -- Show as error notification with long timeout
  vim.notify(error_message, vim.log.levels.ERROR, {
    title = "dbt-power Error",
    timeout = 0,  -- Don't auto-dismiss
  })

  -- Also open a quickfix list with the full error for easy reference
  local qf_list = {}
  for i, line in ipairs(lines) do
    if vim.trim(line) ~= "" then
      table.insert(qf_list, {
        text = line,
        lnum = i,
        col = 1,
      })
    end
  end

  if #qf_list > 0 then
    vim.fn.setqflist(qf_list)
    -- Optional: automatically open quickfix window
    -- vim.cmd("copen")
  end
end

return M
