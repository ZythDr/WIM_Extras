--[[
	WIM_PFUI - pfUI styling for WIM_Tabs
	Applies pfUI's visual style to the custom tab bar
]]

-- Only load if pfUI exists
if not pfUI then return end

-- Store pfUI colors once loaded
local pfColors = {
	bgR = 0.1, bgG = 0.1, bgB = 0.1, bgA = 0.9,
	borderR = 0.3, borderG = 0.3, borderB = 0.3, borderA = 1,
	-- Active tab border (bright gray)
	activeBorderR = 0.7, activeBorderG = 0.7, activeBorderB = 0.7, activeBorderA = 1,
	-- Flash border (bright yellow)
	flashBorderR = 1, flashBorderG = 0.8, flashBorderB = 0.2, flashBorderA = 1
}

local TAB_CLASS_DIM = 0.75
local pfuiFontHooked = false
local hookWindowPropsForFocusHooked = false
local pfuiWindowSkinFixed = false
local pfuiBorderHooked = false
local ApplyFocusBorder
local GetUserFromFrame
local GetClassColorForUser
local LoadPfUIColors
local RefreshTabColors

-- Focus border color for active WIM window (editbox focused)
-- Easy to tweak: values are 0..1
local focusBorder = { r = 0.75, g = 0.75, b = 0.75, a = 1 }
local focusUseClassColor = false

local function ApplyFlashColorFromConfig()
	if WIM_Extras and WIM_Extras.db and WIM_Extras.db.tabFlashColor then
		local c = WIM_Extras.db.tabFlashColor
		if c.r and c.g and c.b then
			pfColors.flashBorderR = c.r
			pfColors.flashBorderG = c.g
			pfColors.flashBorderB = c.b
			pfColors.flashBorderA = c.a or pfColors.flashBorderA
		end
	end
end

local function ApplyFocusBorderColorFromConfig()
	if WIM_Extras and WIM_Extras.db and WIM_Extras.db.pfuiFocusBorderColor then
		local c = WIM_Extras.db.pfuiFocusBorderColor
		if c.r and c.g and c.b then
			focusBorder = { r = c.r, g = c.g, b = c.b, a = c.a or 1 }
		end
	end
end

local function ApplyFocusUseClassColorFromConfig()
	if WIM_Extras and WIM_Extras.db then
		focusUseClassColor = WIM_Extras.db.pfuiFocusUseClassColor == true
	end
end

local function ApplyWIMBorderColor(frame)
	if not frame or not frame.backdrop then return end
	if LoadPfUIColors then LoadPfUIColors() end
	local r, g, b, a = pfColors.borderR, pfColors.borderG, pfColors.borderB, pfColors.borderA
	if frame.backdrop.SetBackdropBorderColor then
		frame.backdrop:SetBackdropBorderColor(r, g, b, a or 1)
	end
	if frame.backdrop_border and frame.backdrop_border.SetBackdropBorderColor then
		frame.backdrop_border:SetBackdropBorderColor(r, g, b, a or 1)
	end
end

local function RefreshWIMBorderColors()
	if not WIM_Windows then return end
	for _, info in pairs(WIM_Windows) do
		if info and info.frame then
			local frame = _G[info.frame]
			if frame then
				ApplyWIMBorderColor(frame)
			end
		end
	end
end


local function HookWIMWindowBorder()
	if pfuiBorderHooked then return end
	if type(hooksecurefunc) ~= "function" then return end
	pfuiBorderHooked = true
	hooksecurefunc("WIM_WindowOnShow", function()
		if this then
			ApplyWIMBorderColor(this)
		end
	end)
end

local function HookWIMWhoInfo()
	if type(WIM_SetWhoInfo) ~= "function" then return end
	if type(hooksecurefunc) == "function" then
		hooksecurefunc("WIM_SetWhoInfo", function()
			RefreshTabColors()
		end)
		return
	end
	-- Fallback for vanilla without hooksecurefunc
	if WIM_PFUI_HookedSetWhoInfo then return end
	WIM_PFUI_HookedSetWhoInfo = true
	local orig = WIM_SetWhoInfo
	WIM_SetWhoInfo = function(theUser)
		orig(theUser)
		RefreshTabColors()
	end
end

-- WIM border color is always pfUI's configured border color.

