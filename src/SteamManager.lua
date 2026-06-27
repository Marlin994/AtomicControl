local turbines = require("turbines")
local reactors = require("reactors")

local M = {}

M.RESERVE_ECO = 1.02
M.RESERVE_NORMAL = 1.05

local function getCalibration(cfg, entry)
  if not cfg or not entry or not entry.name then return nil end
  cfg.turbineCalibrations = cfg.turbineCalibrations or {}
  local v = cfg.turbineCalibrations[entry.name]
  if type(v) == "table" then return tonumber(v.flow) end
  return tonumber(v)
end

function M.getDemand(state, cfg)
  local measured = 0
  local calibrated = 0
  local demand = 0

  for _, entry in ipairs(state.turbines or {}) do
    if entry.enabled then
      local current = turbines.getSteam(entry.p) or 0
      local cal = getCalibration(cfg, entry)

      measured = measured + current

      if cal and cal > 0 then
        calibrated = calibrated + cal
        demand = demand + math.max(current, cal)
      else
        demand = demand + current
      end
    end
  end

  return {
    measured = measured,
    calibrated = calibrated,
    demand = demand
  }
end

function M.getTarget(state, cfg)
  local demand = M.getDemand(state, cfg)

  if cfg.operationMode == "CYANITE" then
    return { demand = demand, target = nil, reserve = nil }
  end

  local reserve = cfg.operationMode == "NORMAL" and M.RESERVE_NORMAL or M.RESERVE_ECO

  return {
    demand = demand,
    target = demand.demand * reserve,
    reserve = reserve
  }
end

function M.getProduction(state)
  return reactors.getTotalSteamProduction(state.reactors or {})
end

return M
