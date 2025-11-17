-- dbt-power.nvim
-- A Neovim plugin for dbt development with Power User-like features
-- Inspired by Molten's inline display approach

local M = {}

-- Default configuration
M.config = {
  dbt_cloud_cli = "dbt",
  dbt_project_dir = nil,

  inline_results = {
    enabled = true,
    max_rows = 500,
    max_column_width = 50,
    auto_clear_on_execute = false,
    style = "markdown",
  },

  preview = {
    auto_compile = false,
    split_position = "right",
    split_size = 80,
  },

  database = {
    use_dadbod = true,
    default_connection = nil,
  },

  ai = {
    enabled = false,
    provider = "anthropic",
    api_key = nil,
  },

  keymaps = {
    compile_preview = "<leader>dv",
    execute_inline = "<C-CR>",
    clear_results = "<leader>dC",
    toggle_auto_compile = "<leader>dA",
  },
}

-- Setup function
function M.setup(opts)
  -- Merge user config with defaults
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  -- Initialize modules
  require("dbt-power.ui.inline_results").setup(M.config.inline_results)
  require("dbt-power.dbt.compile").setup(M.config)
  require("dbt-power.dbt.execute").setup(M.config)
  require("dbt-power.dbt.build").setup(M.config)

  -- Set up commands
  M.create_commands()

  -- Set up keymaps
  M.create_keymaps()

  -- Set up autocommands
  M.create_autocommands()

  print("[dbt-power] Plugin initialized")
end

-- Create keymaps based on configuration
function M.create_keymaps()
  local km = M.config.keymaps
  if not km then return end

  -- Compile preview
  if km.compile_preview then
    vim.keymap.set("n", km.compile_preview, function()
      require("dbt-power.preview").show_compiled_sql()
    end, { desc = "Preview compiled SQL", noremap = true, silent = false })
  end

  -- Execute with dbt show - inline results
  vim.keymap.set("n", "<leader>ds", function()
    require("dbt-power.execute").execute_with_dbt_show_command()
  end, { desc = "Execute query - inline results", noremap = true, silent = false })

  -- Execute with dbt show - buffer results
  vim.keymap.set("n", "<leader>dS", function()
    require("dbt-power.execute").execute_with_dbt_show_buffer()
  end, { desc = "Execute query - buffer results", noremap = true, silent = false })

  -- Preview CTE with method picker (dbt show or snowsql)
  vim.keymap.set("n", "<leader>dq", function()
    require("dbt-power.dbt.cte_preview").show_cte_picker()
  end, { desc = "Preview CTE (pick method)", noremap = true, silent = false })

  -- Preview CTE with snowsql directly
  vim.keymap.set("n", "<leader>dQ", function()
    require("dbt-power.dbt.cte_preview").show_cte_picker_snowsql()
  end, { desc = "Preview CTE (snowsql)", noremap = true, silent = false })

  -- Create ad-hoc temporary model
  vim.keymap.set("n", "<leader>da", function()
    require("dbt-power.dbt.adhoc").create_adhoc_model()
  end, { desc = "Create ad-hoc temporary model", noremap = true, silent = false })

  -- Execute visual selection (inline)
  vim.keymap.set("v", "<leader>dx", ":<C-u>lua require('dbt-power.execute').execute_selection()<CR>", {
    noremap = true,
    silent = false,
    desc = "Execute SQL selection (inline)",
  })

  -- Execute visual selection (buffer)
  vim.keymap.set("v", "<leader>dX", ":<C-u>lua require('dbt-power.execute').execute_selection_with_buffer()<CR>", {
    noremap = true,
    silent = false,
    desc = "Execute SQL selection (buffer)",
  })

  -- Clear inline results
  if km.clear_results then
    vim.keymap.set("n", km.clear_results, function()
      require("dbt-power.ui.inline_results").clear_all()
    end, { desc = "Clear query results", noremap = true, silent = false })
  end

  -- Execute compiled SQL directly with snowsql (buffer - full results)
  vim.keymap.set("n", "<leader>dP", function()
    require("dbt-power.dbt.execute").execute_with_direct_query_buffer()
  end, {
    desc = "Preview compiled model in buffer (full results, no truncation)",
    noremap = true,
    silent = false,
  })

  -- Execute compiled SQL directly with snowsql (inline - full results)
  vim.keymap.set("n", "<leader>dp", function()
    require("dbt-power.dbt.execute").execute_with_direct_query_inline()
  end, {
    desc = "Preview compiled model inline (full results, no truncation)",
    noremap = true,
    silent = false,
  })

  -- Build current model
  vim.keymap.set("n", "<leader>dbm", function()
    require("dbt-power.dbt.build").build_current_model()
  end, {
    desc = "Build current model",
    noremap = true,
    silent = false,
  })

  -- Build upstream dependencies
  vim.keymap.set("n", "<leader>dbu", function()
    require("dbt-power.dbt.build").build_upstream()
  end, {
    desc = "Build upstream dependencies",
    noremap = true,
    silent = false,
  })

  -- Build downstream dependencies
  vim.keymap.set("n", "<leader>dbd", function()
    require("dbt-power.dbt.build").build_downstream()
  end, {
    desc = "Build downstream dependencies",
    noremap = true,
    silent = false,
  })

  -- Build all dependencies (upstream and downstream)
  vim.keymap.set("n", "<leader>dba", function()
    require("dbt-power.dbt.build").build_all_dependencies()
  end, {
    desc = "Build all dependencies (upstream + downstream)",
    noremap = true,
    silent = false,
  })
