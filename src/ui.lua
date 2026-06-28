local utils = require("utils")
local energy = require("energy")
local reactors = require("reactors")
local turbines = require("turbines")
local alarms = require("alarms")
local control = require("control")

local M = {}

local buttons = {}

local function safe(fn, fallback)
  local ok, result = pcall(fn)
  if ok then return result end
  return fallback
end

local function clamp(v, a, b)
  v = tonumber(v) or 0
  if v < a then return a end
  if v > b then return b end
  return v
end

local function padRight(text, width)
  text = tostring(text or "")
  width = tonumber(width) or 0
  if #text >= width then return string.sub(text, 1, width) end
  return text .. string.rep(" ", width - #text)
end

local function padLeft(text, width)
  text = tostring(text or "")
  width = tonumber(width) or 0
  if #text >= width then return string.sub(text, 1, width) end
  return string.rep(" ", width - #text) .. text
end

local function shortNumber(v)
  v = tonumber(v) or 0
  if math.abs(v) >= 1000000000 then
    return string.format("%.2fG", v / 1000000000)
  elseif math.abs(v) >= 1000000 then
    return string.format("%.2fM", v / 1000000)
  elseif math.abs(v) >= 1000 then
    return string.format("%.1fk", v / 1000)
  end
  return tostring(math.floor(v))
end

local function rfText(v)
  v = tonumber(v) or 0
  if math.abs(v) >= 1000000000 then
    return string.format("%.2f GRF/t", v / 1000000000)
  elseif math.abs(v) >= 1000000 then
    return string.format("%.2f MRF/t", v / 1000000)
  elseif math.abs(v) >= 1000 then
    return string.format("%.1f kRF/t", v / 1000)
  end
  return tostring(math.floor(v)) .. " RF/t"
end

local function onOff(v, L)
  if v then return L.on or "ON" end
  return L.off or "OFF"
end

local function writeAt(mon, x, y, text, fg, bg)
  if not mon then return end
  local w, h = mon.getSize()
  if y < 1 or y > h then return end
  if x < 1 then x = 1 end
  if x > w then return end

  mon.setCursorPos(x, y)
  mon.setTextColor(fg or colors.white)
  mon.setBackgroundColor(bg or colors.black)
  mon.write(tostring(text or ""))
end

local function drawButton(mon, b)
  if not mon or not b then return end

  local w, h = mon.getSize()

  b.x1 = clamp(b.x1, 1, w)
  b.x2 = clamp(b.x2, 1, w)
  b.y1 = clamp(b.y1, 1, h)
  b.y2 = clamp(b.y2, 1, h)

  if b.x2 < b.x1 then b.x1, b.x2 = b.x2, b.x1 end
  if b.y2 < b.y1 then b.y1, b.y2 = b.y2, b.y1 end

  local bw = b.x2 - b.x1 + 1
  local label = tostring(b.label or "")
  if #label > bw then label = string.sub(label, 1, bw) end

  mon.setTextColor(colors.white)
  mon.setBackgroundColor(b.bg or colors.gray)

  for y = b.y1, b.y2 do
    mon.setCursorPos(b.x1, y)
    mon.write(string.rep(" ", bw))
  end

  local x = b.x1 + math.floor((bw - #label) / 2)
  local y = b.y1 + math.floor((b.y2 - b.y1) / 2)

  mon.setCursorPos(x, y)
  mon.write(label)

  mon.setBackgroundColor(colors.black)
end

local function addButton(id, x1, y1, x2, y2, label, bg, action)
  buttons[id] = {
    x1 = x1,
    y1 = y1,
    x2 = x2,
    y2 = y2,
    label = label,
    bg = bg,
    action = action
  }
end

local function drawBar(mon, x, y, width, percent, fg)
  percent = clamp(percent or 0, 0, 1)
  width = math.max(1, tonumber(width) or 10)

  local filled = math.floor(width * percent)
  local empty = width - filled

  writeAt(mon, x, y, "[", colors.white)
  writeAt(mon, x + 1, y, string.rep("#", filled), fg or colors.lime)
  writeAt(mon, x + 1 + filled, y, string.rep("-", empty), colors.gray)
  writeAt(mon, x + width + 1, y, "]", colors.white)
end

local function getSelected(list, index)
  if not list or #list == 0 then return nil end
  index = clamp(index or 1, 1, #list)
  return list[index]
end

local function pageInfo(count, pageSize, page)
  count = count or 0
  pageSize = pageSize or 1
  local pages = math.max(1, math.ceil(count / pageSize))
  page = clamp(page or 1, 1, pages)
  local startIndex = ((page - 1) * pageSize) + 1
  local endIndex = math.min(count, startIndex + pageSize - 1)
  return page, pages, startIndex, endIndex
end

local function manualAllowed(cfg)
  return not cfg.auto
end

local function manualButtonColor(cfg, color)
  if manualAllowed(cfg) then return color end
  return colors.gray
end

local function autoBlocked(state, L)
  state.statusLine = L.statusAutoBlocked or "Auto aktiv: Erst auf MANUAL wechseln"
end

local function changeRod(state, cfg, delta, L)
  if not manualAllowed(cfg) then autoBlocked(state, L) return end
  local r = getSelected(state.reactors, state.selectedReactor)
  if not r then return end
  local rod = reactors.getRod(r)
  reactors.setRods(r, rod + delta)
end

local function changeFlow(state, cfg, delta, L)
  if not manualAllowed(cfg) then autoBlocked(state, L) return end
  local t = getSelected(state.turbines, state.selectedTurbine)
  if not t then return end
  local flow = turbines.getFlow(t.p)
  turbines.setFlow(t.p, flow + delta)
end

local function toggleSelectedReactor(state, cfg, L)
  local r = getSelected(state.reactors, state.selectedReactor)
  if not r then return end
  r.enabled = not r.enabled
  state.statusLine = (L.reactor or "Reaktor") .. " " .. onOff(r.enabled, L)
end

local function toggleSelectedTurbine(state, cfg, L)
  local t = getSelected(state.turbines, state.selectedTurbine)
  if not t then return end
  t.enabled = not t.enabled
  state.statusLine = (L.turbine or "Turbine") .. " " .. onOff(t.enabled, L)
end

local function drawHeader(mon, leftW, L)
  writeAt(mon, 2, 1, L.title or "ATOMICCONTROL", colors.yellow)
  writeAt(mon, 2, 2, string.rep("-", math.max(1, leftW - 2)), colors.gray)
end

local function drawOverview(mon, state, cfg, L, leftW)
  local storagePct, storageOk = energy.getPercent(state.storage)
  local barW = math.max(10, leftW - 20)

  writeAt(mon, 2, 4, (L.auto or "Auto") .. ": " .. onOff(cfg.auto, L), cfg.auto and colors.lime or colors.red)
  writeAt(mon, 18, 4, (L.system or "Anlage") .. ": " .. onOff(state.enabled, L), state.enabled and colors.lime or colors.red)
  writeAt(mon, 38, 4, (L.mode or "Modus") .. ": " .. tostring(cfg.operationMode or "NORMAL"), colors.lime)

  if storageOk then
    writeAt(mon, 2, 6, (L.storage or "Speicher") .. ": " .. string.format("%.1f%% ", storagePct * 100), colors.white)
    drawBar(mon, 18, 6, barW, storagePct, storagePct < 0.25 and colors.red or colors.lime)
    writeAt(mon, 2, 7, (L.minMax or "Min/Max") .. ": " .. tostring(cfg.storageMin or 0) .. "% / " .. tostring(cfg.storageMax or 0) .. "%", colors.white)
  else
    writeAt(mon, 2, 6, L.noStorage or "Speicher: NICHT GEFUNDEN", colors.red)
  end

  local turbineRF = turbines.getTotalRF(state.turbines or {})
  local passiveRF = reactors.getTotalPassiveRF(state.reactors or {})
  local totalRF = turbineRF + passiveRF
  local steamProd = reactors.getTotalSteamProduction(state.reactors or {})
  local steamUse = turbines.getTotalSteam(state.turbines or {})

  writeAt(mon, 2, 9, (L.rfTurbines or "RF Turbinen") .. ": " .. rfText(turbineRF), colors.lime)
  writeAt(mon, 2, 10, (L.rfPassive or "RF Passiv") .. ": " .. rfText(passiveRF), colors.lime)
  writeAt(mon, 2, 11, (L.rfTotal or "RF Gesamt") .. ": " .. rfText(totalRF), colors.lime)

  writeAt(mon, 2, 13, (L.steamProduced or "Dampf-Prod") .. ": " .. shortNumber(steamProd) .. " mB/t", colors.cyan)
  writeAt(mon, 2, 14, (L.steamUsed or "Dampf-Verbr") .. ": " .. shortNumber(steamUse) .. " mB/t", colors.cyan)

  local eff = tonumber(cfg.steamTransferEfficiency) or 1.00
  local txt = (L.transferEfficiency or "Dampf-Eff") .. ": " .. string.format("%.1f%%", eff * 100)
  if state.steamTransferEfficiencyMeasured then
    txt = txt .. " (" .. string.format("%.1f%%", state.steamTransferEfficiencyMeasured * 100) .. ")"
  end
  writeAt(mon, 2, 15, txt, colors.lightBlue)

  writeAt(mon, 2, 17, (L.charge or "Ladung") .. ": " .. rfText(state.storageInRF or 0), colors.lime)
  writeAt(mon, 2, 18, (L.net or "Netto") .. ": " .. rfText(state.storageNetRF or 0), (state.storageNetRF or 0) >= 0 and colors.lime or colors.red)

  local alarmLevel = alarms.worstLevel(state.alarms or {})
  local alarmColor = colors.lime
  if alarmLevel == "WARN" then alarmColor = colors.orange end
  if alarmLevel == "ERROR" then alarmColor = colors.red end

  writeAt(mon, 2, 20, (L.alarm or "Alarm") .. ": " .. alarmLevel, alarmColor)

  local y = 21
  for i, a in ipairs(state.alarms or {}) do
    if i > 3 then break end
    writeAt(mon, 2, y, "- " .. tostring(a.text), a.level == "ERROR" and colors.red or colors.orange)
    y = y + 1
  end
end

local function drawReactors(mon, state, cfg, L, leftW)
  local pageSize = 4
  local page, pages, first, last = pageInfo(#(state.reactors or {}), pageSize, state.reactorPage or 1)
  state.reactorPage = page

  local y = 26
  local sel = state.selectedReactor or 1

  writeAt(mon, 2, y, (L.reactors or "Reaktoren") .. ": " .. tostring(#(state.reactors or {})) ..
    " | " .. (L.selected or "Auswahl") .. ": R" .. tostring(sel) ..
    " | " .. (L.page or "Seite") .. " " .. page .. "/" .. pages, colors.yellow)

  y = y + 1
  writeAt(mon, 2, y, "Nr   Typ      Status   Rods     RF/t", colors.gray)
  y = y + 1
  writeAt(mon, 2, y, string.rep("-", math.max(1, leftW - 4)), colors.gray)
  y = y + 1

  if #(state.reactors or {}) == 0 then
    writeAt(mon, 2, y, L.noReactors or "Keine Reaktoren gefunden", colors.red)
    return
  end

  for i = first, last do
    local r = state.reactors[i]
    local prefix = (i == sel) and ">" or " "
    local typ = r.kind == "ACTIVE" and (L.reactorActive or "AKTIV") or (L.reactorPassive or "PASSIV")
    local status = onOff(r.enabled, L)
    local rod = reactors.getRod(r)
    local rf = reactors.getRF(r)

    local line =
      prefix .. "R" .. tostring(i) .. "  " ..
      padRight(typ, 8) .. " " ..
      padRight(status, 7) .. " " ..
      padLeft(tostring(math.floor(rod)) .. "%", 6) .. " " ..
      padLeft(shortNumber(rf), 8)

    writeAt(mon, 2, y, line, i == sel and colors.lime or colors.white)
    y = y + 1
  end
end

local function drawTurbines(mon, state, cfg, L, leftW)
  local pageSize = 4
  local page, pages, first, last = pageInfo(#(state.turbines or {}), pageSize, state.turbinePage or 1)
  state.turbinePage = page

  local y = 36
  local sel = state.selectedTurbine or 1

  writeAt(mon, 2, y, (L.turbines or "Turbinen") .. ": " .. tostring(#(state.turbines or {})) ..
    " | " .. (L.selected or "Auswahl") .. ": T" .. tostring(sel) ..
    " | " .. (L.page or "Seite") .. " " .. page .. "/" .. pages, colors.yellow)

  y = y + 1
  writeAt(mon, 2, y, "Nr   Status  RPM     mB/t    RF/t", colors.gray)
  y = y + 1
  writeAt(mon, 2, y, string.rep("-", math.max(1, leftW - 4)), colors.gray)
  y = y + 1

  if #(state.turbines or {}) == 0 then
    writeAt(mon, 2, y, L.noTurbines or "Keine Turbinen gefunden", colors.red)
    return
  end

  for i = first, last do
    local t = state.turbines[i]
    local prefix = (i == sel) and ">" or " "
    local rpm = turbines.getRPM(t.p)
    local flow = turbines.getFlow(t.p)
    local rf = turbines.getRF(t.p)
    local status = onOff(t.enabled, L)

    if t.enabled and not turbines.getInductor(t.p) then
      status = "FREE"
    end

    local line =
      prefix .. "T" .. tostring(i) .. "  " ..
      padRight(status, 7) .. " " ..
      padLeft(math.floor(rpm), 6) .. " " ..
      padLeft(math.floor(flow), 7) .. " " ..
      padLeft(shortNumber(rf), 8)

    writeAt(mon, 2, y, line, i == sel and colors.lime or colors.white)
    y = y + 1
  end
end

local function drawControlButtons(mon, state, cfg, L, x1, x2, h, saveFn, rescanFn)
  local mid = x1 + math.floor((x2 - x1) / 2)
  local lx1, lx2 = x1, mid - 1
  local rx1, rx2 = mid + 1, x2

  writeAt(mon, x1, 2, L.general or "ALLGEMEIN", colors.yellow)

  addButton("auto", lx1, 4, lx2, 6, L.auto or "AUTO", cfg.auto and colors.green or colors.gray, function()
    cfg.auto = not cfg.auto
    state.statusLine = cfg.auto and (L.statusAutoEnabled or "Auto-Modus aktiviert") or (L.statusManualEnabled or "Manuell aktiviert")
  end)

  addButton("enabled", rx1, 4, rx2, 6, onOff(state.enabled, L), state.enabled and colors.green or colors.red, function()
    state.enabled = not state.enabled
    cfg.enabled = state.enabled
    state.statusLine = state.enabled and (L.statusSystemOn or "Anlage eingeschaltet") or (L.statusSystemOff or "Anlage ausgeschaltet")
  end)

  addButton("mode", x1, 8, x2, 10, (L.mode or "MODUS") .. ": " .. tostring(cfg.operationMode or "NORMAL"), cfg.operationMode == "CYANITE" and colors.red or colors.cyan, function()
    if cfg.operationMode == "CYANITE" then
      cfg.operationMode = "NORMAL"
    else
      cfg.operationMode = "CYANITE"
    end
    state.statusLine = (L.statusMode or "Modus: ") .. tostring(cfg.operationMode)
  end)

  addButton("minDown", lx1, 12, lx2, 14, L.minDown or "MIN -", colors.blue, function()
    cfg.storageMin = clamp((cfg.storageMin or 30) - 5, 0, 100)
  end)

  addButton("minUp", rx1, 12, rx2, 14, L.minUp or "MIN +", colors.blue, function()
    cfg.storageMin = clamp((cfg.storageMin or 30) + 5, 0, 100)
  end)

  addButton("maxDown", lx1, 16, lx2, 18, L.maxDown or "MAX -", colors.purple, function()
    cfg.storageMax = clamp((cfg.storageMax or 90) - 5, 0, 100)
  end)

  addButton("maxUp", rx1, 16, rx2, 18, L.maxUp or "MAX +", colors.purple, function()
    cfg.storageMax = clamp((cfg.storageMax or 90) + 5, 0, 100)
  end)

  writeAt(mon, x1, 20, string.rep("-", math.max(1, x2 - x1 + 1)), colors.gray)
  writeAt(mon, lx1, 21, L.reactor or "REAKTOR", colors.yellow)
  writeAt(mon, rx1, 21, L.turbine or "TURBINE", colors.yellow)

  addButton("reactorToggle", lx1, 23, lx2, 25, L.enabledToggle or "EIN/AUS", colors.brown, function()
    toggleSelectedReactor(state, cfg, L)
  end)

  addButton("turbineToggle", rx1, 23, rx2, 25, L.enabledToggle or "EIN/AUS", colors.brown, function()
    toggleSelectedTurbine(state, cfg, L)
  end)

  addButton("rodDown", lx1, 27, lx2, 29, L.rodDown or "-ROD", manualButtonColor(cfg, colors.gray), function()
    changeRod(state, cfg, -5, L)
  end)

  addButton("flowDown", rx1, 27, rx2, 29, L.flowDown or "-FLOW", manualButtonColor(cfg, colors.gray), function()
    changeFlow(state, cfg, -25, L)
  end)

  addButton("rodUp", lx1, 31, lx2, 33, L.rodUp or "+ROD", manualButtonColor(cfg, colors.gray), function()
    changeRod(state, cfg, 5, L)
  end)

  addButton("flowUp", rx1, 31, rx2, 33, L.flowUp or "+FLOW", manualButtonColor(cfg, colors.gray), function()
    changeFlow(state, cfg, 25, L)
  end)

  addButton("reactorPrev", lx1, 35, lx1 + math.floor((lx2 - lx1) / 2) - 1, 37, "^", colors.lightBlue, function()
    state.selectedReactor = clamp((state.selectedReactor or 1) - 1, 1, math.max(1, #(state.reactors or {})))
  end)

  addButton("reactorNext", lx1 + math.floor((lx2 - lx1) / 2) + 1, 35, lx2, 37, "v", colors.lightBlue, function()
    state.selectedReactor = clamp((state.selectedReactor or 1) + 1, 1, math.max(1, #(state.reactors or {})))
  end)

  addButton("turbinePrev", rx1, 35, rx1 + math.floor((rx2 - rx1) / 2) - 1, 37, "^", colors.lightBlue, function()
    state.selectedTurbine = clamp((state.selectedTurbine or 1) - 1, 1, math.max(1, #(state.turbines or {})))
  end)

  addButton("turbineNext", rx1 + math.floor((rx2 - rx1) / 2) + 1, 35, rx2, 37, "v", colors.lightBlue, function()
    state.selectedTurbine = clamp((state.selectedTurbine or 1) + 1, 1, math.max(1, #(state.turbines or {})))
  end)

  addButton("reactorPagePrev", lx1, 39, lx1 + math.floor((lx2 - lx1) / 2) - 1, 41, "<", colors.lightBlue, function()
    state.reactorPage = math.max(1, (state.reactorPage or 1) - 1)
  end)

  addButton("reactorPageNext", lx1 + math.floor((lx2 - lx1) / 2) + 1, 39, lx2, 41, ">", colors.lightBlue, function()
    state.reactorPage = (state.reactorPage or 1) + 1
  end)

  addButton("turbinePagePrev", rx1, 39, rx1 + math.floor((rx2 - rx1) / 2) - 1, 41, "<", colors.lightBlue, function()
    state.turbinePage = math.max(1, (state.turbinePage or 1) - 1)
  end)

  addButton("turbinePageNext", rx1 + math.floor((rx2 - rx1) / 2) + 1, 39, rx2, 41, ">", colors.lightBlue, function()
    state.turbinePage = (state.turbinePage or 1) + 1
  end)

  addButton("options", x1, h - 4, x2, h - 2, L.option or "OPTION", colors.orange, function()
    state.showOptions = true
  end)
end

local function drawOptions(mon, state, cfg, L, x1, x2, h, saveFn, rescanFn, languageFn, updateFn)
  writeAt(mon, x1, 2, L.options or "OPTIONEN", colors.yellow)
  writeAt(mon, x1, 3, string.rep("-", math.max(1, x2 - x1 + 1)), colors.gray)

  addButton("optLang", x1, 5, x2, 7, (L.language or "LANG") .. ": " .. string.upper(cfg.language or "de"), colors.blue, function()
    if languageFn then languageFn() end
    state.showOptions = false
  end)

  addButton("optRescan", x1, 9, x2, 11, L.rescan or "RESCAN", colors.brown, function()
    if rescanFn then rescanFn() end
    state.showOptions = false
    state.statusLine = L.statusRescan or "Peripherals neu gesucht"
  end)

  addButton("optCalT", x1, 13, x2, 15, L.calibrateTurbine or "CAL T", colors.orange, function()
    if control.startCalibration(state) then
      state.showOptions = false
    end
  end)

  addButton("optCalR", x1, 17, x2, 19, L.calibrateReactor or "CAL R", colors.orange, function()
    if control.startReactorCalibration(state) then
      state.showOptions = false
    end
  end)

  addButton("optUpdate", x1, 21, x2, 23, L.update or "UPDATE", colors.purple, function()
    if updateFn then updateFn() end
    state.showOptions = false
  end)

  addButton("optBack", x1, h - 4, x2, h - 2, L.back or "BACK", colors.gray, function()
    state.showOptions = false
  end)
end

function M.draw(state, cfg, saveFn, rescanFn, L, languageFn, updateFn)
  L = L or {}
  buttons = {}

  local mon = state.monitor
  if not mon then return buttons end

  local w, h = mon.getSize()
  local panelW = math.max(24, math.floor(w * 0.28))
  local leftW = w - panelW - 2
  if leftW < 50 then
    leftW = math.max(40, w - 28)
    panelW = w - leftW - 2
  end

  local panelX1 = leftW + 3
  local panelX2 = w - 2

  mon.setBackgroundColor(colors.black)
  mon.setTextColor(colors.white)
  mon.clear()

  drawHeader(mon, leftW, L)
  drawOverview(mon, state, cfg, L, leftW)
  drawReactors(mon, state, cfg, L, leftW)
  drawTurbines(mon, state, cfg, L, leftW)

  writeAt(mon, 2, h, tostring(state.statusLine or ""), colors.lightGray)

  writeAt(mon, leftW + 1, 1, "|", colors.gray)
  for y = 2, h do
    writeAt(mon, leftW + 1, y, "|", colors.gray)
  end

  if state.showOptions then
    drawOptions(mon, state, cfg, L, panelX1, panelX2, h, saveFn, rescanFn, languageFn, updateFn)
  else
    drawControlButtons(mon, state, cfg, L, panelX1, panelX2, h, saveFn, rescanFn)
  end

  for _, b in pairs(buttons) do
    drawButton(mon, b)
  end

  return buttons
end

function M.handleTouch(btns, x, y)
  btns = btns or buttons

  for _, b in pairs(btns or {}) do
    if x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then
      if b.action then b.action() end
      return true
    end
  end

  return false
end

return M
