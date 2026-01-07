-- Model picker for dbt-power.nvim
-- Supports both Telescope and fzf-lua with configurable backend
-- Default: fzf-lua (faster, lighter weight)
-- Features: fuzzy search, quick actions, file preview (bat or cat)

local M = {}
local Job = require("plenary.job")

M.config = {
  picker = "fzf", -- "telescope" or "fzf" (default: fzf)
}

-- Available actions when selecting a model
M.ACTIONS = {
  open = "open",
  preview = "preview",
  execute = "execute",
  build = "build",
}

function M.setup(config)
  if config and config.picker then
    M.config.picker = config.picker
  end
end

-- Get all dbt models from the project
local function get_dbt_models()
  local project_root = require("dbt-power.utils.project").find_dbt_project()
  if not project_root then
    return {}
  end

  local models_dir = project_root .. "/models"
  local models = {}

  -- Recursively scan models directory
  local function scan_dir(dir, prefix)
    local ok, entries = pcall(vim.fn.readdir, dir)
    if not ok then
      return
    end

    for _, entry in ipairs(entries) do
      local full_path = dir .. "/" .. entry
      local is_dir = vim.fn.isdirectory(full_path) == 1

      if is_dir then
        -- Recursively scan subdirectories
        scan_dir(full_path, prefix .. entry .. "/")
      elseif entry:match("%.sql$") then
        -- Extract model name (filename without .sql)
        local model_name = entry:gsub("%.sql$", "")
        local relative_path = prefix .. entry
        local file_path = full_path

        table.insert(models, {
          name = model_name,
          path = relative_path,
          full_path = file_path,
          display = prefix .. model_name,
        })
      end
    end
  end

  scan_dir(models_dir, "")

  -- Sort by display name
  table.sort(models, function(a, b)
    return a.display < b.display
  end)

  return models
end

-- Telescope picker implementation
local function telescope_picker(on_select)
  local telescope_ok, telescope = pcall(require, "telescope")
  if not telescope_ok then
    vim.notify("[dbt-power] Telescope not installed", vim.log.levels.ERROR)
    return
  end

  local models = get_dbt_models()
  if #models == 0 then
    vim.notify("[dbt-power] No dbt models found", vim.log.levels.WARN)
    return
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local picker = pickers.new({}, {
    prompt_title = "dbt Models",
    finder = finders.new_table({
      results = models,
      entry_maker = function(entry)
        return {
          value = entry,
          display = entry.display,
          ordinal = entry.display,
          filename = entry.full_path,  -- Required by file_previewer
        }
      end,
    }),
    previewer = conf.file_previewer({}),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      -- Default action: open model file
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if not selection or not selection.value then return end
        on_select(selection.value, M.ACTIONS.open)
      end)

      -- <C-p> = preview compiled SQL
      map("i", "<C-p>", function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if not selection or not selection.value then return end
        on_select(selection.value, M.ACTIONS.preview)
      end)

      -- <C-x> = execute model
      map("i", "<C-x>", function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if not selection or not selection.value then return end
        on_select(selection.value, M.ACTIONS.execute)
      end)

      -- <C-b> = build model
      map("i", "<C-b>", function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if not selection or not selection.value then return end
        on_select(selection.value, M.ACTIONS.build)
      end)

      return true
    end,
  })

  picker:find()
end

