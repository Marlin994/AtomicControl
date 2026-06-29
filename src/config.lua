local M = {}

M.FILE = "reactor_turbine_controller.cfg"

local defaults = {
  version = 30,
  language = "de",
  languageSelected = false,
  autostartAsked = false,

  storageMin = 30,
  storageMax = 90,
  auto = true,
  enabled = true,
  operationMode = "NORMAL",
  steamTransferEfficiency = 1.00,

  selectedReactor = 1,
  selectedTurbine = 1,
  reactorPage = 1,
  turbinePage = 1,

  reactors = {},
  turbines = {},
  turbineCalibrations = {},
  reactorCalibrations = {},
  deviceAutoEnabled = {}
}

local function copyTable(tbl)
  local out = {}
  for k, v in pairs(tbl or {}) do
    if type(v) == "table" then
      out[k] = copyTable(v)
    else
      out[k] = v
    end
  end
  return out
end

function M.load()
  local cfg = copyTable(defaults)

  if fs.exists(M.FILE) then
    local ok, loaded = pcall(function()
      local h = fs.open(M.FILE, "r")
      local data = h.readAll()
      h.close()
      return textutils.unserialize(data)
    end)

    if ok and type(loaded) == "table" then
      for k, v in pairs(loaded) do
        cfg[k] = v
      end
    end
  end

  if type(cfg.reactors) ~= "table" then cfg.reactors = {} end
  if type(cfg.turbines) ~= "table" then cfg.turbines = {} end
  if type(cfg.turbineCalibrations) ~= "table" then cfg.turbineCalibrations = {} end
  if type(cfg.reactorCalibrations) ~= "table" then cfg.reactorCalibrations = {},
  deviceAutoEnabled = {} end

  if cfg.language ~= "de" and cfg.language ~= "en" then
    cfg.language = "de"
  end

  -- ECO was removed. Old ECO configs are migrated to NORMAL.
  if cfg.operationMode ~= "NORMAL" and cfg.operationMode ~= "CYANITE" then
    cfg.operationMode = "NORMAL"
  end

  cfg.steamTransferEfficiency = tonumber(cfg.steamTransferEfficiency) or 1.00
  if cfg.steamTransferEfficiency < 0.50 then cfg.steamTransferEfficiency = 0.50 end
  if cfg.steamTransferEfficiency > 1.10 then cfg.steamTransferEfficiency = 1.10 end

  return cfg
end

function M.save(cfg, state)
  if not cfg then return false end

  cfg.reactors = {}
  cfg.turbines = {}

  if type(cfg.turbineCalibrations) ~= "table" then cfg.turbineCalibrations = {} end
  if type(cfg.reactorCalibrations) ~= "table" then cfg.reactorCalibrations = {},
  deviceAutoEnabled = {} end

  if state then
    for _, r in ipairs(state.reactors or {}) do
      if r.name then cfg.reactors[r.name] = r.enabled end
    end

    for _, t in ipairs(state.turbines or {}) do
      if t.name then cfg.turbines[t.name] = t.enabled end
    end

    cfg.selectedReactor = state.selectedReactor or cfg.selectedReactor
    cfg.selectedTurbine = state.selectedTurbine or cfg.selectedTurbine
    cfg.reactorPage = state.reactorPage or cfg.reactorPage
    cfg.turbinePage = state.turbinePage or cfg.turbinePage
  end

  local ok = pcall(function()
    local h = fs.open(M.FILE, "w")
    h.write(textutils.serialize(cfg))
    h.close()
  end)

  return ok
end

return M
