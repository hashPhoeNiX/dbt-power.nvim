-- dbt-power.nvim
-- A Neovim plugin for dbt development with Power User-like features
-- Inspired by VSCode dbt Power User extension using Molten's inline display approach

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
    -- Adapter selection: nil (auto-detect), or specify: "snowflake", "postgres", "bigquery", etc.
    adapter = nil,

    -- Legacy dadbod support
    use_dadbod = false,
    default_connection = nil,

    -- Adapter-specific configurations
    snowflake = {
      connection_name = "default", -- Connection name from ~/.snowsql/config
    },

    postgres = {
      host = "localhost",
      port = 5432,
      database = nil,
      user = nil,
      connection_string = nil, -- Alternative: full connection string
    },

    bigquery = {
      project_id = nil,
      dataset = nil,
      location = "US",
    },

    duckdb = {
      database_path = ":memory:",
    },

    redshift = {
      host = nil,
      port = 5439,
      database = nil,
      user = nil,
      connection_string = nil,
    },

    databricks = {
      host = nil,
      http_path = nil,
      token = nil,
    },

    -- DEPRECATED: Kept for backward compatibility
    snowsql_connection = nil,
  },

  direct_query = {
    max_rows = 100,
    buffer_split_size = 30,
  },

  ai = {
    enabled = false,
    provider = "anthropic",
    api_key = nil,
  },

  picker = {
    default = "telescope", -- "telescope" or "fzf"
  },

  keymaps = {
    compile_preview = "<leader>dv",
    execute_inline = "<C-CR>",
    clear_results = "<leader>dC",
    toggle_auto_compile = "<leader>dA",
    model_picker = "<leader>dm",
  },
}

-- Validate configuration
local function validate_config(config)
  if not config then return true end

  -- Validate inline_results.style
  if config.inline_results and config.inline_results.style then
    local valid_styles = { "markdown", "simple" }
    if not vim.tbl_contains(valid_styles, config.inline_results.style) then
      vim.notify(
        string.format("[dbt-power] Invalid inline_results.style: '%s'. Must be 'markdown' or 'simple'", config.inline_results.style),
        vim.log.levels.WARN
      )
      return false
    end
  end

  -- Validate preview.split_position
  if config.preview and config.preview.split_position then
    local valid_positions = { "right", "below", "left", "above" }
    if not vim.tbl_contains(valid_positions, config.preview.split_position) then
      vim.notify(
        string.format("[dbt-power] Invalid preview.split_position: '%s'. Must be one of: %s",
          config.preview.split_position,
          table.concat(valid_positions, ", ")),
        vim.log.levels.WARN
      )
      return false
    end
  end

  -- Validate picker.default
  if config.picker and config.picker.default then
    local valid_pickers = { "telescope", "fzf" }
    if not vim.tbl_contains(valid_pickers, config.picker.default) then
      vim.notify(
        string.format("[dbt-power] Invalid picker.default: '%s'. Must be 'telescope' or 'fzf'", config.picker.default),
        vim.log.levels.WARN
      )
      return false
    end
  end

  -- Validate numeric values are positive
  if config.inline_results then
    if config.inline_results.max_rows and config.inline_results.max_rows < 1 then
      vim.notify("[dbt-power] inline_results.max_rows must be positive", vim.log.levels.WARN)
      return false
    end
    if config.inline_results.max_column_width and config.inline_results.max_column_width < 1 then
      vim.notify("[dbt-power] inline_results.max_column_width must be positive", vim.log.levels.WARN)
      return false
    end
  end

  if config.direct_query then
    if config.direct_query.max_rows and config.direct_query.max_rows < 1 then
      vim.notify("[dbt-power] direct_query.max_rows must be positive", vim.log.levels.WARN)
      return false
    end
  end

  return true
end

-- Migrate legacy configuration to new adapter structure
local function migrate_legacy_config(config)
  if not config or not config.database then
    return config
  end

  -- Migrate snowsql_connection to snowflake.connection_name
  if config.database.snowsql_connection then
    config.database.snowflake = config.database.snowflake or {}
    if not config.database.snowflake.connection_name then
      config.database.snowflake.connection_name = config.database.snowsql_connection
    end
    vim.notify(
      "[dbt-power] database.snowsql_connection is deprecated. Please use database.snowflake.connection_name",
      vim.log.levels.WARN
    )
  end

  return config
