local turbines = require("turbines")
local reactors = require("reactors")

local M = {}

M.RESERVE_NORMAL = 1.03
M.MEASURED_OVERRIDE_FACTOR = 1.08

local function getCalibration(cfg, entry)
  if not cfg or not entry or not entry.name then return nil end
  cfg.turbineCalibrations = cfg.turbineCalibrations or {}

  local value = cfg.turbineCalibrations[entry.name]
  if type(value) == "table" then return tonumber(value.flow) end
  return tonumber(value)
end

function M.getDemand(state, cfg)
  local measured = 0
  local calibrated = 0
  local demand = 0
  local calibratedCount = 0
  local uncalibratedCount = 0

  for _, entry in ipairs(state.turbines or {}) do
    if entry.enabled then
      local current = turbines.getSteam(entry.p) or 0
      local cal = getCalibration(cfg, entry)

      measured = measured + current

      if cal and cal > 0 then
        calibrated = calibrated + cal
        calibratedCount = calibratedCount + 1

        if current > cal * M.MEASURED_OVERRIDE_FACTOR then
          demand = demand + current
        else
          demand = demand + cal
        end
      else
        uncalibratedCount = uncalibratedCount + 1
        demand = demand + current
      end
    end
  end

  return {
    measured = measured,
    calibrated = calibrated,
    demand = demand,
    calibratedCount = calibratedCount,
    uncalibratedCount = uncalibratedCount
  }
end

function M.getTarget(state, cfg)
  local demand = M.getDemand(state, cfg)

  if cfg.operationMode == "CYANITE" then
    return {
      demand = demand,
      target = nil,
      reserve = nil
    }
  end

  return {
    demand = demand,
    target = demand.demand * M.RESERVE_NORMAL,
    reserve = M.RESERVE_NORMAL
  }
end

function M.getProduction(state)
  return reactors.getTotalSteamProduction(state.reactors or {})
end

return M
