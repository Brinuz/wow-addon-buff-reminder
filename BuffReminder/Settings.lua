-- Settings: the page under Options > AddOns, with a sub-page per class
-- listing its buffs. Your own class comes first.
local addonName, ns = ...

local L = ns.L

local function Recheck()
	ns:QueueCheck()
end

local function BuffTooltip(buff)
	if buff.tooltip then return L[buff.tooltip] end
	local intro = buff.weapon and L.WEAPON_TOOLTIP or L.BUFF_TOOLTIP
	return intro .. "\n" .. HIGHLIGHT_FONT_COLOR:WrapTextInColorCode(table.concat(ns:BuffSpellNames(buff), "\n"))
end

local function ModeOptions()
	local container = Settings.CreateControlTextContainer()
	container:Add(ns.MODE.OFF, L.MODE_OFF)
	container:Add(ns.MODE.OUT_OF_COMBAT, L.MODE_OUT_OF_COMBAT)
	container:Add(ns.MODE.IN_COMBAT, L.MODE_IN_COMBAT)
	container:Add(ns.MODE.ALWAYS, L.MODE_ALWAYS)
	return container:GetData()
end

-- A sub-page for a class, or for the buffs every class has (owners
-- "PROFESSIONS" and "ITEMS").
local function RegisterClass(parent, class, title)
	local buffs = ns.BUFFS[class]
	if not buffs then return end
	if not title then
		local color = C_ClassColor.GetClassColor(class)
		title = LOCALIZED_CLASS_NAMES_MALE[class] or class
		title = color and color:WrapTextInColorCode(title) or title
	end
	local category, layout = Settings.RegisterVerticalLayoutSubcategory(parent, title)
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L.CLASS_BUFFS))
	for _, buff in ipairs(buffs) do
		local setting = Settings.RegisterAddOnSetting(category, "BUFFREMINDER_" .. class .. "_" .. buff.key, buff.key,
			ns.db.modes[class], Settings.VarType.Number, ns:BuffName(buff), buff.mode or ns.MODE.ALWAYS)
		setting:SetValueChangedCallback(Recheck)
		Settings.CreateDropdown(category, setting, ModeOptions, BuffTooltip(buff) .. "\n\n" .. L.MODE_TOOLTIP)
	end
end

local function AddCheckbox(category, key, label, tooltip, default)
	local setting = Settings.RegisterAddOnSetting(category, "BUFFREMINDER_" .. key:upper(), key, ns.db,
		Settings.VarType.Boolean, label, default)
	setting:SetValueChangedCallback(Recheck)
	Settings.CreateCheckbox(category, setting, tooltip)
end

local function Register()
	local category = Settings.RegisterVerticalLayoutCategory(ns.TITLE)
	AddCheckbox(category, "bar", L.BAR, L.BAR_TOOLTIP, true)
	AddCheckbox(category, "message", L.MESSAGE, L.MESSAGE_TOOLTIP, true)
	AddCheckbox(category, "sound", L.SOUND, L.SOUND_TOOLTIP, true)

	local playerClass = select(2, UnitClass("player"))
	RegisterClass(category, playerClass)
	RegisterClass(category, "PROFESSIONS", L.PROFESSIONS)
	RegisterClass(category, "ITEMS", L.ITEMS)
	for _, class in ipairs(CLASS_SORT_ORDER) do
		if class ~= playerClass then
			RegisterClass(category, class)
		end
	end

	Settings.RegisterAddOnCategory(category)
	ns.settingsCategory = category
end

function ns:OpenSettings()
	if ns.settingsCategory then
		Settings.OpenToCategory(ns.settingsCategory:GetID())
	end
end

-- ns.db exists only after ADDON_LOADED, which Core handles first.
ns:On("ADDON_LOADED", function(name)
	if name == addonName and not ns.settingsCategory then
		Register()
	end
end)
