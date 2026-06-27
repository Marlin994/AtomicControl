local utils = require("utils")
local energy = require("energy")
local reactors = require("reactors")
local turbines = require("turbines")

local M = {}

-- Turbine RPM target
M.TARGET_RPM = 1800
M.RPM_DISENGAGE = 1700
M.RPM_REENGAGE = 1750
M.MAX_RPM = 1850

-- Reactor control
M.ROD_STEP_ECO = 1
M.ROD_STEP_NORMAL = 3
M.ROD_STEP_FAST = 6

-- Safety/efficiency floor for active reactors outside CYANITE.
-- Prevents the controller from pulling rods fully to 0% on oversized reactors.
M.ACTIVE_MIN_ROD = 10

-- Flow steps by RPM distance
M.FLOW_STEP_FAR = 25      -- more than 100 RPM away
M.FLOW_STEP_MED = 10      -- 50-100 RPM away
M.FLOW_STEP_FINE = 5      -- 25-50 RPM away
M.FLOW_STEP_ULTRA = 1     -- 0-25 RPM away

-- Calibration search mode
-- We do not wait for a perfectly stable 1800 RPM anymore.
-- Instead we search the crossing point around 1800 RPM.
M.CAL_UNDER_RPM = 1790
M.CAL_OVER_RPM = 1810
M.CAL_TIMEOUT_TICKS = 1200
M.CAL_FLOW_OFFSET = -5

-- After the crossing search we validate the candidate flow as a fixed value.
-- This catches rotor inertia overshoot, e.g. calibrated flow resulting in 1875 RPM.
M.CAL_VALIDATE_TICKS = 80
M.CAL_TARGET_LOW = 1785
M.CAL_TARGET_HIGH = 1815
M.CAL_MAX_VALIDATE_ROUNDS = 8

-- Steam target
M.STEAM_SURPLUS_FACTOR = 1.12
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

local function getCalibrationStepByRpm(rpm)
  local diff = math.abs((rpm or 0) - M.TARGET_RPM)

  -- Calibration is deliberately more conservative near the target,
  -- because the rotor continues to accelerate/decelerate slowly.
  if diff > 100 then
    return M.FLOW_STEP_MED
  elseif diff > 50 then
    return M.FLOW_STEP_FINE
  else
    return M.FLOW_STEP_ULTRA
  end
end

local function getCalibration(cfg, entry)
  if not cfg or not entry or not entry.name then return nil end
  cfg.turbineCalibrations = cfg.turbineCalibrations or {}
  local v = cfg.turbineCalibrations[entry.name]
  if type(v) == "table" then return tonumber(v.flow) end
  return tonumber(v)
end

local function setCalibration(cfg, entry, flow)
  if not cfg or not entry or not entry.name then return end
  cfg.turbineCalibrations = cfg.turbineCalibrations or {}
  cfg.turbineCalibrations[entry.name] = {
    flow = math.floor(flow or 0),
    rpm = M.TARGET_RPM,
    calibratedAt = os.epoch and os.epoch("utc") or os.clock()
  }
end

local function totalSteamUse(state)
  return turbines.getTotalSteam(state.turbines or {})
end

local function totalSteamProduction(state)
  return reactors.getTotalSteamProduction(state.reactors or {})
end

local function totalSteamDemand(state, cfg)
  local demand = 0
  for _, entry in ipairs(state.turbines or {}) do
    if entry.enabled then
      local calibrated = getCalibration(cfg, entry)
      local currentUse = turbines.getSteam(entry.p)
      if calibrated and calibrated > 0 then
        demand = demand + math.max(currentUse, calibrated)
      else
        demand = demand + currentUse
      end
    end
  end
  return demand
end

local function getLowestEnabledTurbineRPM(state)
  local lowest = nil
  for _, entry in ipairs(state.turbines or {}) do
    if entry.enabled then
      local rpm = turbines.getRPM(entry.p)
      if lowest == nil or rpm < lowest then lowest = rpm end
    end
  end
  return lowest or 0
end

