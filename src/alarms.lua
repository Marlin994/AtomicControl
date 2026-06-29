local energy = require("energy")
local reactors = require("reactors")
local turbines = require("turbines")

local M = {}

local function add(list, level, text)
  table.insert(list, {level = level, text = text})
end

local function getTargetRPM(cfg, entry)
  if not cfg or not entry or not entry.name then return 1800 end
  if type(cfg.turbineCalibrations) ~= "table" then return 1800 end

  local value = cfg.turbineCalibrations[entry.name]
  if type(value) == "table" then
    return tonumber(value.rpm) or 1800
  end

  return 1800
end

function M.evaluate(state, cfg, L)
  L = L or {}
  cfg = cfg or {}

  local alarms = {}

  if not state.storage then add(alarms, "ERROR", L.alarmNoStorage or "Kein Energiespeicher") end
  if not state.monitor then add(alarms, "ERROR", L.alarmNoMonitor or "Kein Monitor") end
  if #(state.reactors or {}) == 0 then add(alarms, "ERROR", L.alarmNoReactor or "Kein Reaktor") end

  local storagePct, storageOk = energy.getPercent(state.storage)
  if storageOk then
    if storagePct * 100 <= (cfg.storageMin or 30) then
      add(alarms, "WARN", L.alarmStorageLow or "Speicher unter MIN")
    elseif storagePct * 100 >= (cfg.storageMax or 90) and cfg.operationMode ~= "CYANITE" then
      add(alarms, "WARN", L.alarmStorageHigh or "Speicher ueber MAX")
    end
  end

  local activeTurbines = 0
  for i, t in ipairs(state.turbines or {}) do
    if t.enabled then
      activeTurbines = activeTurbines + 1

      local rpm = turbines.getRPM(t.p)
      local rf = turbines.getRF(t.p)
      local targetRPM = getTargetRPM(cfg, t)
      local diff = rpm - targetRPM

      if rpm > 0 and diff < -100 then add(alarms, "WARN", "T" .. i .. (L.alarmRpmLow or " RPM niedrig")) end
      if rpm > 0 and diff > 100 then add(alarms, "ERROR", "T" .. i .. (L.alarmRpmHigh or " RPM hoch")) end
      if rpm > targetRPM - 50 and rf <= 0 and turbines.getInductor(t.p) then add(alarms, "WARN", "T" .. i .. (L.alarmNoRF or " kein RF")) end
    end
  end

  local activeReactors = 0
  for i, r in ipairs(state.reactors or {}) do
    if r.enabled then
      activeReactors = activeReactors + 1

      if r.kind == "ACTIVE" and activeTurbines == 0 then
        add(alarms, "WARN", string.format(L.alarmActiveNoTurbine or "Aktiver R%d ohne Turbine", i))
      end

      if r.kind == "ACTIVE" and r.steamProduced == 0 and reactors.getRod(r) < 95 and reactors.getActive(r) then
        add(alarms, "WARN", string.format(L.alarmNoSteam or "R%d kein Dampf", i))
      end
    end
  end

  if activeReactors == 0 then add(alarms, "WARN", L.alarmAllReactorsOff or "Alle Reaktoren AUS") end

  state.alarms = alarms
  return alarms
end

function M.worstLevel(alarms)
  local worst = "OK"
  for _, a in ipairs(alarms or {}) do
    if a.level == "ERROR" then return "ERROR" end
    if a.level == "WARN" then worst = "WARN" end
  end
  return worst
end

return M
