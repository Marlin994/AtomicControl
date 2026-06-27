local utils = require("utils")
local energy = require("energy")
local reactors = require("reactors")
local turbines = require("turbines")

local M = {}

M.TARGET_RPM = 1800
M.MIN_RPM = 1750
M.MAX_RPM = 1850
M.ROD_STEP_ECO = 1
M.ROD_STEP_NORMAL = 4
M.FLOW_STEP = 25

local function enabledReactorList(state, kind)
  local out = {}
  for i, r in ipairs(state.reactors or {}) do
    if r.enabled and (not kind or r.kind == kind) then
      table.insert(out, {idx = i, r = r})
    end
  end
  return out
end

local function controlTurbines(state, storageFull, cfg)
  local needsSteam = false
  local cyanite = cfg.operationMode == "CYANITE"

  for _, entry in ipairs(state.turbines or {}) do
    local t = entry.p
    if not entry.enabled then
      turbines.setActive(t, false)
      turbines.setInductor(t, false)
      turbines.setFlow(t, 0)
    else
      local rpm = turbines.getRPM(t)
      local flow = turbines.getFlow(t)

      turbines.setActive(t, state.enabled)

      if storageFull and not cyanite then
        turbines.setInductor(t, false)
        turbines.setFlow(t, 0)
      elseif rpm < M.MIN_RPM then
        turbines.setInductor(t, false)
        turbines.setFlow(t, flow + (cyanite and M.FLOW_STEP * 2 or M.FLOW_STEP))
        needsSteam = true
      elseif rpm > M.MAX_RPM then
        turbines.setInductor(t, true)
        turbines.setFlow(t, flow - M.FLOW_STEP)
      else
        turbines.setInductor(t, true)
        if cyanite and rpm < M.TARGET_RPM - 10 then
          turbines.setFlow(t, flow + M.FLOW_STEP)
          needsSteam = true
        elseif cyanite and rpm > M.TARGET_RPM + 10 then
          turbines.setFlow(t, flow - M.FLOW_STEP)
        end
      end
    end
  end

  return needsSteam
end

local function setLaterReactorsIdle(list, startIndex)
  for i = startIndex, #list do
    reactors.setActive(list[i].r, false)
    reactors.setRods(list[i].r, 100)
    list[i].r.managedActive = false
  end
end

local function distributeActiveReactors(state, cfg, storageLow, storageHigh, steamPct, steamOk, turbinesNeedSteam)
  local list = enabledReactorList(state, "ACTIVE")
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
    setLaterReactorsIdle(list, 1)
    return
  end

  -- Lastverteilung:
  -- ECO: erst einen Reaktor nutzen; weitere erst bei anhaltendem Dampf-/Speichermangel.
  -- NORMAL: schneller weitere Reaktoren zuschalten.
  local wanted = 1
  if storageLow or turbinesNeedSteam or (steamOk and steamPct < 0.30) then
    wanted = cfg.operationMode == "NORMAL" and math.min(#list, 2) or 1
  end
  if steamOk and steamPct < 0.15 then
    wanted = #list
  end

  for i, e in ipairs(list) do
    local r = e.r
    if i <= wanted then
      reactors.setActive(r, true)
      r.managedActive = true
      local rod = reactors.getRod(r)
      if cfg.operationMode == "NORMAL" then
        if storageLow or turbinesNeedSteam or (steamOk and steamPct < 0.55) then
          reactors.setRods(r, rod - M.ROD_STEP_NORMAL)
        elseif steamOk and steamPct > 0.90 then
          reactors.setRods(r, rod + M.ROD_STEP_ECO)
        end
      else
        if storageLow or turbinesNeedSteam or (steamOk and steamPct < 0.35) then
          reactors.setRods(r, rod - M.ROD_STEP_ECO)
        elseif steamOk and steamPct > 0.75 then
          reactors.setRods(r, rod + M.ROD_STEP_ECO)
        end
      end
    else
      reactors.setActive(r, false)
      reactors.setRods(r, 100)
      r.managedActive = false
    end
  end
end

local function distributePassiveReactors(state, cfg, storageLow, storageHigh, storageMidHigh)
  local list = enabledReactorList(state, "PASSIVE")
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
    setLaterReactorsIdle(list, 1)
    return
  end

  -- Lastverteilung passiv:
  -- Erst ein Reaktor, weitere nur wenn der Speicher leer laeuft.
  local wanted = 1
  if storageLow and cfg.operationMode == "NORMAL" then wanted = math.min(#list, 2) end
  if storageLow and (state.storageNetRF or 0) < -1000 then wanted = #list end

  for i, e in ipairs(list) do
    local r = e.r
    if i <= wanted then
      reactors.setActive(r, true)
      r.managedActive = true
      local rod = reactors.getRod(r)
      if storageLow then
        reactors.setRods(r, rod - (cfg.operationMode == "NORMAL" and M.ROD_STEP_NORMAL or M.ROD_STEP_ECO))
      elseif storageMidHigh then
        reactors.setRods(r, rod + M.ROD_STEP_ECO)
      end
    else
      reactors.setActive(r, false)
      reactors.setRods(r, 100)
      r.managedActive = false
    end
  end
end

function M.update(state, cfg)
  if not state.enabled then
    for _, r in ipairs(state.reactors or {}) do reactors.setActive(r, false) end
    for _, t in ipairs(state.turbines or {}) do
      turbines.setActive(t.p, false)
      turbines.setInductor(t.p, false)
      turbines.setFlow(t.p, 0)
    end
    state.statusLine = "Anlage ausgeschaltet"
    return
  end

  if not cfg.auto then
    state.statusLine = "Manueller Modus"
    return
  end

  local storagePct, storageOk = energy.getPercent(state.storage)
  local storageLow = storageOk and storagePct * 100 <= cfg.storageMin
  local storageHigh = storageOk and storagePct * 100 >= cfg.storageMax
  local storageMidHigh = storageOk and storagePct * 100 >= ((cfg.storageMin + cfg.storageMax) / 2)

  local steamPct, steamOk = reactors.getAverageSteamPercent(state.reactors)
  local storageFull = storageHigh and cfg.operationMode ~= "CYANITE"

  local turbinesNeedSteam = controlTurbines(state, storageFull, cfg)

  distributeActiveReactors(state, cfg, storageLow, storageHigh and cfg.operationMode ~= "CYANITE", steamPct, steamOk, turbinesNeedSteam)
  distributePassiveReactors(state, cfg, storageLow, storageHigh and cfg.operationMode ~= "CYANITE", storageMidHigh)

  if cfg.operationMode == "CYANITE" then
    state.statusLine = "CYANITE: Fuel wird verbrannt, RPM geregelt"
  elseif cfg.operationMode == "NORMAL" then
    state.statusLine = "NORMAL: Lastverteilung aktiv"
  else
    state.statusLine = "ECO: Lastverteilung aktiv"
  end
end

return M