-- fzf-lua picker implementation
local function fzf_picker(on_select)
  local fzf_ok, fzf = pcall(require, "fzf-lua")
  if not fzf_ok then
    vim.notify("[dbt-power] fzf-lua not installed", vim.log.levels.ERROR)
    return
  end

  local models = get_dbt_models()
  if #models == 0 then
    vim.notify("[dbt-power] No dbt models found", vim.log.levels.WARN)
    return
  end

  -- Create display strings with full paths for preview
  local items = {}
  for _, model in ipairs(models) do
    -- Format: display_name<TAB>full_path
    table.insert(items, model.display .. "\t" .. model.full_path)
  end

  -- Determine which previewer to use (bat with fallback to cat)
  local previewer_cmd = vim.fn.executable("bat") == 1 and "bat" or "cat"
  local preview_args = previewer_cmd == "bat" and "--theme=ansi --line-number --color=always" or ""

  fzf.fzf_exec(items, {
    prompt = "dbt Models> ",
    previewer = {
      cmd = previewer_cmd,
      args = preview_args,
    },
    winopts = {
      preview = {
        hidden = "nohidden",
        layout = "vertical",
        vertical = "up:50%",
      },
    },
    actions = {
      -- Default action: open file
      ["default"] = function(selected)
        -- Guard against nil or empty selection
        if not selected or #selected == 0 then return end

        -- Extract the model name from the first column (before the tab)
        local display = selected[1]:match("^([^\t]+)")
        if not display then return end

        -- Find the model by display name
        for i, model in ipairs(models) do
          if model.display == display then
            on_select(model, M.ACTIONS.open)
            break
          end
        end
      end,
      -- Custom action: preview compiled SQL (C-p)
      ["ctrl-p"] = function(selected)
        -- Guard against nil or empty selection
        if not selected or #selected == 0 then return end

        local display = selected[1]:match("^([^\t]+)")
        if not display then return end

        for i, model in ipairs(models) do
          if model.display == display then
            on_select(model, M.ACTIONS.preview)
            break
          end
        end
      end,
      -- Custom action: execute (C-x)
      ["ctrl-x"] = function(selected)
        -- Guard against nil or empty selection
        if not selected or #selected == 0 then return end

        local display = selected[1]:match("^([^\t]+)")
        if not display then return end

        for i, model in ipairs(models) do
          if model.display == display then
            on_select(model, M.ACTIONS.execute)
            break
          end
        end
      end,
      -- Custom action: build (C-b)
      ["ctrl-b"] = function(selected)
        -- Guard against nil or empty selection
        if not selected or #selected == 0 then return end

        local display = selected[1]:match("^([^\t]+)")
        if not display then return end

        for i, model in ipairs(models) do
          if model.display == display then
            on_select(model, M.ACTIONS.build)
            break
          end
        end
      end,
    },
  })
end

-- Main picker function
function M.pick_model(on_select)
  if M.config.picker == "fzf" then
    fzf_picker(on_select)
  else
    telescope_picker(on_select)
  end
end

-- Convenience wrapper: show picker and perform action
function M.open_model_picker()
  local picker_name = M.config.picker == "fzf" and "fzf-lua" or "Telescope"
  local help_text = M.config.picker == "fzf"
    and "↵:open | C-p:preview | C-x:execute | C-b:build"
    or "↵:open | C-p:preview | C-x:execute | C-b:build"

  vim.notify(string.format("[dbt-power] Opening %s model picker... (%s)", picker_name, help_text), vim.log.levels.INFO)

  M.pick_model(function(model, action)
    if action == M.ACTIONS.open then
      -- Open model file in current buffer
      vim.cmd("edit " .. model.full_path)
      vim.notify("[dbt-power] Opened model: " .. model.name, vim.log.levels.INFO)
    elseif action == M.ACTIONS.preview then
      -- Open model file and show compiled SQL preview
      vim.cmd("edit " .. model.full_path)
      require("dbt-power.dbt.compile").show_compiled_sql()
    elseif action == M.ACTIONS.execute then
      -- Open model file and execute it
      vim.cmd("edit " .. model.full_path)
      vim.schedule(function()
        require("dbt-power.dbt.execute").execute_with_dbt_show_command()
      end)
    elseif action == M.ACTIONS.build then
      -- Open model file and build it
      vim.cmd("edit " .. model.full_path)
      vim.schedule(function()
        require("dbt-power.dbt.build").build_current_model()
      end)
    end
  end)
end

-- Health check
function M.check()
  vim.health.start("dbt-power.picker")

  vim.health.info(string.format("Configured picker: %s", M.config.picker))

  if M.config.picker == "telescope" then
    local ok = pcall(require, "telescope")
    if ok then
      vim.health.ok("Telescope is installed and ready")
    else
      vim.health.error("Telescope not found (required for telescope picker mode)")
    end
  elseif M.config.picker == "fzf" then
    local ok = pcall(require, "fzf-lua")
    if ok then
      vim.health.ok("fzf-lua is installed and ready")
    else
      vim.health.error("fzf-lua not found (required for fzf picker mode)")
    end
  end

  -- Check for preview tool
  if vim.fn.executable("bat") == 1 then
    vim.health.ok("bat is installed (for syntax-highlighted preview)")
  else
    vim.health.warn("bat not found (preview will use plain cat)")
  end
end

return M
