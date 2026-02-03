--[[
	WIM_Tabs - Tabbed interface for WIM windows
	Consolidates all whisper windows into one location with clickable tabs.
]]

-- State
local Tabs = {
	buttons = {},
	order = {},
	active = nil,
	bar = nil,
	anchor = { left = nil, top = nil },
	barDragging = false,  -- True when dragging via the bar
	flashOn = false,
	switching = false,
	scrollOffset = 0,
	minimized = false,
	skipAnchor = false,  -- Skip ApplyAnchor in Show hook (when restoring from minimized)
	unreadCount = 0,
	layoutPending = false,
	layoutFrame = nil,
	layoutState = nil,
	growDirection = (WIM_Extras and WIM_Extras.db and WIM_Extras.db.tabGrowDirection) or "LEFT",
	flashEnabled = (WIM_Extras and WIM_Extras.db and WIM_Extras.db.tabFlashEnabled) ~= false,
	flashColor = (WIM_Extras and WIM_Extras.db and WIM_Extras.db.tabFlashColor) or { r = 1, g = 0.8, b = 0.2, a = 0.7 },
	flashUseClassColor = (WIM_Extras and WIM_Extras.db and WIM_Extras.db.tabFlashUseClassColor) == true,
	flashInterval = (WIM_Extras and WIM_Extras.db and WIM_Extras.db.tabFlashInterval) or 0.8,
	barHeight = (WIM_Extras and WIM_Extras.db and WIM_Extras.db.tabBarHeight) or 20,
	barPosition = (WIM_Extras and WIM_Extras.db and WIM_Extras.db.tabBarPosition) or "TOP",
	sortMode = (WIM_Extras and WIM_Extras.db and WIM_Extras.db.tabSortMode) or "none",
}

-- Expose for external skinning (e.g., pfUI integration)
WIM_TabsState = Tabs

-- Original functions we hook
local Orig = {}

-- Constants
local TAB_SPACING = 2
local MIN_TAB_WIDTH = 50
local MAX_TAB_WIDTH = 400
local SCROLL_BTN_WIDTH = 16
local MAX_TABS_BEFORE_SCROLL = 4  -- Dynamic sizing up to this many tabs
local TAB_CLASS_DIM = 0.75

local function GetTabHeight()
	return (Tabs.barHeight and Tabs.barHeight > 0) and Tabs.barHeight or 20
end

local function GetMaxScrollOffset(tabCount)
	local visible = MAX_TABS_BEFORE_SCROLL
	return math.max(0, (tabCount or 0) - visible)
end

local function ResetScrollOffsetForGrowth()
	local tabCount = table.getn(Tabs.order)
	if Tabs.growDirection == "RIGHT" then
		Tabs.scrollOffset = GetMaxScrollOffset(tabCount)
	else
		Tabs.scrollOffset = 0
	end
end

-- Skinning hook - call this function when a tab is created
-- External addons can replace this to apply custom styling
WIM_Tabs_OnSkinTab = nil
WIM_Tabs_OnSkinBar = nil
WIM_Tabs_OnUpdateTabLook = nil  -- Called when tab appearance updates (active/inactive/flash)
WIM_Tabs_OnUpdateScrollFlash = nil  -- Called when scroll button flash state changes
WIM_Tabs_OnEnsureFont = nil  -- Called when a WIM frame should re-apply font settings

-- Forward declarations for functions referenced before definition
local RemoveTab
local UpdateTabLook
local SaveAnchor
local UpdateTabVisuals
local ToggleConversationMenu
local BumpToFront

-- Helpers
local FrameUsers = setmetatable({}, { __mode = "k" })

local function GetFrame(user)
	return getglobal("WIM_msgFrame" .. user)
end

local function SafeName(name)
	return string.gsub(name or "", "[^%w]", "")
end

local function WasEditBoxFocusedForActive()
	if not WIM_EditBoxInFocus or not WIM_EditBoxInFocus.GetParent then return false end
	local parent = WIM_EditBoxInFocus:GetParent()
	if not parent or not parent.theUser then return false end
	return parent.theUser == Tabs.active
end

local function FocusEditBoxForUser(user)
	if not user or user == "" then return end
	local msgBox = getglobal("WIM_msgFrame" .. user .. "MsgBox")
	if msgBox and msgBox.SetFocus then
		msgBox:SetFocus()
	end
end

local function HexToRGB(hex)
	if not hex or hex == "" then return nil end
	if string.len(hex) > 6 and string.sub(hex, 1, 2) == "ff" then
		hex = string.sub(hex, 3)
	end
	if string.len(hex) ~= 6 then return nil end
	local r = tonumber(string.sub(hex, 1, 2), 16)
	local g = tonumber(string.sub(hex, 3, 4), 16)
	local b = tonumber(string.sub(hex, 5, 6), 16)
	if not r or not g or not b then return nil end
	return r / 255, g / 255, b / 255
end

local ClassColorCache = {}

local function GetWimClassColor(user)
	if not (WIM_PlayerCache and WIM_PlayerCache[user]) then return nil end
	local class = WIM_PlayerCache[user].class
	if not class or class == "" then return nil end
	if WIM_ClassColors and WIM_ClassColors[class] then
		return HexToRGB(WIM_ClassColors[class])
	end
	return nil
end

local function GetCachedClassColor(user)
	local cached = ClassColorCache[user]
	if cached then
		if cached.r and cached.g and cached.b then
			return cached.r, cached.g, cached.b
		end
	end
	return nil
end

local function UpdateClassColorCache(user, r, g, b, source)
	if not user or not r or not g or not b then return end
	ClassColorCache[user] = { r = r, g = g, b = b, source = source, missAt = nil }
end

local function GetClassColor(user)
	local r, g, b = GetWimClassColor(user)
	if r then
		UpdateClassColorCache(user, r, g, b, "wim")
		return r, g, b
	end
	local now = (GetTime and GetTime()) or 0
	local cached = ClassColorCache[user]
	if cached and cached.missAt and (now - cached.missAt) < 2 then
		return nil
	end
	if WIM_Tabs_GetExternalClassColor then
		r, g, b = WIM_Tabs_GetExternalClassColor(user)
		if r and g and b then
			UpdateClassColorCache(user, r, g, b, "external")
			return r, g, b
		end
	end
	if not cached or not cached.missAt then
		ClassColorCache[user] = { missAt = now, source = "miss" }
	end
	return GetCachedClassColor(user)
end

function WIM_Tabs_GetClassColorForUser(user)
	return GetClassColor(user)
end

local function UpdateUnitClassCacheFromUnit(unit)
	if not unit or not UnitName then return end
	local name = UnitName(unit)
	if not name then return end
	if WIM_PlayerCache and WIM_PlayerCache[name] and WIM_PlayerCache[name].class and WIM_PlayerCache[name].class ~= "" then
		return
	end
	local _, class = UnitClass(unit)
	if not class or not RAID_CLASS_COLORS or not RAID_CLASS_COLORS[class] then return end
	local color = RAID_CLASS_COLORS[class]
	UpdateClassColorCache(name, color.r, color.g, color.b, "unit")
	local btn = Tabs.buttons[name]
	if btn then UpdateTabLook(btn) end
end

local function UpdateUnitClassCache()
	if not Tabs.buttons then return end
	UpdateUnitClassCacheFromUnit("target")
	for i = 1, GetNumPartyMembers() do
		UpdateUnitClassCacheFromUnit("party" .. i)
	end
	for i = 1, GetNumRaidMembers() do
		UpdateUnitClassCacheFromUnit("raid" .. i)
	end
end

local function InsertTabOrder(user)
	if Tabs.growDirection == "RIGHT" then
		table.insert(Tabs.order, user)
	else
		table.insert(Tabs.order, 1, user)
	end
end

local function UpdateFlashTicker()
	if not Tabs.flashFrame then return end
	if not Tabs.flashEnabled then
		Tabs.flashOn = false
		Tabs.flashFrame:Hide()
		return
	end
	if Tabs.unreadCount and Tabs.unreadCount > 0 then
		Tabs.flashFrame:Show()
	else
		Tabs.flashFrame:Hide()
	end
