# Database Connection Setup

This guide covers setting up database connections for use with dbt-power.nvim.

## Connection Methods

### Method 1: vim-dadbod-ui (Recommended for Interactive Use)

1. Open Neovim
2. Press `<leader>db` or run `:DBUIToggle`
3. Press `a` to add a connection
4. Enter connection details

### Method 2: Global Configuration (Recommended for Persistent Connections)

Add to your Neovim config (e.g., in `init.lua` or a separate config file):

```lua
vim.g.dbs = {
  -- Connection name = connection URL
  dev = "postgresql://username:password@localhost:5432/dev_database",
  staging = "postgresql://username:password@staging-host:5432/staging_db",
  prod = "postgresql://username:password@prod-host:5432/prod_db",
}
```

### Method 3: Environment Variables

```lua
vim.g.dbs = {
  dev = os.getenv("DEV_DATABASE_URL"),
  prod = os.getenv("PROD_DATABASE_URL"),
}
```

## Connection String Formats

### PostgreSQL
```
postgresql://username:password@host:5432/database
postgres://username:password@host:5432/database
```

### Snowflake
```
snowflake://account.region.snowflakecomputing.com/database?warehouse=COMPUTE_WH&role=ANALYST
```

### BigQuery
```
bigquery://project-id/dataset
```

### MySQL
```
mysql://username:password@host:3306/database
```

### SQLite
```
sqlite:///path/to/database.db
sqlite://path/to/database.db
```

### DuckDB
```
duckdb:///path/to/database.duckdb
duckdb://path/to/database.duckdb
```

## Securing Credentials

### Option 1: Use Connection Files

Create `~/.local/share/db_ui/connections.json`:

```json
{
  "dev": "postgresql://user:pass@localhost/dev_db",
  "prod": "postgresql://user:pass@prod-host/prod_db"
}
```

### Option 2: Environment Variables

Add to your shell config (`~/.zshrc` or `~/.bashrc`):

```bash
export DEV_DB_URL="postgresql://user:pass@localhost/dev_db"
export PROD_DB_URL="postgresql://user:pass@prod-host/prod_db"
```

Then in Neovim config:

```lua
vim.g.dbs = {
  dev = os.getenv("DEV_DB_URL"),
  prod = os.getenv("PROD_DB_URL"),
}
```

### Option 3: 1Password/Pass Integration

Use CLI tools to fetch credentials:

```lua
local function get_db_url(key)
  local handle = io.popen("op read " .. key)
  local result = handle:read("*a")
  handle:close()
  return result:gsub("%s+", "")
end

vim.g.dbs = {
  prod = get_db_url("op://vault/prod-db/url"),
}
```

## Testing Your Connection

### Using vim-dadbod

```vim
:DB postgresql://user:pass@host/db select 1
```

### Using DBUI

1. Press `<leader>db`
2. Navigate to your connection
3. Press `Enter` to connect
4. Expand tables to verify

### Test Query

Create a test SQL file:

```sql
-- test.sql
SELECT 1 as test_column;
```

Press `<C-CR>` to execute and see inline results.

## dbt Cloud Integration

dbt-power.nvim uses dbt Cloud CLI, which handles credentials automatically.

### Setup dbt Cloud Credentials

1. Download CLI config from dbt Cloud:
   - Go to your project
   - Click Account Settings > CLI
   - Download `dbt_cloud.yml`

2. Save to `~/.dbt/dbt_cloud.yml`

3. dbt commands will now use your Cloud credentials

### Using dbt Cloud with Database Queries

dbt Cloud CLI connects to your data warehouse using credentials stored in dbt Cloud. The vim-dadbod connection is only needed for:

- Ad-hoc SQL queries
- Viewing query results inline
- Exploring database schema in DBUI

## Common Issues

### Connection Timeout

Increase timeout in connection string:
```
postgresql://user:pass@host/db?connect_timeout=30
```

### SSL/TLS Issues

For PostgreSQL:
```
postgresql://user:pass@host/db?sslmode=require
```

For Snowflake:
```
snowflake://account.region/db?warehouse=wh&role=role&authenticator=externalbrowser
```

### Authentication Failed

1. Verify credentials work outside Neovim:
   ```bash
   psql "postgresql://user:pass@host/db"
   ```

2. Check for special characters in password (URL encode them)

3. Verify network access (VPN, firewall, etc.)

## Best Practices

1. **Never commit credentials** to version control
2. Use environment variables or secret managers
3. Test with read-only credentials first
4. Use separate dev/staging/prod connections
5. Set reasonable query timeouts
6. Use connection pooling for production

## Next Steps

After setting up your database connection:

1. Restart Neovim
2. Open a dbt model SQL file
3. Press `<C-CR>` to execute and see results
4. Press `<leader>db` to browse your database
5. Press `<leader>dv` to preview compiled dbt SQL