function M.startCalibration(state, mode)
  if not state or not state.turbines then return false end
  local entry = state.turbines[state.selectedTurbine or 1]
  if not entry then return false end

  mode = mode or "fine"
  if mode ~= "coarse" and mode ~= "fine" then mode = "fine" end

  state.calibration = {
    active = true,
    mode = mode,
    turbineIndex = state.selectedTurbine or 1,
    turbineName = entry.name,
    ticks = 0,

    underFlow = nil,
    underRpm = nil,
    overFlow = nil,
    overRpm = nil,

    bestFlow = nil,
    bestRpm = nil,
    bestError = nil
  }

  if mode == "coarse" then
    state.statusLine = "Grobe Kalibrierung T" .. tostring(state.selectedTurbine) .. " gestartet"
  else
    state.statusLine = "Feine Kalibrierung T" .. tostring(state.selectedTurbine) .. " gestartet"
  end

  return true
end


local function controlCalibration(state, cfg, L)
  local cal = state.calibration
  if not cal or not cal.active then return false end

  local entry = state.turbines[cal.turbineIndex]
  if not entry or entry.name ~= cal.turbineName then
    state.calibration = nil
    state.statusLine = "Kalibrierung abgebrochen"
    return false
  end

  local t = entry.p
  local rpm = turbines.getRPM(t)
  local flow = turbines.getFlow(t)

  entry.enabled = true
  turbines.setActive(t, true)

  -- During calibration we want enough steam from the reactor.
  -- The normal storage based control is skipped while this function runs.
  for _, r in ipairs(state.reactors or {}) do
    if r.enabled and r.kind == "ACTIVE" then
      local steamPct, steamOk = reactors.getSteamPercent(r)

      if not steamOk or steamPct < 0.45 then
        reactors.setActive(r, true)
        reactors.setRods(r, reactors.getRod(r) - M.ROD_STEP_FAST)
      elseif steamPct > 0.80 then
        reactors.setRods(r, reactors.getRod(r) + M.ROD_STEP_NORMAL)
      else
        reactors.setActive(r, true)
      end
    end
  end

  -- Phase 2: fine validation.
  -- Only used for fine calibration.
  if cal.phase == "validate" then
    turbines.setInductor(t, true)
    turbines.setFlow(t, cal.candidateFlow or flow)

    cal.validateTicks = (cal.validateTicks or 0) + 1
    cal.validateRpmSum = (cal.validateRpmSum or 0) + rpm
    cal.validateRpmCount = (cal.validateRpmCount or 0) + 1

    if cal.validateTicks >= M.CAL_VALIDATE_TICKS then
      local avgRpm = cal.validateRpmSum / math.max(1, cal.validateRpmCount)
      local candidate = cal.candidateFlow or flow
      cal.validateRounds = (cal.validateRounds or 0) + 1

      if avgRpm >= M.CAL_TARGET_LOW and avgRpm <= M.CAL_TARGET_HIGH then
        setCalibration(cfg, entry, candidate)
        turbines.setFlow(t, candidate)
        turbines.setInductor(t, true)

        state.configDirty = true
        state.calibration = nil
        state.statusLine =
          "T" .. tostring(cal.turbineIndex) ..
          " fein kalibriert: " .. tostring(math.floor(candidate)) ..
          " mB/t bei " .. tostring(math.floor(avgRpm)) .. " RPM"
        return true
      end

      -- Correct candidate and validate again.
      local error = avgRpm - M.TARGET_RPM
      local correction = 1

      if math.abs(error) > 100 then
        correction = 20
      elseif math.abs(error) > 60 then
        correction = 10
      elseif math.abs(error) > 30 then
        correction = 5
      else
        correction = 2
      end

      if error > 0 then
        candidate = candidate - correction
      else
        candidate = candidate + correction
      end

      if candidate < 0 then candidate = 0 end

      cal.candidateFlow = candidate
      cal.validateTicks = 0
      cal.validateRpmSum = 0
      cal.validateRpmCount = 0

      if cal.validateRounds >= M.CAL_MAX_VALIDATE_ROUNDS then
        setCalibration(cfg, entry, candidate)
        turbines.setFlow(t, candidate)
        turbines.setInductor(t, true)

        state.configDirty = true
        state.calibration = nil
        state.statusLine =
          "T" .. tostring(cal.turbineIndex) ..
          " fein best: " .. tostring(math.floor(candidate)) ..
          " mB/t"
        return true
      end
    end

    state.statusLine =
      "Fein T" .. tostring(cal.turbineIndex) ..
      ": " .. tostring(math.floor(rpm)) ..
      " RPM @ " .. tostring(math.floor(cal.candidateFlow or flow)) .. " mB/t"

    return true
  end

  -- Phase 1: crossing search.
  local rpmError = math.abs((rpm or 0) - M.TARGET_RPM)
  if flow > 0 then
    if not cal.bestError or rpmError < cal.bestError then
      cal.bestError = rpmError
      cal.bestFlow = flow
      cal.bestRpm = rpm
    end
  end

  if rpm <= M.TARGET_RPM then
    cal.underFlow = flow
    cal.underRpm = rpm
  elseif rpm > M.TARGET_RPM and not cal.overFlow then
    cal.overFlow = flow
    cal.overRpm = rpm
  end

  -- If we have both sides of the crossing, calculate candidate.
  if cal.underFlow and cal.overFlow then
    local candidate = math.floor(((cal.underFlow + cal.overFlow) / 2) + M.CAL_FLOW_OFFSET)
    if candidate < 0 then candidate = 0 end

    if cal.mode == "coarse" then
      -- Coarse mode: fast result, no validation phase.
      setCalibration(cfg, entry, candidate)
      turbines.setFlow(t, candidate)
      turbines.setInductor(t, true)

      state.configDirty = true
      state.calibration = nil
      state.statusLine =
        "T" .. tostring(cal.turbineIndex) ..
        " grob kalibriert: " .. tostring(candidate) ..
        " mB/t (" .. math.floor(cal.underRpm or 0) ..
        "/" .. math.floor(cal.overRpm or 0) .. " RPM)"
      return true
    end

    -- Fine mode: validate fixed candidate flow.
    cal.phase = "validate"
    cal.candidateFlow = candidate
    cal.validateTicks = 0
    cal.validateRpmSum = 0
    cal.validateRpmCount = 0
    cal.validateRounds = 0

    turbines.setFlow(t, candidate)
    turbines.setInductor(t, true)

    state.statusLine = "Teste Fein T" .. tostring(cal.turbineIndex) .. ": " .. tostring(candidate) .. " mB/t"
    return true
  end

  -- Flow search.
  local step = getCalibrationStepByRpm(rpm)

  if rpm < M.RPM_DISENGAGE then
    turbines.setInductor(t, false)
    turbines.setFlow(t, flow + math.max(step, M.FLOW_STEP_MED))

  elseif rpm < M.RPM_REENGAGE then
    turbines.setInductor(t, false)
    turbines.setFlow(t, flow + step)

  else
    turbines.setInductor(t, true)

    if rpm < M.TARGET_RPM then
      turbines.setFlow(t, flow + step)
    elseif rpm > M.TARGET_RPM then
      turbines.setFlow(t, flow - math.max(1, step))
    end
  end

  cal.ticks = cal.ticks + 1

  if cal.ticks >= M.CAL_TIMEOUT_TICKS then
    -- Fallback
    if cal.bestFlow and cal.bestError and cal.bestError <= 100 then
      local candidate = math.floor(cal.bestFlow + M.CAL_FLOW_OFFSET)
      if candidate < 0 then candidate = 0 end

      if cal.mode == "coarse" then
        setCalibration(cfg, entry, candidate)
        turbines.setFlow(t, candidate)
        turbines.setInductor(t, true)

        state.configDirty = true
        state.statusLine = "T" .. tostring(cal.turbineIndex) .. " grob best: " .. tostring(candidate) .. " mB/t"
        state.calibration = nil
        return true
      end

      cal.phase = "validate"
      cal.candidateFlow = candidate
      cal.validateTicks = 0
      cal.validateRpmSum = 0
      cal.validateRpmCount = 0
      cal.validateRounds = 0

      turbines.setFlow(t, candidate)
      turbines.setInductor(t, true)

      state.statusLine = "Timeout: teste bestes Ergebnis " .. tostring(candidate) .. " mB/t"
      return true
    else
      state.statusLine = "Kalibrierung Timeout"
      state.calibration = nil
      return true
    end
  end

  local underText = "---"
  local overText = "---"
  if cal.underFlow then underText = tostring(math.floor(cal.underFlow)) .. "@" .. tostring(math.floor(cal.underRpm or 0)) end
  if cal.overFlow then overText = tostring(math.floor(cal.overFlow)) .. "@" .. tostring(math.floor(cal.overRpm or 0)) end

  local prefix = cal.mode == "coarse" and "Grob" or "Fein"
  state.statusLine =
    prefix .. " T" .. tostring(cal.turbineIndex) ..
    ": " .. math.floor(rpm) .. " RPM / " ..
    math.floor(flow) .. " mB/t U:" .. underText .. " O:" .. overText

  return true
