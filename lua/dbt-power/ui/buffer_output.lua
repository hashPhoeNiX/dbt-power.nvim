-- Buffer output for displaying query results in a split window
-- Used for showing full model execution results

local M = {}

local current_buffer = nil
local loading_notif_id = nil

-- Show a loading message
function M.show_loading(message)
  loading_notif_id = vim.notify(message or "[dbt-power] Executing...", vim.log.levels.INFO, {
    title = "dbt-power",
    timeout = 0,  -- Don't auto-dismiss
  })
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
function M.show_results_in_buffer(results, title)
  M.clear_loading()

  -- Close existing buffer if open
  if current_buffer and vim.api.nvim_buf_is_valid(current_buffer) then
    vim.api.nvim_buf_delete(current_buffer, { force = true })
  end

  -- Create new buffer
  current_buffer = vim.api.nvim_create_buf(false, true)

  -- Format results using markdown table format (same as inline)
  local lines = M.format_results_as_markdown(results, title)

  -- Limit to reasonable number for display
  if #lines > 1000 then
    table.insert(lines, "")
    table.insert(lines, "... (truncated, showing first 1000 lines)")
  end

  -- Set buffer content
  vim.api.nvim_buf_set_lines(current_buffer, 0, -1, false, lines)

  -- Make buffer read-only
  vim.api.nvim_set_option_value("modifiable", false, { buf = current_buffer })

  -- Set buffer type
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = current_buffer })

  -- Set buffer name
  vim.api.nvim_buf_set_name(current_buffer, "[dbt-power] Results")

  -- Open split at bottom
  vim.cmd("botright 15split")
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

  -- Return to previous buffer
  vim.cmd("wincmd p")
end

-- Format results as markdown table (same as inline version)
function M.format_results_as_markdown(results, title)
  local lines = {}
  local max_col_width = 50

  -- Add empty line at top
  table.insert(lines, "")

  -- Add title if provided
  if title then
    table.insert(lines, title)
    table.insert(lines, "")
  end

  if not results.columns or #results.columns == 0 then
    table.insert(lines, "[No data]")
    return lines
  end

  -- Header row
  local header_parts = {}
  for _, col in ipairs(results.columns) do
    local col_name = M.truncate_string(tostring(col), max_col_width)
    table.insert(header_parts, col_name)
  end
  local header = "│ " .. table.concat(header_parts, " │ ") .. " │"
  table.insert(lines, header)

  -- Separator row
  local sep_parts = {}
  for _ = 1, #results.columns do
    table.insert(sep_parts, string.rep("─", max_col_width))
  end
  local separator = "├─" .. table.concat(sep_parts, "─┼─") .. "─┤"
  table.insert(lines, separator)

  -- Data rows
  if results.rows and #results.rows > 0 then
    for i, row in ipairs(results.rows) do
      local row_parts = {}
      for j, col in ipairs(results.columns) do
        local value = M.truncate_string(tostring(row[j] or "NULL"), max_col_width)
        table.insert(row_parts, value)
      end
      local row_str = "│ " .. table.concat(row_parts, " │ ") .. " │"
      table.insert(lines, row_str)
    end
  end

  -- Bottom border
  local bottom = "└─" .. table.concat(sep_parts, "─┴─") .. "─┘"
  table.insert(lines, bottom)

  -- Row count info
  table.insert(lines, "")
  local info = string.format("%d rows", #results.rows)
  table.insert(lines, info)
  table.insert(lines, "")

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
