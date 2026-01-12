-- PostgreSQL database adapter
-- Executes queries using psql CLI

local BaseAdapter = require("dbt-power.database.adapter").BaseAdapter
local Job = require("plenary.job")

local M = {}

local PostgresAdapter = setmetatable({}, { __index = BaseAdapter })
PostgresAdapter.__index = PostgresAdapter

function PostgresAdapter:new(config)
  local instance = BaseAdapter.new(self, config)
  instance.name = "postgres"
  instance.cli_command = "psql"
  instance.config = config or {}
  instance:is_cli_available()
  return instance
end

-- Get connection arguments for psql CLI
function PostgresAdapter:get_connection_args()
  local args = {}

  -- Use connection_string if provided
  if self.config.connection_string then
    table.insert(args, self.config.connection_string)
  else
    -- Build connection from components
    if self.config.host then
      table.insert(args, "-h")
      table.insert(args, self.config.host)
    end

    if self.config.port then
      table.insert(args, "-p")
      table.insert(args, tostring(self.config.port))
    end

    if self.config.database then
      table.insert(args, "-d")
      table.insert(args, self.config.database)
    end

    if self.config.user then
      table.insert(args, "-U")
      table.insert(args, self.config.user)
    end
  end

  -- Add formatting options for pipe-separated output
  table.insert(args, "-A") -- Unaligned mode
  table.insert(args, "-F|") -- Pipe separator
  table.insert(args, "-t") -- Tuples only (no headers/footers with count)
  table.insert(args, "-f") -- File flag (SQL file will be appended)

  return args
end

-- Execute SQL using psql CLI
function PostgresAdapter:execute_sql(sql, callback)
  -- Check if CLI is available
  if not self:is_cli_available() then
    vim.notify(
      "[dbt-power] psql CLI not found. Please install PostgreSQL client or it will fallback to dbt show",
      vim.log.levels.WARN
    )
    callback({ error = "psql CLI not available" })
    return
  end

  -- Remove trailing semicolon and whitespace
  sql = vim.trim(sql)
  sql = sql:gsub("%s*;%s*$", "")

  -- Create temp SQL file for execution
  local temp_file = vim.fn.tempname() .. ".sql"
  local file = io.open(temp_file, "w")
  if not file then
    callback({ error = string.format("Could not create temp SQL file at %s", temp_file) })
    return
  end

  file:write(sql)
  file:close()

  -- Get connection arguments
  local args = self:get_connection_args()
  table.insert(args, temp_file) -- Append file path

  -- Cleanup function to ensure temp file is always removed
  local function cleanup()
    pcall(os.remove, temp_file)
  end

  Job:new({
    command = "psql",
    args = args,
    on_exit = function(j, return_val)
      vim.schedule(function()
        -- Always clean up temp file
        cleanup()

        if return_val ~= 0 then
          local stderr = table.concat(j:stderr_result(), "\n")
          local stdout = table.concat(j:result(), "\n")
          local full_output = stderr
          if stdout ~= "" then
            full_output = stdout .. "\n" .. stderr
          end
          callback({ error = "psql query failed:\n" .. full_output })
          return
        end

        -- Parse results from psql output
        local stdout = table.concat(j:result(), "\n")
        local parsed = self:parse_output(stdout)

        callback(parsed)
      end)
    end,
  }):start()
end

-- Parse psql output which comes in pipe-separated format (with -A -F|)
function PostgresAdapter:parse_output(output)
  local columns = {}
  local rows = {}

  if not output or output == "" then
    return { columns = {}, rows = {} }
  end

  local lines = vim.split(output, "\n")

  -- First line should be header
  if #lines < 1 then
    return { columns = {}, rows = {} }
  end

  local header_line = lines[1]
  for col in header_line:gmatch("([^|]+)") do
    local trimmed = vim.trim(col)
    if trimmed ~= "" then
      table.insert(columns, trimmed)
    end
  end

  if #columns == 0 then
    return { columns = {}, rows = {} }
  end

  -- Parse data rows (skip header)
  for i = 2, #lines do
    local line = lines[i]

    -- Skip empty lines
    if vim.trim(line) == "" then
      goto continue_postgres_parse
    end

    -- Parse row
    local row = {}
    for value in line:gmatch("([^|]*)") do
      -- Note: We use [^|]* instead of [^|]+ to handle empty values
      table.insert(row, vim.trim(value))
    end

    -- Only add rows with correct number of columns
    -- Note: psql with -F| can produce n+1 values if line ends with |
    -- so we trim the last empty value if present
    if #row == #columns + 1 and row[#row] == "" then
      table.remove(row)
    end

    if #row == #columns then
      table.insert(rows, row)
    end

    ::continue_postgres_parse::
  end

  return {
    columns = columns,
    rows = rows,
  }
end

-- Validate PostgreSQL-specific configuration
function PostgresAdapter:validate_config()
  -- Either connection_string or (host + database + user) required
  if not self.config.connection_string then
    if not self.config.host or not self.config.database or not self.config.user then
      return false, "PostgreSQL adapter requires either connection_string or (host, database, user)"
    end
  end
  return true, nil
end

M.PostgresAdapter = PostgresAdapter

return M
