-- Combined Autoplay + Auto-Green with Config System
-- Autoplay tab: rhythm game autoplayer
-- Auto-Green tab: basketball auto-release

local function safeGet(fn)
	local ok, v = pcall(fn)
	if ok then
		return v
	end
	return nil
end

local RS = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- ============================================================
-- AUTOPLAY MODULE
-- ============================================================
local ap = {
	enabled = false,
	showESP = false,
	currentKeys = { 0x58, 0x43, 0x4E, 0x4D },
	activeLaneCount = 4,
}

local apConstants = {
	HOLD_MIN_H = 20,
	TAP_HOLD_SEC = 0.05,
	TOUCH_DIST = 30,
	PAST_CATCH = 30,
	APPROACH_DIST = 300,
	MIN_DIST_X = 100,
	LINE_THICK = 4,
	CIRCLE_RADIUS = 20,
	CIRCLE_SIDES = 48,
	CIRCLE_THICK = 2,
	TAIL_THICK = 5,
	MAX_CIRCLES = 8,
	LANE_COLORS = {
		Color3.fromRGB(180, 255, 180),
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(100, 220, 100),
		Color3.fromRGB(60, 180, 60),
	},
	COLOR_ON_LINE = Color3.fromRGB(255, 255, 255),
	COLOR_HOLD = Color3.fromRGB(150, 255, 150),
	COLOR_APPROACH = Color3.fromRGB(100, 130, 100),
	LINE_COLOR = Color3.fromRGB(255, 255, 255),
}

local hitLine = Drawing.new("Line")
hitLine.Color = apConstants.LINE_COLOR
hitLine.Thickness = apConstants.LINE_THICK
hitLine.Visible = false
hitLine.ZIndex = 5

local circles = {}
local tails = {}
for lane = 1, 4 do
	circles[lane] = {}
	tails[lane] = {}
	for j = 1, apConstants.MAX_CIRCLES do
		local c = Drawing.new("Circle")
		c.NumSides = apConstants.CIRCLE_SIDES
		c.Radius = apConstants.CIRCLE_RADIUS
		c.Thickness = apConstants.CIRCLE_THICK
		c.Filled = false
		c.Visible = false
		c.ZIndex = 10
		circles[lane][j] = c

		local t = Drawing.new("Line")
		t.Thickness = apConstants.TAIL_THICK
		t.Visible = false
		t.ZIndex = 9
		tails[lane][j] = t
	end
end

local function apHideESP()
	hitLine.Visible = false
	for lane = 1, 4 do
		for j = 1, apConstants.MAX_CIRCLES do
			circles[lane][j].Visible = false
			tails[lane][j].Visible = false
		end
	end
end

local function apRemoveAll()
	pcall(function()
		hitLine:Remove()
	end)
	for lane = 1, 4 do
		for j = 1, apConstants.MAX_CIRCLES do
			pcall(function()
				circles[lane][j]:Remove()
			end)
			pcall(function()
				tails[lane][j]:Remove()
			end)
		end
	end
end

local apTapping = {}
local apTapRelease = {}
local apHolding = {}
local apHoldStartTime = {}
local apFired = {}
for i = 1, 4 do
	apTapping[i] = false
	apTapRelease[i] = 0
	apHolding[i] = nil
	apHoldStartTime[i] = 0
	apFired[i] = {}
end

local function apReleaseAllKeys()
	for i = 1, 4 do
		if ap.currentKeys[i] then
			keyrelease(ap.currentKeys[i])
		end
		apTapping[i] = false
		apHolding[i] = nil
		apHoldStartTime[i] = 0
		apFired[i] = {}
	end
end

local uiLanesContainer = nil
local uiReceptorData = nil
local guiActive = false