end

-- Setup function
function M.setup(opts)
  -- Migrate legacy configuration
  opts = migrate_legacy_config(opts or {})

  -- Validate configuration before merging
  if not validate_config(opts) then
    vim.notify("[dbt-power] Configuration validation failed. Using defaults.", vim.log.levels.ERROR)
    opts = {}
  end

  -- Merge user config with defaults
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  -- Initialize adapter registry
  local registry = require("dbt-power.database.registry")
  registry.init()

  -- Initialize modules
  require("dbt-power.ui.inline_results").setup(M.config.inline_results)
  require("dbt-power.dbt.compile").setup(M.config)
  require("dbt-power.dbt.execute").setup(M.config)
  require("dbt-power.dbt.build").setup(M.config)
  require("dbt-power.dbt.picker").setup(M.config.picker)

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

  -- Compile preview (normal mode)
  if km.compile_preview then
    vim.keymap.set("n", km.compile_preview, function()
      require("dbt-power.preview").show_compiled_sql()
    end, { desc = "Preview compiled SQL (model)", noremap = true, silent = false })
  end

  -- Compile preview for visual selection
  vim.keymap.set("v", "<leader>dv", ":<C-u>lua require('dbt-power.preview').show_compiled_sql_for_selection()<CR>", {
    noremap = true,
    silent = false,
    desc = "Preview compiled SQL (selection)",
  })

  -- Execute with dbt show - inline results
  vim.keymap.set("n", "<leader>ds", function()
    require("dbt-power.execute").execute_with_dbt_show_command()
  end, { desc = "Execute query - inline results", noremap = true, silent = false })

  -- Execute with dbt show - buffer results
  vim.keymap.set("n", "<leader>dS", function()
    require("dbt-power.execute").execute_with_dbt_show_buffer()
  end, { desc = "Execute query - buffer results", noremap = true, silent = false })

  -- Preview CTE with method picker (dbt show or direct CLI)
  vim.keymap.set("n", "<leader>dq", function()
    require("dbt-power.dbt.cte_preview").show_cte_picker()
  end, { desc = "Preview CTE (pick method)", noremap = true, silent = false })

  -- Preview CTE with direct CLI
  vim.keymap.set("n", "<leader>dQ", function()
    require("dbt-power.dbt.cte_preview").show_cte_picker_cli()
  end, { desc = "Preview CTE (Direct CLI)", noremap = true, silent = false })

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

  -- Model picker
  if km.model_picker then
    vim.keymap.set("n", km.model_picker, function()
      require("dbt-power.dbt.picker").open_model_picker()
    end, {
      desc = "Pick and open dbt model",
      noremap = true,
      silent = false,
    })
  end
end

