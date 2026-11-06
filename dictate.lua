-- Voice typing.
--   Hold Fn, talk, release        -> push-to-talk
--   Double-tap Fn                 -> hands-free: keeps recording, tap Fn to stop
-- Whisper transcribes locally, Claude cleans it up, the text pastes at the cursor.
-- Everything lives next to this file; it is usually symlinked into
-- ~/.hammerspoon, so resolve the link to find the real folder.

local HOME = os.getenv("HOME")
local SELF = hs.fs.pathToAbsolute(debug.getinfo(1, "S").source:sub(2))
local DIR  = (SELF and SELF:match("^(.*)/[^/]+$")) or (HOME .. "/.hammerspoon")

-- Homebrew is /opt/homebrew on Apple silicon, /usr/local on Intel.
local BREW = hs.fs.attributes("/opt/homebrew/bin") and "/opt/homebrew" or "/usr/local"

local TMP        = HOME .. "/.local/share/dictate/tmp"
local LOGDIR     = DIR .. "/logs"
local TRANSCRIBE = DIR .. "/dictate-transcribe"
local CONF       = DIR .. "/config"
local DEBUG_LOG  = DIR .. "/debug.log"
local FFMPEG     = BREW .. "/bin/ffmpeg"
local PATH_ENV   = BREW .. "/bin:/usr/bin:/bin:/usr/sbin"

local ICON_IDLE, ICON_WORK, ICON_LOCK = "🎙", "⏳", "🔒"
local KEYFILE = HOME .. "/.config/dictate/api-key"

-- Cleanup silently does nothing without a key, so say so where it is visible.
local function hasKey()
  local f = io.open(KEYFILE, "r")
  if not f then return false end
  local k = f:read("*a") or ""
  f:close()
  return k:match("%S") ~= nil
end
local DOUBLE_TAP_WINDOW = 0.5

local function dlog(msg)
  local f = io.open(DEBUG_LOG, "a")
  if f then f:write(os.date("%H:%M:%S ") .. msg .. "\n"); f:close() end
end

-- Read a value out of the shell config so there is one source of truth.
local function conf(key, default)
  local f = io.open(CONF, "r")
  if not f then return default end
  local val
  for line in f:lines() do
    if not line:match("^%s*#") then
      local v = line:match("^%s*" .. key .. '%s*=%s*"?([^"#]*)"?')
      if v then val = v:gsub("%s+$", "") end
    end
  end
  f:close()
  if val == nil or val == "" then return default end
  return val
end

local MIC         = conf("MIC", ":default")
local MIN_SECONDS = tonumber(conf("MIN_SECONDS", "0.4")) or 0.4
local OVERLAY     = conf("OVERLAY", "1") == "1"
local SOUND       = conf("SOUND", "0") == "1"

local recorder, startedAt, wavPath
local locked, lastTapAt = false, 0
local workers, ticker = {}, nil
local menu = hs.menubar.new()

local function setIcon(t)
  if menu then menu:setTitle(t) end
end

-- A floating pill, bottom-centre, above fullscreen apps and on every Space.
-- The menu-bar icon can hide behind the notch; this cannot be missed.
local overlay, pulseOn = nil, true

local function hideOverlay()
  if overlay then overlay:delete(); overlay = nil end
end

local function showOverlay()
  if not OVERLAY then return end
  hideOverlay()
  local scr = hs.screen.mainScreen():frame()
  local w, h = 196, 46
  overlay = hs.canvas.new({
    x = scr.x + (scr.w - w) / 2, y = scr.y + scr.h - h - 120, w = w, h = h,
  })
  overlay:appendElements(
    { type = "rectangle", action = "fill",
      roundedRectRadii = { xRadius = 23, yRadius = 23 },
      fillColor = { red = 0.05, green = 0.05, blue = 0.07, alpha = 0.88 } },
    { type = "circle", action = "fill",
      center = { x = 28, y = 23 }, radius = 7,
      fillColor = { red = 0.96, green = 0.24, blue = 0.24, alpha = 1 } },
    { type = "text", text = "0:00", textSize = 16,
      textColor = { white = 1, alpha = 0.95 },
      frame = { x = 48, y = 13, w = 136, h = 24 } }
  )
  overlay:level(hs.canvas.windowLevels.screenSaver)
  overlay:behavior({ "canJoinAllSpaces", "stationary" })
  overlay:show()
end

local function overlayRecording(label)
  if not overlay then return end
  pulseOn = not pulseOn
  overlay[2].fillColor = { red = 0.96, green = 0.24, blue = 0.24,
                           alpha = pulseOn and 1 or 0.3 }
  overlay[3].text = label
end

local function overlayWorking()
  if not overlay then return end
  overlay[2].fillColor = { red = 1, green = 0.68, blue = 0.15, alpha = 1 }
  overlay[3].text = "transcribing…"
