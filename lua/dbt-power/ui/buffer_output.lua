-- Buffer output for displaying query results in a split window
-- Used for showing full model execution results

local M = {}

local current_buffer = nil
local loading_notif_id = nil

-- Show a loading message (returns notification ID for later replacement)
function M.show_loading(message)
  loading_notif_id = vim.notify(message or "[dbt-power] Executing...", vim.log.levels.INFO, {
    title = "dbt-power",
    timeout = 0,  -- Don't auto-dismiss
  })
  return loading_notif_id
end

-- Get the current loading notification ID
function M.get_loading_notif_id()
  return loading_notif_id
end

-- Update the loading message
function M.update_loading(message)
  if loading_notif_id then
    vim.notify(message or "[dbt-power] Executing...", vim.log.levels.INFO, {
      title = "dbt-power",
      timeout = 0,
      replace = loading_notif_id,
    })
  else
    M.show_loading(message)
  end
end

-- Clear the loading message
function M.clear_loading()
  if loading_notif_id then
    vim.api.nvim_set_option_value("cmdheight", 1, {})
    loading_notif_id = nil
  end
end

-- Open a buffer at the bottom to show results
-- split_size: optional height in lines (default 30)
function M.show_results_in_buffer(results, title, split_size)
  M.clear_loading()

  -- Close existing buffer if open
  if current_buffer and vim.api.nvim_buf_is_valid(current_buffer) then
    vim.api.nvim_buf_delete(current_buffer, { force = true })
  end

  -- Create new buffer
  current_buffer = vim.api.nvim_create_buf(false, true)

  -- Format results using markdown table format (same as inline)
  local lines = M.format_results_as_markdown(results, title)

  -- Note: Buffer is scrollable, so we don't truncate large result sets
  -- Just warn if there are a LOT of rows (would cause performance issues)
  if #lines > 5000 then
    table.insert(lines, "")
    table.insert(lines, "⚠️  Warning: Very large result set. Showing first 5000 lines for performance.")
    table.insert(lines, "Use filters or LIMIT clauses to reduce result size.")
  end

  -- Set buffer content
  vim.api.nvim_buf_set_lines(current_buffer, 0, -1, false, lines)

  -- Make buffer read-only
  vim.api.nvim_set_option_value("modifiable", false, { buf = current_buffer })

  -- Set buffer type
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = current_buffer })

  -- Set filetype to markdown so render-markdown can format it
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = current_buffer })

  -- Disable line wrapping for horizontal scrolling
  vim.api.nvim_set_option_value("wrap", false, { win = vim.api.nvim_get_current_win() })

  -- Set buffer name
  vim.api.nvim_buf_set_name(current_buffer, "[dbt-power] Results")

  -- Open split at bottom with configurable size (default 30 lines)
  local size = split_size or 30
  vim.cmd(string.format("botright %dsplit", size))
  vim.api.nvim_set_current_buf(current_buffer)

  -- Add keymaps to close buffer
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_buf_is_valid(current_buffer) then
      vim.api.nvim_buf_delete(current_buffer, { force = true })
      current_buffer = nil
    end
  end, { buffer = current_buffer, silent = true, desc = "Close results buffer" })

  vim.keymap.set("n", "<Esc>", function()
    if vim.api.nvim_buf_is_valid(current_buffer) then
      vim.api.nvim_buf_delete(current_buffer, { force = true })
      current_buffer = nil
    end
  end, { buffer = current_buffer, silent = true, desc = "Close results buffer" })

  -- Add keymap to resize buffer larger
  vim.keymap.set("n", "+", function()
    vim.cmd("resize +10")
  end, { buffer = current_buffer, silent = true, desc = "Make results window taller" })

  vim.keymap.set("n", "-", function()
    vim.cmd("resize -10")
  end, { buffer = current_buffer, silent = true, desc = "Make results window smaller" })

  -- Add keymaps for horizontal scrolling
  vim.keymap.set("n", ">", function()
    vim.cmd("normal! 5zl")  -- Scroll right
  end, { buffer = current_buffer, silent = true, desc = "Scroll right" })

  vim.keymap.set("n", "<", function()
    vim.cmd("normal! 5zh")  -- Scroll left
  end, { buffer = current_buffer, silent = true, desc = "Scroll left" })

  -- Return to previous buffer
  vim.cmd("wincmd p")
end

-- Format results as markdown table (proper markdown syntax for render-markdown)
function M.format_results_as_markdown(results, title)
  local lines = {}
  local max_col_width = 150  -- Increased to show more content without truncation

  -- Add title if provided
  if title then
    table.insert(lines, "## " .. title)
    table.insert(lines, "")
  end

  if not results.columns or #results.columns == 0 then
    table.insert(lines, "No data")
    return lines
  end

  -- Calculate column widths based on content
  local col_widths = {}
  for i, col in ipairs(results.columns) do
    local width = math.min(#tostring(col), max_col_width)
    col_widths[i] = width
  end

  -- Check data rows to adjust widths
  if results.rows and #results.rows > 0 then
    for _, row in ipairs(results.rows) do
      for i, val in ipairs(row) do
        if i <= #results.columns then
          local val_str = tostring(val or "NULL")
          local width = math.min(#val_str, max_col_width)
          col_widths[i] = math.max(col_widths[i] or 0, width)
        end
      end
    end
  end

  -- Header row with proper spacing
  local header_parts = {}
  for i, col in ipairs(results.columns) do
    local col_name = M.truncate_string(tostring(col), col_widths[i] or 20)
    -- Pad to column width
    col_name = col_name .. string.rep(" ", (col_widths[i] or 20) - #col_name)
    table.insert(header_parts, col_name)
  end
  local header = "| " .. table.concat(header_parts, " | ") .. " |"
  table.insert(lines, header)

  -- Separator row (proper markdown syntax)
  local sep_parts = {}
  for i, _ in ipairs(results.columns) do
    table.insert(sep_parts, string.rep("-", (col_widths[i] or 20) + 1))
  end
  local separator = "|" .. table.concat(sep_parts, "|") .. "|"
  table.insert(lines, separator)

  -- Data rows with proper spacing
  if results.rows and #results.rows > 0 then
    for _, row in ipairs(results.rows) do
      local row_parts = {}
      for i, col in ipairs(results.columns) do
        local value = M.truncate_string(tostring(row[i] or "NULL"), col_widths[i] or 20)
        -- Pad to column width
        value = value .. string.rep(" ", (col_widths[i] or 20) - #value)
        table.insert(row_parts, value)
      end
      local row_str = "| " .. table.concat(row_parts, " | ") .. " |"
      table.insert(lines, row_str)
    end
  end

  -- Row count info
  table.insert(lines, "")
  local info = string.format("**%d rows**", #results.rows)
  table.insert(lines, info)

  return lines
end

-- Truncate string to max width
function M.truncate_string(str, max_width)
  if #str > max_width then
    return str:sub(1, max_width - 3) .. "..."
  end
  return str
end

-- Close the results buffer
function M.close_buffer()
  if current_buffer and vim.api.nvim_buf_is_valid(current_buffer) then
    vim.api.nvim_buf_delete(current_buffer, { force = true })
    current_buffer = nil
  end
end

return M
