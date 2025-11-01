-- Buffer output for displaying query results in a split window
-- Used for showing full model execution results

local M = {}

local current_buffer = nil

-- Open a buffer at the bottom to show results
function M.show_results_in_buffer(results, title)
  -- Close existing buffer if open
  if current_buffer and vim.api.nvim_buf_is_valid(current_buffer) then
    vim.api.nvim_buf_delete(current_buffer, { force = true })
  end

  -- Create new buffer
  current_buffer = vim.api.nvim_create_buf(false, true)

  -- Format results as table
  local lines = {}

  -- Add title
  if title then
    table.insert(lines, "")
    table.insert(lines, "═══════════════════════════════════════════════════════════")
    table.insert(lines, "  " .. title)
    table.insert(lines, "═══════════════════════════════════════════════════════════")
    table.insert(lines, "")
  end

  -- Add column headers
  if results.columns and #results.columns > 0 then
    table.insert(lines, "  " .. table.concat(results.columns, " │ "))
    table.insert(lines, "  " .. string.rep("─", math.min(100, #table.concat(results.columns, " │ "))))
    table.insert(lines, "")
  end

  -- Add rows
  if results.rows and #results.rows > 0 then
    for i, row in ipairs(results.rows) do
      table.insert(lines, "  " .. table.concat(row, " │ "))
    end
  else
    table.insert(lines, "  [No results]")
  end

  -- Add summary
  table.insert(lines, "")
  table.insert(lines, "  " .. #(results.rows or {}) .. " rows")
  table.insert(lines, "")

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

-- Close the results buffer
function M.close_buffer()
  if current_buffer and vim.api.nvim_buf_is_valid(current_buffer) then
    vim.api.nvim_buf_delete(current_buffer, { force = true })
    current_buffer = nil
  end
end

return M
