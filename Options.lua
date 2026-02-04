-- Options UI for WIM_Extras (extends WIM's config window)

local initialized = false

local function GetDB()
	if WIM_Extras_EnsureDB then WIM_Extras_EnsureDB() end
	return (WIM_Extras and WIM_Extras.db) or {}
end

local function SetDropDownText(frame, text)
	if not UIDropDownMenu_SetText then return end
	-- Vanilla signature is UIDropDownMenu_SetText(text, frame)
	UIDropDownMenu_SetText(text, frame)
end

local function SetTooltip(frame, text)
	if not frame then return end
	frame.tooltipText = text
	frame:SetScript("OnEnter", function()
		if GameTooltip and this.tooltipText then
			GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
			GameTooltip:SetText(this.tooltipText, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	frame:SetScript("OnLeave", function()
		if GameTooltip then GameTooltip:Hide() end
	end)
end

local function SetSwatchEnabled(btn, enabled)
	if not btn then return end
	btn:EnableMouse(enabled)
	if btn.label and btn.label.SetTextColor then
		if enabled then
			btn.label:SetTextColor(1, 1, 1)
		else
			btn.label:SetTextColor(0.6, 0.6, 0.6)
		end
	end
end

local function CreateCheckBox(name, parent, label, tooltip)
	local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
	local text = getglobal(name .. "Text")
	if text then text:SetText(label) end
	if tooltip then SetTooltip(cb, tooltip) end
	return cb
end

local function CreateSectionTitle(parent, text, anchor, x, y)
	local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetText(text)
	title:SetPoint(anchor, parent, anchor, x, y)
	return title
end

local function CreateColorSwatch(name, parent, label)
	local btn = CreateFrame("Button", name, parent)
	btn:SetWidth(16)
	btn:SetHeight(16)
	btn.tex = btn:CreateTexture(nil, "ARTWORK")
	btn.tex:SetAllPoints()
	btn.tex:SetTexture(1, 1, 1, 1)
	btn.border = btn:CreateTexture(nil, "BACKGROUND")
	btn.border:SetAllPoints()
	btn.border:SetTexture(0, 0, 0, 1)

	btn.label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	btn.label:SetText(label)
	btn.label:SetPoint("LEFT", btn, "RIGHT", 6, 0)

	return btn
end

local function RefreshControls()
	if not WIM_OptionsTabbedFrameExtras then return end
	local db = GetDB()
	local sortMode = db.tabSortMode or "none"
	local sortLabel = "None"
	if sortMode == "incoming_outgoing" then
		sortLabel = "Incoming + Outgoing"
	elseif sortMode == "outgoing" then
		sortLabel = "Only Outgoing"
	end

	if WIM_ExtrasOptionFocusBlocker then
		WIM_ExtrasOptionFocusBlocker:SetChecked(db.focusBlockerEnabled ~= false)
	end
	if WIM_ExtrasOptionTabsGrowLeft then
		WIM_ExtrasOptionTabsGrowLeft:SetChecked(db.tabGrowDirection ~= "RIGHT")
	end
	if WIM_ExtrasOptionTabsGrowRight then
		WIM_ExtrasOptionTabsGrowRight:SetChecked(db.tabGrowDirection == "RIGHT")
	end
	if WIM_ExtrasOptionTabFlash then
		WIM_ExtrasOptionTabFlash:SetChecked(db.tabFlashEnabled ~= false)
	end
	if WIM_ExtrasOptionFlashUseClass then
		WIM_ExtrasOptionFlashUseClass:SetChecked(db.tabFlashUseClassColor == true)
	end
	if WIM_ExtrasOptionTabBarTop then
		WIM_ExtrasOptionTabBarTop:SetChecked(db.tabBarPosition ~= "BOTTOM")
	end
	if WIM_ExtrasOptionTabBarBottom then
		WIM_ExtrasOptionTabBarBottom:SetChecked(db.tabBarPosition == "BOTTOM")
	end
	if WIM_ExtrasOptionTabSort and UIDropDownMenu_SetSelectedValue then
		UIDropDownMenu_SetSelectedValue(WIM_ExtrasOptionTabSort, sortMode)
		SetDropDownText(WIM_ExtrasOptionTabSort, sortLabel)
	end
	if WIM_ExtrasOptionFlashColor and WIM_ExtrasOptionFlashColor.tex then
		local c = db.tabFlashColor or { r = 1, g = 0.8, b = 0.2, a = 0.7 }
		WIM_ExtrasOptionFlashColor.tex:SetVertexColor(c.r, c.g, c.b)
		SetSwatchEnabled(WIM_ExtrasOptionFlashColor, db.tabFlashUseClassColor ~= true)
	end
	if WIM_ExtrasOptionTabHeight then
		local h = db.tabBarHeight or 20
		WIM_ExtrasOptionTabHeight._wimExtrasIgnore = true
		WIM_ExtrasOptionTabHeight:SetValue(h)
		local edit = getglobal("WIM_ExtrasOptionTabHeightEditBox")
		if edit then edit:SetText(h) end
		WIM_ExtrasOptionTabHeight._wimExtrasIgnore = false
	end
	if WIM_ExtrasOptionFlashInterval then
		local v = db.tabFlashInterval or 0.8
		WIM_ExtrasOptionFlashInterval._wimExtrasIgnore = true
		WIM_ExtrasOptionFlashInterval:SetValue(v)
		local sliderMin, sliderMax = WIM_ExtrasOptionFlashInterval:GetMinMaxValues()
		getglobal("WIM_ExtrasOptionFlashIntervalLow"):SetText(string.format("%.1f", sliderMin))
		getglobal("WIM_ExtrasOptionFlashIntervalHigh"):SetText(string.format("%.1f", sliderMax))
		local edit = getglobal("WIM_ExtrasOptionFlashIntervalEditBox")
		if edit then edit:SetText(string.format("%.1f", v)) end
		WIM_ExtrasOptionFlashInterval._wimExtrasIgnore = false
	end
	-- WIM border color is always pfUI's border color now; no extra options needed.
	if WIM_ExtrasOptionPfUIFocusUseClass then
		WIM_ExtrasOptionPfUIFocusUseClass:SetChecked(db.pfuiFocusUseClassColor == true)
		if not pfUI then
			WIM_ExtrasOptionPfUIFocusUseClass:Disable()
		else
			WIM_ExtrasOptionPfUIFocusUseClass:Enable()
		end
	end
	if WIM_ExtrasOptionPfUIFocusOpaque then
		WIM_ExtrasOptionPfUIFocusOpaque:SetChecked(db.pfuiFocusBorderOpaque == true)
		if not pfUI then
			WIM_ExtrasOptionPfUIFocusOpaque:Disable()
		else
			WIM_ExtrasOptionPfUIFocusOpaque:Enable()
		end
	end
	if WIM_ExtrasOptionPfUIFocusBorderColor and WIM_ExtrasOptionPfUIFocusBorderColor.tex then
		local c = db.pfuiFocusBorderColor or { r = 0.75, g = 0.75, b = 0.75, a = 1 }
		WIM_ExtrasOptionPfUIFocusBorderColor.tex:SetVertexColor(c.r, c.g, c.b)
		SetSwatchEnabled(WIM_ExtrasOptionPfUIFocusBorderColor, pfUI and db.pfuiFocusUseClassColor ~= true)
	end
end

local function ApplyFlashColor(r, g, b, a)
	if WIM_Tabs_SetFlashColor then
		WIM_Tabs_SetFlashColor(r, g, b, a)
	end
	if WIM_ExtrasOptionFlashColor and WIM_ExtrasOptionFlashColor.tex then
		WIM_ExtrasOptionFlashColor.tex:SetVertexColor(r, g, b)
	end
end

local function OpenFlashColorPicker()
	local db = GetDB()
	local c = db.tabFlashColor or { r = 1, g = 0.8, b = 0.2, a = 0.7 }
	local prev = { r = c.r, g = c.g, b = c.b, a = c.a }

	ColorPickerFrame.func = function()
		local r, g, b = ColorPickerFrame:GetColorRGB()
		local a = 1
		if OpacitySliderFrame and OpacitySliderFrame.GetValue then
			a = 1 - OpacitySliderFrame:GetValue()
		end
		ApplyFlashColor(r, g, b, a)
	end
	ColorPickerFrame.opacityFunc = ColorPickerFrame.func
	ColorPickerFrame.cancelFunc = function()
		ApplyFlashColor(prev.r, prev.g, prev.b, prev.a)
	end
	ColorPickerFrame.hasOpacity = true
	ColorPickerFrame.opacity = 1 - (c.a or 1)
	ColorPickerFrame:SetColorRGB(c.r, c.g, c.b)
	ColorPickerFrame:Show()
end

local function ApplyTabHeight(value)
	if WIM_Tabs_SetBarHeight then
		WIM_Tabs_SetBarHeight(value)
	end
end

local function ApplyPfUIFocusBorderColor(r, g, b, a)
	if WIM_PFUI_SetFocusBorderColor then
		WIM_PFUI_SetFocusBorderColor(r, g, b, a)
	end
	if WIM_ExtrasOptionPfUIFocusBorderColor and WIM_ExtrasOptionPfUIFocusBorderColor.tex then
		WIM_ExtrasOptionPfUIFocusBorderColor.tex:SetVertexColor(r, g, b)
	end
end

local function OpenPfUIFocusBorderColorPicker()
	local db = GetDB()
	local c = db.pfuiFocusBorderColor or { r = 0.75, g = 0.75, b = 0.75, a = 1 }
	local prev = { r = c.r, g = c.g, b = c.b, a = c.a }

	ColorPickerFrame.func = function()
		local r, g, b = ColorPickerFrame:GetColorRGB()
		local a = 1
		if OpacitySliderFrame and OpacitySliderFrame.GetValue then
			a = 1 - OpacitySliderFrame:GetValue()
		end
		ApplyPfUIFocusBorderColor(r, g, b, a)
	end
	ColorPickerFrame.opacityFunc = ColorPickerFrame.func
	ColorPickerFrame.cancelFunc = function()
		ApplyPfUIFocusBorderColor(prev.r, prev.g, prev.b, prev.a)
	end
	ColorPickerFrame.hasOpacity = true
	ColorPickerFrame.opacity = 1 - (c.a or 1)
	ColorPickerFrame:SetColorRGB(c.r, c.g, c.b)
	ColorPickerFrame:Show()
end

local function HideExtrasTab()
	if WIM_OptionsOptionTab5 then
		PanelTemplates_DeselectTab(WIM_OptionsOptionTab5)
	end
	if WIM_OptionsTabbedFrameExtras then
		WIM_OptionsTabbedFrameExtras:Hide()
	end
end

local function HookOptionsClicks()
	if type(WIM_Options_General_Click) == "function" and not WIM_Extras_HookedGeneral then
		WIM_Extras_HookedGeneral = true
		local orig = WIM_Options_General_Click
		WIM_Options_General_Click = function()
			orig()
			HideExtrasTab()
		end
	end
	if type(WIM_Options_Windows_Click) == "function" and not WIM_Extras_HookedWindows then
		WIM_Extras_HookedWindows = true
		local orig = WIM_Options_Windows_Click
		WIM_Options_Windows_Click = function()
			orig()
			HideExtrasTab()
		end
	end
	if type(WIM_Options_Filter_Click) == "function" and not WIM_Extras_HookedFilter then
		WIM_Extras_HookedFilter = true
		local orig = WIM_Options_Filter_Click
		WIM_Options_Filter_Click = function()
			orig()
			HideExtrasTab()
		end
	end
	if type(WIM_Options_History_Click) == "function" and not WIM_Extras_HookedHistory then
		WIM_Extras_HookedHistory = true
		local orig = WIM_Options_History_Click
		WIM_Options_History_Click = function()
			orig()
			HideExtrasTab()
		end
	end
	if type(WIM_Options_OnShow) == "function" and not WIM_Extras_HookedOnShow then
		WIM_Extras_HookedOnShow = true
		local orig = WIM_Options_OnShow
		WIM_Options_OnShow = function()
			orig()
			RefreshControls()
		end
	end
end

local function CreateOptionsUI()
	if initialized then return end
	if not WIM_Options or not WIM_OptionsTabbedFrame then return end

	initialized = true

	-- Add new tab button
	local tab = CreateFrame("Button", "WIM_OptionsOptionTab5", WIM_Options, "TabButtonTemplate")
	tab:SetText("WIM Extras")
	tab:SetAlpha(0.8)
	tab:ClearAllPoints()
	tab:SetPoint("BOTTOMLEFT", WIM_OptionsOptionTab4, "BOTTOMRIGHT", 0, 0)
	if WIM_OptionsOptionTab4 and WIM_OptionsOptionTab4.GetHeight then
		tab:SetHeight(WIM_OptionsOptionTab4:GetHeight())
	end
	PanelTemplates_TabResize(0, tab)
	getglobal(tab:GetName() .. "HighlightTexture"):SetWidth(tab:GetTextWidth() + 10)
	if tab.GetFontString and tab:GetFontString() then
		tab:GetFontString():SetPoint("CENTER", 0, 0)
	end
	tab:SetScript("OnClick", function()
		PlaySound("igMainMenuOptionCheckBoxOn")
		PanelTemplates_SelectTab(tab)
		PanelTemplates_DeselectTab(WIM_OptionsOptionTab1)
		PanelTemplates_DeselectTab(WIM_OptionsOptionTab2)
		PanelTemplates_DeselectTab(WIM_OptionsOptionTab3)
		PanelTemplates_DeselectTab(WIM_OptionsOptionTab4)
		if WIM_OptionsTabbedFrameGeneral then WIM_OptionsTabbedFrameGeneral:Hide() end
		if WIM_OptionsTabbedFrameWindow then WIM_OptionsTabbedFrameWindow:Hide() end
		if WIM_OptionsTabbedFrameFilter then WIM_OptionsTabbedFrameFilter:Hide() end
		if WIM_OptionsTabbedFrameHistory then WIM_OptionsTabbedFrameHistory:Hide() end
		if WIM_Options_GeneralScroll then WIM_Options_GeneralScroll:Hide() end
		if WIM_OptionsTabbedFrameExtras then WIM_OptionsTabbedFrameExtras:Show() end
		RefreshControls()
	end)

	-- Create extras panel
	local panel = CreateFrame("Frame", "WIM_OptionsTabbedFrameExtras", WIM_OptionsTabbedFrame)
	panel:SetAllPoints(WIM_OptionsTabbedFrame)
	panel:Hide()

	-- Single-column scrollable content (matches WIM's native options style)
	local scroll = CreateFrame("ScrollFrame", "WIM_Options_ExtrasScroll", panel, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 6)

	local content = CreateFrame("Frame", "WIM_Options_ExtrasContent", scroll)
	content:SetWidth(300)
	content:SetHeight(740)
	scroll:SetScrollChild(content)

	CreateSectionTitle(content, "WIM Extras", "TOPLEFT", 10, -10)

	-- Focus blocker toggle
	local focusCb = CreateCheckBox("WIM_ExtrasOptionFocusBlocker", content, "Enable click-outside unfocus",
		"Toggle the full-screen blocker frames used to unfocus WIM when clicking outside.")
	focusCb:SetPoint("TOPLEFT", content, "TOPLEFT", 14, -40)
	focusCb:SetScript("OnClick", function()
		local enabled = this:GetChecked() and true or false
		if WIM_Extras_SetFocusBlockerEnabled then
			WIM_Extras_SetFocusBlockerEnabled(enabled)
		end
	end)

	-- Tab growth direction
	CreateSectionTitle(content, "Tab Growth", "TOPLEFT", 10, -80)
	local leftCb = CreateCheckBox("WIM_ExtrasOptionTabsGrowLeft", content, "New tabs on the left (active left)",
		"Most recent/active tabs appear on the left.")
	leftCb:SetPoint("TOPLEFT", content, "TOPLEFT", 14, -105)
	leftCb:SetScript("OnClick", function()
		if not this:GetChecked() then
			this:SetChecked(true)
			return
		end
		WIM_ExtrasOptionTabsGrowRight:SetChecked(false)
		if WIM_Tabs_SetGrowDirection then
			WIM_Tabs_SetGrowDirection("LEFT")
		end
	end)
	local rightCb = CreateCheckBox("WIM_ExtrasOptionTabsGrowRight", content, "New tabs on the right (active right)",
		"Most recent/active tabs appear on the right.")
	rightCb:SetPoint("TOPLEFT", content, "TOPLEFT", 14, -130)
	rightCb:SetScript("OnClick", function()
		if not this:GetChecked() then
			this:SetChecked(true)
			return
		end
		WIM_ExtrasOptionTabsGrowLeft:SetChecked(false)
		if WIM_Tabs_SetGrowDirection then
			WIM_Tabs_SetGrowDirection("RIGHT")
		end
	end)
	-- Activity-based sorting dropdown
	local sortDrop = CreateFrame("Frame", "WIM_ExtrasOptionTabSort", content, "UIDropDownMenuTemplate")
	sortDrop:SetPoint("TOPLEFT", content, "TOPLEFT", -4, -170)
	UIDropDownMenu_SetWidth(160, sortDrop)
	SetDropDownText(sortDrop, "Activity-based tab sorting")
	sortDrop.valueText = "Activity-based tab sorting"
	SetTooltip(sortDrop, "Controls whether tabs reorder based on activity.")

	local function SetSortMode(value)
		if WIM_Tabs_SetSortMode then
			WIM_Tabs_SetSortMode(value)
		end
		if UIDropDownMenu_SetSelectedValue then
			UIDropDownMenu_SetSelectedValue(sortDrop, value)
		end
	end

	local function InitSortDrop()
		local selected = UIDropDownMenu_GetSelectedValue(sortDrop)
		local function addOption(text, value)
			local info = UIDropDownMenu_CreateInfo and UIDropDownMenu_CreateInfo() or {}
			info.text = text
			info.value = value
			info.func = function()
				SetSortMode(this.value)
				SetDropDownText(sortDrop, text)
			end
			info.checked = (value == selected)
			UIDropDownMenu_AddButton(info)
		end
		addOption("None", "none")
		addOption("Incoming + Outgoing", "incoming_outgoing")
		addOption("Only Outgoing", "outgoing")
	end

	UIDropDownMenu_Initialize(sortDrop, InitSortDrop)

	-- Tab bar
	CreateSectionTitle(content, "Tab Bar", "TOPLEFT", 10, -210)
	local barTop = CreateCheckBox("WIM_ExtrasOptionTabBarTop", content, "Tab bar above window",
		"Place the tab bar above the WIM chat frame.")
	barTop:SetPoint("TOPLEFT", content, "TOPLEFT", 14, -235)
	barTop:SetScript("OnClick", function()
		if not this:GetChecked() then
			this:SetChecked(true)
			return
		end
		WIM_ExtrasOptionTabBarBottom:SetChecked(false)
		if WIM_Tabs_SetBarPosition then
			WIM_Tabs_SetBarPosition("TOP")
		end
	end)
	local barBottom = CreateCheckBox("WIM_ExtrasOptionTabBarBottom", content, "Tab bar below window",
		"Place the tab bar below the WIM chat frame.")
	barBottom:SetPoint("TOPLEFT", content, "TOPLEFT", 14, -255)
	barBottom:SetScript("OnClick", function()
		if not this:GetChecked() then
			this:SetChecked(true)
			return
		end
		WIM_ExtrasOptionTabBarTop:SetChecked(false)
		if WIM_Tabs_SetBarPosition then
			WIM_Tabs_SetBarPosition("BOTTOM")
		end
	end)

	local heightSlider = CreateFrame("Slider", "WIM_ExtrasOptionTabHeight", content, "WIM_Options_SliderTemplate")
	heightSlider:SetWidth(140)
	heightSlider:SetHeight(17)
	-- Leave extra room for the slider template title (it renders above the slider).
	heightSlider:SetPoint("TOPLEFT", content, "TOPLEFT", 14, -304)
	heightSlider:SetMinMaxValues(14, 40)
	heightSlider:SetValueStep(1)
	getglobal("WIM_ExtrasOptionTabHeightTitle"):SetText("Tab bar height")
	getglobal("WIM_ExtrasOptionTabHeightLow"):SetText("14")
	getglobal("WIM_ExtrasOptionTabHeightHigh"):SetText("40")
	heightSlider:SetScript("OnValueChanged", function()
		if this._wimExtrasIgnore then return end
		local v = math.floor(this:GetValue() + 0.5)
		local edit = getglobal("WIM_ExtrasOptionTabHeightEditBox")
		if edit then edit:SetText(v) end
		ApplyTabHeight(v)
	end)

	-- Tab flashing
	CreateSectionTitle(content, "Tab Flashing", "TOPLEFT", 10, -340)
	local flashCb = CreateCheckBox("WIM_ExtrasOptionTabFlash", content, "Enable unread tab flashing",
		"Toggles flashing on unread tabs.")
	flashCb:SetPoint("TOPLEFT", content, "TOPLEFT", 14, -365)
	flashCb:SetScript("OnClick", function()
		if WIM_Tabs_SetFlashEnabled then
			WIM_Tabs_SetFlashEnabled(this:GetChecked() and true or false)
		end
	end)

	local flashClassCb = CreateCheckBox("WIM_ExtrasOptionFlashUseClass", content, "Use class color for flash",
		"Use the tab's class color for unread flash.")
	flashClassCb:SetPoint("TOPLEFT", content, "TOPLEFT", 14, -390)
	flashClassCb:SetScript("OnClick", function()
		if WIM_Tabs_SetFlashUseClassColor then
			WIM_Tabs_SetFlashUseClassColor(this:GetChecked() and true or false)
		end
		RefreshControls()
	end)

	local flashColor = CreateColorSwatch("WIM_ExtrasOptionFlashColor", content, "Flash color")
	flashColor:SetPoint("TOPLEFT", content, "TOPLEFT", 18, -420)
	flashColor:SetScript("OnClick", function()
		local db = GetDB()
		if db.tabFlashUseClassColor ~= true then
			OpenFlashColorPicker()
		end
	end)
	SetTooltip(flashColor, "Choose the flash color for unread tabs.")

	local flashInterval = CreateFrame("Slider", "WIM_ExtrasOptionFlashInterval", content, "WIM_Options_SliderTemplate")
	flashInterval:SetWidth(140)
	flashInterval:SetHeight(17)
	-- Leave room for title + keep it from feeling cramped.
	flashInterval:SetPoint("TOPLEFT", content, "TOPLEFT", 14, -468)
	flashInterval:SetMinMaxValues(0.1, 2.0)
	flashInterval:SetValueStep(0.1)
	getglobal("WIM_ExtrasOptionFlashIntervalTitle"):SetText("Flash interval (sec)")
	-- Override template's OnShow float printing (0.1000000...) with 1dp formatting.
	flashInterval:SetScript("OnShow", function()
		local sliderMin, sliderMax = this:GetMinMaxValues()
		getglobal(this:GetName() .. "Low"):SetText(string.format("%.1f", sliderMin))
		getglobal(this:GetName() .. "High"):SetText(string.format("%.1f", sliderMax))
	end)
	flashInterval:SetScript("OnValueChanged", function()
		if this._wimExtrasIgnore then return end
		local v = math.floor(this:GetValue() * 10 + 0.5) / 10
		local edit = getglobal("WIM_ExtrasOptionFlashIntervalEditBox")
		if edit then edit:SetText(string.format("%.1f", v)) end
		if WIM_Tabs_SetFlashInterval then
			WIM_Tabs_SetFlashInterval(v)
		end
	end)

	-- pfUI skin options
	CreateSectionTitle(content, "pfUI Skin", "TOPLEFT", 10, -490)

	local focusClassCb = CreateCheckBox("WIM_ExtrasOptionPfUIFocusUseClass", content, "Focus border uses class color",
		"Use the active tab's class color for the focus border.")
	focusClassCb:SetPoint("TOPLEFT", content, "TOPLEFT", 14, -515)
	focusClassCb:SetScript("OnClick", function()
		if WIM_PFUI_SetFocusUseClassColor then
			WIM_PFUI_SetFocusUseClassColor(this:GetChecked() and true or false)
		end
		RefreshControls()
	end)

	local focusOpaqueCb = CreateCheckBox("WIM_ExtrasOptionPfUIFocusOpaque", content, "Opaque focus border",
		"Keep the focus border fully opaque (ignore WIM transparency).")
	focusOpaqueCb:SetPoint("TOPLEFT", content, "TOPLEFT", 14, -540)
	focusOpaqueCb:SetScript("OnClick", function()
		if WIM_PFUI_SetFocusBorderOpaque then
			WIM_PFUI_SetFocusBorderOpaque(this:GetChecked() and true or false)
		end
	end)

	local focusBorder = CreateColorSwatch("WIM_ExtrasOptionPfUIFocusBorderColor", content, "Focus border color")
	focusBorder:SetPoint("TOPLEFT", content, "TOPLEFT", 18, -565)
	focusBorder:SetScript("OnClick", function()
		local db = GetDB()
		if pfUI and db.pfuiFocusUseClassColor ~= true then
			OpenPfUIFocusBorderColorPicker()
		end
	end)
	SetTooltip(focusBorder, "Set the pfUI focus border color when the editbox is active.")

	HookOptionsClicks()
	RefreshControls()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function()
	if arg1 == "WIM" then
		CreateOptionsUI()
	elseif arg1 == "WIM_Extras" then
		CreateOptionsUI()
	end
end)
