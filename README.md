# dbt-power.nvim

A Neovim plugin for dbt development with Power User-like features, including inline query results display inspired by Molten. Seamlessly integrates with dbt Cloud CLI and supports multiple database adapters (Snowflake, PostgreSQL, BigQuery, Redshift, DuckDB, Databricks) with automatic detection from your dbt profiles.

## Features

- ✅ **Multi-Database Support**: Automatic adapter detection for Snowflake, PostgreSQL, BigQuery, Redshift, DuckDB, and Databricks
- ✅ **Smart Execution**: Direct CLI execution (psql, bq, snowsql, etc.) with automatic fallback to dbt show
- ✅ **dbt Cloud Integration**: Execute models using dbt Cloud's database connections (no local credentials needed)
- ✅ **Inline Query Results**: Execute SQL and see results inline using extmarks (like Jupyter notebooks)
- ✅ **Compiled SQL Preview**: View compiled dbt models in a split window, with execution from preview
- ✅ **Buffer Results Display**: Execute models and display results in a dedicated buffer window
- ✅ **Model Picker**: Browse and open dbt models with fuzzy search (Telescope or fzf-lua)
- ✅ **Build Commands**: Build models with dependency graph support (upstream/downstream/all)
- ✅ **CTE Preview**: Extract and preview Common Table Expressions from your SQL
- ✅ **Ad-hoc Temporary Models**: Create temporary dbt models for testing, auto-ignored by git
- ✅ **Intelligent Error Handling**: Display actual dbt compilation and execution errors (not generic failures)
- ✅ **Visual Selection Execution**: Execute any SQL selection from your editor
- ✅ **Auto-compile Mode**: Live preview of compiled SQL as you type
- ✅ **Database Integration**: Uses vim-dadbod for local database connections (optional)
- ✅ **CSV Export**: Export query results to CSV
- 🚧 **AI Documentation**: Generate model/column docs (planned)
- 🚧 **Lineage Visualization**: Show model lineage graphs (planned)

## Requirements

