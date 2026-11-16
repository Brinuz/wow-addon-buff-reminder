-- Core: the shared table, saved settings, event routing and the slash
-- command.
local addonName, ns = ...

ns.TITLE = "Buff Reminder"
ns.SLASH = "/brm"

-- When a buff is watched (the per-buff setting).
ns.MODE = {OFF = 0, OUT_OF_COMBAT = 1, IN_COMBAT = 2, ALWAYS = 3}

ns.L = {
	MISSING = "Missing buffs",
	EXPIRED = "%s expired",
	ARMOR = "Armor",
	BLESSING = "Blessing",
	AURA = "Aura",
	ASPECT = "Aspect",
	WEAPON_IMBUE = "Weapon imbue",
	POISONS = "Poisons",
	WEAPON_STONE = "Sharpening stone or oil",
	ITEMS = "Items",
	BUFF_TOOLTIP = "Warn when none of these is on you:",
	WEAPON_TOOLTIP = "Warn when an equipped weapon has none of these:",
	POISONS_TOOLTIP = "Warn when an equipped weapon has no poison (from level 20). Click to apply the poison you used last.",
	WEAPON_STONE_TOOLTIP = "Warn when an equipped weapon has no sharpening stone, weightstone or oil on it, while you carry one. Click to apply the one you used last.",
	CLICK_TO_APPLY = "Click to apply it to your %s.",
	CLICK_TO_CAST = "Click to cast.",
	CLICK_NONE = "Apply it from your bags.",
	SHIFT_DRAG = "Shift-drag to move.",
	SOUND = "Play a sound when a buff expires",
	SOUND_TOOLTIP = "Plays the raid warning sound when a watched buff falls off.",
	MESSAGE = "Show a message when a buff expires",
	MESSAGE_TOOLTIP = "Shows \"<buff> has expired\" in the middle of the screen, like a raid warning.",
	BAR = "Show the missing buffs row",
	BAR_TOOLTIP = "A row of the missing buffs, out of combat. Click one to cast it; shift-drag to move the row.",
	CLASS_BUFFS = "Buffs to watch",
	PROFESSIONS = "Professions",
	MODE_OFF = "Off",
	MODE_OUT_OF_COMBAT = "Out of combat",
	MODE_IN_COMBAT = "In combat",
	MODE_ALWAYS = "Always",
	MODE_TOOLTIP = "When to warn about it: out of combat, in combat, or both.",
	PREVIEW_ON = "Preview on: every buff of your class shows in the row. Shift-drag it to place it, then run %s again.",
	PREVIEW_OFF = "Preview off.",
	RESET = "Row position reset.",
	HELP = "%s options | preview | reset | debug",
}

local DEFAULTS = {
	sound = true,
	message = true,
	bar = true,
	modes = {},     -- [CLASS][buffKey] = ns.MODE
	last = {},      -- [CLASS][buffKey] = spellID last cast for that buff
}

-- ---------------------------------------------------------------- events
-- Files subscribe with ns:On(event, fn); one frame dispatches them all.
local handlers = {}
local eventFrame = CreateFrame("Frame")

function ns:On(event, fn, unit)
	if not handlers[event] then
		handlers[event] = {}
		if unit then
			eventFrame:RegisterUnitEvent(event, unit)
		else
			eventFrame:RegisterEvent(event)
		end
	end
	table.insert(handlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	for _, fn in ipairs(handlers[event]) do
		fn(...)
	end
end)

function ns:Print(msg)
	print(NORMAL_FONT_COLOR:WrapTextInColorCode(ns.TITLE .. ":") .. " " .. msg)
end

-- Saved variables exist only from ADDON_LOADED on. Fill missing defaults;
-- each class's buffs get their own defaults (Buffs.lua).
ns:On("ADDON_LOADED", function(name)
	if name ~= addonName then return end
	BuffReminderDB = BuffReminderDB or {}
	local db = BuffReminderDB
	for k, v in pairs(DEFAULTS) do
		if db[k] == nil then
			db[k] = type(v) == "table" and CopyTable(v) or v
		end
	end
	for class, buffs in pairs(ns.BUFFS) do
		db.modes[class] = db.modes[class] or {}
		db.last[class] = db.last[class] or {}
		-- 0.1.0 saved an on/off checkbox per buff.
		local old = db.classes and db.classes[class] or {}
		for _, buff in ipairs(buffs) do
			if db.modes[class][buff.key] == nil then
				local default = buff.mode or ns.MODE.ALWAYS
				if old[buff.key] == false then
					default = ns.MODE.OFF
				elseif old[buff.key] and default == ns.MODE.OFF then
					default = ns.MODE.ALWAYS
				end
				db.modes[class][buff.key] = default
			end
		end
	end
	db.classes = nil
	ns.db = db
end)

-- ---------------------------------------------------------------- slash
SLASH_BUFFREMINDER1 = ns.SLASH
SLASH_BUFFREMINDER2 = "/buffreminder"
SlashCmdList.BUFFREMINDER = function(msg)
	msg = strtrim(msg or ""):lower()
	if msg == "preview" then
		ns:TogglePreview()
	elseif msg == "reset" then
		ns:ResetBarPosition()
		ns:Print(ns.L.RESET)
	elseif msg == "debug" then
		ns:Debug()
	elseif msg == "options" or msg == "" then
		ns:OpenSettings()
	else
		ns:Print(ns.L.HELP:format(ns.SLASH))
	end
end

function BuffReminder_OnAddonCompartmentClick()
	ns:OpenSettings()
end