function WIM_PFUI_SetFocusBorderColor(r, g, b, a)
	focusBorder = { r = r, g = g, b = b, a = a or 1 }
	if WIM_Extras and WIM_Extras.db then
		WIM_Extras.db.pfuiFocusBorderColor = { r = r, g = g, b = b, a = a or 1 }
	end
	if WIM_Windows then
		for _, info in pairs(WIM_Windows) do
			if info and info.frame then
				local frame = _G[info.frame]
				if frame and frame._wimExtrasFocusBorder and frame._wimExtrasFocusBorder.SetBackdropBorderColor then
					frame._wimExtrasFocusBorder:SetBackdropBorderColor(r, g, b, a or 1)
				end
			end
		end
	end
end

function WIM_PFUI_SetFocusUseClassColor(enabled)
	focusUseClassColor = enabled and true or false
	if WIM_Extras and WIM_Extras.db then
		WIM_Extras.db.pfuiFocusUseClassColor = focusUseClassColor
	end
	if WIM_EditBoxInFocus and WIM_EditBoxInFocus.GetParent and ApplyFocusBorder then
		local frame = WIM_EditBoxInFocus:GetParent()
		if frame then
			ApplyFocusBorder(frame, true)
		end
	end
	if RefreshTabColors then
		RefreshTabColors()
	end
end

function WIM_PFUI_SetFlashColor(r, g, b, a)
	pfColors.flashBorderR = r or pfColors.flashBorderR
	pfColors.flashBorderG = g or pfColors.flashBorderG
	pfColors.flashBorderB = b or pfColors.flashBorderB
	pfColors.flashBorderA = a or pfColors.flashBorderA
	if WIM_Tabs_RefreshLooks then
		WIM_Tabs_RefreshLooks()
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

local function GetPfUIClassColor(user)
	if not user or user == "" then return nil end
	if not pfUI or not pfUI.GetEnvironment then return nil end
	local env = pfUI:GetEnvironment()
	if not env or not env.GetUnitData then return nil end
	local class = env.GetUnitData(user)
	if not class then return nil end
	if RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
		local c = RAID_CLASS_COLORS[class]
		return c.r, c.g, c.b
	end
	if WIM_ClassColors and WIM_ClassColors[class] then
		return HexToRGB(WIM_ClassColors[class])
	end
	return nil
end

local function GetWIMClassColor(user)
	-- Prefer WIM's own cache (it is authoritative once WHO data arrives).
	if not user or user == "" then return nil end
	if not (WIM_PlayerCache and WIM_PlayerCache[user] and WIM_PlayerCache[user].class) then return nil end
	if not (WIM_ClassColors and WIM_ClassColors[WIM_PlayerCache[user].class]) then return nil end
	return HexToRGB(WIM_ClassColors[WIM_PlayerCache[user].class])
end

GetUserFromFrame = function(frame)
	if frame and frame.theUser and frame.theUser ~= "" then
		return frame.theUser
	end
	if WIM_Tabs_GetUserFromFrame then
		return WIM_Tabs_GetUserFromFrame(frame)
	end
	if frame and frame.GetName then
		local name = frame:GetName()
		if name and string.sub(name, 1, 12) == "WIM_msgFrame" then
			local user = string.sub(name, 13)
			if user and user ~= "" then
				return user
			end
		end
	end
	return nil
end

GetClassColorForUser = function(user)
	-- Behavior: use pfUI cache immediately when available, but once WIM has WHO data,
	-- prefer WIM's class (authoritative) so it can override pfUI.
	local wr, wg, wb = GetWIMClassColor(user)
	if wr and wg and wb then
		return wr, wg, wb
	end

	local pr, pg, pb = GetPfUIClassColor(user)
	if pr and pg and pb then
		return pr, pg, pb
	end

	-- Last fallback: tab module's resolver (may use unit/other caches).
	if WIM_Tabs_GetClassColorForUser then
		local tr, tg, tb = WIM_Tabs_GetClassColorForUser(user)
		if tr and tg and tb then
			return tr, tg, tb
		end
	end

	return nil
end

local function GetFocusClassColor(frame)
	local user = nil
	if WIM_TabsState and WIM_TabsState.active then
		user = WIM_TabsState.active
	end
	if not user then
		user = GetUserFromFrame(frame)
	end
	if not user then return nil end

	if WIM_Tabs_GetClassColorForUser then
		local r, g, b = WIM_Tabs_GetClassColorForUser(user)
		if r and g and b then
			return r, g, b
		end
	end

	return GetClassColorForUser(user)
