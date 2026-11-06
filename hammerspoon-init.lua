-- Hammerspoon config. Each feature is its own file in ~/.hammerspoon/.

-- Command-line access (`hs -c "..."`) for debugging.
local ok, ipc = pcall(require, "hs.ipc")
if ok then pcall(function() ipc.cliInstall(os.getenv("HOME") .. "/.local") end) end

-- Auto-reload when any .lua file here changes, so edits take effect immediately.
-- ~/.hammerspoon holds only symlinks, so watch the real directory the files
-- live in, or edits would never trigger a reload. Resolve it from this file.
local SELF  = hs.fs.pathToAbsolute(debug.getinfo(1, "S").source:sub(2))
local WATCH = ((SELF and SELF:match("^(.*)/[^/]+$"))
               or (os.getenv("HOME") .. "/.hammerspoon")) .. "/"
hs.configWatcher = hs.pathwatcher.new(WATCH, function(files)
  for _, f in pairs(files) do
    if f:sub(-4) == ".lua" then
      -- Never wipe state mid-dictation, but do not drop the reload either:
      -- keep checking until the recording is done.
      local function reloadWhenIdle()
        if hs.dictateRecording then
          hs.pendingReload = hs.timer.doAfter(1, reloadWhenIdle)
        else
          hs.reload()
        end
      end
      reloadWhenIdle()
      return
    end
  end
end):start()

-- Start at login and stay out of the Dock; dictation is useless if HS isn't up.
hs.autoLaunch(true)
hs.menuIcon(true)
hs.dockIcon(false)
hs.consoleOnTop(false)

require("dictate")

-- Permission check: the Fn watcher cannot work without Accessibility.
local dbg = io.open(os.getenv("HOME") .. "/.local/share/dictate/debug.log", "a")
if dbg then
  dbg:write(os.date("%H:%M:%S ") .. "accessibility=" .. tostring(hs.accessibilityState()) .. "\n")
  dbg:close()
end

if not hs.accessibilityState() then
  hs.alert.show("Hammerspoon needs Accessibility permission — dictation is OFF", 6)
  hs.dictateAccessibility = false
else
  hs.dictateAccessibility = true
  hs.alert.show("Hammerspoon ready — hold Fn to dictate", 1.5)
end