end

local function SetTabUnread(btn, isUnread)
	if not btn then return end
	if btn.unread == isUnread then return end
	btn.unread = isUnread
	if isUnread then
		Tabs.unreadCount = (Tabs.unreadCount or 0) + 1
	else
		Tabs.unreadCount = math.max(0, (Tabs.unreadCount or 0) - 1)
	end
	UpdateFlashTicker()
end

local function ApplyFlashColor()
	local c = Tabs.flashColor or { r = 1, g = 0.8, b = 0.2, a = 0.7 }
	if Tabs.bar and Tabs.bar.scrollLeft and Tabs.bar.scrollLeft.flash then
		Tabs.bar.scrollLeft.flash:SetTexture(c.r, c.g, c.b, 1)
	end
	if Tabs.bar and Tabs.bar.scrollRight and Tabs.bar.scrollRight.flash then
		Tabs.bar.scrollRight.flash:SetTexture(c.r, c.g, c.b, 1)
	end
	if not Tabs.flashUseClassColor then
		for _, btn in pairs(Tabs.buttons) do
			if btn.flash then
				btn.flash:SetTexture(c.r, c.g, c.b, 1)
			end
		end
	end
end

local function ApplyBarHeight()
	local h = GetTabHeight()
	if Tabs.bar then
		Tabs.bar:SetHeight(h)
	end
	if Tabs.bar and Tabs.bar.scrollLeft then
		Tabs.bar.scrollLeft:SetHeight(h)
	end
	if Tabs.bar and Tabs.bar.scrollRight then
		Tabs.bar.scrollRight:SetHeight(h)
	end
	for _, btn in pairs(Tabs.buttons) do
		if btn and btn.SetHeight then
			btn:SetHeight(h)
		end
	end
	if Tabs.layout then Tabs.layout() end
end

function WIM_Tabs_SetGrowDirection(dir)
	if dir ~= "LEFT" and dir ~= "RIGHT" then return end
	if Tabs.growDirection == dir then return end
	Tabs.growDirection = dir
	if WIM_Extras and WIM_Extras.db then
		WIM_Extras.db.tabGrowDirection = dir
	end
	-- Reverse current order to preserve relative positions, then bump active to front.
	local reversed = {}
	for i = table.getn(Tabs.order), 1, -1 do
		table.insert(reversed, Tabs.order[i])
	end
	Tabs.order = reversed
	if Tabs.active then
		if BumpToFront then
			BumpToFront(Tabs.active, true)
		end
	end
	ResetScrollOffsetForGrowth()
	if Tabs.layout then Tabs.layout() end
end

function WIM_Tabs_SetFlashEnabled(enabled)
	Tabs.flashEnabled = enabled and true or false
	if WIM_Extras and WIM_Extras.db then
		WIM_Extras.db.tabFlashEnabled = Tabs.flashEnabled
	end
	if not Tabs.flashEnabled then
		Tabs.flashOn = false
	end
	UpdateFlashTicker()
	UpdateTabVisuals()
end

function WIM_Tabs_SetFlashColor(r, g, b, a)
	if not Tabs.flashColor then Tabs.flashColor = {} end
	Tabs.flashColor.r = r or Tabs.flashColor.r
	Tabs.flashColor.g = g or Tabs.flashColor.g
	Tabs.flashColor.b = b or Tabs.flashColor.b
	Tabs.flashColor.a = a or Tabs.flashColor.a
	if WIM_Extras and WIM_Extras.db then
		WIM_Extras.db.tabFlashColor = {
			r = Tabs.flashColor.r,
			g = Tabs.flashColor.g,
			b = Tabs.flashColor.b,
			a = Tabs.flashColor.a,
		}
	end
	ApplyFlashColor()
	if WIM_PFUI_SetFlashColor then
		WIM_PFUI_SetFlashColor(Tabs.flashColor.r, Tabs.flashColor.g, Tabs.flashColor.b, Tabs.flashColor.a)
	end
	UpdateTabVisuals()
end

function WIM_Tabs_SetFlashUseClassColor(enabled)
	Tabs.flashUseClassColor = enabled and true or false
	if WIM_Extras and WIM_Extras.db then
		WIM_Extras.db.tabFlashUseClassColor = Tabs.flashUseClassColor
	end
	UpdateTabVisuals()
end

function WIM_Tabs_SetFlashInterval(seconds)
	if type(seconds) ~= "number" then return end
	if seconds < 0.1 then seconds = 0.1 end
	if seconds > 2.0 then seconds = 2.0 end
	seconds = math.floor(seconds * 10 + 0.5) / 10
	Tabs.flashInterval = seconds
	if WIM_Extras and WIM_Extras.db then
		WIM_Extras.db.tabFlashInterval = seconds
	end
end

function WIM_Tabs_SetBarHeight(height)
	if type(height) ~= "number" then return end
	height = math.floor(height + 0.5)
	if height < 14 then height = 14 end
	if height > 40 then height = 40 end
	Tabs.barHeight = height
	if WIM_Extras and WIM_Extras.db then
		WIM_Extras.db.tabBarHeight = height
	end
	if WIM_ExtrasDB then
		WIM_ExtrasDB.tabBarHeight = height
	end
	ApplyBarHeight()
end

function WIM_Tabs_SetBarPosition(pos)
	if pos ~= "TOP" and pos ~= "BOTTOM" then return end
	Tabs.barPosition = pos
	if WIM_Extras and WIM_Extras.db then
		WIM_Extras.db.tabBarPosition = pos
	end
	if Tabs.layout then Tabs.layout() end
end

function WIM_Tabs_SetSortMode(mode)
	if mode ~= "none" and mode ~= "incoming_outgoing" and mode ~= "outgoing" then return end
	Tabs.sortMode = mode
	if WIM_Extras and WIM_Extras.db then
		WIM_Extras.db.tabSortMode = mode
	end
end

local function GetScrollFrame(frame)
	if not frame then return nil end
	return getglobal(frame:GetName() .. "ScrollingMessageFrame")
end

local function GetScrollLeftOffset(scroll, frame)
	if not scroll or not frame then return nil end
	if scroll.GetNumPoints then
		local numPoints = scroll:GetNumPoints()
		for i = 1, numPoints do
			local point, relTo, relPoint, xOfs = scroll:GetPoint(i)
			if relTo == frame and relPoint == "TOPLEFT" then
				return xOfs or 0
			end
		end
	end
	local point, relTo, relPoint, xOfs = scroll:GetPoint(1)
	if relTo == frame and relPoint == "TOPLEFT" then
		return xOfs or 0
	end
	return nil
end

local function SyncBarScale(bar, frame)
	if not bar or not bar.SetScale then return end
	local scale = 1
	if frame and frame.GetScale then
		scale = frame:GetScale() or 1
	end
	if bar:GetScale() ~= scale then
		bar:SetScale(scale)
	end
end

local function GetWimWindowAlpha()
	if WIM_Data and WIM_Data.windowAlpha then return WIM_Data.windowAlpha end
	if WIM_Data_DEFAULTS and WIM_Data_DEFAULTS.windowAlpha then return WIM_Data_DEFAULTS.windowAlpha end
	return 1
end

local function GetCachedChildren(frame)
	if not frame then return nil, 0 end

	local currentCount
	if frame.GetNumChildren then
		currentCount = frame:GetNumChildren()
	end

	if not currentCount then
		local temp = { frame:GetChildren() }
		currentCount = table.getn(temp)
		if not frame._wimExtrasChildren or frame._wimExtrasChildrenCount ~= currentCount then
			frame._wimExtrasChildren = temp
			frame._wimExtrasChildrenCount = currentCount
		end
		return frame._wimExtrasChildren, frame._wimExtrasChildrenCount or currentCount
	end

	if not frame._wimExtrasChildren or frame._wimExtrasChildrenCount ~= currentCount then
		frame._wimExtrasChildren = { frame:GetChildren() }
		frame._wimExtrasChildrenCount = currentCount
	end

	return frame._wimExtrasChildren, frame._wimExtrasChildrenCount
