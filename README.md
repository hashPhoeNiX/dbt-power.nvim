# dbt-power.nvim

A Neovim plugin for dbt development with Power User-like features, including inline query results display inspired by Molten.

## Features

- ✅ **Inline Query Results**: Execute SQL and see results inline using extmarks (like Jupyter notebooks)
- ✅ **Compiled SQL Preview**: View compiled dbt models in a split window
- ✅ **Model Execution**: Run dbt models with async feedback
- ✅ **Visual Selection Execution**: Execute any SQL selection
- ✅ **Auto-compile Mode**: Live preview of compiled SQL as you type
- ✅ **Database Integration**: Uses vim-dadbod for database connections
- ✅ **CSV Export**: Export query results to CSV
- 🚧 **AI Documentation**: Generate model/column docs (planned)
- 🚧 **Lineage Visualization**: Show model lineage graphs (planned)

## Requirements

- Neovim >= 0.10.0
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [vim-dadbod](https://github.com/tpope/vim-dadbod) (optional but recommended)
- [dbtpal](https://github.com/PedramNavid/dbtpal) (optional)
- dbt Cloud CLI or dbt Core

## Installation

### Using lazy.nvim

```lua
{
  dir = "~/Projects/dbt-power.nvim",
  name = "dbt-power",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope.nvim",
    "tpope/vim-dadbod",
    "PedramNavid/dbtpal",
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

## Usage

### Basic Workflow

1. **Execute Current Model**
   ```
   <C-CR> (Control+Enter or Cmd+Enter)
   ```
   Compiles and executes the current dbt model, showing results inline

2. **Execute Selection**
   - Select SQL in visual mode
   - Press `<C-CR>`
   - Results appear below the selection

3. **Preview Compiled SQL**
   ```
   <leader>dv
   ```
   Shows the compiled SQL in a split window

4. **Clear Results**
   ```
   <leader>dC
   ```
   Clears all inline results in the current buffer

5. **Toggle Auto-Compile**
   ```
   <leader>dA
   ```
   Enables live preview of compiled SQL as you type

### Database Setup

Configure database connections using vim-dadbod:

```lua
-- In your config
vim.g.dbs = {
  dev = "postgresql://user:pass@localhost/mydb",
  prod = "snowflake://account.region/db?warehouse=wh",
}
```

Or use vim-dadbod-ui:
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

  -- Database connections
  database = {
    use_dadbod = true,
    default_connection = nil,
  },

  -- AI features (coming soon)
  ai = {
    enabled = false,
    provider = "anthropic",
    api_key = os.getenv("ANTHROPIC_API_KEY"),
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

- `:DbtPreview` - Show compiled SQL in split
- `:DbtExecute` - Execute query and show results inline
- `:DbtClearResults` - Clear all inline results
- `:DbtToggleAutoCompile` - Toggle auto-compile mode

## Development Status

This plugin is in active development. Core features are functional:

- [x] Inline results display
- [x] SQL compilation preview
- [x] Query execution
- [x] Visual selection support
- [x] CSV export
- [ ] AI documentation generation
- [ ] Lineage visualization
- [ ] Cost estimation
- [ ] Column-level lineage

## Inspiration

- [Molten](https://github.com/benlubas/molten-nvim) - For the extmark-based inline display approach
- [dbt Power User](https://marketplace.visualstudio.com/items?itemName=innoverio.vscode-dbt-power-user) - For the feature set
- [dbtpal](https://github.com/PedramNavid/dbtpal) - For dbt integration patterns

## License

MIT

## Contributing

This is currently a personal project under active development. Contributions welcome once v1.0 is released!
