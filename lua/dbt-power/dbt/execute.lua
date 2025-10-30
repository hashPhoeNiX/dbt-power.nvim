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

  -- Execute query via vim-dadbod
  M.execute_query_dadbod(preview_sql, function(results)
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

  -- Execute
  M.execute_query_dadbod(preview_sql, function(results)
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

-- Execute query using vim-dadbod
function M.execute_query_dadbod(sql, callback)
  -- Check if dadbod is available
  if vim.fn.exists(":DB") == 0 then
    callback({ error = "vim-dadbod not available" })
    return
  end

  -- Get default connection from dadbod-ui
  local db_url = vim.g.db or vim.b.db
  if not db_url then
    callback({ error = "No database connection configured. Use :DBUIAddConnection" })
    return
  end

  -- Create temporary file for results
  local tmp_file = vim.fn.tempname()

  -- Execute query
  local cmd = string.format(
    [[echo %s | DB %s > %s]],
    vim.fn.shellescape(sql),
    vim.fn.shellescape(db_url),
    tmp_file
  )

  Job:new({
    command = "sh",
    args = { "-c", cmd },
    on_exit = function(j, return_val)
      vim.schedule(function()
        if return_val ~= 0 then
          local error_msg = table.concat(j:stderr_result(), "\n")
          callback({ error = error_msg })
          return
        end

        -- Parse results
        local results = M.parse_dadbod_results(tmp_file)
        callback(results)

        -- Clean up
        vim.fn.delete(tmp_file)
      end)
    end,
  }):start()
end

-- Parse vim-dadbod output
function M.parse_dadbod_results(filepath)
  local file = io.open(filepath, "r")
  if not file then
    return { error = "Could not read results" }
  end

  local content = file:read("*all")
  file:close()

  -- Parse table format (simple implementation)
  local lines = vim.split(content, "\n")

  if #lines < 2 then
    return { columns = {}, rows = {} }
  end

  -- First line is header
  local header_line = lines[1]
  local columns = {}
  for col in header_line:gmatch("%S+") do
    table.insert(columns, col)
  end

  -- Skip separator line (if present)
  local start_line = 2
  if lines[2]:match("^[-%s|]+$") then
    start_line = 3
  end

  -- Parse data rows
  local rows = {}
  for i = start_line, #lines do
    local line = lines[i]
    if line and line ~= "" then
      local row = {}
      for value in line:gmatch("%S+") do
        table.insert(row, value)
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
