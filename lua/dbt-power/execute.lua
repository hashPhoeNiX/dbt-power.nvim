-- Convenience module for execute functionality
-- Delegates to dbt.execute module

local M = {}

function M.execute_and_show_inline()
  require("dbt-power.dbt.execute").execute_and_show_inline()
end

function M.execute_selection()
  require("dbt-power.dbt.execute").execute_selection()
end

return M
