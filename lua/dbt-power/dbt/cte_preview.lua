-- CTE preview functionality - extract and preview Common Table Expressions
-- Similar to dbt Power User VS Code extension

local M = {}
local Job = require("plenary.job")

M.config = {}

function M.setup(config)
  M.config = config or {}
end

-- Extract CTEs from current SQL file
function M.extract_ctes()
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, "\n")

  local ctes = {}

  -- Find all WITH clauses and extract CTE names
  -- Pattern: WITH cte_name AS ( ... ), another_cte AS ( ... )
  for cte_name in content:gmatch("WITH%s+(%w+)%s+AS") do
    table.insert(ctes, cte_name)
  end

  -- Also match subsequent CTEs (after comma)
  for cte_name in content:gmatch(",%s*(%w+)%s+AS") do
    -- Only add if not already in list
    local found = false
    for _, existing in ipairs(ctes) do
      if existing == cte_name then
        found = true
        break
      end
    end
    if not found then
      table.insert(ctes, cte_name)
    end
  end

  return ctes
end

-- Preview a specific CTE by executing it
function M.preview_cte(cte_name, callback)
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local full_sql = table.concat(lines, "\n")

  -- Extract the CTE definition and wrap it in SELECT *
  local cte_query = M.wrap_cte_for_execution(full_sql, cte_name)

  if not cte_query then
    vim.notify("[dbt-power] Could not find CTE: " .. cte_name, vim.log.levels.ERROR)
    return
  end

  -- Execute the CTE query
  local project_root = require("dbt-power.utils.project").find_dbt_project()
  if not project_root then
    vim.notify("[dbt-power] Not in a dbt project", vim.log.levels.ERROR)
    return
  end

  vim.notify("[dbt-power] Previewing CTE: " .. cte_name, vim.log.levels.INFO)

  -- Use dbt show to execute the CTE
  local limit = M.config.inline_results and M.config.inline_results.max_rows or 500
  local cmd = {
    "dbt",
    "show",
    "--inline",
    cte_query,
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
          vim.notify("[dbt-power] CTE preview failed: " .. stderr, vim.log.levels.ERROR)
          return
        end

        local stdout = table.concat(j:result(), "\n")
        local inline_results = require("dbt-power.ui.inline_results")
        local parse_dbt = require("dbt-power.dbt.execute")
        local results = parse_dbt.parse_dbt_show_results(stdout)

        if not results.columns or #results.columns == 0 then
          vim.notify("[dbt-power] CTE returned no results", vim.log.levels.WARN)
          return
        end

        -- Display in buffer for CTE previews
        local buffer_output = require("dbt-power.ui.buffer_output")
        buffer_output.show_results_in_buffer(results, "CTE: " .. cte_name)

        vim.notify(
          string.format("[dbt-power] CTE preview: %d rows", #results.rows),
          vim.log.levels.INFO
        )
      end)
    end,
  }):start()
end

-- Wrap CTE in SELECT * to execute just that CTE
function M.wrap_cte_for_execution(full_sql, cte_name)
  -- Extract the CTE and everything up to and including its definition
  -- Then SELECT * FROM cte_name

  -- Find the WITH clause start
  local with_start = full_sql:find("WITH%s+")
  if not with_start then
    return nil
  end

  -- Find the main query (after all CTEs)
  -- Look for SELECT, INSERT, UPDATE, DELETE, CREATE after the CTEs
  local main_query_start = full_sql:find("\n%s*SELECT%s+", with_start)
  if not main_query_start then
    main_query_start = full_sql:find("\n%s*INSERT%s+", with_start)
  end
  if not main_query_start then
    main_query_start = full_sql:find("\n%s*UPDATE%s+", with_start)
  end

  if not main_query_start then
    -- Fallback: just wrap the CTE
    return string.format("WITH %s AS (\n%s\n)\nSELECT * FROM %s LIMIT 500",
      cte_name, full_sql, cte_name)
  end

  -- Extract the full WITH clause and replace the main query
  local with_clause = full_sql:sub(with_start, main_query_start)

  return with_clause .. "\nSELECT * FROM " .. cte_name .. " LIMIT 500"
end

-- Show CTE picker using Telescope
function M.show_cte_picker()
  local ctes = M.extract_ctes()

  if #ctes == 0 then
    vim.notify("[dbt-power] No CTEs found in this model", vim.log.levels.WARN)
    return
  end

  if #ctes == 1 then
    -- Only one CTE, preview it directly
    M.preview_cte(ctes[1], function() end)
    return
  end

  -- Try to use Telescope for picker
  local ok, telescope = pcall(require, "telescope.builtin")
  if ok then
    telescope.custom_list({
      prompt_title = "Select CTE to preview",
      results = ctes,
    }, {
      attach_mappings = function(prompt_bufnr, map)
        local actions = require("telescope.actions")
        map("i", "<CR>", function()
          actions.close(prompt_bufnr)
          local selected = ctes[vim.fn.line(".")]
          M.preview_cte(selected, function() end)
        end)
        return true
      end,
    })
  else
    -- Fallback: use vim.ui.select if Telescope not available
    vim.ui.select(ctes, {
      prompt = "Select CTE to preview:",
    }, function(choice)
      if choice then
        M.preview_cte(choice, function() end)
      end
    end)
  end
end

return M