end

local function GetActiveTabBorderColor()
	if not (WIM_TabsState and WIM_TabsState.buttons and WIM_TabsState.active) then return nil end
	local btn = WIM_TabsState.buttons[WIM_TabsState.active]
	if not btn then return nil end
	if btn.GetBackdropBorderColor then
		local r, g, b = btn:GetBackdropBorderColor()
		if r and g and b then
			return r, g, b
		end
	end
	if btn.label and btn.label.GetTextColor then
		local r, g, b = btn.label:GetTextColor()
		if r and g and b then
			return r, g, b
		end
	end
	return nil
end

RefreshTabColors = function()
	if not WIM_TabsState then return end
	if WIM_TabsState.bar and WIM_TabsState.bar.IsVisible and not WIM_TabsState.bar:IsVisible() then return end
	if WIM_Tabs_RefreshLooks then
		WIM_Tabs_RefreshLooks()
	elseif WIM_TabsState.layout then
		WIM_TabsState.layout()
	end
	if ApplyFocusBorder and focusUseClassColor and WIM_EditBoxInFocus and WIM_EditBoxInFocus.GetParent then
		local frame = WIM_EditBoxInFocus:GetParent()
		if frame then
			ApplyFocusBorder(frame, true)
		end
	end
end

local function InitPfUITabColorEvents()
	if WIM_TabsState and WIM_TabsState.pfuiColorFrame then return end
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_ENTERING_WORLD")
	f:RegisterEvent("FRIENDLIST_UPDATE")
	f:RegisterEvent("GUILD_ROSTER_UPDATE")
	f:RegisterEvent("RAID_ROSTER_UPDATE")
	f:RegisterEvent("PARTY_MEMBERS_CHANGED")
	f:RegisterEvent("PLAYER_TARGET_CHANGED")
	f:RegisterEvent("WHO_LIST_UPDATE")
	f:RegisterEvent("CHAT_MSG_SYSTEM")
	f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
	f:SetScript("OnEvent", function()
		RefreshTabColors()
	end)
	if WIM_TabsState then
		WIM_TabsState.pfuiColorFrame = f
	end
end

local function GetWIMFontSize()
	if WIM_Data and WIM_Data.fontSize then return WIM_Data.fontSize end
	if WIM_Data_DEFAULTS and WIM_Data_DEFAULTS.fontSize then return WIM_Data_DEFAULTS.fontSize end
	return nil
end

local function IsPfUIWIMIntegrationEnabled()
	-- Respect pfUI's WIM integration toggle when available.
	if C and C.thirdparty and C.thirdparty.wim and C.thirdparty.wim.enable ~= nil then
		return C.thirdparty.wim.enable ~= "0"
	end
	if pfUI_config and pfUI_config.thirdparty and pfUI_config.thirdparty.wim and pfUI_config.thirdparty.wim.enable ~= nil then
		return pfUI_config.thirdparty.wim.enable ~= "0"
	end
	return true
end

local function EnsurePfUIWindowBackdrop(frame)
	if not frame or frame.backdrop then return end
	if not pfUI or not pfUI.api or not pfUI.api.CreateBackdrop then return end
	if not IsPfUIWIMIntegrationEnabled() then return end
	-- Match pfUI's own WIM integration (CreateBackdrop(..., .8))
	pfUI.api.CreateBackdrop(frame, nil, nil, 0.8)
	if pfUI.api.CreateBackdropShadow then
		pfUI.api.CreateBackdropShadow(frame)
	end
	ApplyWIMBorderColor(frame)
end

local function FixExistingWIMWindows()
	if pfuiWindowSkinFixed then return end
	pfuiWindowSkinFixed = true
	if not WIM_Windows then return end
	for _, info in pairs(WIM_Windows) do
		if info and info.frame then
			local frame = _G[info.frame]
			if frame then
				EnsurePfUIWindowBackdrop(frame)
				ApplyWIMBorderColor(frame)
			end
		end
	end
end

local function EnsureWIMFont(frame)
	if not frame or not frame.GetName then return end
	if not pfUI or not pfUI.font_default then return end
	local msgframe = _G[frame:GetName() .. "ScrollingMessageFrame"]
	if not msgframe or not msgframe.SetFont then return end
	local _, currentSize, flags = msgframe:GetFont()
	local size = GetWIMFontSize() or currentSize
	if size then
		msgframe:SetFont(pfUI.font_default, size, flags)
	end
