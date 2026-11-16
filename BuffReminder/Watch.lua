-- Watch: which of the class's watched buffs are missing, a warning when one
-- falls off, and the spell to cast for each missing one.
local _, ns = ...

local L = ns.L
local playerClass = select(2, UnitClass("player"))

-- What the row shows: parallel lists, reused on every check.
ns.missing, ns.missingCast = {}, {}

-- The buffs on the player at the last check, [key] = aura name (or true for
-- a weapon enchant). A buff that was here and is gone has expired.
local present = {}


-- Known at any rank. Once a higher rank is learned the spellbook stops
-- reporting rank 1's ID as known, so look the spell up by name.
local function IsSpellKnown(spellID)
	local name = C_Spell.GetSpellName(spellID)
	if name and C_SpellBook.FindSpellBookSlotForSpell(name, true) then
		return true
	end
	return C_SpellBook.IsSpellKnown(spellID)
end

-- Rank 1 of the spell to cast: the one last cast for this buff (groups like
-- armors and aspects), else the first one known.
local function CastSpell(buff)
	if not buff.spells then return nil end
	local last = ns.db.last[buff.owner][buff.key]
	if last and IsSpellKnown(last) then return last end
	for _, spellID in ipairs(buff.spells) do
		if IsSpellKnown(spellID) then return spellID end
	end
end

-- The item to apply from the bags: the one last used, else the first one
-- carried.
local function UseItem(buff)
	if not buff.items then return nil end
	local last = ns.db.last[buff.owner][buff.key]
	if last and C_Item.GetItemCount(last) > 0 then return last end
	for _, itemID in ipairs(buff.items) do
		if C_Item.GetItemCount(itemID) > 0 then return itemID end
	end
end

local function IsKnown(buff, castID)
	if buff.minLevel then return UnitLevel("player") >= buff.minLevel end
	if not buff.spells and buff.items then return UseItem(buff) ~= nil end
	return castID ~= nil
end

-- In combat the game hides most auras from lookups by name: they come back
-- nil even when on. What the game still allows: asking whether an aura seen
-- before combat (by its instance ID) is still there, and knowing a buff was
-- just cast. [buff] = {name, instanceID or expires}; expires nil = until
-- combat ends.
local seen = {}

-- The aura's name if the player has any spell that counts, false if none,
-- nil when the game won't say.
local function FindAura(buff)
	-- Spell names are cached once all of them resolved.
	local names = buff.names or ns:BuffSpellNames(buff)
	if #names == #(buff.spells or {}) + #(buff.also or {}) then buff.names = names end
	for _, name in ipairs(names) do
		local aura = C_UnitAuras.GetAuraDataBySpellName("player", name, "HELPFUL")
		if issecretvalue and issecretvalue(aura) then break end
		if aura then
			if not (issecretvalue and issecretvalue(aura.auraInstanceID)) then
				seen[buff] = {name = name, instanceID = aura.auraInstanceID}
			end
			if not (issecretvalue and issecretvalue(aura.duration)) and (aura.duration or 0) > 0 then
				buff.seenDuration = aura.duration
			end
			return name
		end
	end
	if not ns.inCombat then
		seen[buff] = nil
		return false
	end

	local last = seen[buff]
	if not last then return false end
	if last.instanceID then
		if C_UnitAuras.GetAuraDataByAuraInstanceID("player", last.instanceID) then
			return last.name
		end
		seen[buff] = nil
		return false
	end
	if not last.expires or GetTime() < last.expires then
		return last.name
	end
	seen[buff] = nil
	return false
end

-- A buff just cast counts as on, for its last known duration.
local function Cast(buff, name)
	local duration = buff.seenDuration or buff.duration
	seen[buff] = {name = name, expires = duration and GetTime() + duration}
	if duration then
		C_Timer.After(duration + 0.1, function() ns:QueueCheck() end)
	end
	ns:QueueCheck()
end

local function IsWeapon(slot)
	local itemID = GetInventoryItemID("player", slot)
	if not itemID then return false end
	local classID = select(6, C_Item.GetItemInfoInstant(itemID))
	return classID == Enum.ItemClass.Weapon
end

local function HasEnchant(weaponSlot)
	for _, enchant in ipairs(C_Item.GetWeaponEnchantInfo(weaponSlot)) do
		if enchant.hasEnchant then return true end
	end
	return false
