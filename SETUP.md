# Setup Guide for dbt-power.nvim

## Quick Start

### 1. Install dbt Cloud CLI

```bash
# Follow instructions at: https://docs.getdbt.com/docs/cloud/cloud-cli-installation

# macOS (example)
brew install dbt-labs/dbt/dbt

# Verify installation
dbt --version
```

### 2. Configure dbt Cloud CLI

```bash
# Download CLI config from dbt Cloud
# Go to: Your Project > Account Settings > CLI
# Download dbt_cloud.yml

# Save to ~/.dbt/dbt_cloud.yml
mkdir -p ~/.dbt
mv ~/Downloads/dbt_cloud.yml ~/.dbt/
```

### 3. Plugin is Already Configured!

The plugin is already set up in your `lua/plugins/data-tools/dbt.lua` file.

### 4. Set Up Database Connection

#### Option A: Using vim-dadbod-ui (Recommended)

1. Open Neovim
2. Run `:DBUIAddConnection`
3. Enter your connection string:
   - PostgreSQL: `postgresql://user:pass@host:5432/database`
   - Snowflake: `snowflake://account.region/db?warehouse=wh&role=role`
   - BigQuery: `bigquery://project/dataset`

#### Option B: Configure in init.lua

Add to your `init.lua` or a config file:

```lua
vim.g.dbs = {
  dev = "postgresql://user:pass@localhost:5432/dev_db",
  prod = "postgresql://user:pass@prod-host:5432/prod_db",
}
```

### 5. Test the Setup

1. Open a dbt model SQL file
2. Press `<leader>dr` to run the model
3. Press `<C-CR>` (Ctrl+Enter) to execute and see results inline
4. Press `<leader>dv` to preview compiled SQL

## Keybindings Reference

| Key | Action |
|-----|--------|
| `<leader>dr` | Run current dbt model |
| `<leader>dt` | Test current model |
| `<leader>dc` | Compile current model |
| `<leader>dm` | Telescope model picker |
| `<leader>dv` | Preview compiled SQL |
| `<C-CR>` | Execute query inline |
| `<leader>dC` | Clear results |
| `<leader>dA` | Toggle auto-compile |
| `<leader>db` | Toggle DBUI |

## Troubleshooting

### Plugin Not Loading

Check if the plugin directory exists:
```bash
ls -la ~/Projects/dbt-power.nvim
```

### Database Connection Issues

1. Test vim-dadbod:
   ```vim
   :DB postgresql://user:pass@host/db select 1
   ```

2. Check DBUI connections:
   ```vim
   :DBUIToggle
   ```

### dbt Commands Not Working

1. Verify dbt CLI:
   ```bash
   which dbt
   dbt --version
   ```

2. Check you're in a dbt project:
   ```bash
   ls dbt_project.yml
   ```

3. Run health check:
   ```vim
   :checkhealth dbt-power
   ```

## Advanced Configuration

### Custom Database Connection

Edit `lua/plugins/data-tools/dbt.lua` and modify:

```lua
database = {
  use_dadbod = true,
  default_connection = "postgresql://...",
},
```

### Adjust Result Display

```lua
inline_results = {
  max_rows = 1000,  -- Show more rows
  max_column_width = 100,  -- Wider columns
  style = "simple",  -- Simpler display
},
```

### Auto-Compile on Save

Add to your dbt filetype config:

```lua
vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = "*.sql",
  callback = function()
    require("dbt-power.preview").show_compiled_sql()
  end,
})
```

## Next Steps

1. Try executing a model: `<leader>dr`
2. Execute custom SQL: Select text + `<C-CR>`
3. Preview compiled output: `<leader>dv`
4. Explore DBUI: `<leader>db`
5. Clear results when done: `<leader>dC`

## Getting Help

- `:help dbt-power` (coming soon)
- `:checkhealth dbt-power`
- Check `~/Projects/dbt-power.nvim/README.md`
