local utils = require("utils")
local energy = require("energy")
local reactors = require("reactors")
local turbines = require("turbines")
local alarms = require("alarms")
local control = require("control")

local M = {}

local buttons = {}

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
  if not entry or not entry.name then return end
  if type(cfg) ~= "table" then return end

  cfg.deviceAutoEnabled = cfg.deviceAutoEnabled or {}
  cfg.deviceAutoEnabled[entry.name] = value and true or false

  if state then
    state.configDirty = true
  end
end


local function getTurbineCalibration(cfg, entry)
  if not cfg or not entry or not entry.name then return nil end
  if type(cfg.turbineCalibrations) ~= "table" then return nil end

  local v = cfg.turbineCalibrations[entry.name]
  if type(v) == "table" then
    return tonumber(v.flow)
  end

  return tonumber(v)
end

local function setTurbineCalibration(cfg, entry, flow)
  if not cfg or not entry or not entry.name or not flow then return false end
  cfg.turbineCalibrations = cfg.turbineCalibrations or {}

  cfg.turbineCalibrations[entry.name] = {
    flow = math.floor(flow),
    rpm = 1800,
    adjustedAt = os.epoch and os.epoch("utc") or os.clock()
  }

  return true
end

local function writeAt(mon, x, y, text, fg, bg)
  if not mon then return end
  mon.setCursorPos(x, y)
  mon.setTextColor(fg or colors.white)
  mon.setBackgroundColor(bg or colors.black)
  mon.write(tostring(text or ""))
end

local function drawBar(mon, x, y, w, percent, fg)
  percent = utils.clamp(percent or 0, 0, 1)
  local filled = math.floor(w * percent)
  local empty = w - filled
  writeAt(mon, x, y, "[", colors.white, colors.black)
  writeAt(mon, x + 1, y, string.rep("#", filled), fg or colors.lime, colors.black)
  writeAt(mon, x + 1 + filled, y, string.rep("-", empty), colors.gray, colors.black)
  writeAt(mon, x + w + 1, y, "]", colors.white, colors.black)
end

