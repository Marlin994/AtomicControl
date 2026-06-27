local energy = require("energy")
local reactors = require("reactors")
local turbines = require("turbines")
local TurbineController = require("turbinecontroller")
local ActiveReactorController = require("activereactorcontroller")
local PassiveReactorController = require("passivereactorcontroller")
local ReactorCalibration = require("reactorcalibration")

local M = {}

function M.startCalibration(state)
  return TurbineController.startCalibration(state)
end

function M.startReactorCalibration(state)
  return ReactorCalibration.start(state)
end

function M.update(state, cfg, L)
  L = L or {}

  if TurbineController.runCalibration(state, cfg) then
    return
  end

  if ReactorCalibration.update(state, cfg) then
    return
  end

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

  local turbinesNeedSteam = TurbineController.update(state, cfg, storageFull)

  ActiveReactorController.update(
    state,
    cfg,
    storageHigh and cfg.operationMode ~= "CYANITE",
    storageLow,
    steamPct,
    steamOk,
    turbinesNeedSteam
  )

  PassiveReactorController.update(
    state,
    cfg,
    storageLow,
    storageHigh and cfg.operationMode ~= "CYANITE",
    storageMidHigh
  )

  if cfg.operationMode == "CYANITE" then
    state.statusLine = L.statusCyanite or "CYANITE: Fuel wird verbrannt, RPM geregelt"
  else
    state.statusLine = L.statusNormal or "NORMAL: Lastverteilung aktiv"
  end
end

return M