end


local function applyCalibratedFlow(entry, cfg)
  local calibrated = getCalibration(cfg, entry)
  if not calibrated or calibrated <= 0 then return false end

  -- After calibration the turbine flow is fixed.
  -- RPM is no longer controlled by changing turbine flow.
  -- The reactor has to follow the calibrated turbine demand instead.
  turbines.setFlow(entry.p, calibrated)
  return true
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
      local calibrated = getCalibration(cfg, entry)

      turbines.setActive(t, state.enabled)

      if storageFull and not cyanite then
        -- Storage full:
        -- Disengage the turbine and close steam flow.
        -- When demand returns, calibrated turbines immediately go back to their fixed calibrated flow.
        turbines.setInductor(t, false)
        turbines.setFlow(t, 0)

      else
        local hasCalibration = applyCalibratedFlow(entry, cfg)

        if hasCalibration then
          -- Calibrated mode:
          -- Flow stays fixed at the learned value.
          -- Only the inductor is controlled with hysteresis.
          -- If RPM falls, request more steam from the reactor.
          if rpm < M.RPM_DISENGAGE then
            turbines.setInductor(t, false)
            needsMoreSteam = true

          elseif rpm < M.RPM_REENGAGE then
            -- Do not re-engage before 1750 RPM.
            if not engaged then
              turbines.setInductor(t, false)
            end
            needsMoreSteam = true

          else
            turbines.setInductor(t, true)

            if rpm < M.TARGET_RPM - 10 then
              needsMoreSteam = true
            end
          end

        else
          -- Uncalibrated mode:
          -- Use automatic flow control until the turbine has been calibrated.
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
              if rpm < M.TARGET_RPM - 10 then needsMoreSteam = true end
            elseif rpm > M.TARGET_RPM then
              turbines.setFlow(t, flow - step)
            end
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