end

-- Helper: Fully enable a WIM frame and its interactive elements
local function EnableFrame(frame)
	if not frame then return end
	frame:SetAlpha(GetWimWindowAlpha())
	frame._wimExtrasAlpha = nil
	-- WIM expects these child widgets to stay fully opaque even when the window
	-- background is translucent (it does this in WIM_SetWindowProps).
	local frameName = frame:GetName()
	local scroll = frameName and getglobal(frameName .. "ScrollingMessageFrame")
	if scroll and scroll.SetAlpha then scroll:SetAlpha(1) end
	local msgBox = frameName and getglobal(frameName .. "MsgBox")
	if msgBox and msgBox.SetAlpha then msgBox:SetAlpha(1) end
	local shortcut = frameName and getglobal(frameName .. "ShortcutFrame")
	if shortcut and shortcut.SetAlpha then shortcut:SetAlpha(1) end
	frame:EnableMouse(true)
	local children = GetCachedChildren(frame)
	for _, child in ipairs(children or {}) do
		if child.EnableMouse then child:EnableMouse(true) end
	end
	-- Enable shortcut buttons
	for i = 1, 5 do
		local btn = getglobal(frameName .. "ShortcutFrameButton" .. i)
		if btn then btn:EnableMouse(true) end
	end
end

-- Helper: Fully disable a WIM frame (for minimize/hidden state)
local function DisableFrame(frame)
	if not frame then return end
	frame._wimExtrasAlpha = GetWimWindowAlpha()
	frame:SetAlpha(0)
	-- When we hide windows via alpha, also hide the main child widgets so
	-- text/buttons don't remain visible if the client doesn't inherit alpha.
	local frameName = frame:GetName()
	local scroll = frameName and getglobal(frameName .. "ScrollingMessageFrame")
	if scroll and scroll.SetAlpha then scroll:SetAlpha(0) end
	local msgBox = frameName and getglobal(frameName .. "MsgBox")
	if msgBox and msgBox.SetAlpha then msgBox:SetAlpha(0) end
	local shortcut = frameName and getglobal(frameName .. "ShortcutFrame")
	if shortcut and shortcut.SetAlpha then shortcut:SetAlpha(0) end
	frame:EnableMouse(false)
	local children = GetCachedChildren(frame)
	for _, child in ipairs(children or {}) do
		if child.EnableMouse then child:EnableMouse(false) end
	end
	-- Disable shortcut buttons
	for i = 1, 5 do
		local btn = getglobal(frameName .. "ShortcutFrameButton" .. i)
		if btn then btn:EnableMouse(false) end
	end
end

local function EnforceTabVisibility()
	if Tabs.minimized then
		for user in pairs(Tabs.buttons) do
			local f = GetFrame(user)
			if f then DisableFrame(f) end
		end
		return
	end
	if not Tabs.active then return end
	for user in pairs(Tabs.buttons) do
		local f = GetFrame(user)
		if f then
			if user == Tabs.active then
				EnableFrame(f)
			else
				DisableFrame(f)
			end
		end
	end
end

-- Helper: Find which user a WIM frame belongs to
local function GetUserFromFrame(frame)
	if not frame then return nil end
	if frame.theUser and frame.theUser ~= "" then
		FrameUsers[frame] = frame.theUser
		return frame.theUser
	end
	if FrameUsers[frame] then
		return FrameUsers[frame]
	end
	if frame.GetName then
		local name = frame:GetName()
		if name and string.sub(name, 1, 12) == "WIM_msgFrame" then
			local user = string.sub(name, 13)
			if user and user ~= "" then
				FrameUsers[frame] = user
				return user
			end
		end
	end
	if WIM_Windows then
		for user in pairs(WIM_Windows) do
			if GetFrame(user) == frame then
				FrameUsers[frame] = user
				return user
			end
		end
	end
	return nil
end

function WIM_Tabs_GetUserFromFrame(frame)
	return GetUserFromFrame(frame)
end

-- Move a user to the front of the tab order (most recent activity)
BumpToFront = function(user, force)
	if not force then
		local mode = Tabs.sortMode or "none"
		if mode == "none" then
			return
		end
	end
	for i = table.getn(Tabs.order), 1, -1 do
		if Tabs.order[i] == user then
			table.remove(Tabs.order, i)
			break
		end
	end
	InsertTabOrder(user)
end

-- Find the index of a user in the order
local function GetTabIndex(user)
	for i, u in ipairs(Tabs.order) do
		if u == user then return i end
	end
	return nil
end

