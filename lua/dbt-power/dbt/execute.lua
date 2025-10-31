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

  -- Clear previous results at this line
  inline_results.clear_at_line(bufnr, cursor_line)

  -- Show loading indicator
  vim.notify("[dbt-power] Executing query...", vim.log.levels.INFO)

  -- Check if we're in a dbt model file
  local filepath = vim.fn.expand("%:p")

  if filepath:match("%.sql$") then
    -- This is a dbt model - use dbt show
    M.execute_dbt_model(function(results)
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
  vim.notify("[dbt-power] Visual selection execution requires database setup (vim-dadbod)", vim.log.levels.INFO)
  vim.notify("[dbt-power] For now, use <leader>dr to run the full model", vim.log.levels.INFO)
end

-- Execute dbt model using dbt show command
function M.execute_dbt_model(callback)
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

  -- Use dbt show command to compile and execute the model
  -- dbt show: "Generates executable SQL for a named resource or inline query,
  --            runs that SQL, and returns a preview of the results"
  local cmd = {
    M.config.dbt_cloud_cli or "dbt",
    "show",
    "--select",
    model_name,
    "--max-rows",
    tostring(M.config.inline_results.max_rows or 500),
  }

  Job:new({
    command = cmd[1],
    args = vim.list_slice(cmd, 2),
    cwd = project_root,
    on_exit = function(j, return_val)
      vim.schedule(function()
        if return_val ~= 0 then
          -- dbt show failed
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
      table.insert(columns, vim.trim(col))
    end
  else
    -- Pipe format: | col1 | col2 |
    for col in header_line:gmatch("|([^|]+)") do
      table.insert(columns, vim.trim(col))
    end
  end

  -- Parse data rows (skip separators and empty lines)
  for i = header_idx + 1, #lines do
    local line = vim.trim(lines[i])

    -- Skip separator lines
    if line:match("^[%s%┌%┐%└%┘%├%┤%┼%─%┬%┴%│%]+$") or
       line:match("^[%s%-%+%|]+$") or
       line == "" then
      goto continue
    end

    -- Parse data row
    local row = {}
    if line:match("│") then
      -- Box-drawing format: │ val1 │ val2 │
      for value in line:gmatch("│([^│]*)") do
        table.insert(row, vim.trim(value))
      end
    elseif line:match("|") then
      -- Pipe format: | val1 | val2 |
      for value in line:gmatch("|([^|]*)") do
        table.insert(row, vim.trim(value))
      end
    end

    if #row > 0 and #row == #columns then
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