local function setActiveRodsLimited(r, level, cfg)
  if cfg and cfg.operationMode == "CYANITE" then
    reactors.setRods(r, level)
  else
    reactors.setRods(r, utils.clamp(level, M.ACTIVE_MIN_ROD, 100))
  end
end

local function activeReactorNeedsMorePower(state, cfg, steamPct, steamOk, storageLow, turbinesNeedSteam)
  local demand = totalSteamDemand(state, cfg)
  local prod = totalSteamProduction(state)
  local lowestRpm = getLowestEnabledTurbineRPM(state)

  -- Speicher leer hat Prioritaet.
  if storageLow then return true end

  -- Wenn der Dampfpuffer gut gefuellt ist, nicht weiter hochfahren.
  -- Das verhindert, dass ein uebergrosser Reaktor komplett auf 0% Rods geht,
  -- nur weil die Turbine beim Hochlauf noch unter Ziel-RPM liegt.
  if steamOk and steamPct >= 0.55 then
    return false
  end

  -- Turbine fordert Dampf nur dann vom Reaktor an, wenn der Puffer nicht
  -- schon ausreichend gefuellt ist.
  if turbinesNeedSteam and (not steamOk or steamPct < 0.45) then
    return true
  end

  -- RPM unter Ziel ist nur dann ein Grund zum Hochfahren, wenn der Puffer
  -- niedrig ist. Sonst ist es meist Rotortraegheit, nicht Dampfmangel.
  if lowestRpm > 0 and lowestRpm < 1780 and (not steamOk or steamPct < 0.40) then
    return true
  end

  -- Wenn echte Produktionswerte verfuegbar sind, kann auf Nachfrage geregelt werden.
  if demand > 0 and prod > 0 and prod < demand * M.STEAM_DEFICIT_FACTOR then
    return true
  end

  -- Fallback ohne brauchbare Produktionswerte.
  if steamOk and steamPct < 0.30 then
    return true
  end

  return false
