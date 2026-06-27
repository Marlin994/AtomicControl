local utils = require("utils")
local energy = require("energy")
local reactors = require("reactors")
local turbines = require("turbines")

local M = {}

-- Turbine control
M.TARGET_RPM = 1800
M.RPM_FLOW_UP = 1750       -- below this: add steam flow
M.RPM_REENGAGE = 1750      -- re-engage generator/inductor from this RPM upward
M.RPM_DISENGAGE = 1700     -- below this: disengage generator/inductor
M.RPM_FLOW_DOWN = 1825     -- above this: reduce steam flow
M.MAX_RPM = 1850

-- Reactor control
M.ROD_STEP_ECO = 1
M.ROD_STEP_NORMAL = 3
M.ROD_STEP_FAST = 6
M.FLOW_STEP = 25

-- Aim to produce only slightly more steam than the turbines currently consume.
-- This prevents active reactors from sitting at 0% rods while the steam buffer rises.
M.STEAM_SURPLUS_FACTOR = 1.08
M.STEAM_DEFICIT_FACTOR = 0.96

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

      turbines.setActive(t, state.enabled)

      if storageFull and not cyanite then
        turbines.setInductor(t, false)
        turbines.setFlow(t, 0)

      else
        -- New hysteresis:
        -- <1700 RPM  : disengage to allow faster spin-up
        -- 1700-1749  : increase flow, but do not force disengage
        -- >=1750 RPM : engage/re-engage
        -- aim around 1800 RPM by nudging flow up/down

        if rpm < M.RPM_DISENGAGE then
          turbines.setInductor(t, false)
          turbines.setFlow(t, flow + (cyanite and M.FLOW_STEP * 2 or M.FLOW_STEP))
          needsMoreSteam = true

        elseif rpm < M.RPM_REENGAGE then
          -- Between 1700 and 1750: increase flow.
          -- If already disengaged, remain disengaged until 1750.
          if not engaged then
            turbines.setInductor(t, false)
          else
            turbines.setInductor(t, true)
          end

          turbines.setFlow(t, flow + M.FLOW_STEP)
          needsMoreSteam = true

        else
          -- At/above 1750: generator should be engaged.
          turbines.setInductor(t, true)

          if rpm < (M.TARGET_RPM - 10) then
            turbines.setFlow(t, flow + M.FLOW_STEP)
            needsMoreSteam = true

          elseif rpm > M.RPM_FLOW_DOWN then
            turbines.setFlow(t, flow - M.FLOW_STEP)

          elseif rpm > (M.TARGET_RPM + 10) then
            -- small correction, still uses same step for compatibility
            turbines.setFlow(t, flow - M.FLOW_STEP)
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

local function shouldIncreaseActiveReactor(state, steamPct, steamOk, storageLow)
  local use = totalSteamUse(state)
  local prod = totalSteamProduction(state)

  if storageLow then return true end

  -- If turbines consume steam but production is too low, withdraw rods.
  if use > 0 and prod > 0 and prod < use * M.STEAM_DEFICIT_FACTOR then
    return true
  end

  -- If we have no useful production reading, fall back to buffer level.
  if prod <= 0 and use > 0 and steamOk and steamPct < 0.45 then
    return true
  end

  if steamOk and steamPct < 0.25 then
    return true
  end

  return false
end

local function shouldDecreaseActiveReactor(state, steamPct, steamOk, storageMidHigh)
  local use = totalSteamUse(state)
  local prod = totalSteamProduction(state)

  if storageMidHigh then return true end

  -- If production is clearly higher than demand, insert rods.
  -- Example: reactor can make 5000 mB/t while turbines use 2000 mB/t.
  if use > 0 and prod > use * M.STEAM_SURPLUS_FACTOR then
    return true
  end

  -- If buffer is high, also insert rods.
  if steamOk and steamPct > 0.70 then
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

  -- Load distribution:
  -- Start with one active reactor. Add more only if steam buffer is low
  -- or production cannot keep up with turbine demand.
  local wanted = 1

  if use > 0 and prod > 0 and prod < use * 0.80 then
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
      local step = cfg.operationMode == "NORMAL" and M.ROD_STEP_NORMAL or M.ROD_STEP_ECO

      if shouldDecreaseActiveReactor(state, steamPct, steamOk, storageMidHigh) then
        -- Stronger correction if production is much higher than demand.
        local correction = step
        if use > 0 and prod > use * 1.50 then
          correction = M.ROD_STEP_FAST
        end
        reactors.setRods(r, rod + correction)

      elseif shouldIncreaseActiveReactor(state, steamPct, steamOk, storageLow) then
        reactors.setRods(r, rod - step)

      else
        -- Hold rods steady inside the balanced range.
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
