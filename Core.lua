-- Core bootstrap for WIM_Extras modules.

WIM_Extras = WIM_Extras or {}
WIM_Extras.version = WIM_Extras.version or "1.0.0"

WIM_Extras.defaults = {
	focusBlockerEnabled = true,
	tabGrowDirection = "LEFT", -- "LEFT" or "RIGHT"
	tabFlashEnabled = true,
	tabFlashColor = { r = 1, g = 0.8, b = 0.2, a = 0.7 },
	tabFlashUseClassColor = true,
	tabFlashInterval = 0.8,
	tabBarHeight = 20,
	tabBarPosition = "TOP", -- "TOP" or "BOTTOM"
	pfuiFocusBorderColor = { r = 0.75, g = 0.75, b = 0.75, a = 1 },
	pfuiFocusUseClassColor = true,
	pfuiFocusBorderOpaque = false,
	tabSortMode = "none", -- "none", "incoming_outgoing", "outgoing"
}

local function ApplyDefaults(db, defaults)
	for k, v in pairs(defaults) do
		if type(v) == "table" then
			db[k] = db[k] or {}
			for tk, tv in pairs(v) do
				if db[k][tk] == nil then
					db[k][tk] = tv
				end
			end
		elseif db[k] == nil then
			db[k] = v
		end
	end
end

local function NewRuntimeDB()
	local db = {}
	ApplyDefaults(db, WIM_Extras.defaults)
	return db
end

local dbBound = false

local function BindSavedDB()
	-- Use the saved table if present; otherwise fall back to runtime defaults.
	if WIM_ExtrasDB then
		ApplyDefaults(WIM_ExtrasDB, WIM_Extras.defaults)
		WIM_Extras.db = WIM_ExtrasDB
		dbBound = true
		return
	end
	if not WIM_Extras.db then
		WIM_Extras.db = NewRuntimeDB()
	end
end

function WIM_Extras_EnsureDB()
	if dbBound then return end
	BindSavedDB()
end

local function ApplySettings()
	if not WIM_Extras or not WIM_Extras.db then return end
	local db = WIM_Extras.db
	if WIM_Tabs_SetBarHeight and db.tabBarHeight then
		WIM_Tabs_SetBarHeight(db.tabBarHeight)
	end
	if WIM_Tabs_SetGrowDirection and db.tabGrowDirection then
		WIM_Tabs_SetGrowDirection(db.tabGrowDirection)
	end
	if WIM_Tabs_SetFlashEnabled then
		WIM_Tabs_SetFlashEnabled(db.tabFlashEnabled ~= false)
	end
	if WIM_Tabs_SetFlashColor and db.tabFlashColor then
		WIM_Tabs_SetFlashColor(db.tabFlashColor.r, db.tabFlashColor.g, db.tabFlashColor.b, db.tabFlashColor.a)
	end
	if WIM_Tabs_SetFlashUseClassColor then
		WIM_Tabs_SetFlashUseClassColor(db.tabFlashUseClassColor == true)
	end
	if WIM_Tabs_SetFlashInterval and db.tabFlashInterval then
		WIM_Tabs_SetFlashInterval(db.tabFlashInterval)
	end
	if WIM_Tabs_SetBarPosition and db.tabBarPosition then
		WIM_Tabs_SetBarPosition(db.tabBarPosition)
	end
	if WIM_Tabs_SetSortMode and db.tabSortMode then
		WIM_Tabs_SetSortMode(db.tabSortMode)
	end
	if WIM_Extras_SetFocusBlockerEnabled then
		WIM_Extras_SetFocusBlockerEnabled(db.focusBlockerEnabled ~= false)
	end
	if WIM_PFUI_SetFocusBorderColor and db.pfuiFocusBorderColor then
		WIM_PFUI_SetFocusBorderColor(db.pfuiFocusBorderColor.r, db.pfuiFocusBorderColor.g, db.pfuiFocusBorderColor.b, db.pfuiFocusBorderColor.a)
	end
	if WIM_PFUI_SetFocusUseClassColor then
		WIM_PFUI_SetFocusUseClassColor(db.pfuiFocusUseClassColor == true)
	end
	if WIM_PFUI_SetFocusBorderOpaque then
		WIM_PFUI_SetFocusBorderOpaque(db.pfuiFocusBorderOpaque == true)
	end
end

-- Create a DB immediately (SavedVariables should already be present, but fall back if not).
WIM_Extras_EnsureDB()

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("VARIABLES_LOADED")
loader:SetScript("OnEvent", function()
	if event == "ADDON_LOADED" then
		if arg1 == "WIM_Extras" then
			WIM_Extras_EnsureDB()
			ApplySettings()
		end
	elseif event == "VARIABLES_LOADED" then
		WIM_Extras_EnsureDB()
		ApplySettings()
	end
end)
