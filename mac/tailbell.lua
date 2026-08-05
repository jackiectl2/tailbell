-- Centered, clickable Claude Code alerts. Loaded from ~/.hammerspoon/init.lua.
--
-- Why Hammerspoon: macOS pins Notification Center banners to the top-right and
-- offers no way to move them, no way to put a close button on them, and no way to
-- run code when one is clicked. Tools that reposition them (PingPlace) move EVERY
-- notification on the system. Drawing our own overlay is the only way to get a
-- centered, clickable popup that affects Claude Code alone.
--
-- Why hs.canvas rather than hs.alert: hs.alert cannot take a click, cannot carry
-- an icon, and cannot stay up indefinitely under user control.
--
-- Why driven by URL rather than the `hs` CLI: the CLI is broken on Hammerspoon
-- 1.1.1 (upstream #3847 — cannot detect the running app) and hardcodes /usr/local,
-- the wrong prefix on Apple Silicon (#3088). The hammerspoon:// scheme is handled
-- in-app and needs no cliInstall.
--
--   open -g "hammerspoon://tailbell?title=..&message=..&urgent=1&project=bradley"
--
-- ALERTS DO NOT EXPIRE. They stay until dismissed: click ✕ to close one, click the
-- body to jump to that project's editor window and close, or ⌥Esc to clear all.
-- There is deliberately no timeout — a notification you missed because you stepped
-- away is exactly the one worth keeping.

----------------------------------------------------------------- tunables ------
local THEME = {
  -- "Claude is waiting for you". Pale translucent blue; dark text, because white
  -- on a 0.62-alpha light background is unreadable over bright windows.
  urgent = {
    fill = { red = 0.62, green = 0.80, blue = 0.95, alpha = 0.62 },
    text = { white = 0.05, alpha = 1 },
    size = 34,
  },
  -- "Task finished".
  done = {
    fill = { white = 0, alpha = 0.88 },
    text = { white = 1, alpha = 1 },
    size = 32,
  },
}

local FADE_IN  = 1.4    -- slow rise from invisible, so it never startles
local FADE_OUT = 0.5    -- quicker on the way out: you asked for it to go
local WIDTH    = 680
local PAD      = 28
local CLOSE_SZ = 34     -- the ✕ hit target. Larger than it looks it needs to be,
                        -- because it is now the only way to dismiss an alert.
local GAP      = 14

---------------------------------------------------------------- internals ------
local live = {}         -- every on-screen canvas, oldest first

-- Restack survivors so dismissing one closes the gap. Because alerts no longer
-- expire, the stack can grow; once it would run off the screen the step shrinks
-- and they overlap instead of marching into the void.
-- Group key must be unique per display. getUUID() was used here and can return
-- nil, which collapsed every screen into one bucket — so both copies of an alert
-- were laid out against a single screen's frame and stacked there, leaving the
-- other display empty. id() is a number and always present; the frame origin is a
-- last-resort tiebreaker.
local function screenKey(s)
  local ok, id = pcall(function() return s:id() end)
  if ok and id then return "id:" .. tostring(id) end
  local f = s:fullFrame()
  return string.format("xy:%d,%d", f.x, f.y)
end

local function layout()
  local byScreen = {}
  for _, item in ipairs(live) do
    local id = screenKey(item.screen)
    byScreen[id] = byScreen[id] or { screen = item.screen, items = {} }
    table.insert(byScreen[id].items, item)
  end
  for _, group in pairs(byScreen) do
    -- fullFrame, not frame: we want the geometric centre of the display, not the
    -- centre of the area left over after the menu bar and Dock.
    local f = group.screen:fullFrame()
    local n = #group.items
    local h = group.items[1].h
    local step = h + GAP
    local total = (n - 1) * step + h
    if total > f.h - 40 then                      -- would overflow the display
      step = math.max(34, (f.h - 40 - h) / math.max(n - 1, 1))
      total = (n - 1) * step + h
    end
    local top = f.y + (f.h - total) / 2
    for i, item in ipairs(group.items) do
      item.canvas:topLeft({ x = f.x + (f.w - WIDTH) / 2, y = top + (i - 1) * step })
    end
  end
end

local function dismiss(canvas)
  for i, item in ipairs(live) do
    if item.canvas == canvas then
      table.remove(live, i)
      break
    end
  end
  canvas:hide(FADE_OUT)
  hs.timer.doAfter(FADE_OUT + 0.1, function() canvas:delete() end)
  layout()
end

local function dismissAll()
  for i = #live, 1, -1 do dismiss(live[i].canvas) end
end

-- Frontends Claude Code is commonly driven from. Order is preference, not
-- certainty: hs.application.get simply returns nil for anything not installed, so
-- a wrong or outdated id here costs nothing. Run tailbellApps() to find the real id of
-- something that is not being matched.
local EDITORS = {
  "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders",
  "com.vscodium.codium", "com.visualstudio.code.oss",
  "com.todesktop.230313mzl4w4u92",            -- Cursor
  "dev.zed.Zed", "com.sublimetext.4",
}
local DESKTOP = {
  "com.anthropic.claudefordesktop", "com.anthropic.claude",
  "com.anthropic.claudecode", "com.anthropic.claude-code",
  "Claude", "Claude Code",                     -- get() also accepts a name
}
local TERMINALS = {
  "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
  "net.kovidgoyal.kitty", "com.github.wez.wezterm", "dev.warp.Warp-Stable",
  "io.alacritty", "co.zeit.hyper", "com.raphaelamorim.rio",
}

-- Never hijack a click to one of these just because a window happens to carry the
-- project name — a Finder window on the project folder is the obvious trap.
local NEVER = {
  ["com.apple.finder"] = true, ["com.apple.systempreferences"] = true,
  ["org.hammerspoon.Hammerspoon"] = true, ["com.apple.dock"] = true,
}

local function raise(app, project)
  if not app then return false end
  if project and project ~= "" then
    for _, w in ipairs(app:allWindows()) do
      if (w:title() or ""):find(project, 1, true) then
        app:activate(); w:becomeMain(); w:focus()
        return true
      end
    end
  end
  -- Known app but no window names the project — a terminal usually does not put
  -- the remote directory in its title. Surfacing the app still beats nothing.
  app:activate()
  return true
end

local function tryList(list, project)
  for _, id in ipairs(list) do
    local app = hs.application.get(id)
    if app then
      for _, w in ipairs(app:allWindows()) do
        if project and project ~= "" and (w:title() or ""):find(project, 1, true) then
          app:activate(); w:becomeMain(); w:focus()
          return true
        end
      end
    end
  end
  return false
end

-- Bring whatever Claude Code is running in to the front. This used to assume an
-- editor and hardcode three VS Code bundle ids, so clicks did nothing when Claude
-- Code ran in the desktop app or a terminal.
local function focusOwner(project, app, entrypoint)
  project = project or ""
  -- 1. Exact: the local hook walked its own process tree and told us the app.
  if app and app ~= "" and not NEVER[app] then
    if raise(hs.application.get(app), project) then return true end
  end

  -- 2. Kind: entrypoint survives SSH, unlike a bundle id. Search the matching
  --    family first so a project name that appears in several apps resolves to
  --    the one Claude Code actually reported.
  entrypoint = (entrypoint or ""):lower()
  local order
  if entrypoint:find("vscode") or entrypoint:find("code") then
    order = { EDITORS, DESKTOP, TERMINALS }
  elseif entrypoint:find("desktop") or entrypoint:find("app") then
    order = { DESKTOP, EDITORS, TERMINALS }
  elseif entrypoint:find("cli") or entrypoint:find("term") then
    order = { TERMINALS, EDITORS, DESKTOP }
  else
    order = { EDITORS, DESKTOP, TERMINALS }
  end
  for _, list in ipairs(order) do
    if tryList(list, project) then return true end
  end

  -- 3. Last resort: any window anywhere that names the project.
  if project ~= "" then
    for _, a in ipairs(hs.application.runningApplications()) do
      local id = a:bundleID()
      if id and not NEVER[id] then
        for _, w in ipairs(a:allWindows()) do
          if (w:title() or ""):find(project, 1, true) then
            a:activate(); w:becomeMain(); w:focus()
            return true
          end
        end
      end
    end
  end
  return false
end

local function textHeight(str, size)
  local ok, sz = pcall(function()
    return hs.drawing.getTextDrawingSize(
      hs.styledtext.new(str, { font = { name = ".AppleSystemUIFont", size = size } }),
      { w = WIDTH - 2 * PAD - CLOSE_SZ })
  end)
  if ok and sz and sz.h then return sz.h end
  return size * 2.6          -- generous fallback; too tall beats clipped
end

local function build(text, th, screen, ctx)
  local h = math.max(textHeight(text, th.size) + 2 * PAD, 96)
  -- Create the canvas already at its destination on this display. The previous
  -- version built it at (0,0) — the top-left of the *primary* screen — and then
  -- moved it. With "Displays have separate Spaces" on (the macOS default) that
  -- move is unreliable across displays, so copies meant for the secondary screen
  -- could stay behind on the primary one. Which display an alert landed on then
  -- looked random.
  local f = screen:fullFrame()
  local c = hs.canvas.new({
    x = f.x + (f.w - WIDTH) / 2,
    y = f.y + (f.h - h) / 2,
    w = WIDTH, h = h,
  })
  c:level(hs.canvas.windowLevels.overlay)
  c:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
  c:clickActivating(false)      -- clicking must not raise Hammerspoon itself

  c:appendElements(
    { id = "bg", type = "rectangle", action = "fill",
      roundedRectRadii = { xRadius = 18, yRadius = 18 },
      fillColor = th.fill, trackMouseUp = true },
    { id = "body", type = "text", text = text,
      textColor = th.text, textSize = th.size, textAlignment = "center",
      textFont = ".AppleSystemUIFont",
      frame = { x = PAD + CLOSE_SZ, y = PAD, w = WIDTH - 2 * PAD - CLOSE_SZ, h = h - 2 * PAD },
      trackMouseUp = true },
    -- A filled disc behind the glyph, so the only exit reads as a button.
    { id = "closeBg", type = "circle", action = "fill",
      fillColor = { white = th.text.white, alpha = 0.16 },
      center = { x = 14 + CLOSE_SZ / 2, y = 12 + CLOSE_SZ / 2 },
      radius = CLOSE_SZ / 2, trackMouseUp = true },
    { id = "closeX", type = "text", text = "✕",
      textColor = th.text, textSize = 20, textAlignment = "center",
      frame = { x = 14, y = 12 + (CLOSE_SZ - 26) / 2, w = CLOSE_SZ, h = 26 },
      trackMouseUp = true }
  )

  c:mouseCallback(function(canvas, event, id)
    if event ~= "mouseUp" then return end
    if id == "closeBg" or id == "closeX" then
      dismiss(canvas)
    else
      focusOwner(ctx.project, ctx.app, ctx.entrypoint)
      dismiss(canvas)
    end
  end)
  return c, h
end

function tailbellNotify(title, message, urgent, project, app, entrypoint)
  title = title or "Claude Code"
  message = message or ""
  local th = urgent and THEME.urgent or THEME.done
  local text = message ~= "" and (title .. "\n" .. message) or title

  local ctx = { project = project or "", app = app or "", entrypoint = entrypoint or "" }

  local screens = hs.screen.allScreens()
  if #screens == 0 then screens = { hs.screen.primaryScreen() } end

  -- Build every copy first, lay them all out once, then reveal them together, so
  -- both displays fade in at the same moment instead of one lagging the other.
  local made = {}
  for _, screen in ipairs(screens) do
    local c, h = build(text, th, screen, ctx)
    table.insert(live, { canvas = c, screen = screen, h = h })
    table.insert(made, c)
  end
  layout()
  for _, c in ipairs(made) do
    c:show(FADE_IN)
    -- No timer here on purpose. See the header: alerts persist until dismissed.
  end
end

-- Diagnostic: run tailbellApps() in the Hammerspoon Console to list every running app
-- that has windows, with its real bundle id and window titles. This is how to
-- find the id of a frontend that clicks are failing to reach — the lists above
-- are best guesses, and an app only needs to be added there to be preferred.
function tailbellApps()
  local lines = {}
  for _, a in ipairs(hs.application.runningApplications()) do
    local wins = a:allWindows()
    if #wins > 0 then
      table.insert(lines, string.format("%-34s %s", a:bundleID() or "?",
                                        a:name() or "?"))
      for _, w in ipairs(wins) do
        local t = w:title()
        if t and t ~= "" then table.insert(lines, "      " .. t) end
      end
    end
  end
  local out = table.concat(lines, "\n")
  print(out)
  return out
end

-- Diagnostic: run tailbellScreens() in the Hammerspoon Console to see what Hammerspoon
-- believes about your displays. Useful when an alert lands on the wrong one.
function tailbellScreens()
  local lines = {}
  local primary = hs.screen.primaryScreen()
  for i, s in ipairs(hs.screen.allScreens()) do
    local f = s:fullFrame()
    table.insert(lines, string.format(
      "%d. %-28s key=%-12s frame=(%d,%d %dx%d)%s",
      i, tostring(s:name()), screenKey(s), f.x, f.y, f.w, f.h,
      s == primary and "  [PRIMARY]" or ""))
  end
  table.insert(lines, string.format("当前有 %d 条通知在屏上", #live))
  local out = table.concat(lines, "\n")
  print(out)
  return out
end

-- Receipt file. The sender cannot otherwise tell whether this handler exists:
-- `open` succeeds as long as *something* claims the hammerspoon:// scheme, and
-- Hammerspoon claims it whether or not this config loaded. Without a receipt a
-- failed config load silently swallows every notification with no fallback.
local RECEIPT = os.getenv("HOME") .. "/.tailbell/receipt"

local function writeReceipt(token)
  local f = io.open(RECEIPT, "w")
  if f then f:write(token or "") f:close() end
end

hs.urlevent.bind("tailbell", function(_, params)
  params = params or {}
  tailbellNotify(params.title, params.message,
           params.urgent == "1" or params.urgent == "true",
           params.project, params.app, params.entrypoint)
  -- Written only after the alert is actually on screen, so the sender's check
  -- means "this was rendered", not merely "the URL was delivered".
  writeReceipt(params.nonce)
end)

hs.hotkey.bind({ "alt" }, "escape", dismissAll)

-- A config reload tears down this Lua state; without this the canvases would be
-- orphaned on screen with nothing left alive to dismiss them.
hs.shutdownCallback = dismissAll

-- Proves the whole file parsed and every binding above registered. If this line
-- is never reached the receipt stays stale and senders fall back automatically.
writeReceipt("loaded")

-- Load confirmation only. This one is transient by design — it reports that the
-- config parsed, and is not a notification you could miss anything by losing.
-- Shown on every display, for the same reason real alerts are: seeing it on one
-- screen and not the other is exactly the symptom we are trying to rule out.
for _, s in ipairs(hs.screen.allScreens()) do
  hs.alert.show("Claude Code 通知已就绪 · 点正文跳转 · ✕ 关闭 · ⌥Esc 全清",
                { atScreenEdge = 0, textSize = 20 }, s, 3)
end
