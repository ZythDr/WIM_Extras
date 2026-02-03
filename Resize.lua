-- Temporary session-only resize handle for WIM windows.
--
-- Adds a small bottom-right drag handle. Dragging resizes the active window and then
-- applies that size to all WIM windows. The size is NOT persisted; if the user changes
-- WIM's own Window Width/Height sliders (WIM_Data.winSize), we clear the temp size.

WIM_Extras = WIM_Extras or {}

local RESIZE_MIN_W = 250
local RESIZE_MAX_W = 800
local RESIZE_MIN_H = 130
local RESIZE_MAX_H = 600
local RESIZE_SHORTCUT_MIN_H = 240 -- WIM enforces this when shortcut bar is enabled.

local State = {
	temp = nil,        -- { w = number, h = number }
	lastWimSize = nil, -- { w = number, h = number }
}

local function RequestTabsLayout()
	if WIM_TabsState and WIM_TabsState.layout then
		WIM_TabsState.layout()
	end
end

local function ClampResizeSize(w, h)
	if w < RESIZE_MIN_W then w = RESIZE_MIN_W end
	if w > RESIZE_MAX_W then w = RESIZE_MAX_W end
	if h < RESIZE_MIN_H then h = RESIZE_MIN_H end
	if h > RESIZE_MAX_H then h = RESIZE_MAX_H end
	if WIM_Data and WIM_Data.showShortcutBar and h < RESIZE_SHORTCUT_MIN_H then
		h = RESIZE_SHORTCUT_MIN_H
	end
	return w, h
end

local function ApplySizeToWindow(frame, w, h)
	if not frame or not frame.SetWidth or not frame.SetHeight then return end
	w, h = ClampResizeSize(w, h)
	frame:SetWidth(w)
	frame:SetHeight(h)
end

local function ApplySizeToAll(w, h)
	if not WIM_Windows then return end
	for _, info in pairs(WIM_Windows) do
		if info and info.frame then
			local frame = _G[info.frame]
			if frame then
				ApplySizeToWindow(frame, w, h)
			end
		end
	end
	RequestTabsLayout()
end

function WIM_Extras_Resize_Init()
	if WIM_Data and WIM_Data.winSize then
		State.lastWimSize = { w = WIM_Data.winSize.width, h = WIM_Data.winSize.height }
	end
end

function WIM_Extras_Resize_AfterSetWindowProps(theWin)
	if not State.temp then return end
	ApplySizeToWindow(theWin, State.temp.w, State.temp.h)
	RequestTabsLayout()
end

function WIM_Extras_Resize_AfterSetAllWindowProps()
	-- If WIM's own sliders changed, clear any session temp size.
	if WIM_Data and WIM_Data.winSize and State.lastWimSize then
		if WIM_Data.winSize.width ~= State.lastWimSize.w or WIM_Data.winSize.height ~= State.lastWimSize.h then
			State.temp = nil
		end
	end

	if WIM_Data and WIM_Data.winSize then
		State.lastWimSize = { w = WIM_Data.winSize.width, h = WIM_Data.winSize.height }
	end

	if State.temp then
		ApplySizeToAll(State.temp.w, State.temp.h)
	end
end

function WIM_Extras_Resize_EnsureHandle(frame)
	if not frame or frame._wimExtrasResizeHandle then return end

	local handle = CreateFrame("Frame", nil, frame)
	handle:SetWidth(16)
	handle:SetHeight(16)
	handle:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
	handle:SetFrameLevel((frame.GetFrameLevel and frame:GetFrameLevel() or 0) + 20)
	handle:EnableMouse(true)

	handle.tex = handle:CreateTexture(nil, "OVERLAY")
	handle.tex:SetAllPoints()
	handle.tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	handle:SetAlpha(0.2)

	handle:SetScript("OnEnter", function()
		handle:SetAlpha(1)
	end)
	handle:SetScript("OnLeave", function()
		if not handle._resizing then
			handle:SetAlpha(0.2)
		end
	end)

	handle:SetScript("OnMouseDown", function()
		if arg1 ~= "LeftButton" then return end
		handle._resizing = true
		handle:SetAlpha(1)
		handle.startX, handle.startY = GetCursorPosition()
		handle.startW = frame:GetWidth()
		handle.startH = frame:GetHeight()
		handle.scale = (frame.GetEffectiveScale and frame:GetEffectiveScale()) or (frame.GetScale and frame:GetScale()) or 1
		handle:SetScript("OnUpdate", function()
			if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
				handle._resizing = false
				handle:SetScript("OnUpdate", nil)
				handle:SetAlpha(0)
				if State.temp then
					ApplySizeToAll(State.temp.w, State.temp.h)
				end
				return
			end
			local x, y = GetCursorPosition()
			local dx = (x - handle.startX) / handle.scale
			local dy = (y - handle.startY) / handle.scale
			local w = (handle.startW or 0) + dx
			local h = (handle.startH or 0) - dy
			w, h = ClampResizeSize(w, h)
			if not State.temp or State.temp.w ~= w or State.temp.h ~= h then
				State.temp = { w = w, h = h }
				ApplySizeToWindow(frame, w, h)
				RequestTabsLayout()
			end
		end)
	end)

	handle:SetScript("OnMouseUp", function()
		if arg1 ~= "LeftButton" then return end
		handle._resizing = false
		handle:SetScript("OnUpdate", nil)
		handle:SetAlpha(0.2)
		if State.temp then
			ApplySizeToAll(State.temp.w, State.temp.h)
		end
	end)

	frame._wimExtrasResizeHandle = handle
end
