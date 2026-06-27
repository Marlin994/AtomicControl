local M = {}

function M.safe(fn, fallback)
  local ok, result = pcall(fn)
  if ok then return result end
  return fallback
end

function M.clamp(v, a, b)
  v = tonumber(v) or 0
  if v < a then return a end
  if v > b then return b end
  return v
end

function M.boolText(v, L)
  if L then return v and L.on or L.off end
  return v and "AN" or "AUS"
end

function M.padRight(text, width)
  text = tostring(text or "")
  if #text >= width then return string.sub(text, 1, width) end
  return text .. string.rep(" ", width - #text)
end

function M.padLeft(text, width)
  text = tostring(text or "")
  if #text >= width then return string.sub(text, 1, width) end
  return string.rep(" ", width - #text) .. text
end

function M.formatRF(v)
  v = math.floor(tonumber(v) or 0)
  if math.abs(v) >= 1000000000 then
    return string.format("%.2f GRF/t", v / 1000000000)
  elseif math.abs(v) >= 1000000 then
    return string.format("%.2f MRF/t", v / 1000000)
  elseif math.abs(v) >= 1000 then
    return string.format("%.1f kRF/t", v / 1000)
  end
  return tostring(v) .. " RF/t"
end

function M.formatShort(v)
  v = math.floor(tonumber(v) or 0)
  if math.abs(v) >= 1000000000 then
    return string.format("%.2fG", v / 1000000000)
  elseif math.abs(v) >= 1000000 then
    return string.format("%.2fM", v / 1000000)
  elseif math.abs(v) >= 1000 then
    return string.format("%.1fk", v / 1000)
  end
  return tostring(v)
end

return M