end

-- Create user commands
function M.create_commands()
  vim.api.nvim_create_user_command("DbtPreview", function()
    require("dbt-power.preview").show_compiled_sql()
  end, { desc = "Show compiled SQL in split" })

  vim.api.nvim_create_user_command("DbtExecute", function()
    require("dbt-power.execute").execute_and_show_inline()
  end, { desc = "Execute query and show results inline" })

  vim.api.nvim_create_user_command("DbtClearResults", function()
    require("dbt-power.ui.inline_results").clear_all()
  end, { desc = "Clear all inline results" })

  vim.api.nvim_create_user_command("DbtToggleAutoCompile", function()
    require("dbt-power.preview").toggle_auto_compile()
  end, { desc = "Toggle auto-compile preview" })

  vim.api.nvim_create_user_command("DbtAdHoc", function()
    require("dbt-power.dbt.adhoc").create_adhoc_model()
  end, { desc = "Create a temporary ad-hoc dbt model for testing" })
end

-- Create autocommands
function M.create_autocommands()
  local group = vim.api.nvim_create_augroup("DbtPower", { clear = true })

  -- Auto-detect dbt projects
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    pattern = "*.sql",
    callback = function()
      local dbt_project = require("dbt-power.utils.project").find_dbt_project()
      if dbt_project then
        -- Set buffer-local variable
        vim.b.dbt_project_root = dbt_project
      end
    end,
  })
end

-- Health check function
function M.check()
  vim.health.start("dbt-power.nvim")

  -- Check for dbt CLI
  if vim.fn.executable(M.config.dbt_cloud_cli) == 1 then
    vim.health.ok("dbt CLI found: " .. M.config.dbt_cloud_cli)
  else
    vim.health.error("dbt CLI not found: " .. M.config.dbt_cloud_cli)
  end

  -- Check for dependencies
  local deps = { "plenary", "telescope" }
  for _, dep in ipairs(deps) do
    local ok = pcall(require, dep)
    if ok then
      vim.health.ok(dep .. " is installed")
    else
      vim.health.warn(dep .. " is not installed (optional)")
    end
  end

  -- Check for vim-dadbod
  if vim.fn.exists(":DB") > 0 then
    vim.health.ok("vim-dadbod is available")
  else
    vim.health.warn("vim-dadbod not found (optional, but recommended)")
  end
end

return M