end


local function activeReactorShouldThrottle(state, cfg, steamPct, steamOk, storageMidHigh)
  local demand = totalSteamDemand(state, cfg)
  local prod = totalSteamProduction(state)
  local lowestRpm = getLowestEnabledTurbineRPM(state)

  if storageMidHigh then return true end

  -- Bei gutem Dampfpuffer drosseln, auch wenn die Turbine noch leicht
  -- unter 1800 liegt. Das verhindert Ueberproduktion bei grossen Reaktoren.
  if steamOk and steamPct > 0.60 then
    return true
  end

  -- Nur bei wirklich niedrigem RPM und niedrigem Puffer nicht drosseln.
  if lowestRpm > 0 and lowestRpm < 1750 and (not steamOk or steamPct < 0.45) then
    return false
  end

  if demand > 0 and prod > demand * M.STEAM_SURPLUS_FACTOR then
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

  local demand = totalSteamDemand(state, cfg)
  local prod = totalSteamProduction(state)
  local lowestRpm = getLowestEnabledTurbineRPM(state)

  local wanted = 1

  if demand > 0 and prod > 0 and prod < demand * 0.80 then
    wanted = cfg.operationMode == "NORMAL" and math.min(#list, 2) or 1
  end

  if lowestRpm > 0 and lowestRpm < 1650 and (not steamOk or steamPct < 0.35) then wanted = #list end
  if steamOk and steamPct < 0.15 then wanted = #list end

  for i, e in ipairs(list) do
    local r = e.r

    if i <= wanted then
      reactors.setActive(r, true)
      r.managedActive = true

      local rod = reactors.getRod(r)
      local baseStep = cfg.operationMode == "NORMAL" and M.ROD_STEP_NORMAL or M.ROD_STEP_ECO

      if activeReactorNeedsMorePower(state, cfg, steamPct, steamOk, storageLow, turbinesNeedSteam) then
        local step = baseStep
        if lowestRpm > 0 and lowestRpm < 1750 then
          step = M.ROD_STEP_FAST
        elseif demand > 0 and prod > 0 and prod < demand * 0.90 then
          step = M.ROD_STEP_FAST
        end
        setActiveRodsLimited(r, rod - step, cfg)

      elseif activeReactorShouldThrottle(state, cfg, steamPct, steamOk, storageMidHigh) then
        local step = baseStep
        if demand > 0 and prod > demand * 1.50 and lowestRpm >= 1790 then
          step = M.ROD_STEP_FAST
        end
        setActiveRodsLimited(r, rod + step, cfg)

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

  if controlCalibration(state, cfg, L) then return end

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

  if state.configDirty then
    state.statusLine = state.statusLine or "Config geaendert"
  elseif cfg.operationMode == "CYANITE" then
    state.statusLine = L.statusCyanite or "CYANITE: Fuel wird verbrannt, RPM geregelt"
  elseif cfg.operationMode == "NORMAL" then
    state.statusLine = L.statusNormal or "NORMAL: Lastverteilung aktiv"
  else
    state.statusLine = L.statusEco or "ECO: Lastverteilung aktiv"
  end
end

return M
