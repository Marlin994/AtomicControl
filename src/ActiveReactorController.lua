local reactors = require("reactors")
local SteamManager = require("SteamManager")
local TurbineController = require("TurbineController")

local M = {}

M.ROD_STEP_SMALL = 1
M.ROD_STEP_MED = 2
M.ROD_STEP_FAST = 4
M.ROD_STEP_EMERGENCY = 8

local function enabledActiveReactors(state)
  local out = {}
  for i, r in ipairs(state.reactors or {}) do
    if r.enabled and r.kind == "ACTIVE" then
      table.insert(out, {idx = i, r = r})
    end
  end
  return out
end

local function setIdle(list, startIndex)
  for i = startIndex, #list do
    reactors.setActive(list[i].r, false)
    reactors.setRods(list[i].r, 100)
    list[i].r.managedActive = false
  end
end

local function rodStep(errorAbs)
  if errorAbs > 800 then return M.ROD_STEP_EMERGENCY end
  if errorAbs > 400 then return M.ROD_STEP_FAST end
  if errorAbs > 150 then return M.ROD_STEP_MED end
  if errorAbs > 40 then return M.ROD_STEP_SMALL end
  return 0
end

function M.update(state, cfg, storageHigh, storageLow, steamPct, steamOk, turbinesNeedSteam)
  local list = enabledActiveReactors(state)
  if #list == 0 then return end

  if cfg.operationMode == "CYANITE" then
    for _, e in ipairs(list) do
      reactors.setActive(e.r, true)
      reactors.setRods(e.r, 0)
      e.r.managedActive = true
    end
    return
  end

  if storageHigh then
    setIdle(list, 1)
    return
  end

  local targetInfo = SteamManager.getTarget(state, cfg)
  local target = targetInfo.target or 0
  local production = SteamManager.getProduction(state)
  local lowestRpm = TurbineController.lowestRPM(state)

  local wanted = 1
  if target > 0 and production > 0 and production < target * 0.75 then
    wanted = cfg.operationMode == "NORMAL" and math.min(#list, 2) or 1
  end
  if lowestRpm > 0 and lowestRpm < 1650 then wanted = #list end
  if steamOk and steamPct < 0.15 then wanted = #list end

  local error = target - production
  local step = rodStep(math.abs(error))

  if turbinesNeedSteam and step < M.ROD_STEP_MED then step = M.ROD_STEP_MED end
  if storageLow and step < M.ROD_STEP_FAST then step = M.ROD_STEP_FAST end

  for i, e in ipairs(list) do
    local r = e.r

    if i <= wanted then
      reactors.setActive(r, true)
      r.managedActive = true

      local rod = reactors.getRod(r)

      if target <= 0 then
        reactors.setRods(r, rod + M.ROD_STEP_FAST)
      elseif error > 40 then
        reactors.setRods(r, rod - step)
      elseif error < -40 then
        reactors.setRods(r, rod + step)
      else
        reactors.setRods(r, rod)
      end
    else
      reactors.setActive(r, false)
      reactors.setRods(r, 100)
      r.managedActive = false
    end
  end
end

return M
