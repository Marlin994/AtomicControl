local config = require("config")
local devices = require("devices")
local turbines = require("turbines")
local reactors = require("reactors")
local energy = require("energy")
local control = require("control")
local alarms = require("alarms")
local ui = require("ui")
local lang = require("lang")

local args = {...}
local cfg = config.load()
local L = lang.load(cfg.language or "de")

local function hasArg(value)
  for _, a in ipairs(args) do
    if tostring(a):lower() == value then return true end
  end
  return false
end

local forceSetup = hasArg("setup")

local state = {
  enabled = cfg.enabled,
  selectedReactor = cfg.selectedReactor or 1,
  selectedTurbine = cfg.selectedTurbine or 1,
  reactorPage = cfg.reactorPage or 1,
  turbinePage = cfg.turbinePage or 1,
  storageInRF = 0,
  storageOutRF = 0,
  storageNetRF = 0,
  statusLine = L.statusInitializing or "Initialisiere...",
  alarms = {},
  showOptions = false
}

local function currentProgramPath()
  local ok, p = pcall(function()
    if shell and shell.getRunningProgram then return shell.getRunningProgram() end
  end)
  if ok and p and p ~= "" then return p end
end

local function save()
  cfg.enabled = state.enabled
  cfg.selectedReactor = state.selectedReactor
  cfg.selectedTurbine = state.selectedTurbine
  cfg.reactorPage = state.reactorPage
  cfg.turbinePage = state.turbinePage
  config.save(cfg, state)
end

local function askLanguage()
  if cfg.languageSelected and not forceSetup then
    L = lang.load(cfg.language or "de")
    return
  end

  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)

  print("AtomicControl")
  print("-------------")
  if forceSetup then
    print("Setup mode / Setup-Modus")
    print("")
  end

  print("Select language / Sprache waehlen")
  print("")
  print("[1] Deutsch")
  print("[2] English")
  print("")
  write("> ")

  local answer = tostring(read() or "")
  if answer == "2" or string.lower(answer) == "en" or string.lower(answer) == "english" then
    cfg.language = "en"
  else
    cfg.language = "de"
  end

  cfg.languageSelected = true
  L = lang.load(cfg.language or "de")
  save()
end

local function askAutostart()
  if forceSetup then cfg.autostartAsked = false end
  if cfg.autostartAsked then return end
  if (fs.exists("startup.lua") or fs.exists("startup")) and not forceSetup then
    cfg.autostartAsked = true
    save()
    return
  end

  local running = currentProgramPath()
  if not running or running == "startup" or running == "startup.lua" then
    cfg.autostartAsked = true
    save()
    return
  end

  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1,1)
  print(L.setupTitle or "AtomicControl")
  print(L.setupLine or "-------------")
  if forceSetup then print((L.setupModeStarted or "Setup-Modus gestartet.") .. "\n") end
  print(L.setupAsk1 or "Soll dieses Programm beim Start")
  print(L.setupAsk2 or "automatisch geladen werden?")
  print("")
  print(L.setupCreates or "Es wird startup.lua angelegt/ersetzt.")
  print("")
  write(L.setupPrompt or "Autostart aktivieren? (j/n): ")
  local answer = string.lower(read() or "")
  if answer == "j" or answer == "ja" or answer == "y" or answer == "yes" then
    local ok = pcall(function()
      if fs.exists("startup.lua") then fs.delete("startup.lua") end
      local h = fs.open("startup.lua", "w")
      h.writeLine('shell.run("main")')
      h.close()
    end)
    print(ok and (L.setupDone or "Autostart eingerichtet.") or (L.setupFailed or "Autostart fehlgeschlagen."))
    sleep(1.5)
  end
  cfg.autostartAsked = true
  save()
end

local function rescan()
  devices.scan(state, cfg)
  turbines.setup(state.turbines)
  state.selectedReactor = math.max(1, math.min(state.selectedReactor or 1, math.max(#state.reactors,1)))
  state.selectedTurbine = math.max(1, math.min(state.selectedTurbine or 1, math.max(#state.turbines,1)))
end

local function runUpdate()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)

  print("AtomicControl Update")
  print("--------------------")
  print("Downloading update.lua...")
  print("")

  local url = "https://raw.githubusercontent.com/Marlin994/AtomicControl/main/update.lua"
  local tmp = "atomiccontrol_update.lua"

  if fs.exists(tmp) then fs.delete(tmp) end

  local ok = shell.run("wget", url, tmp)
  if not ok or not fs.exists(tmp) then
    print("")
    print("Update download failed.")
    sleep(2)
    return
  end

  shell.run(tmp)

  if fs.exists(tmp) then fs.delete(tmp) end
end

local function toggleLanguage()
  cfg.language = (cfg.language == "de") and "en" or "de"
  cfg.languageSelected = true
  L = lang.load(cfg.language or "de")
  state.statusLine = (cfg.language == "de") and "Sprache: Deutsch" or "Language: English"
  save()
end

askLanguage()
askAutostart()
rescan()

if not state.monitor then error("Kein Monitor gefunden") end
if #state.reactors == 0 then error("Kein Reaktor gefunden") end

state.monitor.setTextScale(0.5)
state.monitor.setBackgroundColor(colors.black)
state.monitor.clear()

local buttons = {}

local function mainLoop()
  while true do
    energy.updateFlow(state, 0.5)
    for _, r in ipairs(state.reactors or {}) do
      reactors.updateSteamProduction(r, 0.5)
    end
    control.update(state, cfg, L)
    alarms.evaluate(state, cfg, L)
    buttons = ui.draw(state, cfg, save, rescan, L, toggleLanguage, runUpdate)
    sleep(0.5)
  end
end

local function touchLoop()
  while true do
    local _, _, x, y = os.pullEvent("monitor_touch")
    if ui.handleTouch(buttons, x, y) then
      save()
      buttons = ui.draw(state, cfg, save, rescan, L, toggleLanguage, runUpdate)
    end
  end
end

parallel.waitForAny(mainLoop, touchLoop)