-- Create the tab bar (once)
local function CreateBar()
	if Tabs.bar then return Tabs.bar end
	
	local bar = CreateFrame("Frame", "WIM_TabBar", UIParent)
	bar:SetFrameStrata("TOOLTIP")
	bar:SetFrameLevel(500)
	bar:SetHeight(GetTabHeight())
	bar:SetWidth(300)
	bar:Hide()
	
	-- Keep tab bar within the screen bounds
	if bar.SetClampedToScreen then bar:SetClampedToScreen(true) end
	if bar.SetClampRectInsets then bar:SetClampRectInsets(0, 0, 0, 0) end
	
	-- Shared drag handlers for bar components
	local function OnBarDragStart()
		if Tabs.active then
			local f = GetFrame(Tabs.active)
			if f then f:StartMoving(); Tabs.barDragging = true end
		end
	end
	
	local function OnBarDragStop()
		if Tabs.barDragging and Tabs.active then
			local f = GetFrame(Tabs.active)
			if f then f:StopMovingOrSizing() end
			Tabs.barDragging = false
			SaveAnchor()
		end
	end
	
	-- No bar background (tabs provide the visual treatment)
	
	-- Left scroll button with solid background to clip tabs
	bar.scrollLeft = CreateFrame("Button", "WIM_TabBarScrollLeft", bar)
	bar.scrollLeft:SetWidth(SCROLL_BTN_WIDTH)
	bar.scrollLeft:SetHeight(GetTabHeight())
	bar.scrollLeft:SetPoint("LEFT", bar, "LEFT", 0, 0)
	bar.scrollLeft:SetFrameStrata("TOOLTIP")
	bar.scrollLeft:SetFrameLevel(503)
	bar.scrollLeft.bg = bar.scrollLeft:CreateTexture(nil, "BACKGROUND")
	bar.scrollLeft.bg:SetAllPoints()
	bar.scrollLeft.bg:SetTexture(0.1, 0.1, 0.1, 0.95)
	bar.scrollLeft.arrow = bar.scrollLeft:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	bar.scrollLeft.arrow:SetPoint("CENTER", bar.scrollLeft, "CENTER", 0, 0)
	bar.scrollLeft.arrow:SetText("<")
	-- Indicator glow for when active tab is to the left (highlight the arrow)
	bar.scrollLeft.indicator = bar.scrollLeft:CreateTexture(nil, "BORDER")
	bar.scrollLeft.indicator:SetAllPoints()
	bar.scrollLeft.indicator:SetTexture(0.5, 0.5, 0.5, 0.1)
	bar.scrollLeft.indicator:Hide()
	-- Flash overlay for unread tabs off-screen to the left
	bar.scrollLeft.flash = bar.scrollLeft:CreateTexture(nil, "ARTWORK")
	bar.scrollLeft.flash:SetAllPoints()
	local c = Tabs.flashColor or { r = 1, g = 0.8, b = 0.2, a = 0.7 }
	bar.scrollLeft.flash:SetTexture(c.r, c.g, c.b, 1)
	bar.scrollLeft.flash:SetAlpha(0)
	bar.scrollLeft:SetScript("OnClick", function()
		if arg1 == "RightButton" then
			ToggleConversationMenu(this)
		elseif arg1 == "MiddleButton" then
			if Tabs.toggleMinimize then Tabs.toggleMinimize() end
		elseif Tabs.scrollOffset > 0 then
			Tabs.scrollOffset = Tabs.scrollOffset - 1
			if Tabs.layout then Tabs.layout() end
		end
	end)
	bar.scrollLeft:RegisterForClicks("LeftButtonUp", "MiddleButtonUp", "RightButtonUp")
	bar.scrollLeft:RegisterForDrag("LeftButton")
	bar.scrollLeft:SetScript("OnDragStart", OnBarDragStart)
	bar.scrollLeft:SetScript("OnDragStop", OnBarDragStop)
	bar.scrollLeft:Hide()
	
	-- Right scroll button with solid background to clip tabs
	bar.scrollRight = CreateFrame("Button", "WIM_TabBarScrollRight", bar)
	bar.scrollRight:SetWidth(SCROLL_BTN_WIDTH)
	bar.scrollRight:SetHeight(GetTabHeight())
	bar.scrollRight:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
	bar.scrollRight:SetFrameStrata("TOOLTIP")
	bar.scrollRight:SetFrameLevel(503)
	bar.scrollRight.bg = bar.scrollRight:CreateTexture(nil, "BACKGROUND")
	bar.scrollRight.bg:SetAllPoints()
	bar.scrollRight.bg:SetTexture(0.1, 0.1, 0.1, 0.95)
	bar.scrollRight.arrow = bar.scrollRight:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	bar.scrollRight.arrow:SetPoint("CENTER", bar.scrollRight, "CENTER", 0, 0)
	bar.scrollRight.arrow:SetText(">")
	-- Indicator glow for when active tab is to the right (highlight the arrow)
	bar.scrollRight.indicator = bar.scrollRight:CreateTexture(nil, "BORDER")
	bar.scrollRight.indicator:SetAllPoints()
	bar.scrollRight.indicator:SetTexture(0.5, 0.5, 0.5, 0.1)
	bar.scrollRight.indicator:Hide()
	-- Flash overlay for unread tabs off-screen to the right
	bar.scrollRight.flash = bar.scrollRight:CreateTexture(nil, "ARTWORK")
	bar.scrollRight.flash:SetAllPoints()
	bar.scrollRight.flash:SetTexture(c.r, c.g, c.b, 1)
	bar.scrollRight.flash:SetAlpha(0)
	bar.scrollRight:SetScript("OnClick", function()
		if arg1 == "RightButton" then
			ToggleConversationMenu(this)
		elseif arg1 == "MiddleButton" then
			if Tabs.toggleMinimize then Tabs.toggleMinimize() end
		else
			Tabs.scrollOffset = Tabs.scrollOffset + 1
			if Tabs.layout then Tabs.layout() end
		end
	end)
	bar.scrollRight:RegisterForClicks("LeftButtonUp", "MiddleButtonUp", "RightButtonUp")
	bar.scrollRight:RegisterForDrag("LeftButton")
	bar.scrollRight:SetScript("OnDragStart", OnBarDragStart)
	bar.scrollRight:SetScript("OnDragStop", OnBarDragStop)
	bar.scrollRight:Hide()
	
	-- Mouse wheel scrolling on the bar
	bar:EnableMouseWheel(true)
	bar:SetScript("OnMouseWheel", function()
		if arg1 > 0 then
			-- Scroll left
			if Tabs.scrollOffset > 0 then
				Tabs.scrollOffset = Tabs.scrollOffset - 1
				if Tabs.layout then Tabs.layout() end
			end
		else
			-- Scroll right
			Tabs.scrollOffset = Tabs.scrollOffset + 1
			if Tabs.layout then Tabs.layout() end
		end
	end)
	
	-- Make bar draggable - drags the WIM frame (bar follows via anchor)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnMouseDown", function()
		if arg1 == "MiddleButton" then
			if Tabs.toggleMinimize then Tabs.toggleMinimize() end
		end
	end)
	bar:SetScript("OnDragStart", OnBarDragStart)
	bar:SetScript("OnDragStop", OnBarDragStop)
	
	Tabs.bar = bar
	
	-- Call skinning hook for bar if defined (for pfUI integration)
	if WIM_Tabs_OnSkinBar then
		WIM_Tabs_OnSkinBar(bar)
	end
	
	return bar
end

-- resize logic lives in Resize.lua

-- Update a single tab's appearance
UpdateTabLook = function(btn)
	if not btn then return end
	local isActive = (btn.user == Tabs.active)
	
	if isActive then
		btn.bg:SetTexture(0.35, 0.35, 0.35, 1)
	else
		btn.bg:SetTexture(0.15, 0.15, 0.15, 1)
	end
	
	local r, g, b = GetClassColor(btn.user)
	if r and g and b then
		if not isActive then
			r, g, b = r * TAB_CLASS_DIM, g * TAB_CLASS_DIM, b * TAB_CLASS_DIM
		end
		btn.label:SetTextColor(r, g, b)
	else
		if isActive then
			btn.label:SetTextColor(1, 1, 1)
		else
			btn.label:SetTextColor(0.7, 0.7, 0.7)
		end
	end
	
	-- Flash overlay for unread
	local flashAlpha = (Tabs.flashColor and Tabs.flashColor.a) or 0.5
	local flashOn = Tabs.flashEnabled and Tabs.flashOn or false
	-- Disable overlay flash entirely when pfUI styling is active (borders handle flash)
	if WIM_Tabs_OnUpdateTabLook then flashAlpha = 0 end
	if not Tabs.flashEnabled then flashAlpha = 0 end
	
	if btn.flash then
		local fr, fg, fb
		if Tabs.flashUseClassColor and r and g and b then
			fr, fg, fb = r, g, b
		else
			local c = Tabs.flashColor or { r = 1, g = 0.8, b = 0.2, a = 0.7 }
			fr, fg, fb = c.r, c.g, c.b
		end
		btn.flash:SetTexture(fr, fg, fb, 1)
	end

	if btn.unread and not isActive and flashAlpha > 0 then
		btn.flash:SetAlpha(flashOn and flashAlpha or 0)
	else
		btn.flash:SetAlpha(0)
	end
	
	-- Call hook for external styling (pfUI border colors)
	if WIM_Tabs_OnUpdateTabLook then
		WIM_Tabs_OnUpdateTabLook(btn, isActive, btn.unread, flashOn)
	end
end