local function setupGUI()
	local pg = safeGet(function()
		return Players.LocalPlayer.PlayerGui
	end)
	if not pg then
		return false
	end
	local rsUI = safeGet(function()
		return pg:FindFirstChild("RhythmServiceUI")
	end)
	if not rsUI then
		return false
	end
	local root = safeGet(function()
		return rsUI:FindFirstChild("RhythmRoot")
	end)
	if not root then
		return false
	end
	local receptors = safeGet(function()
		return root:FindFirstChild("Receptors")
	end)
	local lanesHost = safeGet(function()
		return root:FindFirstChild("Lanes")
	end)
	if not receptors or not lanesHost then
		return false
	end

	local newReceptors = {}
	local validLanes = 0

	for i = 1, 4 do
		local rec = safeGet(function()
			return receptors:FindFirstChild("Receptor" .. i)
		end)
		if rec then
			local bap = safeGet(function()
				return rec.AbsolutePosition
			end)
			local bas = safeGet(function()
				return rec.AbsoluteSize
			end)
			if bap and bas then
				newReceptors[i] = {
					inst = rec,
					cx = bap.X + (bas.X / 2),
					cy = bap.Y + (bas.Y / 2),
					hitY = bap.Y + (bas.Y / 2),
				}
				validLanes = validLanes + 1
			end
		end
	end

	if validLanes == 0 then
		return false
	end

	ap.activeLaneCount = validLanes
	if ap.activeLaneCount == 2 then
		ap.currentKeys = { 0x46, 0x4A }
	else
		ap.currentKeys = { 0x58, 0x43, 0x4E, 0x4D }
		ap.activeLaneCount = 4
	end

	uiReceptorData = newReceptors
	uiLanesContainer = lanesHost
	guiActive = true

	local scale = 1
	local cam = Workspace.CurrentCamera
	if cam then
		scale = cam.ViewportSize.Y / 1080
	end

	local lx = (newReceptors[1] and newReceptors[1].cx or 0) - (50 * scale)
	local rx = (newReceptors[ap.activeLaneCount] and newReceptors[ap.activeLaneCount].cx or 0) + (50 * scale)
	local y = newReceptors[1].hitY
	hitLine.From = Vector2.new(lx, y)
	hitLine.To = Vector2.new(rx, y)

	if ap.enabled and ap.showESP then
		hitLine.Visible = true
	end
	return true
end

local function checkGone()
	local pg = safeGet(function()
		return Players.LocalPlayer.PlayerGui
	end)
	if not pg then
		return true
	end
	local rsUI = safeGet(function()
		return pg:FindFirstChild("RhythmServiceUI")
	end)
	return not rsUI
end

local cachedScale = 1
local cachedCam = nil
local lastScaleUpdate = 0
local lastCheck = 0

setupGUI()

-- ============================================================
-- AUTO-GREEN MODULE
-- (v7) Matcha quirks:
--   * NO DescendantAdded / DescendantRemoving events -> no events.
--   * transient character instances do NOT keep a valid .Parent,
--     so the meter is NEVER cached and .Parent is NEVER trusted.
--     Every tick re-finds the meter FRESH with a cheap targeted
--     FindFirstChild lookup on the character (0.1s), falling back
--     to a hint-based character scan (0.5s).
--   * character-only, so the laggy full PlayerGui sweep is gone.
--   * ignores candidates shorter than MIN_METER_H so small
--     unrelated bars (e.g. SignalFrame) never qualify.
--   * measures the needle as a FILL FRACTION (needle AS.Y / meter
--     AS.Y) so bottom-anchored fill bars map 0..1 correctly.
--   * releases E the first time the needle crosses the release
--     target while moving (works for rising or falling meters).
-- ============================================================
local ag = {
	enabled = false,
	SHOOT_KEY = 0x45, -- E
	RELEASE_TARGET = 0.65,
	shotCount = 0,
	lastReleaseTime = 0,
}

local agMeterFound = false
local agPrevProg = nil
local agLastHintPoll = -9
local AG_HINT_INTERVAL = 0.5
local MIN_METER_H = 60
local METER_BAR_NAME = "BasketballShotMeterBar"
local TRACK_NAME = "Track"

local METER_HINTS = { "meter", "needle", "shoot", "power", "aim", "green", "shot" }
local NEEDLE_HINTS = { "needle", "sweep", "fill", "indicator", "marker" }

local function nameLower(inst)
	return (safeGet(function()
		return inst.Name
	end) or ""):lower()
end

local function hasAnyHint(name, hints)
	for i = 1, #hints do
		if name:find(hints[i], 1, true) then
			return true
		end
	end
	return false
