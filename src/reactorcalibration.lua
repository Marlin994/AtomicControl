local reactors = require("reactors")
local turbines = require("turbines")

local M = {}

-- Rod points to measure. 100 = fully inserted, 0 = full power.
M.ROD_POINTS = {100, 90, 80, 70, 60, 50, 40, 30, 20, 10, 0}

-- Each point is held for WARMUP_TICKS first, then averaged for SAMPLE_TICKS.
M.WARMUP_TICKS = 20
M.SAMPLE_TICKS = 20

M.TURBINE_CAL_FLOW = 2000

local function selectedActiveReactor(state)
  local r = state.reactors and state.reactors[state.selectedReactor or 1]
  if not r then return nil end
  if r.kind ~= "ACTIVE" then return nil end
  return r
end

local function ensureCfg(cfg)
  cfg.reactorCalibrations = cfg.reactorCalibrations or {}
end

local function saveTurbineState(state)
  local saved = {}

  for i, entry in ipairs(state.turbines or {}) do
    saved[i] = {
      enabled = entry.enabled,
      flow = turbines.getFlow(entry.p),
      inductor = turbines.getInductor(entry.p)
    }
  end

  return saved
end

local function restoreTurbineState(state, saved)
  if not saved then return end

  for i, entry in ipairs(state.turbines or {}) do
    local s = saved[i]

    if s then
      entry.enabled = s.enabled
      turbines.setFlow(entry.p, s.flow or 0)
      turbines.setInductor(entry.p, s.inductor and true or false)
      turbines.setActive(entry.p, s.enabled and true or false)
    end
  end
end

local function forceTurbinesForCalibration(state)
  for _, entry in ipairs(state.turbines or {}) do
    entry.enabled = true
    turbines.setActive(entry.p, true)
    turbines.setInductor(entry.p, true)
    turbines.setFlow(entry.p, M.TURBINE_CAL_FLOW)
  end
end

local function disableOtherActiveReactors(state, selected)
  for _, r in ipairs(state.reactors or {}) do
    if r ~= selected and r.kind == "ACTIVE" then
      reactors.setActive(r, false)
      reactors.setRods(r, 100)
    end
  end
end

function M.start(state)
  local r = selectedActiveReactor(state)

  if not r then
    state.statusLine = "Select an active reactor first"
    return false
  end

  state.reactorCalibration = {
    active = true,
    reactorIndex = state.selectedReactor or 1,
    reactorName = r.name,
    pointIndex = 1,
    warmup = M.WARMUP_TICKS,
    samplesLeft = M.SAMPLE_TICKS,
    sampleSum = 0,
    sampleCount = 0,
    points = {},
    savedTurbines = saveTurbineState(state)
  }

  state.statusLine = "Reactor calibration started"
  return true
end

function M.cancel(state)
  if state.reactorCalibration and state.reactorCalibration.savedTurbines then
    restoreTurbineState(state, state.reactorCalibration.savedTurbines)
  end

  state.reactorCalibration = nil
  state.statusLine = "Reactor calibration cancelled"
end

local function finish(state, cfg, r, cal)
  ensureCfg(cfg)

  cfg.reactorCalibrations[r.name] = {
    points = cal.points,
    calibratedAt = os.epoch and os.epoch("utc") or os.clock()
  }

  restoreTurbineState(state, cal.savedTurbines)

  reactors.setRods(r, 100)
  reactors.setActive(r, false)

  state.reactorCalibration = nil
  state.configDirty = true
  state.statusLine = "R" .. tostring(cal.reactorIndex) .. " calibrated"
end

function M.update(state, cfg)
  local cal = state.reactorCalibration
  if not cal or not cal.active then return false end

  local r = state.reactors and state.reactors[cal.reactorIndex]

  if not r or r.name ~= cal.reactorName then
    M.cancel(state)
    return true
  end

  forceTurbinesForCalibration(state)
  disableOtherActiveReactors(state, r)

  reactors.setActive(r, true)

  local rod = M.ROD_POINTS[cal.pointIndex]

  if rod == nil then
    finish(state, cfg, r, cal)
    return true
  end

  reactors.setRods(r, rod)

  if cal.warmup > 0 then
    cal.warmup = cal.warmup - 1
    state.statusLine = "Cal R" .. cal.reactorIndex .. " rod " .. rod .. "% warmup"
    return true
  end

  local steam = reactors.getSteamProduction(r) or 0
  cal.sampleSum = cal.sampleSum + steam
  cal.sampleCount = cal.sampleCount + 1
  cal.samplesLeft = cal.samplesLeft - 1

  state.statusLine = "Cal R" .. cal.reactorIndex .. " rod " .. rod .. "% steam " .. math.floor(steam) .. " mB/t"

  if cal.samplesLeft <= 0 then
    local avg = 0

    if cal.sampleCount > 0 then
      avg = cal.sampleSum / cal.sampleCount
    end

    table.insert(cal.points, {
      rod = rod,
      steam = math.floor(avg)
    })

    cal.pointIndex = cal.pointIndex + 1
    cal.warmup = M.WARMUP_TICKS
    cal.samplesLeft = M.SAMPLE_TICKS
    cal.sampleSum = 0
    cal.sampleCount = 0
  end

  return true
end

function M.getCalibration(cfg, reactor)
  if not cfg or not reactor or not reactor.name then return nil end
  cfg.reactorCalibrations = cfg.reactorCalibrations or {}

  local data = cfg.reactorCalibrations[reactor.name]

  if type(data) == "table" and type(data.points) == "table" then
    return data
  end

  return nil
end

local function sortedPoints(data)
  local points = {}

  for _, p in ipairs(data.points or {}) do
    if tonumber(p.rod) and tonumber(p.steam) then
      table.insert(points, {
        rod = tonumber(p.rod),
        steam = tonumber(p.steam)
      })
    end
  end

  table.sort(points, function(a, b)
    return a.steam < b.steam
  end)

  return points
end

function M.getMaxSteam(cfg, reactor)
  local data = M.getCalibration(cfg, reactor)
  if not data then return nil end

  local maxSteam = nil

  for _, p in ipairs(data.points or {}) do
    local steam = tonumber(p.steam)

    if steam and (not maxSteam or steam > maxSteam) then
      maxSteam = steam
    end
  end

  return maxSteam
end

function M.getRodForSteam(cfg, reactor, desiredSteam)
  local data = M.getCalibration(cfg, reactor)
  if not data then return nil end

  desiredSteam = tonumber(desiredSteam) or 0

  local points = sortedPoints(data)
  if #points == 0 then return nil end

  -- Prefer the smallest overproduction.
  for _, p in ipairs(points) do
    if p.steam >= desiredSteam then
      return p.rod, p.steam
    end
  end

  -- If demand is above the measured maximum, use max power.
  local best = points[#points]
  return best.rod, best.steam
end

return M
