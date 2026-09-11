-- CTE preview functionality - extract and preview Common Table Expressions
-- Similar to dbt Power User VS Code extension

local M = {}
local Job = require("plenary.job")

M.config = {}

function M.setup(config)
  M.config = config or {}
end

-- Extract CTEs from current SQL file
-- Handles standard CTEs, extra whitespace/newlines, and Jinja2 templated CTEs like loop_{{ t }}
function M.extract_ctes()
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, "\n")

  local ctes = {}
  local seen = {}

  -- Normalize content: collapse newlines and multiple spaces for robust matching
  -- This handles cases like:
  --   WITH
  --   my_cte AS (...)
  -- or loop_{{ t }} in Jinja2 loops
  local normalized = content:gsub("\n", " "):gsub("%s+", " ")

  -- Find all WITH clauses and extract CTE names (case-insensitive)
  -- Pattern: WITH <cte_name> AS ( where cte_name is a valid SQL identifier
  for cte_name in normalized:gmatch("[Ww][Ii][Tt][Hh]%s+([_%w]+)%s+[Aa][Ss]%s*%(") do
    if not seen[cte_name] then
      table.insert(ctes, cte_name)
      seen[cte_name] = true
    end
  end

  -- Also match subsequent CTEs (after comma, case-insensitive)
  for cte_name in normalized:gmatch(",%s*([_%w]+)%s+[Aa][Ss]%s*%(") do
    if not seen[cte_name] then
      table.insert(ctes, cte_name)
      seen[cte_name] = true
    end
  end

  return ctes
end

-- Preview a specific CTE by executing it with dbt show
function M.preview_cte(cte_name, callback)
  local project_root = require("dbt-power.utils.project").find_dbt_project()
  if not project_root then
    vim.notify("[dbt-power] Not in a dbt project", vim.log.levels.ERROR)
    return
  end

  local model_name = require("dbt-power.dbt.execute").get_model_name()
  if not model_name then
    vim.notify("[dbt-power] Could not determine model name", vim.log.levels.ERROR)
    return
  end

  -- Show loading message
  local buffer_output = require("dbt-power.ui.buffer_output")
  buffer_output.show_loading("[dbt-power] Executing " .. model_name .. " (CTE: " .. cte_name .. ")...")

  -- First, compile the model to get actual SQL
  local compile_job = Job:new({
    command = "dbt",
    args = { "compile", "--select", model_name },
    cwd = project_root,
    on_exit = function(j, return_val)
      vim.schedule(function()
        if return_val ~= 0 then
          local stderr = table.concat(j:stderr_result(), "\n")
          vim.notify("[dbt-power] Compile failed: " .. stderr, vim.log.levels.ERROR)
          buffer_output.clear_loading()
          return
        end

        -- Read compiled SQL - find it in target/compiled by searching for model name
        -- Compiled structure: target/compiled/<project_name>/models/<path>/<model_name>.sql
        local compiled_path = nil

        -- Use find command for reliable search by model name
        -- Sort by modification time (newest first) to get most recent compilation
        local search_cmd = string.format(
          "find %s/target/compiled -name '%s.sql' -type f 2>/dev/null | sort -r | head -1",
          project_root,
          vim.fn.shellescape(model_name)
        )
        local result = vim.fn.system(search_cmd)
        if result and vim.trim(result) ~= "" then
          compiled_path = vim.trim(result)
        end

        if not compiled_path then
          vim.notify("[dbt-power] Could not find compiled SQL for model: " .. model_name, vim.log.levels.ERROR)
          buffer_output.clear_loading()
          return
        end

        local file = io.open(compiled_path, "r")
        if not file then
          vim.notify("[dbt-power] Could not read compiled SQL file", vim.log.levels.ERROR)
          buffer_output.clear_loading()
          return
        end

        local compiled_sql = file:read("*a")
        file:close()

        -- Now wrap to select from specific CTE
        local cte_query = M.wrap_cte_for_execution(compiled_sql, cte_name)

        if not cte_query then
          vim.notify("[dbt-power] Could not extract CTE: " .. cte_name, vim.log.levels.ERROR)
          buffer_output.clear_loading()
          return
        end

        -- Execute the CTE query
        local limit = M.config.inline_results and M.config.inline_results.max_rows or 500
        local show_cmd = {
          "dbt",
          "show",
          "--inline",
          cte_query,
          "--limit",
          tostring(limit),
        }

        Job:new({
          command = show_cmd[1],
          args = vim.list_slice(show_cmd, 2),
          cwd = project_root,
          on_exit = function(j2, return_val2)
            vim.schedule(function()
              if return_val2 ~= 0 then
                local stderr = table.concat(j2:stderr_result(), "\n")
                vim.notify("[dbt-power] CTE execution failed: " .. stderr, vim.log.levels.ERROR)
                buffer_output.clear_loading()
                return
              end

              local stdout = table.concat(j2:result(), "\n")
              local parse_dbt = require("dbt-power.dbt.execute")
              local results = parse_dbt.parse_dbt_show_results(stdout)

              if not results.columns or #results.columns == 0 then
                -- Debug: show the raw output
                local stderr = table.concat(j2:stderr_result(), "\n")
                vim.notify("[dbt-power] CTE returned no results. Stderr: " .. stderr:sub(1, 200), vim.log.levels.WARN)
                buffer_output.clear_loading()
                return
              end

              -- Display in buffer for CTE previews
              buffer_output.show_results_in_buffer(results, "CTE: " .. cte_name)

              vim.notify(
                string.format("[dbt-power] CTE preview: %d rows", #results.rows),
                vim.log.levels.INFO
              )
            end)
          end,
        }):start()
      end)
    end,
  })

  compile_job:start()
end

-- Preview a specific CTE by executing it with database adapter
function M.preview_cte_with_cli(cte_name, callback)
  local project_root = require("dbt-power.utils.project").find_dbt_project()
  if not project_root then
    vim.notify("[dbt-power] Not in a dbt project", vim.log.levels.ERROR)
    return
  end

  local model_name = require("dbt-power.dbt.execute").get_model_name()
  if not model_name then
    vim.notify("[dbt-power] Could not determine model name", vim.log.levels.ERROR)
    return
  end

  -- Show loading message
  local buffer_output = require("dbt-power.ui.buffer_output")
  buffer_output.show_loading("[dbt-power] Executing " .. model_name .. " (CTE: " .. cte_name .. ") with database adapter...")

  -- Track execution time
  local start_time = vim.loop.hrtime()
  local compile_start = start_time

  -- First, compile the model to get actual SQL
  local compile_job = Job:new({
    command = "dbt",
    args = { "compile", "--select", model_name },
    cwd = project_root,
    on_exit = function(j, return_val)
      vim.schedule(function()
        if return_val ~= 0 then
          local stderr = table.concat(j:stderr_result(), "\n")
          vim.notify("[dbt-power] Compile failed: " .. stderr, vim.log.levels.ERROR)
          buffer_output.clear_loading()
          return
        end

        local compile_end = vim.loop.hrtime()
        local compile_ms = math.floor((compile_end - compile_start) / 1000000)

        -- Read compiled SQL - find it in target/compiled by searching for model name
        local compiled_path = nil

        -- Use find command for reliable search by model name
        -- Sort by modification time (newest first) to get most recent compilation
        local search_cmd = string.format(
          "find %s/target/compiled -name '%s.sql' -type f 2>/dev/null | sort -r | head -1",
          project_root,
          vim.fn.shellescape(model_name)
        )
        local result = vim.fn.system(search_cmd)
        if result and vim.trim(result) ~= "" then
          compiled_path = vim.trim(result)
        end

        if not compiled_path then
          vim.notify("[dbt-power] Could not find compiled SQL for model: " .. model_name, vim.log.levels.ERROR)
          buffer_output.clear_loading()
          return
        end

        local file = io.open(compiled_path, "r")
        if not file then
          vim.notify("[dbt-power] Could not read compiled SQL file", vim.log.levels.ERROR)
          buffer_output.clear_loading()
          return
        end

        local compiled_sql = file:read("*a")
        file:close()

        -- Now wrap to select from specific CTE
        local cte_query = M.wrap_cte_for_execution(compiled_sql, cte_name)

        if not cte_query then
          vim.notify("[dbt-power] Could not extract CTE: " .. cte_name, vim.log.levels.ERROR)
          buffer_output.clear_loading()
          return
        end

        -- Apply row limit from config
        local max_rows = M.config.direct_query and M.config.direct_query.max_rows or 100
        local limited_cte_query = cte_query .. " LIMIT " .. max_rows

        -- Execute via database adapter
        local query_start = vim.loop.hrtime()
        local execute_module = require("dbt-power.dbt.execute")
        execute_module.execute_via_adapter(limited_cte_query, function(results)
          local query_end = vim.loop.hrtime()
          local query_ms = math.floor((query_end - query_start) / 1000000)

          buffer_output.clear_loading()

          if results.error then
            vim.notify("[dbt-power] CTE execution failed: " .. results.error, vim.log.levels.ERROR)
            return
          end

          if not results.columns or #results.columns == 0 then
            vim.notify("[dbt-power] CTE returned no results", vim.log.levels.WARN)
            return
          end

          -- Calculate total execution time
          local end_time = vim.loop.hrtime()
          local total_ms = math.floor((end_time - start_time) / 1000000)
          local total_str = string.format("%.2fs", total_ms / 1000)
          local compile_str = string.format("%.2fs", compile_ms / 1000)
          local query_str = string.format("%.2fs", query_ms / 1000)

          -- Display in buffer for CTE previews with timing
          local title = string.format(
            "CTE: %s | %d rows | Total: %s (compile: %s, query: %s)",
            cte_name,
            #results.rows,
            total_str,
            compile_str,
            query_str
          )
          local split_size = M.config.direct_query and M.config.direct_query.buffer_split_size or 30
          buffer_output.show_results_in_buffer(results, title, split_size)

          vim.notify(
            string.format("[dbt-power] CTE preview: %d rows (%s)", #results.rows, total_str),
            vim.log.levels.INFO
          )
        end)
      end)
    end,
  })

  compile_job:start()
end

-- Wrap CTE in SELECT * to execute just that CTE
function M.wrap_cte_for_execution(full_sql, cte_name)
  -- Replace the final SELECT with SELECT * FROM cte_name
  -- This keeps all the WITH clauses intact
  -- Note: Don't include LIMIT in the query; use --limit flag instead

  -- Find the main SELECT at the end (after all WITH clauses)
  -- Match the final SELECT statement and replace it

  -- Look for the last SELECT statement that's not inside parentheses
  -- Simple approach: find WHERE the last main SELECT starts

  -- Search for WITH/with (case-insensitive helper)
  local function find_keyword(sql, keyword, start_pos)
    local pos = start_pos or 1
    while pos <= #sql do
      local upper_pos = sql:find(keyword:upper(), pos)
      local lower_pos = sql:find(keyword:lower(), pos)
      if upper_pos and lower_pos then
        return math.min(upper_pos, lower_pos)
      elseif upper_pos then
        return upper_pos
      elseif lower_pos then
        return lower_pos
      else
        return nil
      end
    end
    return nil
  end

  local with_end = find_keyword(full_sql, "WITH")
  if not with_end then
    -- No WITH clause, can't preview CTE
    return nil
  end

  -- Find the last SELECT in the query (the main one)
  local last_select = nil
  local pos = with_end
  while true do
    local next_select = find_keyword(full_sql, "SELECT", pos)
    if not next_select then
      break
    end
    last_select = next_select
    pos = next_select + 6
  end

  if not last_select then
    return nil
  end

  -- Extract everything up to the final SELECT
  local before_final_select = full_sql:sub(1, last_select - 1)

  -- Append SELECT * FROM cte_name (without LIMIT - it's handled via --limit flag)
  return before_final_select .. "SELECT * FROM " .. cte_name
end

-- Show CTE picker using vim.ui.select (built-in, always available)
function M.show_cte_picker()
  local ctes = M.extract_ctes()

  if #ctes == 0 then
    vim.notify("[dbt-power] No CTEs found in this model", vim.log.levels.WARN)
    return
  end

  if #ctes == 1 then
    -- Only one CTE, show method picker
    M.show_execution_method_picker(ctes[1])
    return
  end

  -- Use vim.ui.select for CTE picker (built-in, always available)
  vim.ui.select(ctes, {
    prompt = "Select CTE to preview:",
    format_item = function(item)
      return "  " .. item
    end,
  }, function(choice)
    if choice then
      M.show_execution_method_picker(choice)
    end
  end)
end

-- Show picker for execution method (dbt show vs snowsql)
function M.show_execution_method_picker(cte_name)
  local methods = {
    { label = "dbt show", execute = M.preview_cte },
    { label = "Direct CLI", execute = M.preview_cte_with_cli },
  }

  vim.ui.select(methods, {
    prompt = "Select execution method for CTE: " .. cte_name,
    format_item = function(item)
      return "  " .. item.label
    end,
  }, function(choice)
    if choice then
      choice.execute(cte_name, function() end)
    end
  end)
end

-- Preview CTE with dbt show (default)
function M.show_cte_picker_dbt_show()
  local ctes = M.extract_ctes()

  if #ctes == 0 then
    vim.notify("[dbt-power] No CTEs found in this model", vim.log.levels.WARN)
    return
  end

  if #ctes == 1 then
    M.preview_cte(ctes[1], function() end)
    return
  end

  vim.ui.select(ctes, {
    prompt = "Select CTE to preview (dbt show):",
    format_item = function(item)
      return "  " .. item
    end,
  }, function(choice)
    if choice then
      M.preview_cte(choice, function() end)
    end
  end)
end

-- Preview CTE with direct CLI
function M.show_cte_picker_cli()
  local ctes = M.extract_ctes()

  if #ctes == 0 then
    vim.notify("[dbt-power] No CTEs found in this model", vim.log.levels.WARN)
    return
  end

  if #ctes == 1 then
    M.preview_cte_with_cli(ctes[1], function() end)
    return
  end

  vim.ui.select(ctes, {
    prompt = "Select CTE to preview (Direct CLI):",
    format_item = function(item)
      return "  " .. item
    end,
  }, function(choice)
    if choice then
      M.preview_cte_with_cli(choice, function() end)
    end
  end)
end

return M
