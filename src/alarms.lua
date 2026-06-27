local energy = require("energy")
local reactors = require("reactors")
local turbines = require("turbines")

local M = {}

local function add(list, level, text)
  table.insert(list, {level = level, text = text})
end

function M.evaluate(state, cfg)
  local alarms = {}

  if not state.storage then
    add(alarms, "ERROR", "Kein Energiespeicher")
  end

  if not state.monitor then
    add(alarms, "ERROR", "Kein Monitor")
  end

  if #(state.reactors or {}) == 0 then
    add(alarms, "ERROR", "Kein Reaktor")
  end

  local storagePct, storageOk = energy.getPercent(state.storage)
  if storageOk then
    if storagePct * 100 <= (cfg.storageMin or 30) then
      add(alarms, "WARN", "Speicher unter MIN")
    elseif storagePct * 100 >= (cfg.storageMax or 90) and cfg.operationMode ~= "CYANITE" then
      add(alarms, "WARN", "Speicher ueber MAX")
    end
  end

  local activeTurbines = 0
  for i, t in ipairs(state.turbines or {}) do
    if t.enabled then
      activeTurbines = activeTurbines + 1
      local rpm = turbines.getRPM(t.p)
      local rf = turbines.getRF(t.p)
      if rpm > 0 and rpm < 1700 then add(alarms, "WARN", "T" .. i .. " RPM niedrig") end
      if rpm > 1900 then add(alarms, "ERROR", "T" .. i .. " RPM hoch") end
      if rpm > 1750 and rf <= 0 then add(alarms, "WARN", "T" .. i .. " kein RF") end
    end
  end

  local activeReactors = 0
  for i, r in ipairs(state.reactors or {}) do
    if r.enabled then
      activeReactors = activeReactors + 1
      if r.kind == "ACTIVE" and activeTurbines == 0 then
        add(alarms, "WARN", "Aktiver R" .. i .. " ohne Turbine")
      end
      if r.kind == "ACTIVE" and r.steamProduced == 0 and reactors.getRod(r) < 95 and reactors.getActive(r) then
        add(alarms, "WARN", "R" .. i .. " kein Dampf")
      end
    end
  end

  if activeReactors == 0 then add(alarms, "WARN", "Alle Reaktoren AUS") end

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
