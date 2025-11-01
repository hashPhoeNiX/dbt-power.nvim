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
  -- Check if we're in a dbt model file
  local filepath = vim.fn.expand("%:p")

  if filepath:match("%.sql$") then
    -- Get model name and project root
    local model_name = M.get_model_name()
    local project_root = require("dbt-power.utils.project").find_dbt_project()

    if not model_name or not project_root then
      vim.notify("[dbt-power] Could not determine model name or project root", vim.log.levels.ERROR)
      return
    end

    -- Show loading indicator
    local buffer_output = require("dbt-power.ui.buffer_output")
    buffer_output.show_loading("[dbt-power] Executing " .. model_name .. "...")

    -- Use dbt show approach
    M.execute_with_dbt_show(project_root, model_name, function(results)
      if results.error then
        vim.notify("[dbt-power] Error: " .. results.error, vim.log.levels.ERROR)
        buffer_output.clear_loading()
        return
      end

      -- Display in buffer instead of inline
      buffer_output.show_results_in_buffer(results, "Model: " .. model_name)

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

-- Execute current model using dbt show (ALTERNATIVE METHOD)
-- Use different keymap for this (e.g., <leader>ds)
function M.execute_with_dbt_show_command()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1

  -- Clear previous results at this line
  inline_results.clear_at_line(bufnr, cursor_line)

  -- Show loading indicator
  local model_name = M.get_model_name()
  vim.notify("[dbt-power] Executing " .. (model_name or "query") .. "...", vim.log.levels.INFO, {
    timeout = 0,  -- Don't auto-dismiss while waiting
  })

  -- Check if we're in a dbt model file
  local filepath = vim.fn.expand("%:p")

  if filepath:match("%.sql$") then
    -- Get model name and project root
    local model_name = M.get_model_name()
    local project_root = require("dbt-power.utils.project").find_dbt_project()

    if not model_name or not project_root then
      vim.notify("[dbt-power] Could not determine model name or project root", vim.log.levels.ERROR)
      return
    end

    -- Use dbt show approach
    M.execute_with_dbt_show(project_root, model_name, function(results)
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

-- Execute visual selection
function M.execute_selection()
  local bufnr = vim.api.nvim_get_current_buf()
  local start_line = vim.fn.getpos("'<")[2] - 1
  local end_line = vim.fn.getpos("'>")[2]

  -- Get selected text
  local selected_lines = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line, false)
  if #selected_lines == 0 then
    vim.notify("[dbt-power] No selection", vim.log.levels.WARN)
    return
  end

  local selected_sql = table.concat(selected_lines, "\n")
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

  -- Execute via vim-dadbod
  M.execute_via_dadbod(selected_sql, function(results)
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
          vim.notify("[dbt-power] Compile failed: " .. stderr, vim.log.levels.WARN)
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
          os.remove(output_file)
          callback({ error = "Database query failed: " .. stderr })
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
          callback({ error = "dbt show failed: " .. stderr })
          return
        end

        -- Parse results from dbt show output
        local stdout = table.concat(j:result(), "\n")
        local results = M.parse_dbt_show_results(stdout)

        if not results.columns or #results.columns == 0 then
          callback({ error = "No results returned from model" })
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
  local lines = vim.split(output, "\n")
  local columns = {}
  local rows = {}

  -- Debug: check if output is empty
  if not output or output == "" then
    return { columns = {}, rows = {} }
  end

  -- Find header line (contains column names between pipes)
  local header_idx = nil
  for i, line in ipairs(lines) do
    if line:match("┃") or line:match("|") then
      -- Check if this looks like a header row (not separator)
      if not line:match("^[%s%┏%┳%━]+$") and not line:match("^[%s%-%+]+$") then
        header_idx = i
        break
      end
    end
  end

  if not header_idx then
    return { columns = {}, rows = {} }
  end

  -- Parse header row (handles both pipe and box-drawing characters)
  local header_line = lines[header_idx]
  if header_line:match("┃") then
    -- Box-drawing format: ┃ col1 ┃ col2 ┃
    for col in header_line:gmatch("┃([^┃]+)") do
      local trimmed = vim.trim(col)
      -- Skip the "..." truncation marker
      if trimmed ~= "..." then
        table.insert(columns, trimmed)
      end
    end
  else
    -- Pipe format: | col1 | col2 |
    for col in header_line:gmatch("|([^|]+)") do
      local trimmed = vim.trim(col)
      -- Skip the "..." truncation marker
      if trimmed ~= "..." then
        table.insert(columns, trimmed)
      end
    end
  end

  -- Debug: log header parsing
  -- vim.notify("DEBUG: Found " .. #columns .. " columns", vim.log.levels.DEBUG)

  -- Parse data rows (skip separators and empty lines)
  for i = header_idx + 1, #lines do
    local line = vim.trim(lines[i])

    -- Skip separator lines (box-drawing or ASCII separators)
    if line:match("^[┌┐└┘├┤┼─┬┴│%s]+$") or
       line:match("^[%s%-%+|]+$") or
       line == "" then
      goto continue
    end

    -- Parse data row
    local row = {}
    if line:match("│") then
      -- Box-drawing format: │ val1 │ val2 │
      local col_count = 0
      for value in line:gmatch("│([^│]+)") do
        col_count = col_count + 1
        local trimmed = vim.trim(value)
        -- Skip the "..." truncation marker at the end
        if not (col_count > #columns and trimmed == "...") then
          table.insert(row, trimmed)
        end
      end
    elseif line:match("|") then
      -- Pipe format: | val1 | val2 |
      local col_count = 0
      for value in line:gmatch("|([^|]+)") do
        col_count = col_count + 1
        local trimmed = vim.trim(value)
        -- Skip the "..." truncation marker at the end
        if not (col_count > #columns and trimmed == "...") then
          table.insert(row, trimmed)
        end
      end
    end

    -- Accept row if it has at least one value and roughly matches column count
    -- (be lenient with multiline JSON values that might break parsing)
    if #row > 0 and #row >= math.max(1, #columns - 2) then
      -- Pad with empty strings if we have fewer columns than expected
      while #row < #columns do
        table.insert(row, "")
      end
      -- Trim to exact column count if we have too many
      if #row > #columns then
        for i = #row, #columns + 1, -1 do
          table.remove(row)
        end
      end
      table.insert(rows, row)
    end

    ::continue::
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

return M