end

local function isNeedleish(inst)
	return hasAnyHint(nameLower(inst), NEEDLE_HINTS)
end

local function isMeterish(inst)
	return hasAnyHint(nameLower(inst), METER_HINTS)
end

local function isGUIish(class)
	return class == "Frame"
		or class == "ImageLabel"
		or class == "ImageButton"
		or class == "TextButton"
		or class == "BillboardGui"
		or class == "ScreenGui"
		or class == "SurfaceGui"
end

local function isCoreUI(inst)
	local n = nameLower(inst)
	return n == "topbarinset" or n:find("topbar", 1, true)
end

local function findNeedleIn(meter)
	local direct = safeGet(function()
		return meter:FindFirstChild("Needle", true)
	end)
	if direct then
		return direct
	end
	for _, d in
		ipairs(safeGet(function()
			return meter:GetDescendants()
		end) or {})
	do
		if isNeedleish(d) then
			return d
		end
	end
	return nil
end

local function nodeIsMeter(node)
	if not isGUIish(safeGet(function()
		return node.ClassName
	end) or "") then
		return false
	end
	for _, c in
		ipairs(safeGet(function()
			return node:GetChildren()
		end) or {})
	do
		if isNeedleish(c) then
			return true
		end
	end
	if isMeterish(node) then
		return findNeedleIn(node) ~= nil
	end
	return false
end

local function screenHeightLimit()
	local cam = Workspace.CurrentCamera
	local vs = cam and safeGet(function()
		return cam.ViewportSize
	end)
	if vs then
		return vs.Y * 0.6
	end
	return math.huge
end

local function scanSubtreeForMeter(root)
	local best = nil
	local bestY = -1
	local limit = screenHeightLimit()
	for _, d in
		ipairs(safeGet(function()
			return root:GetDescendants()
		end) or {})
	do
		if not isCoreUI(d) and nodeIsMeter(d) then
			local as = safeGet(function()
				return d.AbsoluteSize
			end)
			local h = as and as.Y or 0
			if h >= MIN_METER_H and h < limit and h > bestY then
				best = d
				bestY = h
			end
		end
	end
	return best
end

local function agPathString(inst)
	local parts = {}
	local cur = inst
	while cur and #parts < 10 do
		table.insert(parts, 1, safeGet(function()
			return cur.Name
		end) or "?")
		cur = safeGet(function()
			return cur.Parent
		end)
	end
	return table.concat(parts, ".")
end

local function agGetMeter(now)
	if not ag.enabled then
		return nil
	end
	local lp = safeGet(function()
		return Players.LocalPlayer
	end)
	local char = lp and safeGet(function()
		return Workspace.Players:FindFirstChild(lp.Name)
	end)
	if not char then
		return nil
	end
	local meter = safeGet(function()
		local bar = char:FindFirstChild(METER_BAR_NAME, true)
		return bar and bar:FindFirstChild(TRACK_NAME)
	end)
	if not meter and (now or os.clock()) - agLastHintPoll >= AG_HINT_INTERVAL then
		agLastHintPoll = os.clock()
		meter = scanSubtreeForMeter(char)
	end
	if meter then
		if not agMeterFound then
			agMeterFound = true
			print(string.format("[AutoGreen] meter found: %s", agPathString(meter)))
		end
		return meter
	end
	return nil
end

local function getNeedleProgress(meter, needle)
	if not needle then
		return nil
	end
	local nAs = safeGet(function()
		return needle.AbsoluteSize
	end)
	local mAs = safeGet(function()
		return meter.AbsoluteSize
	end)
	if not nAs or not mAs or mAs.Y <= 0 then
		return nil
	end
	return math.clamp(nAs.Y / mAs.Y, 0, 1)
end

-- ============================================================
-- apFired cleanup (prevents unbounded growth)
-- ============================================================
local lastFiredCleanup = 0
local CLEANUP_INTERVAL = 2