-- Position all tabs and the bar
local function LayoutTabs()
	local bar = Tabs.bar
	if not bar then return end
	
	-- Only show tab bar if there are 2+ tabs
	local tabCount = table.getn(Tabs.order)
	if tabCount < 2 then
		bar:Hide()
		Tabs.layoutState = nil
		return
	end
	
	-- Get bar width from active frame (match WIM window width)
	local frame = Tabs.active and GetFrame(Tabs.active)
	local barWidth = 164
	local barXOffset = 0
	if frame then
		SyncBarScale(bar, frame)
		local w = frame:GetWidth()
		if w and w > 0 then
			barWidth = w
		elseif WIM_Data and WIM_Data.winSize and WIM_Data.winSize.width then
			barWidth = WIM_Data.winSize.width
		else
			local scroll = GetScrollFrame(frame)
			if scroll then
				local sw = scroll:GetWidth()
				if sw and sw > 0 then
					barWidth = sw
					local offset = GetScrollLeftOffset(scroll, frame)
					if offset ~= nil then
						barXOffset = offset
					end
				end
			end
		end
	else
		SyncBarScale(bar, nil)
		if WIM_Data and WIM_Data.winSize and WIM_Data.winSize.width then
			barWidth = WIM_Data.winSize.width
		end
	end
	
	-- Dynamic tab sizing: tabs fill available width but clamp between MIN/MAX
	-- When 5+ tabs, use fixed width and scroll
	local needScroll = tabCount > MAX_TABS_BEFORE_SCROLL
	local tabWidth
	local tabAreaLeft = 0
	local tabAreaRight = barWidth
	local availableWidth = barWidth
	
	if needScroll then
		-- Scrolling mode: fixed tab width, scroll buttons visible
		tabAreaLeft = SCROLL_BTN_WIDTH + 2
		tabAreaRight = barWidth - SCROLL_BTN_WIDTH - 2
		availableWidth = tabAreaRight - tabAreaLeft
		-- Calculate tab width to fit MAX_TABS_BEFORE_SCROLL tabs in visible area
		tabWidth = math.floor((availableWidth - (MAX_TABS_BEFORE_SCROLL - 1) * TAB_SPACING) / MAX_TABS_BEFORE_SCROLL)
		if tabWidth < MIN_TAB_WIDTH then tabWidth = MIN_TAB_WIDTH end
		if tabWidth > MAX_TAB_WIDTH then tabWidth = MAX_TAB_WIDTH end
	else
		-- No scroll: tabs fill the full bar width proportionally
		tabWidth = math.floor((availableWidth - (tabCount - 1) * TAB_SPACING) / tabCount)
		if tabWidth > MAX_TAB_WIDTH then tabWidth = MAX_TAB_WIDTH end
		if tabWidth < MIN_TAB_WIDTH then tabWidth = MIN_TAB_WIDTH end
	end
	
	-- Calculate how many tabs fit in visible area
	local visibleTabCount = math.floor((availableWidth + TAB_SPACING) / (tabWidth + TAB_SPACING))
	if visibleTabCount < 1 then visibleTabCount = 1 end
	
	-- Center tabs within the available area to avoid uneven gaps
	local startOffset = 0
	local usedWidth = (visibleTabCount * tabWidth) + ((visibleTabCount - 1) * TAB_SPACING)
	local extraSpace = availableWidth - usedWidth
	if extraSpace > 0 then
		startOffset = math.floor((extraSpace + 1) / 2)
	end
	
	-- Clamp scroll offset
	local maxOffset = math.max(0, tabCount - visibleTabCount)
	if Tabs.scrollOffset > maxOffset then Tabs.scrollOffset = maxOffset end
	if Tabs.scrollOffset < 0 then Tabs.scrollOffset = 0 end
	
	-- Find active tab index and whether it's off-screen
	local activeIdx = GetTabIndex(Tabs.active)
	local activeDirection = 0  -- -1 = left, 0 = visible, 1 = right
	
	if activeIdx then
		local visibleStart = Tabs.scrollOffset + 1
		local visibleEnd = Tabs.scrollOffset + visibleTabCount
		if activeIdx < visibleStart then
			activeDirection = -1
		elseif activeIdx > visibleEnd then
			activeDirection = 1
		end
	end
	
	-- Show/hide scroll buttons and indicators
	if needScroll then
		bar.scrollLeft:Show()
		bar.scrollRight:Show()
		
		-- Dim scroll buttons when at limits, full white when scrollable
		if Tabs.scrollOffset <= 0 then
			bar.scrollLeft.bg:SetTexture(0.15, 0.15, 0.15, 0.95)
			bar.scrollLeft.arrow:SetTextColor(0.4, 0.4, 0.4)
		else
			bar.scrollLeft.bg:SetTexture(0.25, 0.25, 0.25, 0.95)
			bar.scrollLeft.arrow:SetTextColor(1, 1, 1)
		end
		if Tabs.scrollOffset >= maxOffset then
			bar.scrollRight.bg:SetTexture(0.15, 0.15, 0.15, 0.95)
			bar.scrollRight.arrow:SetTextColor(0.4, 0.4, 0.4)
		else
			bar.scrollRight.bg:SetTexture(0.25, 0.25, 0.25, 0.95)
			bar.scrollRight.arrow:SetTextColor(1, 1, 1)
		end
		
		-- Show indicator when active tab is off-screen
		if activeDirection == -1 then
			bar.scrollLeft.indicator:Show()
			bar.scrollRight.indicator:Hide()
		elseif activeDirection == 1 then
			bar.scrollLeft.indicator:Hide()
			bar.scrollRight.indicator:Show()
		else
			bar.scrollLeft.indicator:Hide()
			bar.scrollRight.indicator:Hide()
		end
	else
		bar.scrollLeft:Hide()
		bar.scrollRight:Hide()
		bar.scrollLeft.indicator:Hide()
		bar.scrollRight.indicator:Hide()
	end
	
	-- Position tabs - clip tabs that overflow scroll button boundaries
	local clipLeft = tabAreaLeft
	local clipRight = tabAreaRight
	
	-- Track flashing tabs that are off-screen
	local flashLeft = false
	local flashRight = false
	
	for i = 1, tabCount do
		local user = Tabs.order[i]
		local btn = Tabs.buttons[user]
		if btn then
			local visibleIdx = i - Tabs.scrollOffset
			local btnLeft = tabAreaLeft + startOffset + (visibleIdx - 1) * (tabWidth + TAB_SPACING)
			local btnRight = btnLeft + tabWidth
			
			-- Check if this tab is completely outside visible area
			if btnRight <= clipLeft then
				-- Completely off-screen to the left
				btn:Hide()
				if btn.unread and user ~= Tabs.active then
					flashLeft = true
				end
			elseif btnLeft >= clipRight then
				-- Completely off-screen to the right
				btn:Hide()
				if btn.unread and user ~= Tabs.active then
					flashRight = true
				end
			else
				-- Tab is at least partially visible - calculate clipped width
				local displayLeft = btnLeft
				local displayWidth = tabWidth
				
				-- Clip left edge
				if btnLeft < clipLeft then
					local overflow = clipLeft - btnLeft
					displayLeft = clipLeft
					displayWidth = displayWidth - overflow
				end
				
				-- Clip right edge
				if btnRight > clipRight then
					local overflow = btnRight - clipRight
					displayWidth = displayWidth - overflow
				end
				
				-- Only show if there's meaningful width left (at least 5 pixels)
				if displayWidth >= 5 then
					btn:SetWidth(displayWidth)
					btn:ClearAllPoints()
					btn:SetPoint("LEFT", bar, "LEFT", displayLeft, 0)
					btn:Show()
					UpdateTabLook(btn)
				else
					btn:Hide()
					-- Track as off-screen for flash purposes
					if btn.unread and user ~= Tabs.active then
						if btnLeft < clipLeft then
							flashLeft = true
						else
							flashRight = true
						end
					end
				end
			end
		end
	end
	
	-- Update scroll button flash states
	if needScroll then
		local flashOn = Tabs.flashEnabled and Tabs.flashOn or false
		local allowOverlay = Tabs.flashEnabled and not WIM_Tabs_OnUpdateScrollFlash and not WIM_Tabs_OnUpdateTabLook
		local overlayAlpha = (Tabs.flashColor and Tabs.flashColor.a) or 0.7
		if flashLeft then
			bar.scrollLeft.flash:SetAlpha(allowOverlay and flashOn and overlayAlpha or 0)
		else
			bar.scrollLeft.flash:SetAlpha(0)
		end
		if flashRight then
			bar.scrollRight.flash:SetAlpha(allowOverlay and flashOn and overlayAlpha or 0)
		else
			bar.scrollRight.flash:SetAlpha(0)
		end
		
		-- Call hook for external styling (pfUI border colors)
		-- activeDirection: -1 = active tab off-screen left, 0 = visible, 1 = off-screen right
		if WIM_Tabs_OnUpdateScrollFlash then
			WIM_Tabs_OnUpdateScrollFlash(bar, flashLeft, flashRight, flashOn, activeDirection)
		end
	end
	
	-- Position bar anchored to WIM frame
	-- Don't reposition if currently dragging
	if Tabs.barDragging then
		-- Just ensure bar stays visible, don't change position
		bar:SetWidth(barWidth)
		bar:Show()
	elseif frame then
		-- Always anchor bar above the WIM frame
		bar:SetWidth(barWidth)
		bar:ClearAllPoints()
		if Tabs.barPosition == "BOTTOM" then
			bar:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", barXOffset, -4)
		else
			bar:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", barXOffset, 4)
		end
		bar:Show()
	else
		bar:Hide()
	end

	Tabs.layoutState = {
		needScroll = needScroll,
		flashLeft = flashLeft,
		flashRight = flashRight,
		activeDirection = activeDirection,
	}
