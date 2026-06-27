local utils = require("utils")
local energy = require("energy")
local reactors = require("reactors")
local turbines = require("turbines")

local M = {}

-- Turbine control
M.TARGET_RPM = 1800
M.RPM_FLOW_UP = 1750
M.RPM_REENGAGE = 1750
M.RPM_DISENGAGE = 1700
M.RPM_FLOW_DOWN = 1825
M.MAX_RPM = 1850

-- Reactor control
M.ROD_STEP_ECO = 1
M.ROD_STEP_NORMAL = 3
M.ROD_STEP_FAST = 6

-- Flow steps based on distance from 1800 RPM
M.FLOW_STEP_FAR = 25      -- more than 100 RPM away
M.FLOW_STEP_MED = 10      -- 50-100 RPM away
M.FLOW_STEP_FINE = 5      -- 25-50 RPM away
M.FLOW_STEP_ULTRA = 1     -- 0-25 RPM away

-- Steam target
M.STEAM_SURPLUS_FACTOR = 1.10
M.STEAM_DEFICIT_FACTOR = 1.03

local function enabledReactorList(state, kind)
  local out = {}
  for i, r in ipairs(state.reactors or {}) do
    if r.enabled and (not kind or r.kind == kind) then
      table.insert(out, {idx = i, r = r})
    end
  end
  return out
end

local function totalSteamUse(state)
  return turbines.getTotalSteam(state.turbines or {})
end

local function totalSteamProduction(state)
  return reactors.getTotalSteamProduction(state.reactors or {})
end

local function getFlowStepByRpm(rpm)
  local diff = math.abs((rpm or 0) - M.TARGET_RPM)

  if diff > 100 then
    return M.FLOW_STEP_FAR
  elseif diff > 50 then
    return M.FLOW_STEP_MED
  elseif diff > 25 then
    return M.FLOW_STEP_FINE
  else
    return M.FLOW_STEP_ULTRA
  end
end

local function getLowestEnabledTurbineRPM(state)
  local lowest = nil

  for _, entry in ipairs(state.turbines or {}) do
    if entry.enabled then
      local rpm = turbines.getRPM(entry.p)
      if lowest == nil or rpm < lowest then
        lowest = rpm
      end
    end
  end

  return lowest or 0
end

local function controlTurbines(state, storageFull, cfg)
  local needsMoreSteam = false
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
      local engaged = turbines.getInductor(t)
      local step = getFlowStepByRpm(rpm)

      turbines.setActive(t, state.enabled)

      if storageFull and not cyanite then
        turbines.setInductor(t, false)
        turbines.setFlow(t, 0)

      else
        -- Hysteresis:
        -- <1700 RPM  : disengage
        -- 1700-1749  : increase flow, stay in previous engagement state
        -- >=1750 RPM : engage
        -- target      : 1800 RPM with finer flow steps near target

        if rpm < M.RPM_DISENGAGE then
          turbines.setInductor(t, false)
          turbines.setFlow(t, flow + math.max(step, M.FLOW_STEP_MED))
          needsMoreSteam = true

        elseif rpm < M.RPM_REENGAGE then
          if not engaged then
            turbines.setInductor(t, false)
          else
            turbines.setInductor(t, true)
          end

          turbines.setFlow(t, flow + step)
          needsMoreSteam = true

        else
          turbines.setInductor(t, true)

          if rpm < M.TARGET_RPM then
            turbines.setFlow(t, flow + step)
            if rpm < M.TARGET_RPM - 10 then
              needsMoreSteam = true
            end

          elseif rpm > M.TARGET_RPM then
            turbines.setFlow(t, flow - step)
          end
        end
      end
    end
  end

  return needsMoreSteam
end

local function setLaterReactorsIdle(list, startIndex)
  for i = startIndex, #list do
    reactors.setActive(list[i].r, false)
    reactors.setRods(list[i].r, 100)
    list[i].r.managedActive = false
  end
end

local function activeReactorNeedsMorePower(state, steamPct, steamOk, storageLow, turbinesNeedSteam)
  local use = totalSteamUse(state)
  local prod = totalSteamProduction(state)
  local lowestRpm = getLowestEnabledTurbineRPM(state)

  if storageLow then return true end
  if turbinesNeedSteam then return true end

  -- Turbine demand should drive the reactor.
  if lowestRpm > 0 and lowestRpm < 1780 then
    return true
  end

  -- If steam production is lower than current turbine consumption,
  -- pull rods out even if the steam buffer is not empty yet.
  if use > 0 then
    if prod <= 0 then
      if steamOk and steamPct < 0.65 then return true end
    elseif prod < use * M.STEAM_DEFICIT_FACTOR then
      return true
    end
  end

  if steamOk and steamPct < 0.35 then
    return true
  end

  return false