end

-- The active minimap tracking's name if it's one that counts, else false.
local function FindTracking(buff)
	local names = buff.names or ns:BuffSpellNames(buff)
	for i = 1, C_Minimap.GetNumTrackingTypes() do
		local info = C_Minimap.GetTrackingInfo(i)
		if info and info.active and tContains(names, info.name) then
			return info.name
		end
	end
	return false
end

-- True when every weapon that should be enchanted is; no weapon counts as
-- nothing missing. Otherwise false and the slot to apply an item to.
local function HasWeaponBuff(buff)
	if not IsWeapon(INVSLOT_MAINHAND) then return true end
	if not HasEnchant(Enum.WeaponSlot.MainHand) then return false, INVSLOT_MAINHAND end
	if buff.bothHands and IsWeapon(INVSLOT_OFFHAND) and not HasEnchant(Enum.WeaponSlot.OffHand) then
		return false, INVSLOT_OFFHAND
	end
	return true
end

-- Whether the buff is up: an aura's name, true for weapon enchants, the
-- tracking's name; false if not, nil when the game won't say.
function ns:FindBuff(buff)
	if buff.weapon then
		local found, slot = HasWeaponBuff(buff)
		-- What the row applies (Bar.lua): this item, to this weapon.
		buff.useItem, buff.useSlot = UseItem(buff), slot or INVSLOT_MAINHAND
		return found and true
	elseif buff.tracking then
		return FindTracking(buff) or FindAura(buff)
	end
	return FindAura(buff)
end

local function Expired(name)
	if ns.db.message then
		RaidWarningUtil.AddMessage(L.EXPIRED:format(name), ChatTypeInfo.RAID_WARNING)
	end
	if ns.db.sound then
		PlaySound(SOUNDKIT.RAID_WARNING)
	end
end

-- Buffs fall off on death and can't be cast on a flight path; neither is
-- worth a warning.
local function IsSuppressed()
	return UnitIsDeadOrGhost("player") or UnitOnTaxi("player")
end

-- Whether a buff's setting asks for a warning right now.
local function IsWanted(mode)
	return mode == ns.MODE.ALWAYS
		or (mode == ns.MODE.IN_COMBAT and ns.inCombat)
		or (mode == ns.MODE.OUT_OF_COMBAT and not ns.inCombat)
end