-- Create user commands
function M.create_commands()
  -- Individual commands (PascalCase style)
  vim.api.nvim_create_user_command("DbtPreview", function()
    require("dbt-power.preview").show_compiled_sql()
  end, { desc = "Show compiled SQL in split" })

  vim.api.nvim_create_user_command("DbtExecute", function()
    require("dbt-power.execute").execute_and_show_inline()
  end, { desc = "Execute query and show results inline" })

  vim.api.nvim_create_user_command("DbtExecuteBuffer", function()
    require("dbt-power.execute").execute_with_dbt_show_buffer()
  end, { desc = "Execute query and show results in buffer" })

  vim.api.nvim_create_user_command("DbtClearResults", function()
    require("dbt-power.ui.inline_results").clear_all()
  end, { desc = "Clear all inline results" })

  vim.api.nvim_create_user_command("DbtToggleAutoCompile", function()
    require("dbt-power.preview").toggle_auto_compile()
  end, { desc = "Toggle auto-compile preview" })

  vim.api.nvim_create_user_command("DbtPreviewCTE", function()
    require("dbt-power.dbt.cte_preview").show_cte_picker()
  end, { desc = "Preview Common Table Expression" })

  vim.api.nvim_create_user_command("DbtAdHoc", function()
    require("dbt-power.dbt.adhoc").create_adhoc_model()
  end, { desc = "Create a temporary ad-hoc dbt model for testing" })

  vim.api.nvim_create_user_command("DbtModels", function()
    require("dbt-power.dbt.picker").open_model_picker()
  end, { desc = "Open model picker (Telescope or fzf-lua)" })

  -- Build commands
  vim.api.nvim_create_user_command("DbtBuildModel", function()
    require("dbt-power.dbt.build").build_current_model()
  end, { desc = "Build current model" })

  vim.api.nvim_create_user_command("DbtBuildUpstream", function()
    require("dbt-power.dbt.build").build_upstream()
  end, { desc = "Build with upstream dependencies" })

  vim.api.nvim_create_user_command("DbtBuildDownstream", function()
    require("dbt-power.dbt.build").build_downstream()
  end, { desc = "Build with downstream dependencies" })

  vim.api.nvim_create_user_command("DbtBuildAll", function()
    require("dbt-power.dbt.build").build_all_dependencies()
  end, { desc = "Build with all dependencies" })

  -- Main :Dbt command with subcommands (Git-style)
  vim.api.nvim_create_user_command("Dbt", function(opts)
    local subcommand = opts.fargs[1]

    if subcommand == "preview" then
      require("dbt-power.preview").show_compiled_sql()
    elseif subcommand == "execute" then
      require("dbt-power.execute").execute_and_show_inline()
    elseif subcommand == "execute_buffer" then
      require("dbt-power.execute").execute_with_dbt_show_buffer()
    elseif subcommand == "clear" then
      require("dbt-power.ui.inline_results").clear_all()
    elseif subcommand == "toggle_auto_compile" then
      require("dbt-power.preview").toggle_auto_compile()
    elseif subcommand == "preview_cte" then
      require("dbt-power.dbt.cte_preview").show_cte_picker()
    elseif subcommand == "adhoc" then
      require("dbt-power.dbt.adhoc").create_adhoc_model()
    elseif subcommand == "models" then
      require("dbt-power.dbt.picker").open_model_picker()
    elseif subcommand == "build" then
      require("dbt-power.dbt.build").build_current_model()
    elseif subcommand == "build_upstream" then
      require("dbt-power.dbt.build").build_upstream()
    elseif subcommand == "build_downstream" then
      require("dbt-power.dbt.build").build_downstream()
    elseif subcommand == "build_all" then
      require("dbt-power.dbt.build").build_all_dependencies()
    else
      vim.notify(
        "Unknown subcommand: " .. (subcommand or "nil") .. "\n" ..
        "Available: preview, execute, execute_buffer, clear, toggle_auto_compile, preview_cte, adhoc, models, build, build_upstream, build_downstream, build_all",
        vim.log.levels.ERROR
      )
    end
  end, {
    nargs = "+",
    desc = "dbt-power commands",
    complete = function(ArgLead, CmdLine, CursorPos)
      local subcommands = {
        "preview",
        "execute",
        "execute_buffer",
        "clear",
        "toggle_auto_compile",
        "preview_cte",
        "adhoc",
        "models",
        "build",
        "build_upstream",
        "build_downstream",
        "build_all",
      }
      return vim.tbl_filter(function(cmd)
        return cmd:find(ArgLead) == 1
      end, subcommands)
    end,
  })
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

  -- Check adapter detection
  local project = require("dbt-power.utils.project")
  local project_root = project.find_dbt_project()
  if project_root then
    local profiles = require("dbt-power.database.profiles")
    local adapter_type = profiles.detect_adapter_type(project_root)
    if adapter_type then
      vim.health.ok("Detected database adapter: " .. adapter_type)

      -- Check if adapter CLI is available
      local registry = require("dbt-power.database.registry")
      local adapter = registry.get_adapter(adapter_type, M.config)
      if adapter then
        if adapter:is_cli_available() then
          vim.health.ok(string.format("%s CLI is available: %s", adapter_type, adapter.cli_command))
        else
          vim.health.warn(string.format("%s CLI not found: %s (will fallback to dbt show)", adapter_type, adapter.cli_command or "unknown"))
        end
      end
    else
      vim.health.warn("Could not detect database adapter from profiles.yml")
    end
  else
    vim.health.info("Not in a dbt project (adapter detection skipped)")
  end
end

return M
