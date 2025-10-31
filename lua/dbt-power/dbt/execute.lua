-- Execute dbt models and show results inline

local M = {}
local Job = require("plenary.job")
local inline_results = require("dbt-power.ui.inline_results")

M.config = {}

function M.setup(config)
  M.config = config or {}
end

-- Execute current model and show results inline
function M.execute_and_show_inline()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1

  -- Get SQL to execute
  local sql = M.get_current_sql()
  if not sql then
    vim.notify("[dbt-power] No SQL to execute", vim.log.levels.WARN)
    return
  end

  -- Add LIMIT for preview
  local preview_sql = M.add_limit_clause(sql, M.config.inline_results.max_rows)

  -- Clear previous results at this line
  inline_results.clear_at_line(bufnr, cursor_line)

  -- Show loading indicator
  vim.notify("[dbt-power] Executing query...", vim.log.levels.INFO)

  -- Execute query via dbt (preferred) or fallback to vim-dadbod
  M.execute_query_dbt(preview_sql, function(results)
    if results.error then
      vim.notify("[dbt-power] Error: " .. results.error, vim.log.levels.ERROR)
      return
    end

    -- Display results inline
    inline_results.display_query_results(bufnr, cursor_line, results)

    vim.notify(
      string.format("[dbt-power] Executed successfully (%d rows)", #results.rows),
      vim.log.levels.INFO
    )
  end)
end

-- Execute visual selection
function M.execute_selection()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Get visual selection
  local start_line = vim.fn.line("'<") - 1
  local end_line = vim.fn.line("'>") - 1
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line + 1, false)
  local sql = table.concat(lines, "\n")

  if not sql or sql == "" then
    vim.notify("[dbt-power] No SQL selected", vim.log.levels.WARN)
    return
  end

  -- Clear previous results
  inline_results.clear_at_line(bufnr, end_line)

  -- Add LIMIT
  local preview_sql = M.add_limit_clause(sql, M.config.inline_results.max_rows)

  -- Show loading indicator
  vim.notify("[dbt-power] Executing selection...", vim.log.levels.INFO)

  -- Execute via dbt (preferred) or fallback to vim-dadbod
  M.execute_query_dbt(preview_sql, function(results)
    if results.error then
      vim.notify("[dbt-power] Error: " .. results.error, vim.log.levels.ERROR)
      return
    end

    inline_results.display_query_results(bufnr, end_line, results)
    vim.notify(
      string.format("[dbt-power] Executed successfully (%d rows)", #results.rows),
      vim.log.levels.INFO
    )
  end)
end

-- Get SQL from current context
function M.get_current_sql()
  -- Check if we're in a dbt model
  local filepath = vim.fn.expand("%:p")

  if filepath:match("%.sql$") then
    -- Option 1: Compile the model first
    local compiled_sql = M.compile_current_model()
    if compiled_sql then
      return compiled_sql
    end

    -- Option 2: Use buffer content directly
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    return table.concat(lines, "\n")
  end

  return nil
end

-- Compile current dbt model
function M.compile_current_model()
  local model_name = M.get_model_name()
  if not model_name then
    return nil
  end

  -- Run dbt compile synchronously
  local project_root = require("dbt-power.utils.project").find_dbt_project()
  if not project_root then
    vim.notify("[dbt-power] Not in a dbt project", vim.log.levels.WARN)
    return nil
  end

  local cmd = string.format(
    "cd %s && %s compile --select %s",
    project_root,
    M.config.dbt_cloud_cli,
    model_name
  )

  local result = vim.fn.system(cmd)

  -- Read compiled SQL from target/compiled/
  local compiled_path = string.format(
    "%s/target/compiled/%s",
    project_root,
    vim.fn.expand("%:.")
  )

  if vim.fn.filereadable(compiled_path) == 1 then
    local file = io.open(compiled_path, "r")
    if file then
      local content = file:read("*all")
      file:close()
      return content
    end
  end

  return nil
end

-- Execute query using dbt query command
function M.execute_query_dbt(sql, callback)
  local project_root = require("dbt-power.utils.project").find_dbt_project()
  if not project_root then
    callback({ error = "Not in a dbt project" })
    return
  end

  -- Create temporary SQL file
  local tmp_sql = vim.fn.tempname() .. ".sql"
  local tmp_results = vim.fn.tempname() .. ".json"

  local file = io.open(tmp_sql, "w")
  if not file then
    callback({ error = "Could not create temporary SQL file" })
    return
  end
  file:write(sql)
  file:close()

  -- Execute using dbt query command (if available in dbt >= 1.5)
  local cmd = {
    M.config.dbt_cloud_cli or "dbt",
    "query",
    "--sql",
    sql,
    "--inline",
  }

  Job:new({
    command = cmd[1],
    args = vim.list_slice(cmd, 2),
    cwd = project_root,
    on_exit = function(j, return_val)
      vim.schedule(function()
        -- Clean up temp file
        vim.fn.delete(tmp_sql)

        if return_val ~= 0 then
          -- dbt query might not be available, try alternative method
          M.execute_query_dadbod_fallback(sql, callback)
          return
        end

        -- Parse results from dbt query output
        local stdout = table.concat(j:result(), "\n")
        local results = M.parse_dbt_query_results(stdout)
        callback(results)
      end)
    end,
  }):start()
end

-- Execute query using vim-dadbod (fallback)
function M.execute_query_dadbod_fallback(sql, callback)
  -- Check if dadbod is available
  if vim.fn.exists(":DB") == 0 then
    callback({ error = "vim-dadbod not available. Install vim-dadbod and configure database connection." })
    return
  end

  -- Try to get database connection from dadbod
  -- First check if any connection is configured
  local db_list = vim.fn.dadbod#get_db_list()
  if not db_list or #db_list == 0 then
    callback({ error = "No database connections configured. Use :DBUIAddConnection to add one." })
    return
  end

  -- Use the first available connection
  local db_name = db_list[1]

  -- Create temporary file for SQL
  local tmp_sql = vim.fn.tempname() .. ".sql"
  local tmp_results = vim.fn.tempname() .. ".csv"

  local file = io.open(tmp_sql, "w")
  if not file then
    callback({ error = "Could not create temporary SQL file" })
    return
  end
  file:write(sql)
  file:close()

  -- Use dadbod's execute method through Vim's DB command
  Job:new({
    command = "sh",
    args = {
      "-c",
      string.format(
        "cd %s && cat %s | %s query '%s' > %s 2>&1",
        vim.fn.shellescape(vim.fn.getcwd()),
        vim.fn.shellescape(tmp_sql),
        M.config.dbt_cloud_cli or "dbt",
        db_name,
        vim.fn.shellescape(tmp_results)
      )
    },
    on_exit = function(j, return_val)
      vim.schedule(function()
        -- Clean up temp files
        vim.fn.delete(tmp_sql)

        if return_val ~= 0 then
          local error_output = table.concat(j:stderr_result(), "\n")
          callback({ error = error_output or "Query execution failed" })
          vim.fn.delete(tmp_results)
          return
        end

        -- Parse CSV results
        local results = M.parse_csv_results(tmp_results)
        callback(results)

        -- Clean up results file
        vim.fn.delete(tmp_results)
      end)
    end,
  }):start()
end

-- Parse dbt query output
function M.parse_dbt_query_results(output)
  -- dbt query outputs a table-formatted result
  local lines = vim.split(output, "\n")

  if #lines < 2 then
    return { columns = {}, rows = {} }
  end

  -- Parse header (first non-empty line)
  local header_line = ""
  local start_idx = 1
  for i, line in ipairs(lines) do
    if line and line:match("%S") then
      header_line = line
      start_idx = i + 1
      break
    end
  end

  -- Extract column names (handle piped separator)
  local columns = {}
  if header_line:match("|") then
    -- Piped format: | col1 | col2 |
    for col in header_line:gmatch("|([^|]+)") do
      table.insert(columns, vim.trim(col))
    end
  else
    -- Space-separated
    for col in header_line:gmatch("%S+") do
      table.insert(columns, col)
    end
  end

  -- Skip separator line if present
  local data_start = start_idx
  if lines[start_idx] and lines[start_idx]:match("^[%s%|%-]+$") then
    data_start = start_idx + 1
  end

  -- Parse data rows
  local rows = {}
  for i = data_start, #lines do
    local line = lines[i]
    if line and line:match("%S") then
      local row = {}
      if line:match("|") then
        -- Piped format
        for value in line:gmatch("|([^|]*)") do
          table.insert(row, vim.trim(value))
        end
      else
        -- Space-separated
        for value in line:gmatch("%S+") do
          table.insert(row, value)
        end
      end
      if #row > 0 then
        table.insert(rows, row)
      end
    end
  end

  return {
    columns = columns,
    rows = rows,
  }
end

-- Parse CSV results file
function M.parse_csv_results(filepath)
  local file = io.open(filepath, "r")
  if not file then
    return { error = "Could not read results file" }
  end

  local content = file:read("*all")
  file:close()

  local lines = vim.split(content, "\n")
  if #lines < 1 then
    return { columns = {}, rows = {} }
  end

  -- Parse header (first line)
  local columns = {}
  local header = lines[1]
  for col in header:gmatch("([^,]+)") do
    table.insert(columns, vim.trim(col))
  end

  -- Parse data rows
  local rows = {}
  for i = 2, #lines do
    local line = vim.trim(lines[i])
    if line ~= "" then
      local row = {}
      -- Simple CSV parsing (doesn't handle quoted commas)
      for value in line:gmatch("([^,]+)") do
        table.insert(row, vim.trim(value))
      end
      if #row > 0 then
        table.insert(rows, row)
      end
    end
  end

  return {
    columns = columns,
    rows = rows,
  }
end

-- Parse vim-dadbod output (legacy fallback)
function M.parse_dadbod_results(filepath)
  local file = io.open(filepath, "r")
  if not file then
    return { error = "Could not read results" }
  end

  local content = file:read("*all")
  file:close()

  -- Try CSV format first
  return M.parse_csv_results(filepath)
end

-- Add LIMIT clause to SQL
function M.add_limit_clause(sql, limit)
  -- Simple implementation - just append LIMIT
  -- TODO: Handle cases where LIMIT already exists
  sql = sql:gsub("%s*;%s*$", "") -- Remove trailing semicolon
  return string.format("%s\nLIMIT %d", sql, limit)
end

-- Get model name from filepath
function M.get_model_name()
  local filepath = vim.fn.expand("%:t:r") -- filename without extension
  return filepath
end

return M