local function Check()
	local missing, missingCast = ns.missing, ns.missingCast
	wipe(missing)
	wipe(missingCast)
	local suppressed = IsSuppressed()
	local modes = ns.db.modes

	for _, buff in ipairs(ns:PlayerBuffs()) do
		local mode = modes[buff.owner][buff.key] or ns.MODE.OFF
		local castID = CastSpell(buff)
		if ns.preview then
			table.insert(missing, buff)
			missingCast[#missing] = castID or (buff.spells and buff.spells[1]) or false
		elseif mode ~= ns.MODE.OFF and IsKnown(buff, castID) then
			-- Followed in every state, so a buff that dropped out of combat
			-- shows once combat starts; warned about only when wanted.
			local wanted = IsWanted(mode) and not suppressed
			local found = ns:FindBuff(buff)
			if found ~= nil then
				local before = present[buff.key]
				if not found and before and wanted then
					Expired(before == true and ns:BuffName(buff) or before)
				end
				present[buff.key] = found or nil
			end
			-- Unknown (secret) counts as missing only if it was missing before.
			if not present[buff.key] and wanted then
				table.insert(missing, buff)
				missingCast[#missing] = castID or false
			end
		else
			present[buff.key] = nil
		end
	end
	if suppressed then wipe(present) end
	ns:UpdateBar()
end

-- The buffs the row can show during combat: known, and set to warn in
-- combat. Fills the two lists (buff, spell to cast) like ns.missing.
function ns:FillCombatBuffs(buffs, casts)
	wipe(buffs)
	wipe(casts)
	for _, buff in ipairs(ns:PlayerBuffs()) do
		local mode = ns.db.modes[buff.owner][buff.key]
		local castID = CastSpell(buff)
		if (mode == ns.MODE.IN_COMBAT or mode == ns.MODE.ALWAYS) and IsKnown(buff, castID) then
			table.insert(buffs, buff)
			casts[#buffs] = castID or false
		end
	end
end

-- UNIT_AURA comes in bursts; check once per frame.
local pending = false
local function RunCheck()
	pending = false
	if ns.db then Check() end
end

function ns:QueueCheck()
	if not pending then
		pending = true
		C_Timer.After(0, RunCheck)
	end
end

local function Queue() ns:QueueCheck() end

ns:On("UNIT_AURA", Queue, "player")
ns:On("UNIT_INVENTORY_CHANGED", Queue, "player")
for _, event in ipairs({"PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "WEAPON_ENCHANT_CHANGED", "PLAYER_LEVEL_UP",
	"MINIMAP_UPDATE_TRACKING", "BAG_UPDATE_DELAYED",
	"PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_CONTROL_GAINED", "PLAYER_CONTROL_LOST"}) do
	ns:On(event, Queue)
end

-- Kept here rather than read from InCombatLockdown: the row changes over
-- on these events, when lockdown isn't set yet (or anymore).
ns.inCombat = InCombatLockdown()
ns:On("PLAYER_REGEN_DISABLED", function()
	ns.inCombat = true
	Queue()
end)
ns:On("PLAYER_REGEN_ENABLED", function()
	ns.inCombat = false
	Queue()
end)

-- Remember which spell of a group was cast last (Ice Armor or Mage Armor,
-- which Aspect), so the row casts that one, and count it as on (in combat
-- the aura itself can't be seen). Higher ranks have their own IDs; they
-- share the name with rank 1.
ns:On("UNIT_SPELLCAST_SUCCEEDED", function(_, _, spellID)
	if not ns.db then return end
	if issecretvalue and issecretvalue(spellID) then
		ns.lastCastSecret = true
		return
	end
	ns.lastCastSecret = false
	local name = C_Spell.GetSpellName(spellID)
	if not name then return end
	for _, buff in ipairs(ns:PlayerBuffs()) do
		for _, rankOne in ipairs(buff.spells or {}) do
			if C_Spell.GetSpellName(rankOne) == name then
				ns.db.last[buff.owner][buff.key] = rankOne
				if not buff.weapon and not buff.tracking then
					Cast(buff, name)
				end
				return
			end
		end
	end
end, "player")

-- The same for items applied from the bags: which stone, oil or poison.
hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
	local itemID = ns.db and C_Container.GetContainerItemID(bag, slot)
	if not itemID then return end
	for _, buff in ipairs(ns:PlayerBuffs()) do
		if buff.items and tContains(buff.items, itemID) then
			ns.db.last[buff.owner][buff.key] = itemID
			return
		end
	end
end)

-- Weapon enchants run out without an event on some clients; look again
-- every few seconds for classes that watch one.
ns:On("PLAYER_LOGIN", function()
	for _, buff in ipairs(ns:PlayerBuffs()) do
		if buff.weapon then
			C_Timer.NewTicker(5, Queue)
			return
		end
	end
end)

function ns:TogglePreview()
	ns.preview = not ns.preview
	ns:Print(ns.preview and L.PREVIEW_ON:format(ns.SLASH .. " preview") or L.PREVIEW_OFF)
	ns:QueueCheck()
end

function ns:Debug()
	ns:Print("debug")
	print(("  class %s, level %d, suppressed %s, combat %s, preview %s"):format(playerClass, UnitLevel("player"),
		tostring(IsSuppressed() and true or false), tostring(InCombatLockdown()), tostring(ns.preview or false)))
	print("  last cast hidden by the game:", tostring(ns.lastCastSecret))
	for _, buff in ipairs(ns:PlayerBuffs()) do
		local castID = CastSpell(buff)
		local found = ns:FindBuff(buff)
		local last = seen[buff]
		print(("  %s: mode %s, known %s, cast %s, on you %s, seen %s"):format(ns:BuffName(buff),
			tostring(ns.db.modes[buff.owner][buff.key]), tostring(IsKnown(buff, castID)),
			castID and (C_Spell.GetSpellName(castID) or castID) or "-", tostring(found),
			last and (last.instanceID and "aura " .. last.instanceID or "cast, "
				.. (last.expires and ("%.0fs left"):format(last.expires - GetTime()) or "until combat ends")) or "-"))
	end
end
