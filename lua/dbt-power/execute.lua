-- Convenience module for execute functionality
-- Delegates to dbt.execute module

local M = {}

function M.execute_and_show_inline()
  require("dbt-power.dbt.execute").execute_and_show_inline()
end

function M.execute_with_dbt_show_command()
  require("dbt-power.dbt.execute").execute_with_dbt_show_command()
end

function M.execute_with_dbt_show_buffer()
  require("dbt-power.dbt.execute").execute_with_dbt_show_buffer()
end

function M.execute_selection()
  require("dbt-power.dbt.execute").execute_selection()
end

function M.execute_selection_with_buffer()
  require("dbt-power.dbt.execute").execute_selection_with_buffer()
end

return M
