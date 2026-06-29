local reactors = require("reactors")
local SteamManager = require("steammanager")
local TurbineController = require("turbinecontroller")
local ReactorCalibration = require("reactorcalibration")

local M = {}

local function deviceAutoEnabled(cfg, entry)
  if not entry or not entry.name then return true end
  if type(cfg) ~= "table" then return true end
  if type(cfg.deviceAutoEnabled) ~= "table" then
    cfg.deviceAutoEnabled = {}
    return true
  end

  local value = cfg.deviceAutoEnabled[entry.name]
  if value == nil then return true end
  return value and true or false
end


M.DEADBAND = 40
M.ROD_STEP_SMALL = 1
M.ROD_STEP_MED = 2
M.ROD_STEP_FAST = 4
M.ROD_STEP_EMERGENCY = 8

local function enabledActiveReactors(state, cfg)
  local out = {}

  for i, r in ipairs(state.reactors or {}) do
    if not deviceAutoEnabled(cfg, r) then
      r.enabled = false
      reactors.setActive(r, false)
      reactors.setRods(r, 100)
      r.managedActive = false
    elseif r.enabled and r.kind == "ACTIVE" then
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
  if errorAbs > M.DEADBAND then return M.ROD_STEP_SMALL end
  return 0
end

local function moveRodsToward(r, targetRod)
  local current = reactors.getRod(r)
  local delta = targetRod - current

  if math.abs(delta) <= 1 then
    reactors.setRods(r, targetRod)
  elseif delta > 0 then
    reactors.setRods(r, current + math.min(delta, 3))
  else
    reactors.setRods(r, current + math.max(delta, -3))
  end
end

local function calibratedControl(state, cfg, list, target)
  local remaining = target
  local usedAnyCalibration = false

  for _, e in ipairs(list) do
    local r = e.r
    local data = ReactorCalibration.getCalibration(cfg, r)

    if remaining > M.DEADBAND and data then
      usedAnyCalibration = true
      reactors.setActive(r, true)
      r.managedActive = true

      local rod, expectedSteam = ReactorCalibration.getRodForSteam(cfg, r, remaining)

      if rod then
        moveRodsToward(r, rod)
        remaining = remaining - (expectedSteam or 0)
      else
        reactors.setRods(r, 0)
      end
    else
      reactors.setActive(r, false)
      reactors.setRods(r, 100)
      r.managedActive = false
    end
  end

  return usedAnyCalibration
end

local function fallbackControl(state, cfg, list, storageLow, steamPct, steamOk, turbinesNeedSteam)
  local targetInfo = SteamManager.getTarget(state, cfg)
  local target = targetInfo.target or 0
  local production = SteamManager.getProduction(state)
  local lowestRpm = TurbineController.lowestRPM(state)

  local wanted = 1

  if target > 0 and production > 0 and production < target * 0.75 then
    wanted = math.min(#list, 2)
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
      elseif error > M.DEADBAND then
        reactors.setRods(r, rod - step)
      elseif error < -M.DEADBAND then
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

function M.update(state, cfg, storageHigh, storageLow, steamPct, steamOk, turbinesNeedSteam)
  local list = enabledActiveReactors(state, cfg)
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

  if target <= 0 then
    setIdle(list, 1)
    return
  end

  if calibratedControl(state, cfg, list, target) then
    return
  end

  fallbackControl(state, cfg, list, storageLow, steamPct, steamOk, turbinesNeedSteam)
end

return M
