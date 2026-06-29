local utils = require("utils")
local energy = require("energy")
local reactors = require("reactors")
local turbines = require("turbines")
local alarms = require("alarms")
local control = require("control")

local M = {}

local buttons = {}

local PANEL_X1 = 62
local PANEL_X2 = 88

local LEFT_X1 = 62
local LEFT_X2 = 74
local RIGHT_X1 = 76
local RIGHT_X2 = 88

local SMALL_L1 = 62
local SMALL_L2 = 67
local SMALL_R1 = 83
local SMALL_R2 = 88

local function safeTable(value)
  if type(value) == "table" then return value end
  return {}
end

local function safeNumber(value, fallback)
  local n = tonumber(value)
  if n == nil then return fallback or 0 end
  return n
end

local function safeText(value, fallback)
  if value == nil then return fallback or "" end
  return tostring(value)
end

local function yesNo(value, L)
  L = L or {}
  return value and (L.yes or "JA") or (L.no or "NEIN")
end

local function getListItem(list, index)
  list = safeTable(list)
  index = safeNumber(index, 1)
  if #list < 1 then return nil end
  index = utils.clamp(index, 1, #list)
  return list[index]
end

local function clampSelection(state)
  state.reactors = safeTable(state.reactors)
  state.turbines = safeTable(state.turbines)

  state.selectedReactor = utils.clamp(state.selectedReactor or 1, 1, math.max(#state.reactors, 1))
  state.selectedTurbine = utils.clamp(state.selectedTurbine or 1, 1, math.max(#state.turbines, 1))

  state.reactorPage = utils.clamp(state.reactorPage or 1, 1, 999)
  state.turbinePage = utils.clamp(state.turbinePage or 1, 1, 999)
end

local function writeAt(mon, x, y, text, fg, bg)
  if not mon then return end
  local w, h = mon.getSize()
  x = utils.clamp(x or 1, 1, w)
  y = utils.clamp(y or 1, 1, h)
  mon.setCursorPos(x, y)
  mon.setTextColor(fg or colors.white)
  mon.setBackgroundColor(bg or colors.black)
  mon.write(tostring(text or ""))
end

local function drawBar(mon, x, y, width, percent, fg)
  percent = utils.clamp(percent or 0, 0, 1)
  width = math.max(1, math.floor(width or 1))

  local filled = math.floor(width * percent)
  local empty = width - filled

  writeAt(mon, x, y, "[", colors.white, colors.black)
  writeAt(mon, x + 1, y, string.rep("#", filled), fg or colors.lime, colors.black)
  writeAt(mon, x + 1 + filled, y, string.rep("-", empty), colors.gray, colors.black)
  writeAt(mon, x + width + 1, y, "]", colors.white, colors.black)
end

local function addButton(id, x1, y1, x2, y2, label, bg, action)
  buttons[id] = {
    x1 = x1,
    y1 = y1,
    x2 = x2,
    y2 = y2,
    label = tostring(label or ""),
    bg = bg or colors.gray,
    action = action
  }
end

local function drawButton(mon, b)
  if not mon or not b then return end

  local w, h = mon.getSize()
  local x1 = utils.clamp(b.x1 or 1, 1, w)
  local x2 = utils.clamp(b.x2 or x1, 1, w)
  local y1 = utils.clamp(b.y1 or 1, 1, h)
  local y2 = utils.clamp(b.y2 or y1, 1, h)

  if x2 < x1 then x1, x2 = x2, x1 end
  if y2 < y1 then y1, y2 = y2, y1 end

  local width = x2 - x1 + 1
  if width < 1 then return end

  mon.setBackgroundColor(b.bg or colors.gray)
  mon.setTextColor(colors.white)

  for y = y1, y2 do
    mon.setCursorPos(x1, y)
    mon.write(string.rep(" ", width))
  end

  local label = tostring(b.label or "")
  if #label > width then
    label = string.sub(label, 1, width)
  end

  local lx = x1 + math.floor((width - #label) / 2)
  local ly = y1 + math.floor((y2 - y1) / 2)

  writeAt(mon, lx, ly, label, colors.white, b.bg or colors.gray)
end

local function button(mon, id, x1, y1, x2, y2, label, bg, action)
  addButton(id, x1, y1, x2, y2, label, bg, action)
  drawButton(mon, buttons[id])
end

local function pageTitle(mon, title)
  writeAt(mon, PANEL_X1, 2, title, colors.yellow)
  writeAt(mon, PANEL_X1, 3, string.rep("-", PANEL_X2 - PANEL_X1 + 1), colors.gray)
end

local function setPage(state, page)
  state.menuPage = page or "main"
end

local function manualBlocked(state, cfg, L)
  if cfg and cfg.auto then
    state.statusLine = L.statusAutoBlocked or "Auto aktiv: Erst auf MANUAL wechseln"
    return true
  end
  return false
end

local function manualColor(cfg, base)
  if cfg and cfg.auto then return colors.gray end
  return base
end

local function isDeviceAutoEnabled(cfg, entry)
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

local function setDeviceAutoEnabled(cfg, state, entry, value)
  if type(cfg) ~= "table" then return end
  if not entry or not entry.name then return end

  cfg.deviceAutoEnabled = cfg.deviceAutoEnabled or {}
  cfg.deviceAutoEnabled[entry.name] = value and true or false

  if state then
    state.configDirty = true
  end
end

local function getTurbineCalibration(cfg, entry)
  if not cfg or not entry or not entry.name then return nil end
  if type(cfg.turbineCalibrations) ~= "table" then return nil end

  local value = cfg.turbineCalibrations[entry.name]
  if type(value) == "table" then
    return tonumber(value.flow)
  end

  return tonumber(value)
end

local function getTurbineTargetRPM(cfg, entry)
  if not cfg or not entry or not entry.name then return 1800 end
  if type(cfg.turbineCalibrations) ~= "table" then return 1800 end

  local value = cfg.turbineCalibrations[entry.name]
  if type(value) == "table" then
    return tonumber(value.rpm) or 1800
  end

  return 1800
end

local function setTurbineTargetRPM(cfg, state, entry, rpm)
  if not cfg or not entry or not entry.name then return false end

  rpm = utils.clamp(math.floor(tonumber(rpm) or 1800), 1200, 2200)

  cfg.turbineCalibrations = cfg.turbineCalibrations or {}

  local old = cfg.turbineCalibrations[entry.name]
  local cal = {}

  if type(old) == "table" then
    for k, v in pairs(old) do
      cal[k] = v
    end
  elseif tonumber(old) then
    cal.flow = tonumber(old)
  end

  cal.rpm = rpm
  cal.adjustedAt = os.epoch and os.epoch("utc") or os.clock()

  cfg.turbineCalibrations[entry.name] = cal

  if state then
    state.configDirty = true
    state.statusLine = "T" .. tostring(state.selectedTurbine or "?") .. " Soll-RPM: " .. tostring(rpm)
  end

  return true
end


local function setTurbineCalibration(cfg, entry, flow)
  if not cfg or not entry or not entry.name or not flow then return false end

  cfg.turbineCalibrations = cfg.turbineCalibrations or {}

  local old = cfg.turbineCalibrations[entry.name]
  local cal = {}

  if type(old) == "table" then
    for k, v in pairs(old) do
      cal[k] = v
    end
  end

  cal.flow = math.floor(flow)
  cal.rpm = tonumber(cal.rpm) or 1800
  cal.adjustedAt = os.epoch and os.epoch("utc") or os.clock()

  cfg.turbineCalibrations[entry.name] = cal
  return true
end

local function setSelectedReactor(state, index, reactorsPerPage)
  state.reactors = safeTable(state.reactors)
  if #state.reactors < 1 then
    state.selectedReactor = 1
    state.reactorPage = 1
    return
  end

  if index < 1 then index = #state.reactors end
  if index > #state.reactors then index = 1 end

  state.selectedReactor = index
  state.reactorPage = math.ceil(index / math.max(1, reactorsPerPage or 1))
end

local function setSelectedTurbine(state, index, turbinesPerPage)
  state.turbines = safeTable(state.turbines)
  if #state.turbines < 1 then
    state.selectedTurbine = 1
    state.turbinePage = 1
    return
  end

  if index < 1 then index = #state.turbines end
  if index > #state.turbines then index = 1 end

  state.selectedTurbine = index
  state.turbinePage = math.ceil(index / math.max(1, turbinesPerPage or 1))
end

local function drawMainMenu(mon, state, cfg, L)
  pageTitle(mon, L.mainMenu or "HAUPTMENUE")

  writeAt(mon, PANEL_X1, 5, L.system or "System", colors.lightGray)

  button(mon, "auto", LEFT_X1, 6, LEFT_X2, 8, cfg.auto and "AUTO" or (L.manual or "MANUAL"), cfg.auto and colors.green or colors.gray, function()
    cfg.auto = not cfg.auto
    state.configDirty = true
    state.statusLine = cfg.auto and (L.statusAutoEnabled or "Auto-Modus aktiviert") or (L.statusManualEnabled or "Manuell aktiviert")
  end)

  button(mon, "power", RIGHT_X1, 6, RIGHT_X2, 8, state.enabled and "AN" or "AUS", state.enabled and colors.green or colors.red, function()
    state.enabled = not state.enabled
    cfg.enabled = state.enabled
    state.configDirty = true
    state.statusLine = state.enabled and (L.statusSystemOn or "Anlage eingeschaltet") or (L.statusSystemOff or "Anlage ausgeschaltet")
  end)

  writeAt(mon, PANEL_X1, 10, L.mode or "Modus", colors.lightGray)

  button(mon, "mode", PANEL_X1, 11, PANEL_X2, 13, cfg.operationMode or "NORMAL", cfg.operationMode == "NORMAL" and colors.cyan or colors.red, function()
    if cfg.operationMode == "NORMAL" then
      cfg.operationMode = "CYANITE"
    else
      cfg.operationMode = "NORMAL"
    end

    state.configDirty = true
    state.statusLine = (L.statusMode or "Modus: ") .. cfg.operationMode
  end)

  writeAt(mon, PANEL_X1, 15, L.storage or "Speicher", colors.lightGray)

  writeAt(mon, PANEL_X1, 16, (L.reactorOnBelow or "Reaktor EIN ab") .. ": " .. tostring(cfg.storageMin) .. "%", colors.white)

  button(mon, "minDown", LEFT_X1, 17, LEFT_X2, 19, "-5%", colors.purple, function()
    cfg.storageMin = utils.clamp((cfg.storageMin or 30) - 5, 0, (cfg.storageMax or 90) - 5)
    state.configDirty = true
  end)

  button(mon, "minUp", RIGHT_X1, 17, RIGHT_X2, 19, "+5%", colors.purple, function()
    cfg.storageMin = utils.clamp((cfg.storageMin or 30) + 5, 0, (cfg.storageMax or 90) - 5)
    state.configDirty = true
  end)

  writeAt(mon, PANEL_X1, 21, (L.reactorOffAbove or "Reaktor AUS ab") .. ": " .. tostring(cfg.storageMax) .. "%", colors.white)

  button(mon, "maxDown", LEFT_X1, 22, LEFT_X2, 24, "-5%", colors.purple, function()
    cfg.storageMax = utils.clamp((cfg.storageMax or 90) - 5, (cfg.storageMin or 30) + 5, 100)
    state.configDirty = true
  end)

  button(mon, "maxUp", RIGHT_X1, 22, RIGHT_X2, 24, "+5%", colors.purple, function()
    cfg.storageMax = utils.clamp((cfg.storageMax or 90) + 5, (cfg.storageMin or 30) + 5, 100)
    state.configDirty = true
  end)

  writeAt(mon, PANEL_X1, 27, L.pages or "Seiten", colors.lightGray)

  button(mon, "pageReactors", PANEL_X1, 28, PANEL_X2, 30, L.reactors or "REAKTOREN", colors.brown, function()
    setPage(state, "reactors")
  end)

  button(mon, "pageTurbines", PANEL_X1, 32, PANEL_X2, 34, L.turbines or "TURBINEN", colors.brown, function()
    setPage(state, "turbines")
  end)

  button(mon, "pageOptions", PANEL_X1, 36, PANEL_X2, 38, L.options or "OPTIONEN", colors.brown, function()
    setPage(state, "options")
  end)
end

local function drawReactorMenu(mon, state, cfg, L, reactorsPerPage)
  pageTitle(mon, L.reactors or "REAKTOREN")

  local list = safeTable(state.reactors)
  local index = utils.clamp(state.selectedReactor or 1, 1, math.max(#list, 1))
  state.selectedReactor = index

  local r = getListItem(list, index)

  writeAt(mon, PANEL_X1, 5, (L.selected or "Auswahl") .. ": R" .. tostring(index) .. " / " .. tostring(math.max(#list, 1)), colors.lightGray)

  if r then
    local kind = r.kind == "ACTIVE" and (L.reactorActive or "AKTIV") or (L.reactorPassive or "PASSIV")
    local power = utils.clamp(100 - reactors.getRod(r), 0, 100)
    local autoAllowed = isDeviceAutoEnabled(cfg, r)

    writeAt(mon, PANEL_X1, 7, (L.type or "Typ") .. ": " .. kind, r.kind == "ACTIVE" and colors.cyan or colors.orange)
    writeAt(mon, PANEL_X1, 8, (L.status or "Status") .. ": " .. utils.boolText(r.enabled, L), r.enabled and colors.lime or colors.red)
    writeAt(mon, PANEL_X1, 9, (L.autoAllowed or "Auto erlaubt") .. ": " .. yesNo(autoAllowed, L), autoAllowed and colors.lime or colors.red)
    writeAt(mon, PANEL_X1, 10, (L.power or "Leistung") .. ": " .. tostring(power) .. "%", colors.white)

    if r.kind == "ACTIVE" then
      writeAt(mon, PANEL_X1, 11, (L.steamProduced or "Dampf-Prod") .. ": " .. tostring(math.floor(reactors.getSteamProduction(r))) .. " mB/t", colors.cyan)
    else
      writeAt(mon, PANEL_X1, 11, (L.rfPassive or "RF Passiv") .. ": " .. utils.formatRF(reactors.getRF(r)), colors.lime)
    end
  else
    writeAt(mon, PANEL_X1, 7, L.noReactors or "Keine Reaktoren gefunden", colors.red)
  end

  button(mon, "reactorPrev", SMALL_L1, 13, SMALL_L2, 15, "<", colors.blue, function()
    setSelectedReactor(state, (state.selectedReactor or 1) - 1, reactorsPerPage)
  end)

  button(mon, "reactorNext", SMALL_R1, 13, SMALL_R2, 15, ">", colors.blue, function()
    setSelectedReactor(state, (state.selectedReactor or 1) + 1, reactorsPerPage)
  end)

  button(mon, "reactorAutoToggle", PANEL_X1, 17, PANEL_X2, 19, L.autoAllowedToggle or "AUTO ERLAUBT", colors.cyan, function()
    local entry = getListItem(state.reactors, state.selectedReactor)
    if not entry then return end

    local newValue = not isDeviceAutoEnabled(cfg, entry)
    setDeviceAutoEnabled(cfg, state, entry, newValue)

    if cfg.auto and not newValue then
      entry.enabled = false
      reactors.setRods(entry, 100)
    end

    state.statusLine = (L.autoAllowed or "Auto erlaubt") .. ": " .. yesNo(newValue, L)
  end)

  button(mon, "reactorToggle", PANEL_X1, 21, PANEL_X2, 23, L.reactorToggle or "REAKTOR AN/AUS", manualColor(cfg, colors.brown), function()
    if manualBlocked(state, cfg, L) then return end

    local entry = getListItem(state.reactors, state.selectedReactor)
    if not entry then return end

    entry.enabled = not entry.enabled

    if not entry.enabled then
      reactors.setRods(entry, 100)
    end
  end)

  button(mon, "powerDown", LEFT_X1, 25, LEFT_X2, 27, L.powerDown or "LEIST -", manualColor(cfg, colors.gray), function()
    if manualBlocked(state, cfg, L) then return end

    local entry = getListItem(state.reactors, state.selectedReactor)
    if entry then
      reactors.setRods(entry, reactors.getRod(entry) + 1)
    end
  end)

  button(mon, "powerUp", RIGHT_X1, 25, RIGHT_X2, 27, L.powerUp or "LEIST +", manualColor(cfg, colors.gray), function()
    if manualBlocked(state, cfg, L) then return end

    local entry = getListItem(state.reactors, state.selectedReactor)
    if entry then
      reactors.setRods(entry, reactors.getRod(entry) - 1)
    end
  end)

  button(mon, "calReactor", PANEL_X1, 30, PANEL_X2, 32, L.calibrateReactor or "KAL REAK.", colors.orange, function()
    if control.startReactorCalibration(state) then
      setPage(state, "main")
    end
  end)

  button(mon, "backMainR", PANEL_X1, 45, PANEL_X2, 47, L.back or "ZURUECK", colors.gray, function()
    setPage(state, "main")
  end)
end

local function drawTurbineMenu(mon, state, cfg, L, turbinesPerPage)
  pageTitle(mon, L.turbines or "TURBINEN")

  local list = safeTable(state.turbines)
  local index = utils.clamp(state.selectedTurbine or 1, 1, math.max(#list, 1))
  state.selectedTurbine = index

  local t = getListItem(list, index)

  writeAt(mon, PANEL_X1, 5, (L.selected or "Auswahl") .. ": T" .. tostring(index) .. " / " .. tostring(math.max(#list, 1)), colors.lightGray)

  if t then
    local rpm = turbines.getRPM(t.p)
    local flow = turbines.getSteam(t.p)
    local rf = turbines.getRF(t.p)
    local calFlow = getTurbineCalibration(cfg, t)
    local targetRpm = getTurbineTargetRPM(cfg, t)
    local autoAllowed = isDeviceAutoEnabled(cfg, t)

    local tStatus = L.off or "AUS"
    local tStatusColor = colors.red

    if t.enabled then
      if turbines.getInductor(t.p) then
        tStatus = L.on or "AN"
        tStatusColor = colors.lime
      else
        tStatus = L.free or "FREI"
        tStatusColor = colors.orange
      end
    end

    writeAt(mon, PANEL_X1, 7, (L.status or "Status") .. ": " .. tStatus, tStatusColor)
    writeAt(mon, PANEL_X1, 8, (L.autoAllowed or "Auto erlaubt") .. ": " .. yesNo(autoAllowed, L), autoAllowed and colors.lime or colors.red)
    writeAt(mon, PANEL_X1, 9, "RPM: " .. tostring(math.floor(rpm)) .. " / " .. tostring(math.floor(targetRpm)), colors.white)
    writeAt(mon, PANEL_X1, 10, "Flow: " .. tostring(math.floor(flow)) .. " mB/t", colors.orange)
    writeAt(mon, PANEL_X1, 11, "Kal.: " .. (calFlow and tostring(math.floor(calFlow)) or "---") .. " mB/t", calFlow and colors.cyan or colors.gray)
    writeAt(mon, PANEL_X1, 12, "RF/t: " .. utils.formatRF(rf), colors.lime)
  else
    writeAt(mon, PANEL_X1, 7, L.noTurbines or "Keine Turbinen gefunden", colors.red)
  end

  button(mon, "turbPrev", SMALL_L1, 14, SMALL_L2, 16, "<", colors.blue, function()
    setSelectedTurbine(state, (state.selectedTurbine or 1) - 1, turbinesPerPage)
  end)

  button(mon, "turbNext", SMALL_R1, 14, SMALL_R2, 16, ">", colors.blue, function()
    setSelectedTurbine(state, (state.selectedTurbine or 1) + 1, turbinesPerPage)
  end)

  button(mon, "turbAutoToggle", PANEL_X1, 18, PANEL_X2, 20, L.autoAllowedToggle or "AUTO ERLAUBT", colors.cyan, function()
    local entry = getListItem(state.turbines, state.selectedTurbine)
    if not entry then return end

    local newValue = not isDeviceAutoEnabled(cfg, entry)
    setDeviceAutoEnabled(cfg, state, entry, newValue)

    if cfg.auto and not newValue then
      entry.enabled = false
      turbines.setFlow(entry.p, 0)
      turbines.setInductor(entry.p, false)
      turbines.setActive(entry.p, false)
    end

    state.statusLine = (L.autoAllowed or "Auto erlaubt") .. ": " .. yesNo(newValue, L)
  end)

  button(mon, "turbToggle", PANEL_X1, 22, PANEL_X2, 24, L.turbineToggle or "TURBINE AN/AUS", manualColor(cfg, colors.brown), function()
    if manualBlocked(state, cfg, L) then return end

    local entry = getListItem(state.turbines, state.selectedTurbine)
    if not entry then return end

    entry.enabled = not entry.enabled

    if not entry.enabled then
      turbines.setFlow(entry.p, 0)
      turbines.setInductor(entry.p, false)
      turbines.setActive(entry.p, false)
    end
  end)

  writeAt(mon, PANEL_X1, 25, L.targetRpm or "Soll-RPM", colors.lightGray)

  button(mon, "rpmDown10", LEFT_X1, 26, LEFT_X2, 28, "RPM -10", colors.purple, function()
    local entry = getListItem(state.turbines, state.selectedTurbine)
    if not entry then return end
    setTurbineTargetRPM(cfg, state, entry, getTurbineTargetRPM(cfg, entry) - 10)
  end)

  button(mon, "rpmUp10", RIGHT_X1, 26, RIGHT_X2, 28, "RPM +10", colors.purple, function()
    local entry = getListItem(state.turbines, state.selectedTurbine)
    if not entry then return end
    setTurbineTargetRPM(cfg, state, entry, getTurbineTargetRPM(cfg, entry) + 10)
  end)

  button(mon, "rpmDown1", LEFT_X1, 30, LEFT_X2, 32, "RPM -1", colors.purple, function()
    local entry = getListItem(state.turbines, state.selectedTurbine)
    if not entry then return end
    setTurbineTargetRPM(cfg, state, entry, getTurbineTargetRPM(cfg, entry) - 1)
  end)

  button(mon, "rpmUp1", RIGHT_X1, 30, RIGHT_X2, 32, "RPM +1", colors.purple, function()
    local entry = getListItem(state.turbines, state.selectedTurbine)
    if not entry then return end
    setTurbineTargetRPM(cfg, state, entry, getTurbineTargetRPM(cfg, entry) + 1)
  end)

  button(mon, "rpmUseCurrent", PANEL_X1, 34, PANEL_X2, 36, L.useCurrentRpm or "IST ALS SOLL", colors.cyan, function()
    local entry = getListItem(state.turbines, state.selectedTurbine)
    if not entry then return end
    setTurbineTargetRPM(cfg, state, entry, turbines.getRPM(entry.p))
  end)

  button(mon, "flowDown", LEFT_X1, 38, LEFT_X2, 40, L.flowDown or "FLOW -", cfg.auto and colors.cyan or colors.gray, function()
    local entry = getListItem(state.turbines, state.selectedTurbine)
    if not entry then return end

    if cfg.auto then
      local calibrated = getTurbineCalibration(cfg, entry)

      if calibrated then
        setTurbineCalibration(cfg, entry, math.max(0, calibrated - 1))
        state.configDirty = true
        state.statusLine = "Kal Flow T" .. tostring(state.selectedTurbine) .. ": " .. tostring(math.max(0, calibrated - 1)) .. " mB/t"
      else
        state.statusLine = "Turbine nicht kalibriert"
      end

      return
    end

    turbines.setFlow(entry.p, turbines.getFlow(entry.p) - 25)
  end)

  button(mon, "flowUp", RIGHT_X1, 38, RIGHT_X2, 40, L.flowUp or "FLOW +", cfg.auto and colors.cyan or colors.gray, function()
    local entry = getListItem(state.turbines, state.selectedTurbine)
    if not entry then return end

    if cfg.auto then
      local calibrated = getTurbineCalibration(cfg, entry)

      if calibrated then
        setTurbineCalibration(cfg, entry, calibrated + 1)
        state.configDirty = true
        state.statusLine = "Kal Flow T" .. tostring(state.selectedTurbine) .. ": " .. tostring(calibrated + 1) .. " mB/t"
      else
        state.statusLine = "Turbine nicht kalibriert"
      end

      return
    end

    turbines.setFlow(entry.p, turbines.getFlow(entry.p) + 25)
  end)

  button(mon, "calTurbine", PANEL_X1, 42, PANEL_X2, 44, L.calibrateTurbine or "KAL TURB.", colors.orange, function()
    if control.startCalibration(state) then
      setPage(state, "main")
    end
  end)

  button(mon, "backMainT", PANEL_X1, 45, PANEL_X2, 47, L.back or "ZURUECK", colors.gray, function()
    setPage(state, "main")
  end)
end

local function drawOptionsMenu(mon, state, cfg, L, rescanFn, languageFn, updateFn, totalSteamUse, totalSteamProd)
  pageTitle(mon, L.options or "OPTIONEN")

  local liveEff = state.steamTransferEfficiencyMeasured

  if not liveEff and totalSteamProd and totalSteamProd > 0 and totalSteamUse and totalSteamUse > 0 then
    liveEff = utils.clamp(totalSteamUse / totalSteamProd, 0.50, 1.10)
  end

  writeAt(mon, PANEL_X1, 5, L.optionsSystem or "System", colors.lightGray)

  button(mon, "optLang", PANEL_X1, 6, PANEL_X2, 8, (L.language or "SPRACHE") .. ": " .. string.upper(cfg.language or "de"), colors.blue, function()
    if languageFn then languageFn() end
  end)

  button(mon, "optRescan", PANEL_X1, 10, PANEL_X2, 12, L.rescan or "RESCAN", colors.brown, function()
    if rescanFn then rescanFn() end
    state.statusLine = L.statusRescan or "Peripherals neu gesucht"
  end)

  writeAt(mon, PANEL_X1, 15, L.optionsSteam or "Dampf", colors.lightGray)
  writeAt(mon, PANEL_X1, 16, (L.transferEfficiency or "Dampf-Eff") .. ": " .. string.format("%.1f%%", (tonumber(cfg.steamTransferEfficiency) or 1.00) * 100), colors.lightBlue)

  local liveText = "--"
  if liveEff then liveText = string.format("%.1f%%", liveEff * 100) end
  writeAt(mon, PANEL_X1, 17, (L.liveEfficiency or "Live") .. ": " .. liveText, liveEff and colors.lightBlue or colors.gray)

  button(mon, "optApplySteamEff", PANEL_X1, 18, PANEL_X2, 20, L.applyLiveEfficiency or "EFF UEBERN.", liveEff and colors.cyan or colors.gray, function()
    local measured = state.steamTransferEfficiencyMeasured

    if not measured and totalSteamProd and totalSteamProd > 0 and totalSteamUse and totalSteamUse > 0 then
      measured = utils.clamp(totalSteamUse / totalSteamProd, 0.50, 1.10)
    end

    if measured then
      cfg.steamTransferEfficiency = utils.clamp(measured, 0.50, 1.10)
      state.configDirty = true
      state.statusLine = (L.statusEfficiencyApplied or "Dampf-Eff uebernommen: ") .. string.format("%.1f%%", cfg.steamTransferEfficiency * 100)
    else
      state.statusLine = L.statusEfficiencyNoLive or "Kein Live-Wert verfuegbar"
    end
  end)

  button(mon, "optResetSteamEff", PANEL_X1, 22, PANEL_X2, 24, L.resetEfficiency or "EFF RESET", colors.gray, function()
    cfg.steamTransferEfficiency = 1.00
    state.configDirty = true
    state.statusLine = L.statusEfficiencyReset or "Dampf-Eff auf 100% gesetzt"
  end)

  writeAt(mon, PANEL_X1, 27, L.optionsMaintenance or "Wartung", colors.lightGray)

  button(mon, "optUpdate", PANEL_X1, 28, PANEL_X2, 30, L.update or "UPDATE", colors.purple, function()
    if updateFn then updateFn() end
  end)

  button(mon, "backMainO", PANEL_X1, 45, PANEL_X2, 47, L.back or "ZURUECK", colors.gray, function()
    setPage(state, "main")
  end)
end

local function drawControlPanel(mon, state, cfg, L, rescanFn, languageFn, updateFn, reactorsPerPage, turbinesPerPage, totalSteamUse, totalSteamProd)
  if state.showOptions then
    state.menuPage = "options"
    state.showOptions = false
  end

  state.menuPage = state.menuPage or "main"

  if state.menuPage == "reactors" then
    drawReactorMenu(mon, state, cfg, L, reactorsPerPage)
  elseif state.menuPage == "turbines" then
    drawTurbineMenu(mon, state, cfg, L, turbinesPerPage)
  elseif state.menuPage == "options" then
    drawOptionsMenu(mon, state, cfg, L, rescanFn, languageFn, updateFn, totalSteamUse, totalSteamProd)
  else
    state.menuPage = "main"
    drawMainMenu(mon, state, cfg, L)
  end
end

local function drawMainStatus(mon, state, cfg, L, storagePct, storageOk, steamPct, steamOk, turbineRF, passiveRF, totalRF, totalSteamUse, totalSteamProd)
  local mbPerRF = turbineRF > 0 and totalSteamUse / turbineRF or 0

  writeAt(mon, 2, 1, L.title or "ATOMICCONTROL", colors.yellow)
  writeAt(mon, 2, 2, string.rep("-", 54), colors.gray)

  writeAt(mon, 2, 4, (L.auto or "Auto") .. ": " .. utils.boolText(cfg.auto, L), cfg.auto and colors.lime or colors.orange)
  writeAt(mon, 16, 4, (L.system or "Anlage") .. ": " .. utils.boolText(state.enabled, L), state.enabled and colors.lime or colors.red)
  writeAt(mon, 34, 4, (L.mode or "Modus") .. ": " .. tostring(cfg.operationMode), cfg.operationMode == "NORMAL" and colors.cyan or colors.red)

  if storageOk then
    writeAt(mon, 2, 6, (L.storage or "Speicher") .. ": " .. math.floor(storagePct * 100) .. "%")
    drawBar(mon, 15, 6, 32, storagePct, storagePct * 100 >= cfg.storageMax and colors.red or colors.lime)
  else
    writeAt(mon, 2, 6, L.noStorage or "Speicher: NICHT GEFUNDEN", colors.red)
  end

  writeAt(mon, 2, 7, (L.minMax or "Min/Max") .. ": " .. tostring(cfg.storageMin) .. "% / " .. tostring(cfg.storageMax) .. "%")

  if steamOk then
    writeAt(mon, 2, 9, (L.steam or "Dampf") .. ":   " .. math.floor(steamPct * 100) .. "%")
    drawBar(mon, 15, 9, 32, steamPct, colors.cyan)
  else
    writeAt(mon, 2, 9, L.noSteam or "Dampf:   n/a", colors.gray)
  end

  writeAt(mon, 2, 11, (L.rfTurbines or "RF Turbinen") .. ": " .. utils.formatRF(turbineRF), colors.lime)
  writeAt(mon, 2, 12, (L.rfPassive or "RF Passiv") .. ":   " .. utils.formatRF(passiveRF), colors.lime)
  writeAt(mon, 2, 13, (L.rfTotal or "RF Gesamt") .. ":   " .. utils.formatRF(totalRF), colors.lime)
  writeAt(mon, 2, 14, (L.steamUsed or "Dampf-Verbr") .. ": " .. math.floor(totalSteamUse) .. " mB/t", colors.orange)
  writeAt(mon, 2, 15, (L.steamProduced or "Dampf-Prod") .. ":  " .. math.floor(totalSteamProd) .. " mB/t", colors.cyan)
  writeAt(mon, 2, 16, (L.efficiency or "Effizienz") .. ":   " .. string.format("%.4f", mbPerRF) .. " mB/RF", colors.cyan)
  writeAt(mon, 2, 17, (L.charge or "Ladung") .. ":      " .. utils.formatRF(state.storageInRF or 0), colors.cyan)
  writeAt(mon, 2, 18, (L.net or "Netto") .. ":       " .. utils.formatRF(state.storageNetRF or 0), (state.storageNetRF or 0) >= 0 and colors.lime or colors.red)

  local eff = tonumber(cfg.steamTransferEfficiency) or 1.00
  local measured = state.steamTransferEfficiencyMeasured

  if not measured and totalSteamProd and totalSteamProd > 0 and totalSteamUse and totalSteamUse > 0 then
    measured = utils.clamp(totalSteamUse / totalSteamProd, 0.50, 1.10)
  end

  local effLabel = L.transferEfficiency
  if not effLabel or effLabel == "transferEfficiency" then
    effLabel = "Dampf-Eff"
  end

  local txt = effLabel .. ": " .. string.format("%.1f%%", eff * 100)

  if measured then
    txt = txt .. " (" .. string.format("%.1f%%", measured * 100) .. ")"
  end

  writeAt(mon, 2, 19, utils.padRight(txt, 36), colors.lightBlue)

  local worst = alarms.worstLevel(state.alarms or {})
  local alarmColor = worst == "ERROR" and colors.red or (worst == "WARN" and colors.orange or colors.lime)
  writeAt(mon, 40, 18, (L.alarm or "Alarm") .. ": " .. worst, alarmColor)
end

local function drawReactorTable(mon, state, L)
  local list = safeTable(state.reactors)
  local reactorListStartY = 23
  local reactorListEndY = 27
  local reactorsPerPage = math.max(1, reactorListEndY - reactorListStartY + 1)
  local totalPages = math.max(1, math.ceil(math.max(#list, 1) / reactorsPerPage))

  state.reactorPage = utils.clamp(state.reactorPage or 1, 1, totalPages)

  local first = ((state.reactorPage - 1) * reactorsPerPage) + 1
  local last = math.min(#list, first + reactorsPerPage - 1)

  writeAt(mon, 2, 20, (L.reactors or "Reaktoren") .. ": " .. tostring(#list) .. " | " .. (L.selected or "Auswahl") .. ": R" .. tostring(state.selectedReactor) .. " | " .. (L.page or "Seite") .. " " .. tostring(state.reactorPage) .. "/" .. tostring(totalPages), colors.yellow)
  writeAt(mon, 2, 21, "Nr", colors.gray)
  writeAt(mon, 8, 21, "Typ", colors.gray)
  writeAt(mon, 18, 21, L.status or "Status", colors.gray)
  writeAt(mon, 29, 21, L.power or "Leistung", colors.gray)
  writeAt(mon, 43, 21, "RF/t", colors.gray)
  writeAt(mon, 2, 22, string.rep("-", 48), colors.gray)

  local y = reactorListStartY

  for i = first, last do
    local r = list[i]
    local selected = i == state.selectedReactor
    local kind = r.kind == "ACTIVE" and (L.reactorActive or "AKTIV") or (L.reactorPassive or "PASSIV")
    local power = utils.clamp(100 - reactors.getRod(r), 0, 100)

    writeAt(mon, 2, y, (selected and ">" or " ") .. "R" .. tostring(i), selected and colors.lime or colors.yellow)
    writeAt(mon, 8, y, utils.padRight(kind, 7), r.kind == "ACTIVE" and colors.cyan or colors.orange)
    writeAt(mon, 18, y, utils.padRight(utils.boolText(r.enabled, L), 6), r.enabled and colors.lime or colors.red)
    writeAt(mon, 29, y, utils.padLeft(tostring(power) .. "%", 8), colors.white)
    writeAt(mon, 43, y, utils.padLeft(utils.formatShort(reactors.getRF(r)), 8), colors.lime)

    y = y + 1
  end

  return reactorsPerPage
end

local function drawTurbineTable(mon, state, cfg, L, h)
  local list = safeTable(state.turbines)
  local listStartY = 32
  local listEndY = math.max(listStartY, h - 2)
  local turbinesPerPage = math.max(1, listEndY - listStartY + 1)
  local totalPages = math.max(1, math.ceil(math.max(#list, 1) / turbinesPerPage))

  state.turbinePage = utils.clamp(state.turbinePage or 1, 1, totalPages)

  local first = ((state.turbinePage - 1) * turbinesPerPage) + 1
  local last = math.min(#list, first + turbinesPerPage - 1)

  writeAt(mon, 2, 29, (L.turbines or "Turbinen") .. ": " .. tostring(#list) .. " | " .. (L.selected or "Auswahl") .. ": T" .. tostring(state.selectedTurbine) .. " | " .. (L.page or "Seite") .. " " .. tostring(state.turbinePage) .. "/" .. tostring(totalPages), colors.yellow)
  writeAt(mon, 2, 30, "Nr", colors.gray)
  writeAt(mon, 8, 30, L.status or "Status", colors.gray)
  writeAt(mon, 18, 30, "RPM/Soll", colors.gray)
  writeAt(mon, 31, 30, "Flow", colors.gray)
  writeAt(mon, 40, 30, "Kal.", colors.gray)
  writeAt(mon, 49, 30, "RF/t", colors.gray)
  writeAt(mon, 2, 31, string.rep("-", 56), colors.gray)

  local y = listStartY

  for i = first, last do
    local e = list[i]
    local rpm = turbines.getRPM(e.p)
    local rf = turbines.getRF(e.p)
    local targetRpm = getTurbineTargetRPM(cfg, e)

    local rpmColor = colors.lime
    if rpm < 1700 or rpm > 1850 then
      rpmColor = colors.red
    elseif rpm < 1750 then
      rpmColor = colors.orange
    end

    if rpm == 0 then
      rpmColor = colors.gray
    end

    local tStatus = L.off or "AUS"
    local tStatusColor = colors.red

    if e.enabled then
      if turbines.getInductor(e.p) then
        tStatus = L.on or "AN"
        tStatusColor = colors.lime
      else
        tStatus = L.free or "FREI"
        tStatusColor = colors.orange
      end
    end

    local calFlow = getTurbineCalibration(cfg, e)
    local calText = "---"

    if calFlow then
      calText = tostring(math.floor(calFlow))
    end

    writeAt(mon, 2, y, (i == state.selectedTurbine and ">" or " ") .. "T" .. tostring(i), i == state.selectedTurbine and colors.lime or colors.yellow)
    writeAt(mon, 8, y, utils.padRight(tStatus, 6), tStatusColor)
    writeAt(mon, 18, y, utils.padLeft(tostring(math.floor(rpm)) .. "/" .. tostring(math.floor(targetRpm)), 10), rpmColor)
    writeAt(mon, 31, y, utils.padLeft(math.floor(turbines.getFlow(e.p)), 6), colors.orange)
    writeAt(mon, 40, y, utils.padLeft(calText, 6), calFlow and colors.cyan or colors.gray)
    writeAt(mon, 49, y, utils.padLeft(utils.formatShort(rf), 7), colors.lime)

    y = y + 1
  end

  return turbinesPerPage
end

function M.draw(state, cfg, saveFn, rescanFn, L, languageFn, updateFn)
  if not state then return {} end
  cfg = cfg or {}
  L = L or {}

  buttons = {}

  local mon = state.monitor
  if not mon then return buttons end

  cfg.storageMin = safeNumber(cfg.storageMin, 30)
  cfg.storageMax = safeNumber(cfg.storageMax, 90)
  cfg.operationMode = cfg.operationMode or "NORMAL"
  cfg.deviceAutoEnabled = safeTable(cfg.deviceAutoEnabled)
  cfg.turbineCalibrations = safeTable(cfg.turbineCalibrations)

  if state.enabled == nil then
    state.enabled = cfg.enabled
    if state.enabled == nil then state.enabled = true end
  end

  clampSelection(state)

  local w, h = mon.getSize()

  local storagePct, storageOk = energy.getPercent(state.storage)
  local steamPct, steamOk = reactors.getAverageSteamPercent(state.reactors)
  local turbineRF = turbines.getTotalRF(state.turbines)
  local passiveRF = reactors.getTotalPassiveRF(state.reactors)
  local totalRF = turbineRF + passiveRF
  local totalSteamUse = turbines.getTotalSteam(state.turbines)
  local totalSteamProd = reactors.getTotalSteamProduction(state.reactors)

  mon.setTextScale(0.5)
  mon.setBackgroundColor(colors.black)
  mon.setTextColor(colors.white)
  mon.clear()

  drawMainStatus(mon, state, cfg, L, storagePct, storageOk, steamPct, steamOk, turbineRF, passiveRF, totalRF, totalSteamUse, totalSteamProd)

  local reactorsPerPage = drawReactorTable(mon, state, L)
  local turbinesPerPage = drawTurbineTable(mon, state, cfg, L, h)

  drawControlPanel(mon, state, cfg, L, rescanFn, languageFn, updateFn, reactorsPerPage, turbinesPerPage, totalSteamUse, totalSteamProd)

  writeAt(mon, 2, h, utils.padRight(state.statusLine or "", math.max(10, w - 2)), colors.lightGray)

  return buttons
end

function M.handleTouch(currentButtons, x, y)
  for _, b in pairs(currentButtons or buttons or {}) do
    if x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then
      if b.action then b.action() end
      return true
    end
  end

  return false
end

return M