- Neovim >= 0.10.0
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- **One of the following** (for model picker):
  - [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) OR
  - [fzf-lua](https://github.com/ibhagwan/fzf-lua)
- [vim-dadbod](https://github.com/tpope/vim-dadbod) (optional, for local database connections)
- [dbtpal](https://github.com/PedramNavid/dbtpal) (optional, for additional dbt utilities)
- dbt Cloud CLI or dbt Core
- **Database CLI** (optional, for direct execution - falls back to `dbt show` if not available):
  - `snowsql` for Snowflake
  - `psql` for PostgreSQL/Redshift
  - `bq` for BigQuery
  - `duckdb` for DuckDB
  - Databricks uses `dbt show` by default

## Why dbt-power.nvim?

**Works with ANY dbt database** - The plugin automatically detects your database type from your dbt profiles and uses the appropriate execution method. No manual configuration needed!

- **Snowflake** users get direct `snowsql` execution (no row limits)
- **PostgreSQL/Redshift** users get direct `psql` execution
- **BigQuery** users get direct `bq query` execution
- **DuckDB** users get direct `duckdb` execution
- **Databricks** users get optimized `dbt show` execution
- **Any database** falls back to universal `dbt show` if CLI not available

Previously, visual selection execution (`<leader>dx`, `<leader>dX`) only worked with Snowflake. **Now it works with ALL databases!**

## Quick Start

1. **Ensure dbt is configured:**
   ```bash
   dbt --version  # Should be dbt Cloud CLI or dbt Core
   dbt debug     # Verify your profiles.yml is configured
   ```

2. **Install the plugin:**
   Follow installation steps below

3. **Open a dbt model file** and try:
   - `<leader>dm` or `:Dbt models` - Browse all models with fuzzy search
   - `<leader>dv` or `:Dbt preview` - Preview compiled SQL
   - `<leader>dS` or `:Dbt execute_buffer` - Execute and view results
   - `<leader>dx` (Visual mode) - Execute SQL selection (works with all databases!)
   - `<leader>dbm` or `:Dbt build` - Build current model
   - `<leader>da` or `:Dbt adhoc` - Create ad-hoc test model

4. **Check adapter detection:**
   ```vim
   :checkhealth dbt-power
   ```
   This shows your detected database adapter and CLI availability.

## Installation

### Using lazy.nvim

```lua
{
  dir = "~/Projects/dbt-power.nvim",
  name = "dbt-power",
  dependencies = {
    "nvim-lua/plenary.nvim",
    -- Choose ONE of the following for model picker:
    "nvim-telescope/telescope.nvim",  -- OR
    -- "ibhagwan/fzf-lua",

    -- Optional dependencies:
    -- "tpope/vim-dadbod",     -- For local database connections
    -- "PedramNavid/dbtpal",   -- For additional dbt utilities
  },
  dev = true,
  ft = { "sql", "yaml", "md" },
  config = function()
    require("dbt-power").setup({
      -- Configuration options
      dbt_cloud_cli = "dbt",
      inline_results = {
        enabled = true,
        max_rows = 500,
        max_column_width = 50,
        style = "markdown", -- or "simple"
      },
    })
  end,
}
```

**Note:** Only one picker (Telescope or fzf-lua) is required for the model picker feature. vim-dadbod and dbtpal are optional.

## Usage

### Keybindings

| Keybinding | Action | Mode |
|-----------|--------|------|
| `<leader>dv` | Preview compiled SQL in split | Normal |
| `<leader>dS` | Execute model → results in buffer | Normal |
| `<leader>ds` | Execute model → inline results | Normal |
| `<leader>dm` | Open model picker (browse all models) | Normal |
| `<leader>da` | Create ad-hoc temporary model | Normal |
| `<leader>dC` | Clear inline results | Normal |
| `<leader>dA` | Toggle auto-compile mode | Normal |
| `<leader>dq` | Preview CTE (Common Table Expression) | Normal |
| `<leader>dx` | Execute visual selection | Visual |
| `<leader>dbm` | Build current model | Normal |
| `<leader>dbu` | Build with upstream dependencies (+) | Normal |
| `<leader>dbd` | Build with downstream dependencies (+) | Normal |
| `<leader>dba` | Build all dependencies (@) | Normal |

### Workflow Examples

#### 1. Execute and View Results in Buffer (Recommended)
```
1. Open a dbt model file
2. Press <leader>dv  → Preview compiled SQL in split
3. Press <leader>dS  → Execute model, see results in bottom buffer
4. Press q           → Close results buffer
```

#### 2. Quick Inline Results
```
1. Open a dbt model file
2. Press <leader>ds → Results appear inline below the code
3. Press <leader>dC → Clear results
```

#### 3. Ad-hoc Testing (New!)
```
1. Press <leader>da             → Creates models/adhoc/adhoc_YYYYMMDD_HHMMSS.sql
2. Write your test SQL query
3. Press <leader>dS or <leader>ds → Execute
4. Delete file when done (won't be committed, auto-ignored in git)
```

#### 4. Preview Compiled SQL Before Executing
```
1. Press <leader>dv → See compiled SQL in right split
2. Review the compiled output
3. Press <leader>dS → Execute from preview buffer
4. See results in bottom buffer
```

#### 5. Visual Selection Execution
```
1. Select SQL in visual mode (V)
2. Press <leader>dx → Execute selection inline
3. Results appear below selection
```

#### 6. Model Picker - Browse All Models
```
1. Press <leader>dm         → Open fuzzy finder with all dbt models
2. Type to filter models    → Search by name or path
3. Press Enter              → Open selected model
4. Or preview in split      → See model before opening
```

#### 7. Build with Dependencies
```
1. Open a dbt model file
2. Press <leader>dbm        → Build just this model
3. Or <leader>dbu           → Build with upstream dependencies (+model)
4. Or <leader>dbd           → Build with downstream dependencies (model+)
5. Or <leader>dba           → Build all dependencies (@model)
6. View build output in buffer
```

#### 8. CTE Preview
```
1. Open a dbt model with CTEs
2. Press <leader>dq         → Select a CTE from list
3. View CTE execution results
4. Debug individual CTEs before full model
```

### Error Handling

The plugin now properly extracts and displays dbt errors:

**If compilation fails:**
```
dbt show execution failed for model: stg_users

Encountered an error:
Compilation Error
  Invalid identifier 'COLUMN_NAME' in model stg_users.sql
```

**If database error occurs:**
```
dbt show execution failed for model: stg_users

Encountered an error:
Runtime Error
  Database Error in model stg_users
    000904 (42000): SQL compilation error: error line 12 at position 4
    invalid identifier 'ID'
```

### Database Setup

#### Automatic Adapter Detection

The plugin automatically detects your database type from `~/.dbt/profiles.yml`:

```yaml
# ~/.dbt/profiles.yml
my_project:
  target: dev
  outputs:
    dev:
      type: snowflake  # or postgres, bigquery, redshift, duckdb, databricks
      # ... other connection details
```

**No configuration needed!** The plugin will:
1. Read your active dbt profile
2. Detect the database adapter type
3. Use the appropriate CLI (snowsql, psql, bq, etc.)
4. Fall back to `dbt show` if CLI is not available

#### Supported Databases

| Database | CLI Command | Status |
|----------|------------|--------|
| Snowflake | `snowsql` | ✅ Full support |
| PostgreSQL | `psql` | ✅ Full support |
| BigQuery | `bq` | ✅ Full support |
| Redshift | `psql` | ✅ Full support (uses PostgreSQL protocol) |
| DuckDB | `duckdb` | ✅ Full support |
| Databricks | N/A | ✅ Uses `dbt show` (recommended) |

#### Manual Adapter Configuration

Override auto-detection if needed:

```lua
require("dbt-power").setup({
  database = {
    -- Manually specify adapter (overrides auto-detection)
    adapter = "postgres",  -- or "snowflake", "bigquery", etc.

    -- Adapter-specific configurations
    postgres = {
      host = "localhost",
      port = 5432,
      database = "mydb",
      user = "myuser",
      -- Or use connection string:
      connection_string = "postgresql://user:pass@localhost:5432/mydb",
    },

    snowflake = {
      connection_name = "default",  -- From ~/.snowsql/config
    },

    bigquery = {
      project_id = "my-gcp-project",
      dataset = "my_dataset",
      location = "US",
    },

    duckdb = {
      database_path = ":memory:",  -- or path to .duckdb file
    },
  },
})
```

#### Backward Compatibility

Old Snowflake configurations still work:

```lua
require("dbt-power").setup({
  database = {
    snowsql_connection = "default",  -- DEPRECATED but still works
  },
})
```

You'll see a deprecation warning guiding you to the new config format.

#### Optional: vim-dadbod Integration

For ad-hoc SQL queries outside dbt models, configure vim-dadbod:

```lua
-- In your config
vim.g.dbs = {
  dev = "postgresql://user:pass@localhost/mydb",
  snowflake = "snowflake://username@account.region/database?warehouse=warehouse_name&private_key_path=/path/to/rsa_key.p8",
}
vim.g.db_ui_default_connection = "dev"
```

Or use the interactive setup:
```
:DBUIAddConnection
```

## Configuration

Full configuration options:

```lua
require("dbt-power").setup({
  -- dbt CLI configuration
  dbt_cloud_cli = "dbt",
  dbt_project_dir = nil, -- Auto-detect

  -- Inline results
  inline_results = {
    enabled = true,
    max_rows = 500,
    max_column_width = 50,
    auto_clear_on_execute = false,
    style = "markdown", -- or "simple"
  },

  -- Compiled SQL preview
  preview = {
    auto_compile = false,
    split_position = "right", -- or "below"
    split_size = 80,
  },

  -- Database adapter configuration
  database = {
    -- Adapter selection: nil (auto-detect), or specify: "snowflake", "postgres", etc.
    adapter = nil,

    -- Adapter-specific configurations
    snowflake = {
      connection_name = "default",  -- From ~/.snowsql/config
    },

    postgres = {
      host = "localhost",
      port = 5432,
      database = nil,
      user = nil,
      connection_string = nil,  -- Alternative: full connection string
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

    -- Legacy vim-dadbod support (optional)
    use_dadbod = false,
    default_connection = nil,
  },

  -- Direct query execution settings
  direct_query = {
    max_rows = 100,              -- Row limit for direct queries
    buffer_split_size = 30,      -- Split window height for results
  },

  -- AI features (coming soon)
  ai = {
    enabled = false,
    provider = "anthropic",
    api_key = os.getenv("ANTHROPIC_API_KEY"),
  },

  -- Model picker
  picker = {
    default = "telescope", -- "telescope" or "fzf"
  },

  -- Keymaps (set to false to disable)
  keymaps = {
    compile_preview = "<leader>dv",
    execute_inline = "<C-CR>",
    clear_results = "<leader>dC",
    toggle_auto_compile = "<leader>dA",
  },
})
```

## Commands

The plugin provides commands in two styles:
1. **PascalCase** (e.g., `:DbtPreview`) - traditional Neovim style
2. **Subcommand** (e.g., `:Dbt preview`) - Git-style with tab completion

Both styles do the same thing - use whichever you prefer!

### Execution & Preview
| PascalCase | Subcommand | Description |
|-----------|-----------|-------------|
| `:DbtPreview` | `:Dbt preview` | Show compiled SQL in split window |
| `:DbtExecute` | `:Dbt execute` | Execute current model and show results inline |
| `:DbtExecuteBuffer` | `:Dbt execute_buffer` | Execute current model and show results in buffer window |
| `:DbtClearResults` | `:Dbt clear` | Clear all inline results from current buffer |
| `:DbtToggleAutoCompile` | `:Dbt toggle_auto_compile` | Toggle auto-compile mode (live preview as you type) |
| `:DbtPreviewCTE` | `:Dbt preview_cte` | Preview a Common Table Expression |

### Model Management
| PascalCase | Subcommand | Description |
|-----------|-----------|-------------|
| `:DbtModels` | `:Dbt models` | Open model picker to browse and select models |
| `:DbtAdHoc` | `:Dbt adhoc` | Create a new temporary ad-hoc model for testing |

### Build Commands
| PascalCase | Subcommand | Description |
|-----------|-----------|-------------|
| `:DbtBuildModel` | `:Dbt build` | Build the current model |
| `:DbtBuildUpstream` | `:Dbt build_upstream` | Build current model with upstream dependencies (+) |
| `:DbtBuildDownstream` | `:Dbt build_downstream` | Build current model with downstream dependencies (+) |
| `:DbtBuildAll` | `:Dbt build_all` | Build current model with all dependencies (@) |

**Pro Tip**: The `:Dbt` command has tab completion! Type `:Dbt <Tab>` to see all available subcommands.

### Ad-Hoc Model Management

The plugin provides Lua functions for managing ad-hoc models:

```lua
-- Create a new ad-hoc model
require("dbt-power.dbt.adhoc").create_adhoc_model()

-- List all ad-hoc models
require("dbt-power.dbt.adhoc").list_adhoc_models()

-- Clean up all ad-hoc models
require("dbt-power.dbt.adhoc").cleanup_adhoc_models()
```

Ad-hoc models are stored in `models/adhoc/` and are automatically ignored by git (see `.gitignore`)

## Development Status

Core features are complete and stable. Additional features planned:

**Completed:**
- [x] Multi-database adapter support (Snowflake, PostgreSQL, BigQuery, Redshift, DuckDB, Databricks)
- [x] Automatic adapter detection from dbt profiles
- [x] Direct CLI execution with smart fallback
- [x] Inline results display (extmarks)
- [x] SQL compilation preview
- [x] Query execution via dbt show (dbt Cloud)
- [x] Buffer results display
- [x] Visual selection execution (now works with all databases!)
- [x] CSV export
- [x] Ad-hoc temporary models
- [x] Intelligent error handling
- [x] Execution from preview buffer
- [x] Model picker (Telescope/fzf-lua)
- [x] Build commands with dependency graph
- [x] CTE preview and execution

**Planned:**
- [ ] AI documentation generation
- [ ] Lineage visualization
- [ ] Cost estimation
- [ ] Column-level lineage
- [ ] Model graph display

## Troubleshooting

### Check Plugin Health

Run `:checkhealth dbt-power` to verify:
- dbt CLI availability
- Database adapter detection
- CLI tool availability (psql, bq, snowsql, etc.)
- Plugin dependencies

### "Not in a dbt model file" error
- Make sure you're in a `.sql` file in a dbt project
- The plugin auto-detects dbt projects by looking for `dbt_project.yml`
- Use `:checkhealth dbt-power` to verify plugin health

### "Could not detect database adapter" error
- Ensure `~/.dbt/profiles.yml` exists and is properly formatted
- Verify your dbt profile is configured: `dbt debug`
- Check that the profile `type` field matches a supported database
- Manually specify adapter in config if auto-detection fails:
  ```lua
  require("dbt-power").setup({
    database = { adapter = "postgres" }
  })
  ```

### Database CLI not found (falls back to dbt show)
- Install the appropriate CLI for your database:
  - Snowflake: Install snowsql
  - PostgreSQL/Redshift: Install PostgreSQL client (`psql`)
  - BigQuery: Install Google Cloud SDK (`gcloud` + `bq`)
  - DuckDB: Install DuckDB CLI
- The plugin will automatically fall back to `dbt show` if CLI is not available
- Check CLI availability: `:checkhealth dbt-power`

### Visual selection execution not working (`<leader>dx`)
- This was previously Snowflake-only, now works with all databases
- Ensure adapter is detected: `:checkhealth dbt-power`
- If CLI is not available, it will use `dbt show` (limited to 500 rows)

### Execution returns "No results returned from model"
- Verify your model compiles correctly: `dbt compile -s <model_name>`
- Check for dbt Cloud compilation errors
- Ensure you have permissions to the database/schema
- Review the actual error message displayed in the notification

### Preview buffer doesn't show results after execution
- Press `<leader>dS` (buffer results) instead of `<leader>ds` (inline)
- Results window should appear at the bottom of your editor
- Press `q` to close the results buffer

### dbt Cloud CLI not found
- Ensure dbt Cloud CLI is installed: `which dbt`
- Configure path in setup if needed:
  ```lua
  require("dbt-power").setup({
    dbt_cloud_cli = "/path/to/dbt",
  })
  ```

### Performance issues with large models
- Inline results are limited to 500 rows by default (configurable)
- Large datasets will truncate for display but full results are still available
- Use `max_rows` configuration to adjust
- Direct CLI execution has no row limit (unlike `dbt show` which is limited to 500)

## Inspiration

- [Molten](https://github.com/benlubas/molten-nvim) - For the extmark-based inline display approach
- [dbt Power User](https://marketplace.visualstudio.com/items?itemName=innoverio.vscode-dbt-power-user) - For the feature set and workflow inspiration
- [dbtpal](https://github.com/PedramNavid/dbtpal) - For dbt integration patterns

## License

MIT

## Contributing

This is currently a personal project under active development. Contributions welcome once v1.0 is released!