end

local function EnsureFocusBorder(frame)
	if not frame then return nil end
	if frame._wimExtrasFocusBorder then return frame._wimExtrasFocusBorder end
	if not pfUI or not pfUI.api or not pfUI.api.CreateBackdrop then return nil end

	local border = CreateFrame("Frame", nil, frame)
	border:SetAllPoints(frame)
	border:SetFrameLevel((frame.GetFrameLevel and frame:GetFrameLevel() or 0) + 10)
	-- Force fully transparent background so the focus border never darkens the window.
	pfUI.api.CreateBackdrop(border, nil, true, 0)
	if border.SetBackdropColor then
		border:SetBackdropColor(0, 0, 0, 0)
	end
	if border.backdrop and border.backdrop.SetBackdropColor then
		border.backdrop:SetBackdropColor(0, 0, 0, 0)
	end
	border:SetBackdropBorderColor(focusBorder.r, focusBorder.g, focusBorder.b, focusBorder.a)
	border:Hide()

	frame._wimExtrasFocusBorder = border
	return border
end

ApplyFocusBorder = function(frame, focused)
	local border = EnsureFocusBorder(frame)
	if not border then return end
	if focused then
		if focusUseClassColor then
			local r, g, b = GetActiveTabBorderColor()
			if not (r and g and b) then
				r, g, b = GetFocusClassColor(frame)
			end
			if r and g and b then
				border:SetBackdropBorderColor(r, g, b, focusBorder.a or 1)
			else
				border:SetBackdropBorderColor(focusBorder.r, focusBorder.g, focusBorder.b, focusBorder.a)
			end
		else
			border:SetBackdropBorderColor(focusBorder.r, focusBorder.g, focusBorder.b, focusBorder.a)
		end
		border:Show()
	else
		border:Hide()
	end
end

local function HookEditBoxFocus(frame)
	if not frame or not frame.GetName then return end
	local msgBox = _G[frame:GetName() .. "MsgBox"]
	if not msgBox or msgBox._wimExtrasFocusHooked or not msgBox.SetScript then return end
	msgBox._wimExtrasFocusHooked = true

	local function onGain()
		ApplyFocusBorder(frame, true)
	end
	local function onLost()
		ApplyFocusBorder(frame, false)
	end

	if msgBox.HookScript then
		msgBox:HookScript("OnEditFocusGained", onGain)
		msgBox:HookScript("OnEditFocusLost", onLost)
	else
		local origGain = msgBox:GetScript("OnEditFocusGained")
		local origLost = msgBox:GetScript("OnEditFocusLost")
		msgBox:SetScript("OnEditFocusGained", function()
			if origGain then origGain() end
			onGain()
		end)
		msgBox:SetScript("OnEditFocusLost", function()
			if origLost then origLost() end
			onLost()
		end)
	end

	if WIM_EditBoxInFocus == msgBox then
		ApplyFocusBorder(frame, true)
	end
end

local function HookWindowPropsForFocus()
	if hookWindowPropsForFocusHooked then return end
	if type(WIM_SetWindowProps) ~= "function" then return end
	hookWindowPropsForFocusHooked = true
	local orig = WIM_SetWindowProps
	WIM_SetWindowProps = function(theWin)
		orig(theWin)
		if theWin then
			HookEditBoxFocus(theWin)
		end
	end
end

-- Load colors from pfUI config
LoadPfUIColors = function()
	if pfUI_config and pfUI_config.appearance and pfUI_config.appearance.border then
		if pfUI.api and pfUI.api.GetStringColor then
			pfColors.bgR, pfColors.bgG, pfColors.bgB, pfColors.bgA = 
				pfUI.api.GetStringColor(pfUI_config.appearance.border.background)
			pfColors.borderR, pfColors.borderG, pfColors.borderB, pfColors.borderA = 
				pfUI.api.GetStringColor(pfUI_config.appearance.border.color)
		end
	end
end

-- Skin a single tab button with pfUI style
local function SkinTab(btn)
	if not btn or btn._pfuiSkinned then return end
	if not pfUI.api or not pfUI.api.CreateBackdrop then return end
	
	-- Hide the original background texture
	if btn.bg then
		btn.bg:Hide()
	end
	
	-- Create pfUI backdrop
	pfUI.api.CreateBackdrop(btn, nil, true)
	btn:SetBackdropColor(pfColors.bgR, pfColors.bgG, pfColors.bgB, pfColors.bgA)
	btn:SetBackdropBorderColor(pfColors.borderR, pfColors.borderG, pfColors.borderB, pfColors.borderA)
	
	btn._pfuiSkinned = true