end

local function activeReactorShouldThrottle(state, steamPct, steamOk, storageMidHigh)
  local use = totalSteamUse(state)
  local prod = totalSteamProduction(state)
  local lowestRpm = getLowestEnabledTurbineRPM(state)

  if storageMidHigh then return true end

  -- Do not throttle while turbines are still below target.
  if lowestRpm > 0 and lowestRpm < 1790 then
    return false
  end

  -- If production is substantially above turbine demand, insert rods.
  if use > 0 and prod > use * M.STEAM_SURPLUS_FACTOR then
    return true
  end

  -- If buffer is already high, insert rods.
  if steamOk and steamPct > 0.75 then
    return true
  end

  return false
end

local function distributeActiveReactors(state, cfg, storageLow, storageHigh, storageMidHigh, steamPct, steamOk, turbinesNeedSteam)
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

  local use = totalSteamUse(state)
  local prod = totalSteamProduction(state)
  local lowestRpm = getLowestEnabledTurbineRPM(state)

  -- Load distribution: one active reactor first; add more only if demand cannot be met.
  local wanted = 1

  if use > 0 and prod > 0 and prod < use * 0.80 then
    wanted = cfg.operationMode == "NORMAL" and math.min(#list, 2) or 1
  end

  if lowestRpm > 0 and lowestRpm < 1650 then
    wanted = #list
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
      local baseStep = cfg.operationMode == "NORMAL" and M.ROD_STEP_NORMAL or M.ROD_STEP_ECO

      if activeReactorNeedsMorePower(state, steamPct, steamOk, storageLow, turbinesNeedSteam) then
        local step = baseStep

        -- Stronger pull-out when turbine RPM is far too low or steam production lags.
        if lowestRpm > 0 and lowestRpm < 1750 then
          step = M.ROD_STEP_FAST
        elseif use > 0 and prod > 0 and prod < use * 0.90 then
          step = M.ROD_STEP_FAST
        end

        reactors.setRods(r, rod - step)

      elseif activeReactorShouldThrottle(state, steamPct, steamOk, storageMidHigh) then
        local step = baseStep

        -- Stronger throttle only if production greatly exceeds demand and RPM is healthy.
        if use > 0 and prod > use * 1.50 and lowestRpm >= 1790 then
          step = M.ROD_STEP_FAST
        end

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

function M.update(state, cfg, L)
  L = L or {}

  if not state.enabled then
    for _, r in ipairs(state.reactors or {}) do reactors.setActive(r, false) end
    for _, t in ipairs(state.turbines or {}) do
      turbines.setActive(t.p, false)
      turbines.setInductor(t.p, false)
      turbines.setFlow(t.p, 0)
    end
    state.statusLine = L.statusSystemOff or "Anlage ausgeschaltet"
    return
  end

  if not cfg.auto then
    state.statusLine = L.statusManualMode or "Manueller Modus"
    return
  end

  local storagePct, storageOk = energy.getPercent(state.storage)
  local storageLow = storageOk and storagePct * 100 <= cfg.storageMin
  local storageHigh = storageOk and storagePct * 100 >= cfg.storageMax
  local storageMidHigh = storageOk and storagePct * 100 >= ((cfg.storageMin + cfg.storageMax) / 2)

  local steamPct, steamOk = reactors.getAverageSteamPercent(state.reactors)
  local storageFull = storageHigh and cfg.operationMode ~= "CYANITE"

  local turbinesNeedSteam = controlTurbines(state, storageFull, cfg)

  distributeActiveReactors(
    state,
    cfg,
    storageLow,
    storageHigh and cfg.operationMode ~= "CYANITE",
    storageMidHigh,
    steamPct,
    steamOk,
    turbinesNeedSteam
  )

  distributePassiveReactors(
    state,
    cfg,
    storageLow,
    storageHigh and cfg.operationMode ~= "CYANITE",
    storageMidHigh
  )

  if cfg.operationMode == "CYANITE" then
    state.statusLine = L.statusCyanite or "CYANITE: Fuel wird verbrannt, RPM geregelt"
  elseif cfg.operationMode == "NORMAL" then
    state.statusLine = L.statusNormal or "NORMAL: Lastverteilung aktiv"
  else
    state.statusLine = L.statusEco or "ECO: Lastverteilung aktiv"
  end
end

return M