local function cleanupFired()
	local now = os.clock()
	if now - lastFiredCleanup < CLEANUP_INTERVAL then
		return
	end
	lastFiredCleanup = now
	if not uiLanesContainer then
		return
	end
	for lane = 1, 4 do
		local laneF = apFired[lane]
		for note in pairs(laneF) do
			if not safeGet(function()
				return note.Parent
			end) then
				laneF[note] = nil
			end
		end
	end
end

-- ============================================================
-- COMBINED RENDER LOOP
-- ============================================================
local conn = RS.RenderStepped:Connect(function(dt)
	if not isrbxactive() then
		return
	end
	local now = os.clock()

	-- AUTOPLAY TICK
	if ap.enabled then
		if now - lastScaleUpdate >= 0.25 then
			lastScaleUpdate = now
			cachedCam = Workspace.CurrentCamera
			if cachedCam then
				cachedScale = cachedCam.ViewportSize.Y / 1080
			end
		end

		if now - lastCheck >= 0.5 then
			lastCheck = now
			if guiActive then
				if checkGone() then
					guiActive = false
					apHideESP()
					apReleaseAllKeys()
				end
			else
				setupGUI()
			end
		end

		if guiActive and uiReceptorData then
			if ap.showESP then
				hitLine.Thickness = apConstants.LINE_THICK * cachedScale
				hitLine.Visible = true
			end

			for lane = 1, 4 do
				for j = 1, apConstants.MAX_CIRCLES do
					circles[lane][j].Visible = false
					tails[lane][j].Visible = false
				end
			end

			for lane = 1, ap.activeLaneCount do
				local vk = ap.currentKeys[lane]
				if apTapping[lane] and now >= apTapRelease[lane] then
					keyrelease(vk)
					apTapping[lane] = false
				end

				if apHolding[lane] then
					local h = apHolding[lane]
					local dead = false

					if not dead then
						local parent = safeGet(function()
							return h.inst.Parent
						end)
						if not parent then
							dead = true
						else
							local head = safeGet(function()
								return h.inst:FindFirstChild("Head")
							end)
							if not head then
								dead = true
							else
								local ap2 = safeGet(function()
									return head.AbsolutePosition
								end)
								local as = safeGet(function()
									return head.AbsoluteSize
								end)
								if not ap2 or not as then
									dead = true
								else
									local headCY = ap2.Y + (as.Y / 2)
									local tail = safeGet(function()
										return h.inst:FindFirstChild("Tail")
									end)
									local tailH = (
										tail
										and safeGet(function()
											return tail.AbsoluteSize.Y
										end)
									) or 0
									local hitY = uiReceptorData[lane].hitY
									if tailH < 4 or (headCY - tailH) >= hitY then
										dead = true
									end
								end
							end
						end
					end

					if dead then
						keyrelease(vk)
						apHolding[lane] = nil
						apHoldStartTime[lane] = 0
					end
				end
			end

			cleanupFired()

			local rawNotes = safeGet(function()
				return uiLanesContainer:GetChildren()
			end)
			if rawNotes then
				local laneNotes = { {}, {}, {}, {} }

				for i = 1, #rawNotes do
					local note = rawNotes[i]
					local proceed = true

					if safeGet(function()
						return note.ClassName
					end) ~= "Frame" then
						proceed = false
					end
					if proceed and safeGet(function()
						return note.Name
					end) ~= "NoteTemplate" then
						proceed = false
					end

					local head
					if proceed then
						head = safeGet(function()
							return note:FindFirstChild("Head")
						end)
					end
					if proceed and not head then
						proceed = false
					end

					local ap2, as
					if proceed then
						ap2 = safeGet(function()
							return head.AbsolutePosition
						end)
						as = safeGet(function()
							return head.AbsoluteSize
						end)
					end
					if proceed and (not ap2 or not as) then
						proceed = false
					end

					local headCX, headCY
					local bestLane, minDistX
					if proceed then
						headCX = ap2.X + (as.X / 2)
						headCY = ap2.Y + (as.Y / 2)

						bestLane = nil
						minDistX = math.huge
						for li = 1, ap.activeLaneCount do
							if uiReceptorData[li] then
								local dx = math.abs(headCX - uiReceptorData[li].cx)
								if dx < minDistX then
									minDistX = dx
									bestLane = li
								end
							end
						end
					end
					if proceed and (not bestLane or minDistX > apConstants.MIN_DIST_X) then
						proceed = false
					end

					local laneF, hitY, distY
					if proceed then
						laneF = apFired[bestLane]
						if laneF[note] then
							if not safeGet(function()
								return note.Parent
							end) then
								laneF[note] = nil
							end
							proceed = false
						end
					end
					if proceed then
						hitY = uiReceptorData[bestLane].hitY
						distY = headCY - hitY
						if distY > apConstants.PAST_CATCH then
							laneF[note] = true
							proceed = false
						end
					end
					if proceed and distY < -apConstants.APPROACH_DIST then
						proceed = false
					end

					if proceed then
						local tail = safeGet(function()
							return note:FindFirstChild("Tail")
						end)
						local tailH = (tail and safeGet(function()
							return tail.AbsoluteSize.Y
						end)) or 0
						local isHold = tailH > apConstants.HOLD_MIN_H

						laneNotes[bestLane][#laneNotes[bestLane] + 1] = {
							note = note,
							headCY = headCY,
							dist = distY,
							isHold = isHold,
							tailH = tailH,
						}
					end
				end

				for lane = 1, ap.activeLaneCount do
					local rd = uiReceptorData[lane]
					if rd then
						local vk = ap.currentKeys[lane]
						local cx = rd.cx
						local notes = laneNotes[lane]
						local laneF = apFired[lane]

						table.sort(notes, function(a, b)
							return a.headCY < b.headCY
						end)

						for j = 1, #notes do
							if j > apConstants.MAX_CIRCLES then
								break
							end
							local e = notes[j]
							local onLine = e.dist >= -apConstants.TOUCH_DIST and e.dist <= apConstants.PAST_CATCH

							if ap.showESP then
								local c = circles[lane][j]
								local t = tails[lane][j]
								local col
								if onLine then
									col = apConstants.COLOR_ON_LINE
								elseif e.dist < -apConstants.TOUCH_DIST then
									local fade = 1 - (math.abs(e.dist) / apConstants.APPROACH_DIST)
									local r = apConstants.COLOR_APPROACH.R
										+ (apConstants.LANE_COLORS[lane].R - apConstants.COLOR_APPROACH.R) * fade
									local g = apConstants.COLOR_APPROACH.G
										+ (apConstants.LANE_COLORS[lane].G - apConstants.COLOR_APPROACH.G) * fade
									local b = apConstants.COLOR_APPROACH.B
										+ (apConstants.LANE_COLORS[lane].B - apConstants.COLOR_APPROACH.B) * fade
									col = Color3.new(r, g, b)
								else
									col = e.isHold and apConstants.COLOR_HOLD or apConstants.LANE_COLORS[lane]
								end

								c.Color = col
								c.Radius = apConstants.CIRCLE_RADIUS * cachedScale
								c.Thickness = apConstants.CIRCLE_THICK * cachedScale
								c.Filled = e.isHold and not onLine
								c.Position = Vector2.new(cx, e.headCY)
								c.Visible = true

								if e.isHold and e.tailH > 0 then
									t.From = Vector2.new(cx, e.headCY)
									t.To = Vector2.new(cx, e.headCY - e.tailH)
									t.Thickness = apConstants.TAIL_THICK * cachedScale
									t.Color = col
									t.Visible = true
								end
							end

							if onLine and not apTapping[lane] and not apHolding[lane] then
								laneF[e.note] = true
								if e.isHold then
									keypress(vk)
									apHolding[lane] = { inst = e.note, tailH = e.tailH }
									apHoldStartTime[lane] = now
								else
									keypress(vk)
									apTapping[lane] = true
									apTapRelease[lane] = now + apConstants.TAP_HOLD_SEC
								end
								break
							end
						end
					end
				end
			end
		elseif not ap.enabled then
			apHideESP()
		end
	end

	-- AUTO-GREEN TICK
	if ag.enabled then
		local meter = agGetMeter(now)
		if not meter then
			agPrevProg = nil
		else
			local needle = findNeedleIn(meter)
			local progress = getNeedleProgress(meter, needle)
			if needle and progress then
				local prev = agPrevProg
				agPrevProg = progress
				local target = ag.RELEASE_TARGET
				if prev then
					local delta = progress - prev
					local crossedUp = prev < target and progress >= target and delta >= 0.004
					local crossedDown = prev > target and progress <= target and delta <= -0.004
					if (crossedUp or crossedDown) and (now - ag.lastReleaseTime) > 0.15 then
						ag.lastReleaseTime = now
						ag.shotCount = ag.shotCount + 1
						print(
							string.format(
								"[Shot #%d] RELEASE at %.2f%% (target %.2f%%)",
								ag.shotCount,
								progress * 100,
								target * 100
							)
						)
						keyrelease(ag.SHOOT_KEY)
					end
				end
			end
		end
	end
end)