end

local function RequestLayout()
	if Tabs.layoutPending then return end
	Tabs.layoutPending = true
	if not Tabs.layoutFrame then
		local f = CreateFrame("Frame")
		f:Hide()
		f:SetScript("OnUpdate", function()
			this:Hide()
			Tabs.layoutPending = false
			LayoutTabs()
		end)
		Tabs.layoutFrame = f
	end
	Tabs.layoutFrame:Show()
end

UpdateTabVisuals = function()
	local bar = Tabs.bar
	if not bar or (bar.IsVisible and not bar:IsVisible()) then return end

	if not Tabs.layoutState then
		LayoutTabs()
		return
	end

	for _, btn in pairs(Tabs.buttons) do
		if btn and btn.IsVisible and btn:IsVisible() then
			UpdateTabLook(btn)
		end
	end

	if Tabs.layoutState.needScroll then
		local flashLeft = Tabs.layoutState.flashLeft
		local flashRight = Tabs.layoutState.flashRight
		local flashOn = Tabs.flashEnabled and Tabs.flashOn or false
		local allowOverlay = Tabs.flashEnabled and not WIM_Tabs_OnUpdateScrollFlash and not WIM_Tabs_OnUpdateTabLook
		local overlayAlpha = (Tabs.flashColor and Tabs.flashColor.a) or 0.7

		if bar.scrollLeft and bar.scrollLeft.flash then
			bar.scrollLeft.flash:SetAlpha(flashLeft and (allowOverlay and flashOn and overlayAlpha or 0) or 0)
		end
		if bar.scrollRight and bar.scrollRight.flash then
			bar.scrollRight.flash:SetAlpha(flashRight and (allowOverlay and flashOn and overlayAlpha or 0) or 0)
		end
		if WIM_Tabs_OnUpdateScrollFlash then
			WIM_Tabs_OnUpdateScrollFlash(bar, flashLeft, flashRight, flashOn, Tabs.layoutState.activeDirection or 0)
		end
	end
end

-- Store reference for scroll buttons (defined after LayoutTabs)
Tabs.layout = RequestLayout
WIM_Tabs_RefreshLooks = UpdateTabVisuals

-- Save window position from active frame
SaveAnchor = function()
	if not Tabs.active then return end
	local f = GetFrame(Tabs.active)
	if f then
		Tabs.anchor.left = f:GetLeft()
		Tabs.anchor.top = f:GetTop()
	end
end

-- Apply saved position to a frame
local function ApplyAnchor(frame)
	if Tabs.anchor.left and Tabs.anchor.top then
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", Tabs.anchor.left, Tabs.anchor.top)
	end
end

ToggleConversationMenu = function(anchor)
	if not WIM_ConversationMenu or not WIM_Icon_DropDown_Update then return end
	if WIM_ConversationMenu.IsVisible and WIM_ConversationMenu:IsVisible() then
		WIM_ConversationMenu:Hide()
		return
	end
	WIM_Icon_DropDown_Update()
	WIM_ConversationMenu:ClearAllPoints()
	if anchor then
		WIM_ConversationMenu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	else
		WIM_ConversationMenu:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end
	WIM_ConversationMenu:Show()
end

-- Show a specific user's window, hide all others
local function ShowUser(user)
	if not user then return end
	local frame = GetFrame(user)
	if not frame then return end
	
	Tabs.switching = true
	
	-- Save anchor from current visible window before hiding
	SaveAnchor()
	
	-- Hide all other windows
	for u, btn in pairs(Tabs.buttons) do
		if u ~= user then
			local f = GetFrame(u)
			if f and f:IsVisible() then
				f:Hide()
			end
		end
	end
	
	-- Apply anchor BEFORE showing (so frame is positioned correctly)
	ApplyAnchor(frame)
	
	-- Show target and set active
	Tabs.active = user
	frame:Show()
	
	-- Clear unread
	local btn = Tabs.buttons[user]
	if btn then
		SetTabUnread(btn, false)
	end
	if WIM_Windows and WIM_Windows[user] then
		WIM_Windows[user].newMSG = false
	end
	
	-- Auto-scroll to ensure clicked tab is visible
	local tabCount = table.getn(Tabs.order)
	if tabCount > MAX_TABS_BEFORE_SCROLL then
		local idx = GetTabIndex(user)
		if idx then
			-- Calculate visible range
			local visibleCount = MAX_TABS_BEFORE_SCROLL
			local maxOffset = math.max(0, tabCount - visibleCount)
			
			-- Adjust scroll to show selected tab (preferring it toward the left)
			if idx <= Tabs.scrollOffset then
				-- Tab is to the left of visible area
				Tabs.scrollOffset = idx - 1
			elseif idx > Tabs.scrollOffset + visibleCount then
				-- Tab is to the right of visible area
				Tabs.scrollOffset = idx - visibleCount
			end
			
			-- Clamp
			if Tabs.scrollOffset > maxOffset then Tabs.scrollOffset = maxOffset end
			if Tabs.scrollOffset < 0 then Tabs.scrollOffset = 0 end
		end
	end
	
	Tabs.layout()
	
	Tabs.switching = false
end

-- Toggle minimize state (make WIM invisible/click-through but keep tab bar visible)
local function ToggleMinimize()
	if Tabs.minimized then
		-- Restore: make WIM visible and interactive again
		Tabs.minimized = false
		
		-- Restore all WIM frames to visible and interactive
		-- Note: frames are already "shown", just invisible - don't call Show()
		for user in pairs(Tabs.buttons) do
			local f = GetFrame(user)
			if f then
				if user == Tabs.active then
					EnableFrame(f)
				else
					DisableFrame(f)
				end
			end
		end
		
		-- If the active frame was hidden (inactive before minimize), show it now
		if Tabs.active then
			local f = GetFrame(Tabs.active)
			if f and not f:IsVisible() then
				-- Just show it, let skipAnchor (set by caller) determine if we reposition
				f:Show()
			end
		end
		
		Tabs.layout()
	else
		-- Minimize: make WIM invisible and click-through
		Tabs.minimized = true
		
		-- Make all WIM frames invisible and click-through
		for user in pairs(Tabs.buttons) do
			local f = GetFrame(user)
			if f then
				DisableFrame(f)
			end
		end
		
		-- Keep tab bar visible
		if Tabs.bar then
			Tabs.bar:Show()
		end
	end
end

Tabs.toggleMinimize = ToggleMinimize

