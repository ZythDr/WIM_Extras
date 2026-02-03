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

local pfuiFontHooked = false

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

local function RefreshTabColors()
	if not WIM_TabsState or not WIM_TabsState.layout then return end
	if WIM_TabsState.bar and WIM_TabsState.bar.IsVisible and not WIM_TabsState.bar:IsVisible() then return end
	WIM_TabsState.layout()
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

local function ApplyWIMFontToMsgFrame(msgframe)
	if not msgframe or not msgframe.SetFont then return end
	if not pfUI or not pfUI.font_default then return end
	local _, currentSize, flags = msgframe:GetFont()
	local size = (WIM_Data and WIM_Data.fontSize) or currentSize
	msgframe:SetFont(pfUI.font_default, size, flags)
end

local function HookMsgFrameFont(frame)
	if not frame or not frame.GetName then return end
	local msgframe = _G[frame:GetName() .. "ScrollingMessageFrame"]
	if not msgframe then return end
	if msgframe._wimPfuiFontHooked then
		ApplyWIMFontToMsgFrame(msgframe)
		return
	end
	msgframe._wimPfuiFontHooked = true
	local origSetFont = msgframe.SetFont
	msgframe.SetFont = function(self, font, size, flags)
		local useFont = (pfUI and pfUI.font_default) or font
		local useSize = (WIM_Data and WIM_Data.fontSize) or size
		return origSetFont(self, useFont, useSize, flags)
	end
	ApplyWIMFontToMsgFrame(msgframe)
end

local function ApplyWIMFontSizeToExisting()
	if not WIM_Windows then return end
	for _, info in pairs(WIM_Windows) do
		if info and info.frame then
			local frame = _G[info.frame]
			if frame then HookMsgFrameFont(frame) end
		end
	end
end

local function HookWIMWindowFontSize()
	if pfuiFontHooked then return end
	if type(hooksecurefunc) ~= "function" then return end
	if type(WIM_WindowOnShow) ~= "function" or type(WIM_SetWindowProps) ~= "function" then return end
	hooksecurefunc("WIM_WindowOnShow", function()
		if this then HookMsgFrameFont(this) end
	end)
	hooksecurefunc("WIM_SetWindowProps", function(theWin)
		if theWin then HookMsgFrameFont(theWin) end
	end)
	pfuiFontHooked = true
end

-- Load colors from pfUI config
local function LoadPfUIColors()
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

-- Update tab border colors based on state
local function UpdateTabLook(btn, isActive, isUnread, flashOn)
	if not btn then return end
	if not btn._pfuiSkinned then
		SkinTab(btn)
	end
	if not btn._pfuiSkinned then return end
	if not btn.SetBackdropBorderColor then return end
	
	if isActive then
		-- Active tab gets bright gray border
		btn:SetBackdropBorderColor(
			pfColors.activeBorderR, pfColors.activeBorderG, 
			pfColors.activeBorderB, pfColors.activeBorderA
		)
	elseif isUnread and flashOn then
		-- Flashing unread tab gets yellow border
		btn:SetBackdropBorderColor(
			pfColors.flashBorderR, pfColors.flashBorderG, 
			pfColors.flashBorderB, pfColors.flashBorderA
		)
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
		if bar.scrollLeft.bg then bar.scrollLeft.bg:Hide() end
		pfUI.api.CreateBackdrop(bar.scrollLeft, nil, true)
		bar.scrollLeft:SetBackdropColor(pfColors.bgR, pfColors.bgG, pfColors.bgB, pfColors.bgA)
		bar.scrollLeft:SetBackdropBorderColor(pfColors.borderR, pfColors.borderG, pfColors.borderB, pfColors.borderA)
		bar.scrollLeft._pfuiSkinned = true
	end
	
	if bar.scrollRight then
		if bar.scrollRight.bg then bar.scrollRight.bg:Hide() end
		pfUI.api.CreateBackdrop(bar.scrollRight, nil, true)
		bar.scrollRight:SetBackdropColor(pfColors.bgR, pfColors.bgG, pfColors.bgB, pfColors.bgA)
		bar.scrollRight:SetBackdropBorderColor(pfColors.borderR, pfColors.borderG, pfColors.borderB, pfColors.borderA)
		bar.scrollRight._pfuiSkinned = true
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
	
	-- Provide pfUI class cache for tab name colors
	WIM_Tabs_GetExternalClassColor = GetPfUIClassColor
	InitPfUITabColorEvents()
	HookWIMWindowFontSize()
	ApplyWIMFontSizeToExisting()
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
				DEFAULT_CHAT_FRAME:AddMessage("|cff33ffcc[WIM_PFUI]|r pfUI styling applied to WIM tabs")
			end
		end
	end)
end)

-- Slash command to manually reskin
SLASH_WIMPFUI1 = "/wimpfui"
SlashCmdList["WIMPFUI"] = function()
	if pfUI and pfUI.api then
		SetupHooks()
		DEFAULT_CHAT_FRAME:AddMessage("|cff33ffcc[WIM_PFUI]|r Reskinned WIM tabs")
	else
		DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[WIM_PFUI]|r pfUI not loaded")
	end
end