-- ============================================================
-- UI
-- ============================================================
local VERSION = "2.3.1"

local Lib = loadstring(game:HttpGet("https://raw.githubusercontent.com/neaxusxgod-png/INS-ui/main/uilib.min.lua"))()
	or INSui
local win = Lib:CreateWindow({
	title = "Gakuran",
	subtitle = "v" .. VERSION,
	size = Vector2.new(550, 350),
	menuKey = "f1",
	configName = "default",
	autoSave = true,
})
win:AddSettingsTab()
Lib:ApplyThemePreset("Waifu")

-- AUTOPLAY TAB
local apTab = win:Tab("Autoplay", "sparkles")
local apSec = apTab:Section("Settings", "Full")

apSec:Toggle("autoplay", false, function(v)
	ap.enabled = v
	if not ap.enabled then
		apReleaseAllKeys()
		apHideESP()
	end
end)

apSec:Toggle("visual", false, function(v)
	ap.showESP = v
	if not ap.showESP then
		apHideESP()
	end
end)

apSec:Colorpicker("hit line color", apConstants.LINE_COLOR, function(c, a)
	apConstants.LINE_COLOR = c
	hitLine.Color = c
end)

apSec:Colorpicker("circle color", apConstants.LANE_COLORS[1], function(c, a)
	apConstants.LANE_COLORS[1] = c
	apConstants.LANE_COLORS[2] = c
	apConstants.LANE_COLORS[3] = c
	apConstants.LANE_COLORS[4] = c
end)