end

local function cue(name)
  if not SOUND then return end
  local snd = hs.sound.getByName(name)
  if snd then snd:play() end
end

local function notify(msg, secs)
  hs.alert.closeAll()
  hs.alert.show(msg, secs or 1.2)
end

-- While recording, show elapsed time so a long dictation visibly keeps going.
local function startTicker()
  if ticker then ticker:stop() end
  ticker = hs.timer.doEvery(0.5, function()
    if not recorder then return end
    local secs = math.floor(hs.timer.secondsSinceEpoch() - (startedAt or 0))
    local clock = string.format("%d:%02d", math.floor(secs / 60), secs % 60)
    setIcon(string.format("%s %s", locked and ICON_LOCK or "🔴", clock))
    overlayRecording(locked and (clock .. "  · tap Fn") or clock)
  end)
end

local function stopTicker()
  if ticker then ticker:stop(); ticker = nil end
end

-- Clipboard handling, which has two opposite failure modes:
--   restore blindly -> an OLD dictation keeps reappearing on the clipboard
--   never restore   -> dictating destroys whatever you had copied
-- So: restore what you had, UNLESS it was one of our own dictations.
local flagWatcher            -- forward declaration; defined below
local ours, lastDictation = {}, nil

local function wasOurs(text)
  for _, t in ipairs(ours) do if t == text then return true end end
  return false
end

local function pasteAtCursor(text)
  local prev = hs.pasteboard.getContents()
  hs.pasteboard.setContents(text)
  lastDictation = text
  table.insert(ours, text)
  while #ours > 10 do table.remove(ours, 1) end

  -- Our synthetic Cmd-V generates flagsChanged events that would re-enter our
  -- own tap. Suspend it across the keystroke.
  if flagWatcher then flagWatcher:stop() end
  hs.eventtap.keyStroke({ "cmd" }, "v", 0)
  dictateTimers = dictateTimers or {}
  dictateTimers.restore = hs.timer.doAfter(0.4, function()
    if flagWatcher and not flagWatcher:isEnabled() then flagWatcher:start() end
    if prev and prev ~= "" and not wasOurs(prev) then
      hs.pasteboard.setContents(prev)   -- give you back what you had copied
    end
  end)
end

local function transcribe(path)
  setIcon(ICON_WORK)
  local t
  t = hs.task.new(TRANSCRIBE, function(code, stdout, stderr)
    workers[t] = nil
    if not recorder then setIcon(ICON_IDLE); hideOverlay() end
    os.remove(path)
    local text = (stdout or ""):gsub("^%s+", ""):gsub("%s+$", "")
    dlog(string.format("transcribe exit=%d chars=%d err=%s",
                       code, #text, tostring(stderr):sub(1, 200)))
    if text == "" then
      notify(code == 0 and "Dictate: nothing heard" or "Dictate: transcription failed", 2)
      return
    end
    pasteAtCursor(text)
  end, { path })
  t:setEnvironment({ PATH = PATH_ENV, HOME = HOME })
  workers[t] = true
  t:start()
end

local function startRecording()
  if recorder then return end
  hs.fs.mkdir(TMP)
  wavPath = TMP .. "/dictate-" .. os.time() .. ".wav"
  startedAt = hs.timer.secondsSinceEpoch()
  recorder = hs.task.new(FFMPEG, nil, {
    "-hide_banner", "-loglevel", "error", "-nostdin",
    "-f", "avfoundation", "-i", MIC,
    "-ar", "16000", "-ac", "1", "-y", wavPath,
  })
  recorder:start()
  hs.dictateRecording = true
  setIcon("🔴")
  showOverlay()
  startTicker()
  cue("Tink")
  dlog("record start mic=" .. MIC .. " -> " .. wavPath)
end

local function discardRecording()
  if not recorder then return end
  recorder:terminate()
  recorder = nil
  hs.dictateRecording = false
  stopTicker()
  hideOverlay()
  setIcon(ICON_IDLE)
  if wavPath then os.remove(wavPath) end
end

local function finishRecording()
  if not recorder then return end
  local held = hs.timer.secondsSinceEpoch() - (startedAt or 0)
  recorder:terminate()
  recorder = nil
  hs.dictateRecording = false
  stopTicker()
  dlog(string.format("record stop, held %.2fs", held))

  local path = wavPath
  setIcon(ICON_WORK)
  overlayWorking()
  cue("Pop")
  -- Wait for ffmpeg to actually finish writing instead of guessing a delay.
  local tries, lastSize = 0, -1
  local waiter
  waiter = hs.timer.doEvery(0.1, function()
    tries = tries + 1
    local attrs = hs.fs.attributes(path)
    local size = attrs and attrs.size or 0
    if size > 1024 and size == lastSize then
      waiter:stop()
      dlog(string.format("wav settled at %d bytes after %.1fs", size, tries * 0.1))
      transcribe(path)
    elseif tries > 50 then
      waiter:stop()
      setIcon(ICON_IDLE)
      hideOverlay()
      dlog("gave up waiting for " .. path .. " (size " .. size .. ")")
      notify("Dictate: recording never landed", 2)
    end
    lastSize = size
  end)
end

-- Fn alone is the trigger. Fn with any other modifier is left to the system.
flagWatcher = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged }, function(e)
  local f = e:getFlags()
  local fnAlone = f.fn and not (f.cmd or f.alt or f.ctrl or f.shift)
  local now = hs.timer.secondsSinceEpoch()

  if fnAlone then                                   -- Fn pressed down
    if locked then return false end                 -- a tap to stop; act on release
    if recorder then dlog("fn down ignored: already recording") end
    startRecording()
  elseif not f.fn then                              -- Fn released
    if locked then
      locked = false
      dlog("hands-free stop")
      finishRecording()
      return false
    end
    if not recorder then dlog("fn up with no recording in flight"); return false end
    local held = now - (startedAt or now)
    if held >= MIN_SECONDS then
      finishRecording()                             -- normal push-to-talk
    elseif now - lastTapAt < DOUBLE_TAP_WINDOW then
      locked = true                                 -- second quick tap: hands-free
      dlog("hands-free start")
      notify("Hands-free — tap Fn to stop", 2)
      startTicker()
    else
      lastTapAt = now                               -- first tap: discard, wait
      dlog(string.format("fn tap %.2fs discarded (under MIN_SECONDS=%.2f); "
        .. "tap again within %.1fs for hands-free", held, MIN_SECONDS, DOUBLE_TAP_WINDOW))
      discardRecording()
    end
  end
  return false
end)
flagWatcher:start()

