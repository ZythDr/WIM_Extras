-- Unfocus WIM edit box when clicking outside the active WIM window.
--
-- We use 4 "blocker" frames around the active WIM window (a hole over the window).
-- This reliably detects outside clicks on vanilla clients.

local State = {
	driver = nil,
	blockers = nil,
	forwarder = nil,
}

-- When true: any click that isn't on the editbox itself clears focus.
-- When false: only clicks outside the entire active WIM window clear focus.
local UNFOCUS_ON_CLICK_OUTSIDE_EDITBOX = true

local function IsFocusBlockerEnabled()
	if WIM_Extras and WIM_Extras.db and WIM_Extras.db.focusBlockerEnabled == false then
		return false
	end
	return true
end

local function AnyModifierDown()
	return (IsShiftKeyDown and IsShiftKeyDown()) or (IsControlKeyDown and IsControlKeyDown()) or (IsAltKeyDown and IsAltKeyDown())
end

local function EnsureEscapeUnfocus(editBox)
	if not editBox then return end
	if not editBox.SetScript then return end
	if editBox._wimExtrasEscFunc and editBox.GetScript and editBox:GetScript("OnEscapePressed") == editBox._wimExtrasEscFunc then
		return
	end
	local fn = function()
		this:ClearFocus()
	end
	editBox._wimExtrasEscFunc = fn
	editBox:SetScript("OnEscapePressed", fn)
end

local function EnsureInsertDedup(editBox)
	if not editBox or editBox._wimExtrasInsertHooked then return end
	if type(editBox.Insert) ~= "function" then return end
	editBox._wimExtrasInsertHooked = true

	-- Some combinations of bag addons + WIM hooks can call Insert() twice for the same link.
	local origInsert = editBox.Insert
	editBox.Insert = function(self, text)
		if type(text) == "string" and string.find(text, "|H", 1, true) then
			local now = (GetTime and GetTime()) or 0
			if self._wimExtrasLastInsertText == text and self._wimExtrasLastInsertAt and (now - self._wimExtrasLastInsertAt) < 0.15 then
				return
			end
			self._wimExtrasLastInsertText = text
			self._wimExtrasLastInsertAt = now
		end
		return origInsert(self, text)
	end
end

local function IsDescendant(frame, parent)
	while frame do
		if frame == parent then
			return true
		end
		if not frame.GetParent then
			return false
		end
		frame = frame:GetParent()
	end
	return false
end

local function GetKeyboardFocusCompat()
	if type(GetCurrentKeyBoardFocus) == "function" then
		return GetCurrentKeyBoardFocus()
	end
	if type(GetKeyboardFocus) == "function" then
		return GetKeyboardFocus()
	end
	if type(GetFocus) == "function" then
		return GetFocus()
	end
	return nil
end

local function GetFocusedWIMEditBox()
	if WIM_EditBoxInFocus then
		return WIM_EditBoxInFocus
	end

	local focus = GetKeyboardFocusCompat()
	if focus and focus.GetName then
		local name = focus:GetName()
		if name and string.find(name, "WIM_msgFrame", 1, true) and string.find(name, "MsgBox", 1, true) then
			WIM_EditBoxInFocus = focus
			return focus
		end
	end

	return nil
end

local function ClearWIMFocus()
	if AnyModifierDown() then return end
	local eb = GetFocusedWIMEditBox()
	if not eb or not eb.ClearFocus then return end
	eb:ClearFocus()
end

local function HideBlockers()
	if not State.blockers then return end
	for _, frame in pairs(State.blockers) do
		frame:Hide()
	end
end

local function ShouldUnfocusFromMouseFocus(mouseFocus, eb, parent)
	if not mouseFocus then
		return true
	end

	if UNFOCUS_ON_CLICK_OUTSIDE_EDITBOX then
		return not IsDescendant(mouseFocus, eb)
	end

	return not IsDescendant(mouseFocus, parent)
end

local function TryUnfocusFromBlockerClick()
	if AnyModifierDown() then return end

	local eb = GetFocusedWIMEditBox()
	if not eb then return end

	EnsureEscapeUnfocus(eb)
	EnsureInsertDedup(eb)

	local parent = eb:GetParent()
	if not parent then return end

	local focus = (GetMouseFocus and GetMouseFocus()) or nil
	if not ShouldUnfocusFromMouseFocus(focus, eb, parent) then
		return
	end

	ClearWIMFocus()
