local utils = require("utils")
local energy = require("energy")
local reactors = require("reactors")
local turbines = require("turbines")
local alarms = require("alarms")
local control = require("control")

local M = {}

local buttons = {}

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
  mon.setBackgroundColor(b.bg)
  mon.setTextColor(colors.white)
  for y=b.y1,b.y2 do
    mon.setCursorPos(b.x1, y)
    mon.write(string.rep(" ", b.x2-b.x1+1))
  end
  local x = b.x1 + math.floor((b.x2-b.x1+1-#b.label)/2)
  local y = b.y1 + math.floor((b.y2-b.y1)/2)
  writeAt(mon, x, y, b.label, colors.white, b.bg)
end

local function drawControlPanel(mon, state, cfg, saveFn, rescanFn, reactorsPerPage, turbinesPerPage, L, languageFn, updateFn)
  L = L or {}

  local panelX1, panelX2 = 62, 88
  local leftX1, leftX2 = 62, 74
  local rightX1, rightX2 = 76, 88
  local smallLeftA, smallLeftB, smallLeftC, smallLeftD = 62, 67, 69, 74
  local smallRightA, smallRightB, smallRightC, smallRightD = 76, 81, 83, 88

  local function drawOptionsMenu()
    -- Options menu gets the full right panel.
    -- General controls are hidden while this menu is open.

    local liveEff = state.steamTransferEfficiencyMeasured
    if (not liveEff) and totalSteamProd and totalSteamProd > 0 and totalSteamUse and totalSteamUse > 0 then
      liveEff = utils.clamp(totalSteamUse / totalSteamProd, 0.50, 1.10)
    end

    writeAt(mon, panelX1, 2, L.options or "OPTIONEN", colors.yellow)
    writeAt(mon, panelX1, 3, string.rep("-", panelX2-panelX1+1), colors.gray)

    writeAt(mon, panelX1, 4, L.optionsSystem or "System", colors.lightGray)
    addButton("optLang", panelX1, 5, panelX2, 7, (L.language or "LANG") .. ": " .. string.upper(cfg.language or "de"), colors.blue, function()
      if languageFn then languageFn() end
      state.showOptions = false
    end)

    addButton("optRescan", panelX1, 9, panelX2, 11, L.rescan or "RESCAN", colors.brown, function()
      if rescanFn then rescanFn() end
      state.showOptions = false
      state.statusLine = L.statusRescan or "Peripherals neu gesucht"
    end)

    writeAt(mon, panelX1, 13, L.optionsCalibration or "Kalibrierung", colors.lightGray)
    addButton("optCalTurbine", panelX1, 14, panelX2, 16, L.calibrateTurbine or "KAL T", colors.orange, function()
      if control.startCalibration(state) then
        state.showOptions = false
      end
    end)

    addButton("optCalReactor", panelX1, 18, panelX2, 20, L.calibrateReactor or "KAL R", colors.orange, function()
      if control.startReactorCalibration(state) then
        state.showOptions = false
      end
    end)

    writeAt(mon, panelX1, 22, L.optionsSteam or "Dampf", colors.lightGray)
    local liveText = "--"
    if liveEff then
      liveText = string.format("%.1f%%", liveEff * 100)
    end
    writeAt(mon, panelX1, 23, (L.liveEfficiency or "Live") .. ": " .. liveText, liveEff and colors.lightBlue or colors.gray)

    addButton("optApplySteamEff", panelX1, 24, panelX2, 26, L.applyLiveEfficiency or "EFF UEBERN.", liveEff and colors.cyan or colors.gray, function()
      local measured = state.steamTransferEfficiencyMeasured

      if (not measured) and totalSteamProd and totalSteamProd > 0 and totalSteamUse and totalSteamUse > 0 then
        measured = utils.clamp(totalSteamUse / totalSteamProd, 0.50, 1.10)
      end

      if measured then
        cfg.steamTransferEfficiency = utils.clamp(measured, 0.50, 1.10)
        state.configDirty = true
        state.statusLine = (L.statusEfficiencyApplied or "Dampf-Eff uebernommen: ") .. string.format("%.1f%%", cfg.steamTransferEfficiency * 100)
        state.showOptions = false
      else
        state.statusLine = L.statusEfficiencyNoLive or "Kein Live-Wert verfuegbar"
      end
    end)

    writeAt(mon, panelX1, 28, L.optionsMaintenance or "Wartung", colors.lightGray)
    addButton("optUpdate", panelX1, 29, panelX2, 31, L.update or "UPDATE", colors.purple, function()
      if updateFn then updateFn() end
      state.showOptions = false
    end)

    addButton("optBack", panelX1, 45, panelX2, 47, L.back or "BACK", colors.gray, function()
      state.showOptions = false
    end)
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

  if state.showOptions then
    drawOptionsMenu()
    return
  end

  writeAt(mon, panelX1, 2, L.general or "ALLGEMEIN", colors.yellow)
  writeAt(mon, panelX1, 3, string.rep("-", panelX2-panelX1+1), colors.gray)

  addButton("auto", leftX1,4,leftX2,6,cfg.auto and "AUTO" or (L.manual or "MANUAL"), cfg.auto and colors.green or colors.gray, function()
    cfg.auto = not cfg.auto
    state.statusLine = cfg.auto and (L.statusAutoEnabled or "Auto-Modus aktiviert") or (L.statusManualEnabled or "Manuell aktiviert")
  end)

  addButton("power", rightX1,4,rightX2,6,state.enabled and "ON" or "OFF", state.enabled and colors.green or colors.red, function()
    state.enabled = not state.enabled
    cfg.enabled = state.enabled
    state.statusLine = state.enabled and (L.statusSystemOn or "Anlage eingeschaltet") or (L.statusSystemOff or "Anlage ausgeschaltet")
  end)

  addButton("mode", leftX1,8,rightX2,10,"MODUS: "..cfg.operationMode, cfg.operationMode=="NORMAL" and colors.cyan or colors.red, function()
    if cfg.operationMode == "NORMAL" then
      cfg.operationMode = "CYANITE"
    else
      cfg.operationMode = "NORMAL"
    end
    state.statusLine = (L.statusMode or "Modus: ") .. cfg.operationMode
  end)

  addButton("minDown", leftX1,12,leftX2,14,L.minDown or "MIN -", colors.purple, function() cfg.storageMin = utils.clamp(cfg.storageMin-5,0,cfg.storageMax-5) end)
  addButton("minUp", rightX1,12,rightX2,14,L.minUp or "MIN +", colors.purple, function() cfg.storageMin = utils.clamp(cfg.storageMin+5,0,cfg.storageMax-5) end)
  addButton("maxDown", leftX1,16,leftX2,18,L.maxDown or "MAX -", colors.purple, function() cfg.storageMax = utils.clamp(cfg.storageMax-5,cfg.storageMin+5,100) end)
  addButton("maxUp", rightX1,16,rightX2,18,L.maxUp or "MAX +", colors.purple, function() cfg.storageMax = utils.clamp(cfg.storageMax+5,cfg.storageMin+5,100) end)

  writeAt(mon, panelX1,20,string.rep("-", panelX2-panelX1+1), colors.gray)
  writeAt(mon, leftX1,21,L.reactor or "REAKTOR", colors.yellow)
  writeAt(mon, rightX1,21,L.turbine or "TURBINE", colors.yellow)

  addButton("reactorToggle", leftX1,23,leftX2,25,L.enabledToggle or "EIN/AUS", manualColor(colors.brown), function()
    if manualBlocked() then return end
    local r = state.reactors[state.selectedReactor]
    if r then r.enabled = not r.enabled; if not r.enabled then reactors.setRods(r,100) end end
  end)

  addButton("rodDown", leftX1,27,leftX2,29,L.rodDown or "-ROD", manualColor(colors.gray), function()
    if manualBlocked() then return end
    local r = state.reactors[state.selectedReactor]; if r then reactors.setRods(r, reactors.getRod(r)-1) end
  end)

  addButton("rodUp", leftX1,31,leftX2,33,L.rodUp or "+ROD", manualColor(colors.gray), function()
    if manualBlocked() then return end
    local r = state.reactors[state.selectedReactor]; if r then reactors.setRods(r, reactors.getRod(r)+1) end
  end)

  addButton("reactorDown", smallLeftA,35,smallLeftB,37,"^", colors.blue, function()
    if #state.reactors>0 then state.selectedReactor=state.selectedReactor-1; if state.selectedReactor<1 then state.selectedReactor=#state.reactors end; state.reactorPage=math.ceil(state.selectedReactor/reactorsPerPage) end
  end)

  addButton("reactorUp", smallLeftC,35,smallLeftD,37,"v", colors.blue, function()
    if #state.reactors>0 then state.selectedReactor=state.selectedReactor+1; if state.selectedReactor>#state.reactors then state.selectedReactor=1 end; state.reactorPage=math.ceil(state.selectedReactor/reactorsPerPage) end
  end)

  addButton("rPageDown", smallLeftA,39,smallLeftB,41,"<", colors.lightBlue, function()
    local pages=math.max(1, math.ceil(math.max(#state.reactors,1)/reactorsPerPage)); state.reactorPage=state.reactorPage-1; if state.reactorPage<1 then state.reactorPage=pages end; state.selectedReactor=((state.reactorPage-1)*reactorsPerPage)+1
  end)

  addButton("rPageUp", smallLeftC,39,smallLeftD,41,">", colors.lightBlue, function()
    local pages=math.max(1, math.ceil(math.max(#state.reactors,1)/reactorsPerPage)); state.reactorPage=state.reactorPage+1; if state.reactorPage>pages then state.reactorPage=1 end; state.selectedReactor=((state.reactorPage-1)*reactorsPerPage)+1
  end)

  addButton("turbToggle", rightX1,23,rightX2,25,L.enabledToggle or "EIN/AUS", manualColor(colors.brown), function()
    if manualBlocked() then return end
    local t = state.turbines[state.selectedTurbine]
    if t then t.enabled = not t.enabled; if not t.enabled then turbines.setFlow(t.p,0); turbines.setInductor(t.p,false); turbines.setActive(t.p,false) end end
  end)

  addButton("flowDown", rightX1,27,rightX2,29,L.flowDown or "-FLOW", cfg.auto and colors.cyan or colors.gray, function()
    local t = state.turbines[state.selectedTurbine]
    if not t then return end

    if cfg.auto then
      local calibrated = getTurbineCalibration(cfg, t)
      if calibrated then
        setTurbineCalibration(cfg, t, math.max(0, calibrated - 1))
        state.configDirty = true
        state.statusLine = "Kal Flow T" .. tostring(state.selectedTurbine) .. ": " .. tostring(math.max(0, calibrated - 1)) .. " mB/t"
      else
        state.statusLine = "Turbine nicht kalibriert"
      end
      return
    end

    local tObj = t.p
    turbines.setFlow(tObj, turbines.getFlow(tObj)-25)
  end)

  addButton("flowUp", rightX1,31,rightX2,33,L.flowUp or "+FLOW", cfg.auto and colors.cyan or colors.gray, function()
    local t = state.turbines[state.selectedTurbine]
    if not t then return end

    if cfg.auto then
      local calibrated = getTurbineCalibration(cfg, t)
      if calibrated then
        setTurbineCalibration(cfg, t, calibrated + 1)
        state.configDirty = true
        state.statusLine = "Kal Flow T" .. tostring(state.selectedTurbine) .. ": " .. tostring(calibrated + 1) .. " mB/t"
      else
        state.statusLine = "Turbine nicht kalibriert"
      end
      return
    end

    local tObj = t.p
    turbines.setFlow(tObj, turbines.getFlow(tObj)+25)
  end)

  addButton("turbDown", smallRightA,35,smallRightB,37,"^", colors.blue, function()
    if #state.turbines>0 then state.selectedTurbine=state.selectedTurbine-1; if state.selectedTurbine<1 then state.selectedTurbine=#state.turbines end; state.turbinePage=math.ceil(state.selectedTurbine/turbinesPerPage) end
  end)

  addButton("turbUp", smallRightC,35,smallRightD,37,"v", colors.blue, function()
    if #state.turbines>0 then state.selectedTurbine=state.selectedTurbine+1; if state.selectedTurbine>#state.turbines then state.selectedTurbine=1 end; state.turbinePage=math.ceil(state.selectedTurbine/turbinesPerPage) end
  end)

  addButton("pageDown", smallRightA,39,smallRightB,41,"<", colors.lightBlue, function()
    local pages=math.max(1, math.ceil(math.max(#state.turbines,1)/turbinesPerPage)); state.turbinePage=state.turbinePage-1; if state.turbinePage<1 then state.turbinePage=pages end; state.selectedTurbine=((state.turbinePage-1)*turbinesPerPage)+1
  end)

  addButton("pageUp", smallRightC,39,smallRightD,41,">", colors.lightBlue, function()
    local pages=math.max(1, math.ceil(math.max(#state.turbines,1)/turbinesPerPage)); state.turbinePage=state.turbinePage+1; if state.turbinePage>pages then state.turbinePage=1 end; state.selectedTurbine=((state.turbinePage-1)*turbinesPerPage)+1
  end)

  addButton("options", panelX1,45,panelX2,47,L.option or "OPTION", colors.brown, function()
    state.showOptions = not state.showOptions
  end)
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
  writeAt(mon,2,21,"Nr",colors.gray); writeAt(mon,8,21,"Typ",colors.gray); writeAt(mon,18,21,L.status or "Status",colors.gray); writeAt(mon,29,21,L.rods or "Rods",colors.gray); writeAt(mon,39,21,"RF/t",colors.gray)
  writeAt(mon,2,22,string.rep("-",48),colors.gray)
  local y=23
  for i=firstReactor,lastReactor do
    local r=state.reactors[i]
    local sel=i==state.selectedReactor
    local kind=r.kind=="ACTIVE" and (L.reactorActive or "AKTIV") or (L.reactorPassive or "PASSIV")
    writeAt(mon,2,y,(sel and ">" or " ").."R"..i, sel and colors.lime or colors.yellow)
    writeAt(mon,8,y,utils.padRight(kind,7), r.kind=="ACTIVE" and colors.cyan or colors.orange)
    writeAt(mon,18,y,utils.padRight(utils.boolText(r.enabled,L),6), r.enabled and colors.lime or colors.red)
    writeAt(mon,29,y,utils.padLeft(reactors.getRod(r).."%",5),colors.white)
    writeAt(mon,39,y,utils.padLeft(utils.formatShort(reactors.getRF(r)),8),colors.lime)
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
  writeAt(mon,18,30,"RPM",colors.gray)
  writeAt(mon,27,30,"Flow",colors.gray)
  writeAt(mon,36,30,"Kal.",colors.gray)
  writeAt(mon,45,30,"RF/t",colors.gray)
  writeAt(mon,54,30,"mB/RF",colors.gray)
  writeAt(mon,2,31,string.rep("-",58),colors.gray)
  y=32
  for i=firstTurbine,lastTurbine do
    local e=state.turbines[i]
    local rpm=turbines.getRPM(e.p)
    local steam=turbines.getSteam(e.p)
    local rf=turbines.getRF(e.p)
    local eff=rf>0 and steam/rf or 0
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
    writeAt(mon,18,y,utils.padLeft(math.floor(rpm),5),rpmColor)
    writeAt(mon,27,y,utils.padLeft(math.floor(turbines.getFlow(e.p)),6),colors.orange)
    writeAt(mon,36,y,utils.padLeft(calText,6),calFlow and colors.cyan or colors.gray)
    writeAt(mon,45,y,utils.padLeft(utils.formatShort(rf),7),colors.lime)
    writeAt(mon,54,y,utils.padLeft(string.format("%.4f",eff),7),colors.cyan)
    y=y+1
  end

  drawControlPanel(mon, state, cfg, saveFn, rescanFn, reactorsPerPage, turbinesPerPage, L, languageFn, updateFn)

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