-- A previous Hammerspoon reload can orphan an ffmpeg that still holds the mic.
hs.task.new("/usr/bin/pkill", nil, { "-f", "avfoundation.*dictate" }):start()
os.execute("rm -f '" .. TMP .. "'/*.wav 2>/dev/null")

setIcon(ICON_IDLE)
hideOverlay()
hs.dictateRecording = false
local menuItems = {
  { title = "Hold Fn to dictate", disabled = true },
  { title = "Double-tap Fn for hands-free", disabled = true },
  { title = "-" },
}
if not hasKey() then
  table.insert(menuItems, { title = "⚠︎  Add API key — grammar cleanup is off", fn = function()
      hs.execute("open -a Terminal '" .. DIR .. "/dictate-key'")
    end })
  table.insert(menuItems, { title = "-" })
end
for _, item in ipairs({
  { title = "Copy last dictation", fn = function()
      if lastDictation then hs.pasteboard.setContents(lastDictation) end
    end },
  { title = "Open today's log", fn = function()
      hs.execute("open '" .. LOGDIR .. "/" .. os.date("%Y-%m-%d") .. ".md'")
    end },
  { title = "Open debug log", fn = function() hs.execute("open -t '" .. DEBUG_LOG .. "'") end },
  { title = "Edit config", fn = function() hs.execute("open -t '" .. CONF .. "'") end },
  { title = "-" },
  { title = "Reload Hammerspoon", fn = function() hs.reload() end },
}) do table.insert(menuItems, item) end
menu:setMenu(menuItems)

-- macOS disables event taps without warning (slow callback, synthetic events,
-- sleep/wake). Nothing else in this file matters if the tap is dead, so watch it.
dictateTimers = dictateTimers or {}
dictateTimers.tapWatchdog = hs.timer.doEvery(2, function()
  if flagWatcher and not flagWatcher:isEnabled() then
    flagWatcher:start()
    dlog("WATCHDOG: flagWatcher was disabled, restarted it")
  end
end)

-- Re-arm after the display sleeps or the machine wakes, which also kills taps.
dictateTimers.caffeine = hs.caffeinate.watcher.new(function(evt)
  if evt == hs.caffeinate.watcher.systemDidWake
    or evt == hs.caffeinate.watcher.screensDidUnlock then
    if flagWatcher and not flagWatcher:isEnabled() then
      flagWatcher:start()
      dlog("WAKE: restarted flagWatcher")
    end
  end
end):start()

dictateTimers.heartbeat = hs.timer.doEvery(60, function()
  dlog(string.format("heartbeat tap=%s recording=%s locked=%s",
    tostring(flagWatcher:isEnabled()), tostring(recorder ~= nil), tostring(locked)))
end)


dlog("dictate loaded, flagWatcher running=" .. tostring(flagWatcher:isEnabled()))

return true