apSec:Colorpicker("hold color", apConstants.COLOR_HOLD, function(c, a)
	apConstants.COLOR_HOLD = c
end)

-- AUTO-GREEN TAB
local agTab = win:Tab("Auto-Green", "target")
local agSec = agTab:Section("Settings", "Full", "You may need to change the % a little yourself to get 100% perfect")

agSec:Toggle("auto green", false, function(v)
	ag.enabled = v
	if ag.enabled then
		agPrevProg = nil
		agMeterFound = false
		agLastHintPoll = -9
	else
		agPrevProg = nil
		agMeterFound = false
		keyrelease(ag.SHOOT_KEY)
	end
end)

agSec:Slider("release target %", 65, 0.1, 10, 80, "%", function(v)
	ag.RELEASE_TARGET = v / 100
	print("[AutoGreen] Release target: " .. v .. "%")
end)

agSec:Label("Hold E to and it releases for you.")

-- VERSION INFO
local infoTab = win:Tab("Info", "sparkles")
local infoSec = infoTab:Section("Version", "Full")
infoSec:Label("Gakuran v" .. VERSION)
infoSec:Label("Autoplay + Auto-Green")

local tipsSec = infoTab:Section("Auto-Green Guide", "Full")
tipsSec:Info(
	"Hold E to start the shot meter, the script releases when the bar hits the target %.\n\nHigher % = releases when the bar is fuller (later)\nLower % = releases when the bar is emptier (sooner)\n\nThe bar fills over the first part of the charge, so aim HIGH. Start around 65% and tweak from there - different in-game heights may need a slight adjustment for 100% perfects."
)

local warnSec = infoTab:Section("Warning", "Full")
warnSec:Info(
	"Keep Auto-Green turned OFF unless you're actually using the basketballs.\n\nLeaving it on in the background causes lag even when idle."
)

-- agSec:Label("")

pcall(function()
	notify("loaded")
end)