end

local function ForwardClick(button)
	if not GetMouseFocus then return end

	if not State.forwarder then
		State.forwarder = CreateFrame("Frame")
	end

	local f = State.forwarder
	f.button = button
	f.elapsed = 0
	f:SetScript("OnUpdate", function()
		this.elapsed = (this.elapsed or 0) + (arg1 or 0)
		if this.elapsed < 0 then return end
		this:SetScript("OnUpdate", nil)

		local target = GetMouseFocus()
		if not target or target == UIParent then return end

		if AnyModifierDown() then return end

		-- Prefer Button:Click (covers most UI and unit frames). Fall back to scripts.
		if type(target.Click) == "function" then
			pcall(target.Click, target, f.button)
			return
		end

		if type(target.GetScript) == "function" then
			local down = target:GetScript("OnMouseDown")
			if type(down) == "function" then
				-- Emulate WoW's `this`/`arg1` for legacy scripts.
				local oldThis, oldArg1 = this, arg1
				this = target
				arg1 = f.button
				pcall(down)
				this, arg1 = oldThis, oldArg1
			end
		end
	end)
end

local function CreateBlocker(name)
	local f = CreateFrame("Frame", name, UIParent)
	f:EnableMouse(true)
	-- Keep blocker below WIM frames/tab bar so clicks on tabs/windows aren't consumed.
	f:SetFrameStrata("LOW")
	f:SetFrameLevel(5)
	f:Hide()

	f:SetScript("OnMouseDown", function()
		-- Consume the click so we can clear focus first, then try to forward the click
		-- to whatever was underneath for minimal friction.
		local button = arg1

		HideBlockers()
		TryUnfocusFromBlockerClick()

		ForwardClick(button)
	end)

	return f
end

local function EnsureBlockers()
	if State.blockers then return end
	State.blockers = {
		top = CreateBlocker("WIMExtras_BlockerTop"),
		bottom = CreateBlocker("WIMExtras_BlockerBottom"),
		left = CreateBlocker("WIMExtras_BlockerLeft"),
		right = CreateBlocker("WIMExtras_BlockerRight"),
	}
end

local function UpdateBlockers(parent)
	-- Anchor the 4 blockers around the WIM window, leaving a "hole" over the window itself.
	State.blockers.top:ClearAllPoints()
	State.blockers.top:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
	State.blockers.top:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", 0, 0)

	State.blockers.bottom:ClearAllPoints()
	State.blockers.bottom:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
	State.blockers.bottom:SetPoint("TOPRIGHT", parent, "BOTTOMRIGHT", 0, 0)

	State.blockers.left:ClearAllPoints()
	State.blockers.left:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
	State.blockers.left:SetPoint("BOTTOMRIGHT", parent, "BOTTOMLEFT", 0, 0)

	State.blockers.right:ClearAllPoints()
	State.blockers.right:SetPoint("TOPLEFT", parent, "TOPRIGHT", 0, 0)
	State.blockers.right:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0)
end

local function Refresh()
	if not IsFocusBlockerEnabled() then
		HideBlockers()
		return
	end

	local eb = GetFocusedWIMEditBox()
	if not eb then
		HideBlockers()
		return
	end

	if eb.IsVisible and not eb:IsVisible() then
		HideBlockers()
		return
	end

	EnsureEscapeUnfocus(eb)
	EnsureInsertDedup(eb)

	local parent = eb:GetParent()
	if not parent then
		HideBlockers()
		return
	end

	if AnyModifierDown() then
		HideBlockers()
		return
	end

	EnsureBlockers()
	UpdateBlockers(parent)
	for _, frame in pairs(State.blockers) do
		frame:Show()
	end
end

local function Init()
	if State.driver then return end

	local f = CreateFrame("Frame")
	f.elapsed = 0
	f:RegisterEvent("MODIFIER_STATE_CHANGED")
	f:SetScript("OnEvent", function()
		Refresh()
	end)
	f:SetScript("OnUpdate", function()
		this.elapsed = (this.elapsed or 0) + (arg1 or 0)
		if this.elapsed < 0.05 then return end
		this.elapsed = 0
		Refresh()
	end)
	State.driver = f
end

Init()

function WIM_Extras_SetFocusBlockerEnabled(enabled)
	if WIM_Extras and WIM_Extras.db then
		WIM_Extras.db.focusBlockerEnabled = enabled and true or false
	end
	Refresh()
end
