-- Convenience module for preview functionality
-- Delegates to dbt.compile module

local M = {}

function M.show_compiled_sql()
  require("dbt-power.dbt.compile").show_compiled_sql()
end

function M.show_compiled_sql_for_selection()
  require("dbt-power.dbt.compile").show_compiled_sql_for_selection()
end

function M.toggle_auto_compile()
  require("dbt-power.dbt.compile").toggle_auto_compile()
end

return M