end

local function SkinScrollButton(btn)
	if not btn or btn._pfuiSkinned then return end
	if not pfUI.api or not pfUI.api.CreateBackdrop then return end
	if btn.bg then btn.bg:Hide() end
	pfUI.api.CreateBackdrop(btn, nil, true)
	btn:SetBackdropColor(pfColors.bgR, pfColors.bgG, pfColors.bgB, pfColors.bgA)
	btn:SetBackdropBorderColor(pfColors.borderR, pfColors.borderG, pfColors.borderB, pfColors.borderA)
	btn._pfuiSkinned = true
end

-- Update tab border colors based on state
local function UpdateTabLook(btn, isActive, isUnread, flashOn)
	if not btn then return end
	if not btn._pfuiSkinned then
		SkinTab(btn)
	end
	if not btn._pfuiSkinned then return end
	if not btn.SetBackdropBorderColor then return end
	
	if isActive then
		if btn.user then
			local r, g, b = GetClassColorForUser(btn.user)
			if r and g and b then
				btn:SetBackdropBorderColor(r, g, b, pfColors.activeBorderA)
				-- Keep focus border in sync with active tab class color.
				if focusUseClassColor and WIM_EditBoxInFocus and WIM_EditBoxInFocus.GetParent then
					local frame = WIM_EditBoxInFocus:GetParent()
					if frame then
						ApplyFocusBorder(frame, true)
					end
				end
				return
			end
		end
		-- Active tab gets bright gray border
		btn:SetBackdropBorderColor(
			pfColors.activeBorderR, pfColors.activeBorderG,
			pfColors.activeBorderB, pfColors.activeBorderA
		)
	elseif isUnread and flashOn then
		if WIM_Extras and WIM_Extras.db and WIM_Extras.db.tabFlashUseClassColor and btn.user then
			local r, g, b = GetClassColorForUser(btn.user)
			if r and g and b then
				r, g, b = r * TAB_CLASS_DIM, g * TAB_CLASS_DIM, b * TAB_CLASS_DIM
				btn:SetBackdropBorderColor(r, g, b, pfColors.flashBorderA)
			else
				btn:SetBackdropBorderColor(
					pfColors.flashBorderR, pfColors.flashBorderG,
					pfColors.flashBorderB, pfColors.flashBorderA
				)
			end
		else
			-- Flashing unread tab gets yellow border
			btn:SetBackdropBorderColor(
				pfColors.flashBorderR, pfColors.flashBorderG, 
				pfColors.flashBorderB, pfColors.flashBorderA
			)
		end
	else
		-- Normal inactive tab gets default border
		btn:SetBackdropBorderColor(
			pfColors.borderR, pfColors.borderG, 
			pfColors.borderB, pfColors.borderA
		)
	end
end

