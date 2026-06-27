local reactors = require("reactors")

local M = {}

M.ROD_STEP_NORMAL = 3

local function enabledPassiveReactors(state)
  local out = {}

  for i, r in ipairs(state.reactors or {}) do
    if r.enabled and r.kind == "PASSIVE" then
      table.insert(out, {idx = i, r = r})
    end
  end

  return out
end

local function setIdle(list, startIndex)
  for i = startIndex, #list do
    reactors.setActive(list[i].r, false)
    reactors.setRods(list[i].r, 100)
    list[i].r.managedActive = false
  end
end

function M.update(state, cfg, storageLow, storageHigh, storageMidHigh)
  local list = enabledPassiveReactors(state)
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
    setIdle(list, 1)
    return
  end

  local wanted = 1

  if storageLow then wanted = math.min(#list, 2) end
  if storageLow and (state.storageNetRF or 0) < -1000 then wanted = #list end

  for i, e in ipairs(list) do
    local r = e.r

    if i <= wanted then
      reactors.setActive(r, true)
      r.managedActive = true

      local rod = reactors.getRod(r)

      if storageLow then
        reactors.setRods(r, rod - M.ROD_STEP_NORMAL)
      elseif storageMidHigh then
        reactors.setRods(r, rod + 1)
      end
    else
      reactors.setActive(r, false)
      reactors.setRods(r, 100)
      r.managedActive = false
    end
  end
end

return M
