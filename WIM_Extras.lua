-- Unfocus WIM edit box when clicking outside the active WIM window

local function WIMExtras_IsPointOutside(frame)
	if not frame or not frame.GetLeft then return false end
	if not UIParent or not UIParent.GetEffectiveScale then return false end
	if not GetCursorPosition then return false end

	local left, right = frame:GetLeft(), frame:GetRight()
	local top, bottom = frame:GetTop(), frame:GetBottom()
	if not left or not right or not top or not bottom then return false end

	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	x = x / scale
	y = y / scale

	if x < left or x > right or y < bottom or y > top then
		return true
	end
	return false
end

local function WIMExtras_ClearFocusIfOutside()
	if not WIM_EditBoxInFocus or not WIM_EditBoxInFocus.ClearFocus then return end
	if not WIM_EditBoxInFocus:IsVisible() then return end
	local parent = WIM_EditBoxInFocus:GetParent()
	if not parent or not parent:IsVisible() then return end
	if WIMExtras_IsPointOutside(parent) then
		WIM_EditBoxInFocus:ClearFocus()
	end
end

local function WIMExtras_OnUpdate(self)
	if not WIM_EditBoxInFocus or not WIM_EditBoxInFocus.ClearFocus then
		self.wasDown = false
		return
	end
	if not WIM_EditBoxInFocus:IsVisible() then
		self.wasDown = false
		return
	end
	if not IsMouseButtonDown then return end

	local isDown = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") or IsMouseButtonDown("MiddleButton")
	if isDown and not self.wasDown then
		WIMExtras_ClearFocusIfOutside()
	end
	self.wasDown = isDown
end

local function WIMExtras_InitClickOutsideFocus()
	if WIMExtras_ClickOutsideHooked then return end

	local watcher = CreateFrame("Frame")
	watcher.wasDown = false
	watcher:SetScript("OnUpdate", WIMExtras_OnUpdate)

	WIMExtras_ClickOutsideWatcher = watcher
    	WIMExtras_ClickOutsideHooked = true
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function()
	if arg1 == "WIM" then
		WIMExtras_InitClickOutsideFocus()
	end
end)