-- Update scroll button border colors based on flash state and active direction
-- activeDirection: -1 = active tab off-screen left, 0 = visible, 1 = off-screen right
local function UpdateScrollFlash(bar, flashLeft, flashRight, flashOn, activeDirection)
	if not bar then return end
	
	-- Reduce the built-in flash overlay alpha since we use borders
	if bar.scrollLeft and bar.scrollLeft.flash then
		if flashLeft then
			bar.scrollLeft.flash:SetAlpha(flashOn and 0.2 or 0)
		end
	end
	if bar.scrollRight and bar.scrollRight.flash then
		if flashRight then
			bar.scrollRight.flash:SetAlpha(flashOn and 0.2 or 0)
		end
	end
	
	-- Left scroll button border color
	-- Priority: flashing yellow > active gray > normal
	if bar.scrollLeft and bar.scrollLeft._pfuiSkinned and bar.scrollLeft.SetBackdropBorderColor then
		if flashLeft and flashOn then
			-- Flashing tab off-screen to left - yellow border
			bar.scrollLeft:SetBackdropBorderColor(
				pfColors.flashBorderR, pfColors.flashBorderG, 
				pfColors.flashBorderB, pfColors.flashBorderA
			)
		elseif activeDirection == -1 then
			-- Active tab off-screen to left - bright gray border
			bar.scrollLeft:SetBackdropBorderColor(
				pfColors.activeBorderR, pfColors.activeBorderG, 
				pfColors.activeBorderB, pfColors.activeBorderA
			)
		else
			-- Normal state
			bar.scrollLeft:SetBackdropBorderColor(
				pfColors.borderR, pfColors.borderG, 
				pfColors.borderB, pfColors.borderA
			)
		end
	end
	
	-- Right scroll button border color
	-- Priority: flashing yellow > active gray > normal
	if bar.scrollRight and bar.scrollRight._pfuiSkinned and bar.scrollRight.SetBackdropBorderColor then
		if flashRight and flashOn then
			-- Flashing tab off-screen to right - yellow border
			bar.scrollRight:SetBackdropBorderColor(
				pfColors.flashBorderR, pfColors.flashBorderG, 
				pfColors.flashBorderB, pfColors.flashBorderA
			)
		elseif activeDirection == 1 then
			-- Active tab off-screen to right - bright gray border
			bar.scrollRight:SetBackdropBorderColor(
				pfColors.activeBorderR, pfColors.activeBorderG, 
				pfColors.activeBorderB, pfColors.activeBorderA
			)
		else
			-- Normal state
			bar.scrollRight:SetBackdropBorderColor(
				pfColors.borderR, pfColors.borderG, 
				pfColors.borderB, pfColors.borderA
			)
		end
	end
end

-- Skin the main tab bar with pfUI style
local function SkinBar(bar)
	if not bar or bar._pfuiSkinned then return end
	if not pfUI.api or not pfUI.api.CreateBackdrop then return end
	
	LoadPfUIColors()
	
	-- Remove default/pfUI backdrops on the main bar (keep it transparent)
	if bar.bg then
		bar.bg:Hide()
	end
	if bar.SetBackdrop then
		bar:SetBackdrop(nil)
	end
	
	-- Style scroll buttons if they exist
	if bar.scrollLeft then
		SkinScrollButton(bar.scrollLeft)
	end
	if bar.scrollRight then
		SkinScrollButton(bar.scrollRight)
	end
	
	bar._pfuiSkinned = true
end

-- Set up the skinning hooks
local function SetupHooks()
	-- Hook tab creation
	WIM_Tabs_OnSkinTab = SkinTab
	
	-- Hook bar creation
	WIM_Tabs_OnSkinBar = SkinBar
	
	-- Hook tab appearance updates (for border colors)
	WIM_Tabs_OnUpdateTabLook = UpdateTabLook
	
	-- Hook scroll button flash updates (for border colors)
	WIM_Tabs_OnUpdateScrollFlash = UpdateScrollFlash
	ApplyFlashColorFromConfig()
	ApplyFocusBorderColorFromConfig()
	ApplyFocusUseClassColorFromConfig()
	HookWIMWindowBorder()
	HookWIMWhoInfo()
	RefreshWIMBorderColors()
	
	-- Provide pfUI class cache for tab name colors
	WIM_Tabs_GetExternalClassColor = GetPfUIClassColor
	InitPfUITabColorEvents()
	WIM_Tabs_OnEnsureFont = EnsureWIMFont
	HookWindowPropsForFocus()
	FixExistingWIMWindows()
	if not pfuiFontHooked then
		pfuiFontHooked = true
		if WIM_Windows then
			for _, info in pairs(WIM_Windows) do
				if info and info.frame then
					local frame = _G[info.frame]
					if frame then
						EnsureWIMFont(frame)
						HookEditBoxFocus(frame)
					end
				end
			end
		end
	end
	-- Skin any existing bar and tabs
	if WIM_TabsState then
		if WIM_TabsState.bar then
			SkinBar(WIM_TabsState.bar)
		end
		if WIM_TabsState.buttons then
			for user, btn in pairs(WIM_TabsState.buttons) do
				SkinTab(btn)
			end
		end
	end
end

-- Initialize after pfUI is ready
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function()
	-- Delay to ensure WIM_Tabs and pfUI are both ready
	local timer = CreateFrame("Frame")
	timer.elapsed = 0
	timer:SetScript("OnUpdate", function()
		this.elapsed = this.elapsed + (arg1 or 0)
		if this.elapsed > 1 then
			this:Hide()
			if pfUI and pfUI.api and pfUI.api.CreateBackdrop then
				SetupHooks()
			end
		end
	end)
end)