local function addButton(id, x1, y1, x2, y2, label, bg, action)
  buttons[id] = {x1=x1,y1=y1,x2=x2,y2=y2,label=label,bg=bg,action=action}
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
  if width <= 0 then return end

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

  local x = x1 + math.floor((width - #label) / 2)
  local y = y1 + math.floor((y2 - y1) / 2)

  writeAt(mon, x, y, label, colors.white, b.bg or colors.gray)
end

local function drawControlPanel(mon, state, cfg, saveFn, rescanFn, reactorsPerPage, turbinesPerPage, L, languageFn, updateFn, totalSteamUse, totalSteamProd)
  L = L or {}

  local panelX1, panelX2 = 62, 88
  local leftX1, leftX2 = 62, 74
  local rightX1, rightX2 = 76, 88
  local smallLeftA, smallLeftB, smallLeftC, smallLeftD = 62, 67, 69, 74
  local smallRightA, smallRightB, smallRightC, smallRightD = 76, 81, 83, 88

  local function button(id, x1, y1, x2, y2, label, bg, action)
    addButton(id, x1, y1, x2, y2, label, bg, action)
    drawButton(mon, buttons[id])
  end

  if state.showOptions then
    state.menuPage = "options"
    state.showOptions = false
  end

  state.menuPage = state.menuPage or "main"

  local function pageTitle(title)
    writeAt(mon, panelX1, 2, title, colors.yellow)
    writeAt(mon, panelX1, 3, string.rep("-", panelX2-panelX1+1), colors.gray)
  end

  local function go(page)
    state.menuPage = page
  end

  local function manualColor(base)
    if cfg.auto then return colors.gray end
    return base
  end

  local function manualBlocked()
    if cfg.auto then
      state.statusLine = L.statusAutoBlocked or "Auto aktiv: Erst auf MANUAL wechseln"
      return true
    end
    return false
  end

  local function drawMainMenu()
    pageTitle(L.mainMenu or "HAUPTMENUE")

    writeAt(mon, panelX1, 5, L.system or "System", colors.lightGray)
    button("auto", leftX1, 6, leftX2, 8, cfg.auto and "AUTO" or (L.manual or "MANUAL"), cfg.auto and colors.green or colors.gray, function()
      cfg.auto = not cfg.auto
      state.statusLine = cfg.auto and (L.statusAutoEnabled or "Auto-Modus aktiviert") or (L.statusManualEnabled or "Manuell aktiviert")
    end)

    button("power", rightX1, 6, rightX2, 8, state.enabled and "AN" or "AUS", state.enabled and colors.green or colors.red, function()
      state.enabled = not state.enabled
      cfg.enabled = state.enabled
      state.statusLine = state.enabled and (L.statusSystemOn or "Anlage eingeschaltet") or (L.statusSystemOff or "Anlage ausgeschaltet")
    end)

    writeAt(mon, panelX1, 10, L.mode or "Modus", colors.lightGray)
    button("mode", panelX1, 11, panelX2, 13, cfg.operationMode, cfg.operationMode=="NORMAL" and colors.cyan or colors.red, function()
      if cfg.operationMode == "NORMAL" then cfg.operationMode = "CYANITE" else cfg.operationMode = "NORMAL" end
      state.statusLine = (L.statusMode or "Modus: ") .. cfg.operationMode
    end)

    writeAt(mon, panelX1, 15, L.storage or "Speicher", colors.lightGray)
    writeAt(mon, panelX1, 16, (L.reactorOnBelow or "Reaktor EIN ab") .. ": " .. tostring(cfg.storageMin) .. "%", colors.white)
    button("minDown", leftX1, 17, leftX2, 19, "-5%", colors.purple, function() cfg.storageMin = utils.clamp(cfg.storageMin-5,0,cfg.storageMax-5) end)
    button("minUp", rightX1, 17, rightX2, 19, "+5%", colors.purple, function() cfg.storageMin = utils.clamp(cfg.storageMin+5,0,cfg.storageMax-5) end)

    writeAt(mon, panelX1, 21, (L.reactorOffAbove or "Reaktor AUS ab") .. ": " .. tostring(cfg.storageMax) .. "%", colors.white)
    button("maxDown", leftX1, 22, leftX2, 24, "-5%", colors.purple, function() cfg.storageMax = utils.clamp(cfg.storageMax-5,cfg.storageMin+5,100) end)
    button("maxUp", rightX1, 22, rightX2, 24, "+5%", colors.purple, function() cfg.storageMax = utils.clamp(cfg.storageMax+5,cfg.storageMin+5,100) end)

    writeAt(mon, panelX1, 27, L.pages or "Seiten", colors.lightGray)
    button("pageReactors", panelX1, 28, panelX2, 30, L.reactors or "REAKTOREN", colors.brown, function() go("reactors") end)
    button("pageTurbines", panelX1, 32, panelX2, 34, L.turbines or "TURBINEN", colors.brown, function() go("turbines") end)
    button("pageOptions", panelX1, 36, panelX2, 38, L.options or "OPTIONEN", colors.brown, function() go("options") end)
  end

  local function drawReactorMenu()
    pageTitle(L.reactors or "REAKTOREN")
    local r = state.reactors[state.selectedReactor]
    writeAt(mon, panelX1, 5, (L.selected or "Auswahl") .. ": R" .. tostring(state.selectedReactor) .. " / " .. tostring(math.max(#state.reactors, 1)), colors.lightGray)
    if r then
      local kind = r.kind=="ACTIVE" and (L.reactorActive or "AKTIV") or (L.reactorPassive or "PASSIV")
      local power = utils.clamp(100 - reactors.getRod(r), 0, 100)
      writeAt(mon, panelX1, 7, (L.type or "Typ") .. ": " .. kind, r.kind=="ACTIVE" and colors.cyan or colors.orange)
      writeAt(mon, panelX1, 8, (L.status or "Status") .. ": " .. utils.boolText(r.enabled,L), r.enabled and colors.lime or colors.red)
      writeAt(mon, panelX1, 9, (L.autoAllowed or "Auto erlaubt") .. ": " .. yesNo(isDeviceAutoEnabled(cfg, r)), isDeviceAutoEnabled(cfg, r) and colors.lime or colors.red)
      writeAt(mon, panelX1, 10, (L.power or "Leistung") .. ": " .. tostring(power) .. "%", colors.white)
      if r.kind == "ACTIVE" then
        writeAt(mon, panelX1, 11, (L.steamProduced or "Dampf-Prod") .. ": " .. tostring(math.floor(reactors.getSteamProduction(r))) .. " mB/t", colors.cyan)
      else
        writeAt(mon, panelX1, 11, (L.rfPassive or "RF Passiv") .. ": " .. utils.formatRF(reactors.getRF(r)), colors.lime)
      end
    else
      writeAt(mon, panelX1, 7, L.noReactors or "Keine Reaktoren gefunden", colors.red)
    end

    button("reactorPrev", smallLeftA, 12, smallLeftB, 14, "<", colors.blue, function()
      if #state.reactors>0 then state.selectedReactor=state.selectedReactor-1; if state.selectedReactor<1 then state.selectedReactor=#state.reactors end; state.reactorPage=math.ceil(state.selectedReactor/reactorsPerPage) end
    end)
    button("reactorNext", smallLeftC, 12, smallLeftD, 14, ">", colors.blue, function()
      if #state.reactors>0 then state.selectedReactor=state.selectedReactor+1; if state.selectedReactor>#state.reactors then state.selectedReactor=1 end; state.reactorPage=math.ceil(state.selectedReactor/reactorsPerPage) end
    end)
    button("reactorToggle", panelX1, 16, panelX2, 18, L.reactorToggle or "REAKTOR AN/AUS", manualColor(colors.brown), function()
      if manualBlocked() then return end
      local rr = state.reactors[state.selectedReactor]
      if rr then rr.enabled = not rr.enabled; if not rr.enabled then reactors.setRods(rr,100) end end
    end)
    button("powerDown", leftX1, 20, leftX2, 22, L.powerDown or "LEIST -", manualColor(colors.gray), function()
      if manualBlocked() then return end
      local rr = state.reactors[state.selectedReactor]; if rr then reactors.setRods(rr, reactors.getRod(rr)+1) end
    end)
    button("powerUp", rightX1, 20, rightX2, 22, L.powerUp or "LEIST +", manualColor(colors.gray), function()
      if manualBlocked() then return end
      local rr = state.reactors[state.selectedReactor]; if rr then reactors.setRods(rr, reactors.getRod(rr)-1) end
    end)
    button("calReactor", panelX1, 25, panelX2, 27, L.calibrateReactor or "KAL REAK.", colors.orange, function()
      if control.startReactorCalibration(state) then state.menuPage = "main" end
    end)
    button("backMainR", panelX1, 45, panelX2, 47, L.back or "ZURUECK", colors.gray, function() go("main") end)
  end

  local function drawTurbineMenu()
    pageTitle(L.turbines or "TURBINEN")
    local t = state.turbines[state.selectedTurbine]
    writeAt(mon, panelX1, 5, (L.selected or "Auswahl") .. ": T" .. tostring(state.selectedTurbine) .. " / " .. tostring(math.max(#state.turbines, 1)), colors.lightGray)
    if t then
      local rpm = turbines.getRPM(t.p)
      local flow = turbines.getSteam(t.p)
      local rf = turbines.getRF(t.p)
      local calFlow = getTurbineCalibration(cfg, t)
      local targetRpm = 1800
      if type(cfg.turbineCalibrations) == "table" and type(cfg.turbineCalibrations[t.name]) == "table" then targetRpm = tonumber(cfg.turbineCalibrations[t.name].rpm) or 1800 end
      local tStatus = L.off or "AUS"
      local tStatusColor = colors.red
      if t.enabled then
        if turbines.getInductor(t.p) then tStatus = L.on or "AN"; tStatusColor = colors.lime else tStatus = L.free or "FREI"; tStatusColor = colors.orange end
      end
      writeAt(mon, panelX1, 7, (L.status or "Status") .. ": " .. tStatus, tStatusColor)
      writeAt(mon, panelX1, 8, (L.autoAllowed or "Auto erlaubt") .. ": " .. yesNo(isDeviceAutoEnabled(cfg, t)), isDeviceAutoEnabled(cfg, t) and colors.lime or colors.red)
      writeAt(mon, panelX1, 9, "RPM: " .. tostring(math.floor(rpm)) .. " / " .. tostring(math.floor(targetRpm)), colors.white)
      writeAt(mon, panelX1, 10, "Flow: " .. tostring(math.floor(flow)) .. " mB/t", colors.orange)
      writeAt(mon, panelX1, 11, "Kal.: " .. (calFlow and tostring(math.floor(calFlow)) or "---") .. " mB/t", calFlow and colors.cyan or colors.gray)
      writeAt(mon, panelX1, 12, "RF/t: " .. utils.formatRF(rf), colors.lime)
    else
      writeAt(mon, panelX1, 7, L.noTurbines or "Keine Turbinen gefunden", colors.red)
    end
    button("turbPrev", smallRightA, 13, smallRightB, 15, "<", colors.blue, function()
      if #state.turbines>0 then state.selectedTurbine=state.selectedTurbine-1; if state.selectedTurbine<1 then state.selectedTurbine=#state.turbines end; state.turbinePage=math.ceil(state.selectedTurbine/turbinesPerPage) end
    end)
    button("turbNext", smallRightC, 13, smallRightD, 15, ">", colors.blue, function()
      if #state.turbines>0 then state.selectedTurbine=state.selectedTurbine+1; if state.selectedTurbine>#state.turbines then state.selectedTurbine=1 end; state.turbinePage=math.ceil(state.selectedTurbine/turbinesPerPage) end
    end)
    button("turbToggle", panelX1, 17, panelX2, 19, L.turbineToggle or "TURBINE AN/AUS", manualColor(colors.brown), function()
      if manualBlocked() then return end
      local tt = state.turbines[state.selectedTurbine]
      if tt then tt.enabled = not tt.enabled; if not tt.enabled then turbines.setFlow(tt.p,0); turbines.setInductor(tt.p,false); turbines.setActive(tt.p,false) end end
    end)
    button("flowDown", leftX1, 21, leftX2, 23, L.flowDown or "FLOW -", cfg.auto and colors.cyan or colors.gray, function()
      local tt = state.turbines[state.selectedTurbine]; if not tt then return end
      if cfg.auto then
        local calibrated = getTurbineCalibration(cfg, tt)
        if calibrated then setTurbineCalibration(cfg, tt, math.max(0, calibrated - 1)); state.configDirty = true; state.statusLine = "Kal Flow T" .. tostring(state.selectedTurbine) .. ": " .. tostring(math.max(0, calibrated - 1)) .. " mB/t" else state.statusLine = "Turbine nicht kalibriert" end
        return
      end
      turbines.setFlow(tt.p, turbines.getFlow(tt.p)-25)
    end)
    button("flowUp", rightX1, 21, rightX2, 23, L.flowUp or "FLOW +", cfg.auto and colors.cyan or colors.gray, function()
      local tt = state.turbines[state.selectedTurbine]; if not tt then return end
      if cfg.auto then
        local calibrated = getTurbineCalibration(cfg, tt)
        if calibrated then setTurbineCalibration(cfg, tt, calibrated + 1); state.configDirty = true; state.statusLine = "Kal Flow T" .. tostring(state.selectedTurbine) .. ": " .. tostring(calibrated + 1) .. " mB/t" else state.statusLine = "Turbine nicht kalibriert" end
        return
      end
      turbines.setFlow(tt.p, turbines.getFlow(tt.p)+25)
    end)
    button("calTurbine", panelX1, 26, panelX2, 28, L.calibrateTurbine or "KAL TURB.", colors.orange, function()
      if control.startCalibration(state) then state.menuPage = "main" end
    end)
    button("backMainT", panelX1, 45, panelX2, 47, L.back or "ZURUECK", colors.gray, function() go("main") end)
  end

  local function drawOptionsMenu()
    pageTitle(L.options or "OPTIONEN")
    local liveEff = state.steamTransferEfficiencyMeasured
    if (not liveEff) and totalSteamProd and totalSteamProd > 0 and totalSteamUse and totalSteamUse > 0 then liveEff = utils.clamp(totalSteamUse / totalSteamProd, 0.50, 1.10) end
    writeAt(mon, panelX1, 5, L.optionsSystem or "System", colors.lightGray)
    button("optLang", panelX1, 6, panelX2, 8, (L.language or "SPRACHE") .. ": " .. string.upper(cfg.language or "de"), colors.blue, function() if languageFn then languageFn() end end)
    button("optRescan", panelX1, 10, panelX2, 12, L.rescan or "RESCAN", colors.brown, function() if rescanFn then rescanFn() end; state.statusLine = L.statusRescan or "Peripherals neu gesucht" end)
    writeAt(mon, panelX1, 15, L.optionsSteam or "Dampf", colors.lightGray)
    writeAt(mon, panelX1, 16, (L.transferEfficiency or "Dampf-Eff") .. ": " .. string.format("%.1f%%", (tonumber(cfg.steamTransferEfficiency) or 1.00) * 100), colors.lightBlue)
    local liveText = "--"; if liveEff then liveText = string.format("%.1f%%", liveEff * 100) end
    writeAt(mon, panelX1, 17, (L.liveEfficiency or "Live") .. ": " .. liveText, liveEff and colors.lightBlue or colors.gray)
    button("optApplySteamEff", panelX1, 18, panelX2, 20, L.applyLiveEfficiency or "EFF UEBERN.", liveEff and colors.cyan or colors.gray, function()
      local measured = state.steamTransferEfficiencyMeasured
      if (not measured) and totalSteamProd and totalSteamProd > 0 and totalSteamUse and totalSteamUse > 0 then measured = utils.clamp(totalSteamUse / totalSteamProd, 0.50, 1.10) end
      if measured then cfg.steamTransferEfficiency = utils.clamp(measured, 0.50, 1.10); state.configDirty = true; state.statusLine = (L.statusEfficiencyApplied or "Dampf-Eff uebernommen: ") .. string.format("%.1f%%", cfg.steamTransferEfficiency * 100) else state.statusLine = L.statusEfficiencyNoLive or "Kein Live-Wert verfuegbar" end
    end)
    button("optResetSteamEff", panelX1, 22, panelX2, 24, L.resetEfficiency or "EFF RESET", colors.gray, function() cfg.steamTransferEfficiency = 1.00; state.configDirty = true; state.statusLine = L.statusEfficiencyReset or "Dampf-Eff auf 100% gesetzt" end)
    writeAt(mon, panelX1, 27, L.optionsMaintenance or "Wartung", colors.lightGray)
    button("optUpdate", panelX1, 28, panelX2, 30, L.update or "UPDATE", colors.purple, function() if updateFn then updateFn() end end)
    button("backMainO", panelX1, 45, panelX2, 47, L.back or "ZURUECK", colors.gray, function() go("main") end)
  end

  if state.menuPage == "reactors" then drawReactorMenu()
  elseif state.menuPage == "turbines" then drawTurbineMenu()
  elseif state.menuPage == "options" then drawOptionsMenu()
  else state.menuPage = "main"; drawMainMenu() end
end


function M.draw(state, cfg, saveFn, rescanFn, L, languageFn, updateFn)
  L = L or {}
  local mon = state.monitor
  buttons = {}
  if not mon then return buttons end
  local w,h = mon.getSize()

  state.selectedReactor = utils.clamp(state.selectedReactor or 1, 1, math.max(#state.reactors, 1))
  state.selectedTurbine = utils.clamp(state.selectedTurbine or 1, 1, math.max(#state.turbines, 1))
  state.reactorPage = utils.clamp(state.reactorPage or 1, 1, 999)
  state.turbinePage = utils.clamp(state.turbinePage or 1, 1, 999)

  local storagePct, storageOk = energy.getPercent(state.storage)
  local steamPct, steamOk = reactors.getAverageSteamPercent(state.reactors)
  local turbineRF = turbines.getTotalRF(state.turbines)
  local passiveRF = reactors.getTotalPassiveRF(state.reactors)
  local totalRF = turbineRF + passiveRF
  local totalSteamUse = turbines.getTotalSteam(state.turbines)
  local totalSteamProd = reactors.getTotalSteamProduction(state.reactors)
  local mbPerRF = turbineRF > 0 and totalSteamUse / turbineRF or 0

  mon.setTextScale(0.5)
  mon.setBackgroundColor(colors.black)
  mon.setTextColor(colors.white)
  mon.clear()

  writeAt(mon,2,1,L.title or "ATOMICCONTROL",colors.yellow)
  writeAt(mon,2,2,string.rep("-",54),colors.gray)
  writeAt(mon,2,4,(L.auto or "Auto")..": "..utils.boolText(cfg.auto,L),cfg.auto and colors.lime or colors.orange)
  writeAt(mon,16,4,(L.system or "Anlage")..": "..utils.boolText(state.enabled,L),state.enabled and colors.lime or colors.red)
  writeAt(mon,34,4,(L.mode or "Modus")..": "..cfg.operationMode,cfg.operationMode=="NORMAL" and colors.cyan or colors.red)

  if storageOk then
    writeAt(mon,2,6,(L.storage or "Speicher")..": "..math.floor(storagePct*100).."%")
    drawBar(mon,15,6,32,storagePct, storagePct*100>=cfg.storageMax and colors.red or colors.lime)
  else
    writeAt(mon,2,6,L.noStorage or "Speicher: NICHT GEFUNDEN",colors.red)
  end

  writeAt(mon,2,7,(L.minMax or "Min/Max")..": "..cfg.storageMin.."% / "..cfg.storageMax.."%")

  if steamOk then
    writeAt(mon,2,9,(L.steam or "Dampf")..":   "..math.floor(steamPct*100).."%")
    drawBar(mon,15,9,32,steamPct,colors.cyan)
  else
    writeAt(mon,2,9,L.noSteam or "Dampf:   n/a",colors.gray)
  end

  writeAt(mon,2,11,(L.rfTurbines or "RF Turbinen")..": "..utils.formatRF(turbineRF),colors.lime)
  writeAt(mon,2,12,(L.rfPassive or "RF Passiv")..":   "..utils.formatRF(passiveRF),colors.lime)
  writeAt(mon,2,13,(L.rfTotal or "RF Gesamt")..":   "..utils.formatRF(totalRF),colors.lime)
  writeAt(mon,2,14,(L.steamUsed or "Dampf-Verbr")..": "..math.floor(totalSteamUse).." mB/t",colors.orange)
  writeAt(mon,2,15,(L.steamProduced or "Dampf-Prod")..":  "..math.floor(totalSteamProd).." mB/t",colors.cyan)
  writeAt(mon,2,16,(L.efficiency or "Effizienz")..":   "..string.format("%.4f",mbPerRF).." mB/RF",colors.cyan)
  writeAt(mon,2,17,(L.charge or "Ladung")..":      "..utils.formatRF(state.storageInRF or 0),colors.cyan)
  writeAt(mon,2,18,(L.net or "Netto")..":       "..utils.formatRF(state.storageNetRF or 0),(state.storageNetRF or 0)>=0 and colors.lime or colors.red)

  do
    local eff = tonumber(cfg.steamTransferEfficiency) or 1.00
    local measured = state.steamTransferEfficiencyMeasured

    if not measured and totalSteamProd and totalSteamProd > 0 and totalSteamUse and totalSteamUse > 0 then
      measured = utils.clamp(totalSteamUse / totalSteamProd, 0.50, 1.10)
    end

    local label = L.transferEfficiency
    if not label or label == "transferEfficiency" then
      label = "Dampf-Eff"
    end

    local txt = label..": "..string.format("%.1f%%", eff * 100)

    if measured then
      txt = txt.." ("..string.format("%.1f%%", measured * 100)..")"
    end

    writeAt(mon,2,19,utils.padRight(txt,36),colors.lightBlue)
  end

  local worst = alarms.worstLevel(state.alarms or {})
  local ac = worst=="ERROR" and colors.red or (worst=="WARN" and colors.orange or colors.lime)
  writeAt(mon,40,18,(L.alarm or "Alarm")..": "..worst,ac)

  local reactorListStartY, reactorListEndY = 22, 27
  local reactorsPerPage = math.max(1, reactorListEndY-reactorListStartY+1)
  local totalReactorPages = math.max(1, math.ceil(math.max(#state.reactors,1)/reactorsPerPage))
  state.reactorPage = utils.clamp(state.reactorPage,1,totalReactorPages)
  local firstReactor = ((state.reactorPage-1)*reactorsPerPage)+1
  local lastReactor = math.min(#state.reactors, firstReactor+reactorsPerPage-1)

  writeAt(mon,2,20,(L.reactors or "Reaktoren")..": "..#state.reactors.." | "..(L.selected or "Auswahl")..": R"..state.selectedReactor.." | "..(L.page or "Seite").." "..state.reactorPage.."/"..totalReactorPages,colors.yellow)
  writeAt(mon,2,21,"Nr",colors.gray); writeAt(mon,8,21,"Typ",colors.gray); writeAt(mon,18,21,L.status or "Status",colors.gray); writeAt(mon,29,21,L.power or "Leistung",colors.gray); writeAt(mon,43,21,"RF/t",colors.gray)
  writeAt(mon,2,22,string.rep("-",48),colors.gray)
  local y=23
  for i=firstReactor,lastReactor do
    local r=state.reactors[i]
    local sel=i==state.selectedReactor
    local kind=r.kind=="ACTIVE" and (L.reactorActive or "AKTIV") or (L.reactorPassive or "PASSIV")
    writeAt(mon,2,y,(sel and ">" or " ").."R"..i, sel and colors.lime or colors.yellow)
    writeAt(mon,8,y,utils.padRight(kind,7), r.kind=="ACTIVE" and colors.cyan or colors.orange)
    writeAt(mon,18,y,utils.padRight(utils.boolText(r.enabled,L),6), r.enabled and colors.lime or colors.red)
    local power = utils.clamp(100 - reactors.getRod(r), 0, 100)
    writeAt(mon,29,y,utils.padLeft(power.."%",8),colors.white)
    writeAt(mon,43,y,utils.padLeft(utils.formatShort(reactors.getRF(r)),8),colors.lime)
    y=y+1
  end

  local listStartY = 30
  local listEndY = math.max(listStartY, h-2)
  local turbinesPerPage = math.max(1, listEndY-listStartY-1)
  local totalPages = math.max(1, math.ceil(math.max(#state.turbines,1)/turbinesPerPage))
  state.turbinePage = utils.clamp(state.turbinePage,1,totalPages)
  local firstTurbine = ((state.turbinePage-1)*turbinesPerPage)+1
  local lastTurbine = math.min(#state.turbines, firstTurbine+turbinesPerPage-1)

  writeAt(mon,2,29,(L.turbines or "Turbinen")..": "..#state.turbines.." | "..(L.selected or "Auswahl")..": T"..state.selectedTurbine.." | "..(L.page or "Seite").." "..state.turbinePage.."/"..totalPages,colors.yellow)
  writeAt(mon,2,30,"Nr",colors.gray)
  writeAt(mon,8,30,L.status or "Status",colors.gray)
  writeAt(mon,18,30,"RPM/Soll",colors.gray)
  writeAt(mon,31,30,"Flow",colors.gray)
  writeAt(mon,40,30,"Kal.",colors.gray)
  writeAt(mon,49,30,"RF/t",colors.gray)
  writeAt(mon,2,31,string.rep("-",56),colors.gray)
  y=32
  for i=firstTurbine,lastTurbine do
    local e=state.turbines[i]
    local rpm=turbines.getRPM(e.p)
    local steam=turbines.getSteam(e.p)
    local rf=turbines.getRF(e.p)
    local targetRpm = 1800
    if type(cfg.turbineCalibrations) == "table" and type(cfg.turbineCalibrations[e.name]) == "table" then
      targetRpm = tonumber(cfg.turbineCalibrations[e.name].rpm) or 1800
    end
    local rpmColor=colors.lime
    if rpm<1700 or rpm>1850 then rpmColor=colors.red elseif rpm<1750 then rpmColor=colors.orange end
    if rpm==0 then rpmColor=colors.gray end

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

    writeAt(mon,2,y,(i==state.selectedTurbine and ">" or " ").."T"..i, i==state.selectedTurbine and colors.lime or colors.yellow)
    writeAt(mon,8,y,utils.padRight(tStatus,6), tStatusColor)
    writeAt(mon,18,y,utils.padLeft(tostring(math.floor(rpm)).."/"..tostring(math.floor(targetRpm)),10),rpmColor)
    writeAt(mon,31,y,utils.padLeft(math.floor(turbines.getFlow(e.p)),6),colors.orange)
    writeAt(mon,40,y,utils.padLeft(calText,6),calFlow and colors.cyan or colors.gray)
    writeAt(mon,49,y,utils.padLeft(utils.formatShort(rf),7),colors.lime)
    y=y+1
  end

  drawControlPanel(mon, state, cfg, saveFn, rescanFn, reactorsPerPage, turbinesPerPage, L, languageFn, updateFn, totalSteamUse, totalSteamProd)

  for _, b in pairs(buttons) do drawButton(mon,b) end
  writeAt(mon,2,h,utils.padRight(state.statusLine or "", math.max(10,w-2)), colors.lightGray)

  return buttons
end

function M.handleTouch(buttons, x, y)
  for _, b in pairs(buttons or {}) do
    if x>=b.x1 and x<=b.x2 and y>=b.y1 and y<=b.y2 then
      b.action()
      return true
    end
  end
  return false
end

return M