-- Create a tab button for a user
local function CreateTab(user)
	if Tabs.buttons[user] then return Tabs.buttons[user] end
	
	CreateBar()
	
	local btn = CreateFrame("Button", "WIM_Tab_" .. SafeName(user), Tabs.bar)
	btn:SetFrameStrata("TOOLTIP")
	btn:SetFrameLevel(501)
	btn:SetHeight(GetTabHeight())
	btn:SetWidth(MAX_TAB_WIDTH)  -- Initial width, will be adjusted by LayoutTabs
	
	-- Truncate name to 10 chars max for display
	local name = (WIM_GetAlias and WIM_GetAlias(user)) or user
	local displayName = name
	if string.len(displayName) > 10 then
		displayName = string.sub(displayName, 1, 9) .. ".."
	end
	
	-- Background
	btn.bg = btn:CreateTexture(nil, "BACKGROUND")
	btn.bg:SetAllPoints()
	
	-- Flash overlay (behind text)
	btn.flash = btn:CreateTexture(nil, "ARTWORK")
	btn.flash:SetAllPoints()
	local c = Tabs.flashColor or { r = 1, g = 0.8, b = 0.2, a = 0.7 }
	btn.flash:SetTexture(c.r, c.g, c.b, 1)
	btn.flash:SetAlpha(0)
	
	-- Label (in front of flash)
	btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	btn.label:SetPoint("CENTER", btn, "CENTER", 0, 0)
	btn.label:SetText(displayName)
	
	btn.user = user
	btn.unread = false
	
	-- Make tabs draggable - drags the WIM frame (bar follows via anchor)
	btn:RegisterForDrag("LeftButton")
	btn:SetScript("OnDragStart", function()
		if Tabs.active then
			local f = GetFrame(Tabs.active)
			if f then f:StartMoving(); Tabs.barDragging = true end
		end
	end)
	btn:SetScript("OnDragStop", function()
		if Tabs.barDragging and Tabs.active then
			local f = GetFrame(Tabs.active)
			if f then f:StopMovingOrSizing() end
			Tabs.barDragging = false
			SaveAnchor()
		end
	end)
	
	btn:SetScript("OnClick", function()
		if arg1 == "RightButton" and IsShiftKeyDown() then
			-- Shift+Right-click = Fully close the conversation
			if WIM_CloseConvo then WIM_CloseConvo(this.user) end
		elseif arg1 == "RightButton" and IsControlKeyDown and IsControlKeyDown() then
			-- Ctrl+Right-click = Hide window and remove tab (even when scroll menu is enabled)
			local f = GetFrame(this.user)
			if f then f:Hide() end
			RemoveTab(this.user)
		elseif arg1 == "RightButton" then
			-- Right-click = Hide window and remove tab
			local f = GetFrame(this.user)
			if f then f:Hide() end
			RemoveTab(this.user)
		elseif arg1 == "MiddleButton" then
			-- Middle-click = Toggle minimize
			ToggleMinimize()
		else
			local carryFocus = WasEditBoxFocusedForActive()
			-- Left-click = Switch to this tab (restores from minimized)
			if Tabs.minimized then
				-- If we're clicking the same tab, don't move (it's already there)
				-- If we're switching tabs, DO move (to snap to the correct/active position)
				local wasActive = (Tabs.active == this.user)
				
				-- If switching tabs, explicitly move the new tab to current position
				if not wasActive then
					local fNew = GetFrame(this.user)
					if fNew then ApplyAnchor(fNew) end
				end
				
				Tabs.active = this.user
				ToggleMinimize()  -- This will show the active user
				
				local btn = Tabs.buttons[this.user]
				if btn then SetTabUnread(btn, false) end
				if carryFocus then
					FocusEditBoxForUser(this.user)
				end
			else
				ShowUser(this.user)
				if carryFocus then
					FocusEditBoxForUser(this.user)
				end
			end
		end
	end)
	btn:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
	
	btn:SetScript("OnEnter", function()
		if this.user ~= Tabs.active then
			this.bg:SetTexture(0.35, 0.35, 0.35, 1)
		end
	end)
	btn:SetScript("OnLeave", function()
		UpdateTabLook(this)
	end)
	
	Tabs.buttons[user] = btn
	InsertTabOrder(user)
	
	-- Call skinning hook if defined (for pfUI integration)
	if WIM_Tabs_OnSkinTab then
		WIM_Tabs_OnSkinTab(btn)
	end
	
	return btn
end

-- Remove a tab
RemoveTab = function(user)
	local btn = Tabs.buttons[user]
	if btn then
		if btn.unread then
			SetTabUnread(btn, false)
		end
		btn:Hide()
		Tabs.buttons[user] = nil
	end
	
	-- Find the index of the user being removed
	local removedIdx = nil
	for i = table.getn(Tabs.order), 1, -1 do
		if Tabs.order[i] == user then
			removedIdx = i
			table.remove(Tabs.order, i)
			break
		end
	end
	
	-- If we removed the active tab, switch to another
	if Tabs.active == user then
		local newActive = nil
		if removedIdx and removedIdx > 1 then
			-- Switch to previous tab
			newActive = Tabs.order[removedIdx - 1]
		else
			-- Switch to first remaining tab
			newActive = Tabs.order[1]
		end
		
		if newActive then
			ShowUser(newActive)
		else
			Tabs.active = nil
		end
	else
		Tabs.layout()
	end
end

-- Flash animation
local function UpdateFlash()
	if not Tabs.flashEnabled then
		Tabs.flashOn = false
		UpdateTabVisuals()
		return
	end
	if not Tabs.unreadCount or Tabs.unreadCount <= 0 then return end
	Tabs.flashOn = not Tabs.flashOn
	if Tabs.bar and Tabs.bar:IsVisible() then
		UpdateTabVisuals()
	end
end

-- Hook WIM_CloseConvo
local function HookClose()
	if Orig.CloseConvo then return end
	if type(WIM_CloseConvo) ~= "function" then return end
	
	Orig.CloseConvo = WIM_CloseConvo
	WIM_CloseConvo = function(user)
		Orig.CloseConvo(user)
		RemoveTab(user)
	end
end

-- Hook drag events and Show() on WIM frames
local function HookFrame(frame)
	if not frame or frame._tabHooked then return end
	if WIM_Extras_Resize_EnsureHandle then
		WIM_Extras_Resize_EnsureHandle(frame)
	end
	
	-- Hook Show() to manage window visibility
	local origShow = frame.Show
	frame.Show = function(self)
		-- Find which user this frame belongs to
		local frameUser = GetUserFromFrame(self)
		
		-- If we're minimized, allow the Show but keep invisible/click-through
		if Tabs.minimized then
			if frameUser then
				CreateTab(frameUser)
				local btn = Tabs.buttons[frameUser]
				if btn then SetTabUnread(btn, true) end
			end
			-- Still call Show so WIM's internal state is correct
			if not Tabs.skipAnchor then
				ApplyAnchor(self)
			end
			origShow(self)
			if WIM_Tabs_OnEnsureFont then
				WIM_Tabs_OnEnsureFont(self)
			end
			-- But make it invisible and click-through
			DisableFrame(self)
			Tabs.layout()
			return
		end
		
		-- If we're switching tabs or this is the active user, allow Show
		-- Otherwise, suppress it (prevents the "flash" on new messages)
		if Tabs.switching or frameUser == Tabs.active or not Tabs.active then
			-- Apply anchor position before showing (unless skipAnchor is set)
			if not Tabs.skipAnchor then
				ApplyAnchor(self)
			end
			origShow(self)
			-- Ensure visible and interactive
			EnableFrame(self)
			if WIM_Tabs_OnEnsureFont then
				WIM_Tabs_OnEnsureFont(self)
			end
		else
			-- New message for non-active user: create tab and mark unread
			if frameUser then
				CreateTab(frameUser)
				local btn = Tabs.buttons[frameUser]
				if btn then SetTabUnread(btn, true) end
		Tabs.layout()
	end
end
	end
	
	-- Hook Hide() to hide tab bar when active window is hidden (unless minimized)
	local origHide = frame.Hide
	frame.Hide = function(self)
		origHide(self)
		-- Don't hide bar if minimized
		if Tabs.minimized then return end
		-- Find which user this frame belongs to
		local frameUser = GetUserFromFrame(self)
		-- If the active window was hidden, hide the tab bar
		if frameUser and frameUser == Tabs.active and Tabs.bar then
			Tabs.bar:Hide()
		end
	end
	
	-- Hook drag events on the scroll area to save anchor after user drags WIM
	local scroll = getglobal(frame:GetName() .. "ScrollingMessageFrame")
	if scroll then
		local origUp = scroll:GetScript("OnMouseUp")
		scroll:SetScript("OnMouseUp", function()
			SaveAnchor()
			if origUp then origUp() end
		end)
	end
	frame._tabHooked = true
end

-- Hook WIM_PostMessage - THE MAIN EVENT HOOK
-- This catches ALL whisper activity: incoming (1), outgoing (2), show window (5)
local function HookPost()
	if Orig.PostMessage then return end
	if type(WIM_PostMessage) ~= "function" then return end
	
	Orig.PostMessage = WIM_PostMessage
	WIM_PostMessage = function(user, msg, ttype, from, raw_msg, hotkeyFix)
		-- Check if frame exists BEFORE calling original
		local frameExisted = (GetFrame(user) ~= nil)
		
		-- Hook frame if it exists
		local frame = GetFrame(user)
		if frame then
			HookFrame(frame)
		end
		
		-- Create tab for this user
		CreateTab(user)
		
		-- Save current anchor before any switching
		SaveAnchor()
		
		-- ttype 5 = show window (Reply keybind, /w command)
		if ttype == 5 then
			-- User explicitly wants this window - exit minimized state
			if Tabs.minimized then
				Tabs.minimized = false
				Tabs.skipAnchor = true  -- Don't reposition - frame is already where user wants it
			end
			-- No automatic reordering here unless user toggles sort mode elsewhere.
			
			-- Hide all other windows first (set invisible, keep WIM state)
			for u, btn in pairs(Tabs.buttons) do
				if u ~= user then
					DisableFrame(GetFrame(u))
				end
			end
			
			Tabs.active = user
			Tabs.switching = true  -- Allow Show() through
			local btn = Tabs.buttons[user]
			if btn then SetTabUnread(btn, false) end
			
			-- Auto-scroll to show active tab
			ResetScrollOffsetForGrowth()
			-- Note: Don't call Show() here - let WIM_PostMessage handle it
			-- We'll apply anchor after the original function runs
		end
		
		-- ttype 1 = incoming whisper, ttype 2 = outgoing
		if ttype == 1 or ttype == 2 then
			-- Activity-based sorting (optional)
			local mode = Tabs.sortMode or "none"
			if mode == "incoming_outgoing" then
				BumpToFront(user, true)
			elseif mode == "outgoing" and ttype == 2 then
				BumpToFront(user, true)
			end
			
			-- If minimized, just mark as unread (don't restore)
			if Tabs.minimized then
				if user ~= Tabs.active then
					local btn = Tabs.buttons[user]
					if btn then SetTabUnread(btn, true) end
				end
			else
				-- If no window is visible yet, this becomes active
				local anyVisible = false
				for u in pairs(Tabs.buttons) do
					local f = GetFrame(u)
					if f and f:IsVisible() and f:GetAlpha() > 0 then anyVisible = true; break end
				end
				
				if not anyVisible then
					Tabs.active = user
					Tabs.switching = true
					-- Auto-scroll to show active tab
					ResetScrollOffsetForGrowth()
				elseif user ~= Tabs.active then
					-- Mark as unread if not active
					local btn = Tabs.buttons[user]
					if btn then SetTabUnread(btn, true) end
				end
			end
		end
		
		local result = Orig.PostMessage(user, msg, ttype, from, raw_msg, hotkeyFix)
		
		-- After WIM does its thing, handle the frame
		frame = GetFrame(user)  -- Re-fetch in case it was just created
		if frame then
			HookFrame(frame)  -- Ensure hooked
			
			-- If this is the active user, ensure correct position
			if user == Tabs.active then
				-- If frame was just created (didn't exist before), 
				-- WIM showed it at default position - fix it
				if not frameExisted and frame:IsVisible() and not Tabs.skipAnchor then
					ApplyAnchor(frame)
				elseif Tabs.switching and not Tabs.skipAnchor then
					ApplyAnchor(frame)
				end
			end

			-- Enforce correct alpha/visibility immediately (covers first-time Show before hook installed)
			if Tabs.minimized then
				DisableFrame(frame)
			elseif user == Tabs.active then
				EnableFrame(frame)
			elseif frame:IsVisible() and frame:GetAlpha() > 0 then
				-- Non-active frame somehow visible - make it invisible
				DisableFrame(frame)
				local btn = Tabs.buttons[user]
				if btn then SetTabUnread(btn, true) end
			end
		end
		
		Tabs.layout()
		Tabs.switching = false
		Tabs.skipAnchor = false  -- Reset after processing
		
		return result
	end
end

-- Hook WIM_HideAll to hide tab bar (unless we're in minimize mode)
local function HookHideAll()
	if Orig.HideAll then return end
	if type(WIM_HideAll) ~= "function" then return end
	
	Orig.HideAll = WIM_HideAll
	WIM_HideAll = function()
		Orig.HideAll()
		-- Don't hide bar if minimized
		if Tabs.minimized then return end
		if Tabs.bar then Tabs.bar:Hide() end
	end
end

-- Hook WIM_SetWindowProps to keep tab bar sizing in sync
local function HookSetWindowProps()
	if Orig.SetWindowProps then return end
	if type(WIM_SetWindowProps) ~= "function" then return end
	
	Orig.SetWindowProps = WIM_SetWindowProps
	WIM_SetWindowProps = function(theWin)
		Orig.SetWindowProps(theWin)
		if WIM_Extras_Resize_AfterSetWindowProps then
			WIM_Extras_Resize_AfterSetWindowProps(theWin)
		end
		if theWin and WIM_Tabs_OnEnsureFont then
			WIM_Tabs_OnEnsureFont(theWin)
		end
		if Tabs.active and Tabs.layout then
			local activeFrame = GetFrame(Tabs.active)
			if activeFrame == theWin then
				Tabs.layout()
			end
		end
	end
end

local function HookSetAllWindowProps()
	if Orig.SetAllWindowProps then return end
	if type(WIM_SetAllWindowProps) ~= "function" then return end

	Orig.SetAllWindowProps = WIM_SetAllWindowProps
	WIM_SetAllWindowProps = function()
		Orig.SetAllWindowProps()
		-- Keep cached alpha in sync for hidden windows.
		local newAlpha = GetWimWindowAlpha()
		for user in pairs(Tabs.buttons) do
			local frame = GetFrame(user)
			if frame and frame._wimExtrasAlpha ~= nil then
				frame._wimExtrasAlpha = newAlpha
			end
		end
		EnforceTabVisibility()
		if WIM_Tabs_OnEnsureFont then
			for user in pairs(Tabs.buttons) do
				local frame = GetFrame(user)
				if frame then
					WIM_Tabs_OnEnsureFont(frame)
				end
			end
		end
		if WIM_Extras_Resize_AfterSetAllWindowProps then
			WIM_Extras_Resize_AfterSetAllWindowProps()
		end
	end
end

-- Hook WIM_SetWhoInfo to update tab name colors when class data arrives
local function HookSetWhoInfo()
	if Orig.SetWhoInfo then return end
	if type(WIM_SetWhoInfo) ~= "function" then return end
	
	Orig.SetWhoInfo = WIM_SetWhoInfo
	WIM_SetWhoInfo = function(theUser)
		Orig.SetWhoInfo(theUser)
		local btn = Tabs.buttons[theUser]
		if btn then UpdateTabLook(btn) end
	end
end

local function InitClassColorEvents()
	if Tabs.classEventFrame then return end
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_ENTERING_WORLD")
	f:RegisterEvent("PLAYER_TARGET_CHANGED")
	f:RegisterEvent("PARTY_MEMBERS_CHANGED")
	f:RegisterEvent("RAID_ROSTER_UPDATE")
	f:SetScript("OnEvent", function()
		if table.getn(Tabs.order) == 0 then return end
		UpdateUnitClassCache()
	end)
	Tabs.classEventFrame = f
end

-- Initialize
local function Init()
	HookClose()
	HookPost()
	HookHideAll()
	HookSetWindowProps()
	HookSetAllWindowProps()
	HookSetWhoInfo()
	InitClassColorEvents()
	UpdateUnitClassCache()
	if WIM_Extras_Resize_Init then
		WIM_Extras_Resize_Init()
	end
	if WIM_Extras and WIM_Extras.db and WIM_Extras.db.tabBarHeight then
		WIM_Tabs_SetBarHeight(WIM_Extras.db.tabBarHeight)
	end
	
	-- Flash animation timer (lightweight - only updates tab colors)
	local flasher = CreateFrame("Frame")
	Tabs.flashFrame = flasher
	flasher:Hide()
	flasher.elapsed = 0
	flasher:SetScript("OnUpdate", function()
		this.elapsed = this.elapsed + (arg1 or 0)
		local interval = Tabs.flashInterval or 0.8
		if this.elapsed > interval then
			this.elapsed = 0
			UpdateFlash()
		end
	end)
	
end

-- Start on addon load
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function()
	if arg1 == "WIM_Extras" then Init() end
end)
