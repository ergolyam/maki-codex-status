local BOTTOM_STATUSLINE = true
local URL = "https://chatgpt.com/backend-api/wham/usage"
local INTERVAL_MS = 180000
local current = " Codex: -- "
local buf, win

local function display()
  if BOTTOM_STATUSLINE then
    if buf then buf:set_lines({ { { current, "dim" } } }) end
  else
    maki.ui.set_status_hint({ { current, "dim" } })
  end
end

local function publish(message)
  current = " Codex: " .. tostring(message):sub(1, 14)
  display()
end

local function reopen(session_id)
  if not BOTTOM_STATUSLINE then return end
  if win then win:close() end
  buf = maki.ui.buf({ scratch = true })
  buf:line({ { current, "dim" } })
  win = maki.ui.open_win(buf, {
    session = session_id,
    anchor = "SW", row = 0, col = 13,
    width = 24, height = 1,
    border = "none", focus = false,
  })
end

maki.api.create_autocmd("SessionFocusChanged", {
  callback = function(ev)
    if BOTTOM_STATUSLINE then
      maki.async.spawn(function() reopen(ev.data.session_id) end)
    end
  end,
})

local function weekly_left()
  local state = maki.env.state_dir()
  if not state then return nil, "No state dir" end

  local raw, read_err = maki.fs.read(state .. "/auth/openai.json")
  if not raw then return nil, "No OAuth: " .. tostring(read_err) end
  local token, json_err = maki.json.decode(raw, {
    luanil = { object = true, array = true },
  })
  if type(token) ~= "table" or type(token.access) ~= "string" then
    return nil, "Bad OAuth: " .. tostring(json_err)
  end

  local headers = { Authorization = "Bearer " .. token.access }
  if type(token.account_id) == "string" then
    headers["chatgpt-account-id"] = token.account_id
  end

  local response, req_err = maki.net.request(URL, {
    headers = headers, timeout = 12, retry = 0, max_bytes = 65536,
  })
  if not response then return nil, "Request: " .. tostring(req_err) end
  if response.status ~= 200 then return nil, "HTTP " .. tostring(response.status) end

  local data, decode_err = maki.json.decode(response.body, {
    luanil = { object = true, array = true },
  })
  if type(data) ~= "table" or type(data.rate_limit) ~= "table" then
    return nil, "No limits: " .. tostring(decode_err)
  end

  for _, key in ipairs({ "secondary_window", "primary_window" }) do
    local w = data.rate_limit[key]
    if type(w) == "table"
       and tonumber(w.limit_window_seconds) == 7 * 24 * 3600
       and type(w.used_percent) == "number" then
      return math.floor(math.max(0, math.min(100, 100 - w.used_percent)) + 0.5)
    end
  end
  return nil, "No weekly window"
end

maki.async.spawn(function()
  if BOTTOM_STATUSLINE then reopen() end
  while true do
    local ok, left, err = pcall(weekly_left)
    if ok and left ~= nil then
      publish(left .. "% left")
    else
      publish(ok and tostring(err) or ("Lua error: " .. tostring(left)))
    end
    maki.async.sleep(INTERVAL_MS)
  end
end)
