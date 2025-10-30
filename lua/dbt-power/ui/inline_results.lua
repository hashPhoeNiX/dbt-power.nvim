-- Inline results display module
-- Inspired by Molten's extmark-based output display

local M = {}

-- Namespace for extmarks
M.ns_id = vim.api.nvim_create_namespace("dbt_power_results")

-- Configuration
M.config = {
  max_rows = 500,
  max_column_width = 50,
  style = "markdown",
}

function M.setup(config)
  M.config = vim.tbl_extend("force", M.config, config or {})
end

-- Display query results inline using extmarks
function M.display_query_results(bufnr, line_num, results, opts)
  opts = opts or {}
  local style = opts.style or M.config.style

  -- Format results based on style
  local formatted
  if style == "markdown" then
    formatted = M.format_as_markdown_table(results)
  else
    formatted = M.format_as_simple_table(results)
  end

  -- Create extmark with virtual lines
  local extmark_opts = {
    virt_lines = formatted,
    virt_lines_above = false,
    id = nil, -- Auto-generate ID
  }

  -- Store extmark ID for later clearing
  local mark_id = vim.api.nvim_buf_set_extmark(bufnr, M.ns_id, line_num, 0, extmark_opts)

  -- Store metadata
  if not vim.b[bufnr].dbt_power_results then
    vim.b[bufnr].dbt_power_results = {}
  end
  table.insert(vim.b[bufnr].dbt_power_results, {
    mark_id = mark_id,
    line = line_num,
    row_count = #results.rows,
  })

  return mark_id
end

-- Format results as markdown table
function M.format_as_markdown_table(results)
  local lines = {}
  local max_rows = M.config.max_rows
  local max_col_width = M.config.max_column_width

  -- Add separator line
  table.insert(lines, { { "", "Comment" } })

  -- Header row
  local header_parts = {}
  for _, col in ipairs(results.columns) do
    local col_name = M.truncate_string(tostring(col), max_col_width)
    table.insert(header_parts, col_name)
  end
  local header = "│ " .. table.concat(header_parts, " │ ") .. " │"
  table.insert(lines, { { header, "Title" } })

  -- Separator row
  local sep_parts = {}
  for _ = 1, #results.columns do
    table.insert(sep_parts, string.rep("─", max_col_width))
  end
  local separator = "├─" .. table.concat(sep_parts, "─┼─") .. "─┤"
  table.insert(lines, { { separator, "Comment" } })

  -- Data rows
  local row_count = math.min(#results.rows, max_rows)
  for i = 1, row_count do
    local row = results.rows[i]
    local row_parts = {}

    for j, col in ipairs(results.columns) do
      local value = M.truncate_string(tostring(row[j] or "NULL"), max_col_width)
      table.insert(row_parts, value)
    end

    local row_str = "│ " .. table.concat(row_parts, " │ ") .. " │"
    table.insert(lines, { { row_str, "Normal" } })
  end

  -- Bottom border
  local bottom = "└─" .. table.concat(sep_parts, "─┴─") .. "─┘"
  table.insert(lines, { { bottom, "Comment" } })

  -- Row count info
  local info
  if #results.rows > max_rows then
    info = string.format("Showing %d of %d rows", max_rows, #results.rows)
  else
    info = string.format("%d rows", #results.rows)
  end
  table.insert(lines, { { info, "Comment" } })
  table.insert(lines, { { "", "Comment" } })

  return lines
end

-- Format results as simple table
function M.format_as_simple_table(results)
  local lines = {}
  local max_rows = M.config.max_rows
  local max_col_width = M.config.max_column_width

  -- Header
  local header_parts = {}
  for _, col in ipairs(results.columns) do
    table.insert(header_parts, M.truncate_string(tostring(col), max_col_width))
  end
  table.insert(lines, { { table.concat(header_parts, " | "), "Title" } })
  table.insert(lines, { { string.rep("-", 80), "Comment" } })

  -- Rows
  local row_count = math.min(#results.rows, max_rows)
  for i = 1, row_count do
    local row = results.rows[i]
    local row_parts = {}

    for j = 1, #results.columns do
      local value = M.truncate_string(tostring(row[j] or "NULL"), max_col_width)
      table.insert(row_parts, value)
    end

    table.insert(lines, { { table.concat(row_parts, " | "), "Normal" } })
  end

  -- Info
  if #results.rows > max_rows then
    table.insert(lines, { { string.format("... %d more rows", #results.rows - max_rows), "Comment" } })
  end

  return lines
end

-- Truncate string to max length
function M.truncate_string(str, max_len)
  str = tostring(str)
  if #str > max_len then
    return str:sub(1, max_len - 3) .. "..."
  end
  -- Pad to consistent width
  return str .. string.rep(" ", max_len - #str)
end

-- Clear all results in buffer
function M.clear_all(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Clear all extmarks in namespace
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns_id, 0, -1)

  -- Clear metadata
  vim.b[bufnr].dbt_power_results = {}

  print("[dbt-power] Cleared all results")
end

-- Clear results at specific line
function M.clear_at_line(bufnr, line_num)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Get extmarks at line
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, M.ns_id, { line_num, 0 }, { line_num, -1 }, {})

  -- Delete each mark
  for _, mark in ipairs(marks) do
    vim.api.nvim_buf_del_extmark(bufnr, M.ns_id, mark[1])
  end
end

-- Export results to CSV
function M.export_to_csv(results, filepath)
  local file = io.open(filepath, "w")
  if not file then
    vim.notify("Failed to open file: " .. filepath, vim.log.levels.ERROR)
    return false
  end

  -- Write header
  file:write(table.concat(results.columns, ",") .. "\n")

  -- Write rows
  for _, row in ipairs(results.rows) do
    local row_str = {}
    for _, value in ipairs(row) do
      -- Escape commas and quotes
      local escaped = tostring(value):gsub('"', '""')
      if escaped:find("[,\n\"]") then
        escaped = '"' .. escaped .. '"'
      end
      table.insert(row_str, escaped)
    end
    file:write(table.concat(row_str, ",") .. "\n")
  end

  file:close()
  vim.notify("Exported to " .. filepath, vim.log.levels.INFO)
  return true
end

return M
