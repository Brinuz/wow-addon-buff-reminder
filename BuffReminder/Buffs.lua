-- Buffs: the buffs each class keeps on itself, by spell ID (rank 1; every
-- rank shares the name, which is what auras are matched by).
--   spells   castable, in order of preference; known when any is known
--   also     other spells that count as the buff (group versions, which
--            low levels can't cast)
--   label    an ns.L key, for groups named after no single spell
--   mode     when it's watched until changed in the settings (an ns.MODE;
--            default ALWAYS)
--   weapon   checks a temporary weapon enchant instead of an aura, on the
--            main hand, or on both hands when `bothHands` (an off-hand
--            weapon only)
--   tracking checks the minimap tracking instead of an aura
--   items    weapon items applied from the bags, best first; the row uses
--            the one last used. Without spells or minLevel, known while
--            one is in the bags
--   tooltip  an ns.L key, the settings tooltip for buffs with no spells
--   minLevel known from this level (for buffs with no spell to know)
--   duration seconds, for a buff cast in combat before its aura was ever
--            seen (in combat the game hides it); the seen one wins
local _, ns = ...

ns.BUFFS = {
	WARRIOR = {
		{key = "BATTLE_SHOUT", spells = {6673}, mode = ns.MODE.IN_COMBAT, duration = 120},
	},
	PALADIN = {
		-- Might, Wisdom, Kings, Salvation, Light, Sanctuary.
		{key = "BLESSING", label = "BLESSING", spells = {19740, 19742, 20217, 1038, 19977, 20911},
			also = {25782, 25894, 25898, 25895, 25890, 25899}},
		-- Devotion, Retribution, Concentration, Sanctity, then the resistances.
		{key = "AURA", label = "AURA", spells = {465, 7294, 19746, 20218, 19876, 19888, 19891}},
		{key = "RIGHTEOUS_FURY", spells = {25780}, mode = ns.MODE.OFF},
	},
	PRIEST = {
		{key = "FORTITUDE", spells = {1243}, also = {21562}},
		{key = "INNER_FIRE", spells = {588}},
		{key = "DIVINE_SPIRIT", spells = {14752}, also = {27681}},
		{key = "SHADOW_PROTECTION", spells = {976}, also = {27683}, mode = ns.MODE.OFF},
		{key = "SHADOWFORM", spells = {15473}, mode = ns.MODE.OFF},
	},
	SHAMAN = {
		{key = "LIGHTNING_SHIELD", spells = {324}},
		-- Rockbiter, Flametongue, Frostbrand, Windfury.
		{key = "WEAPON_IMBUE", label = "WEAPON_IMBUE", spells = {8017, 8024, 8033, 8232}, weapon = true},
	},
	DRUID = {
		{key = "MARK_OF_THE_WILD", spells = {1126}, also = {21849}},
		{key = "THORNS", spells = {467}},
		{key = "OMEN_OF_CLARITY", spells = {16864}},
	},
	ROGUE = {
		{key = "POISONS", label = "POISONS", tooltip = "POISONS_TOOLTIP", weapon = true, bothHands = true,
			minLevel = 20, items = {
				8928, 8927, 8926, 6950, 6949, 6947,        -- Instant Poison VI to I
				20844, 8985, 8984, 2893, 2892,             -- Deadly Poison V to I
				10922, 10921, 10920, 10918,                -- Wound Poison IV to I
				9186, 6951, 5237,                          -- Mind-numbing Poison III to I
				3776, 3775,                                -- Crippling Poison II, I
			}},
	},
	MAGE = {
		{key = "ARCANE_INTELLECT", spells = {1459}, also = {23028}},
		-- Ice, Frost, Mage.
		{key = "ARMOR", label = "ARMOR", spells = {7302, 168, 6117}},
		{key = "DAMPEN_AMPLIFY", spells = {604, 1008}, mode = ns.MODE.OFF},
	},
	WARLOCK = {
		-- Demon Armor replaces Demon Skin.
		{key = "DEMON_ARMOR", spells = {706, 687}},
		{key = "SOUL_LINK", spells = {19028}},
	},
	-- Gathering professions, for every class. One group: only one kind of
	-- tracking is on at a time.
	PROFESSIONS = {
		-- Find Herbs, Find Minerals.
		{key = "FIND", spells = {2383, 2580}, tracking = true, mode = ns.MODE.OUT_OF_COMBAT},
	},
	-- Weapon stones and oils, for every class.
	ITEMS = {
		{key = "WEAPON_STONE", label = "WEAPON_STONE", tooltip = "WEAPON_STONE_TOOLTIP", weapon = true,
			bothHands = true, mode = ns.MODE.OUT_OF_COMBAT, items = {
				23122, 18262, 12404, 7964, 2871, 2863, 2862, -- sharpening stones: Consecrated, Elemental, Dense to Rough
				12643, 7965, 3241, 3240, 3239,              -- weightstones: Dense to Rough
				23123, 20749, 20750, 20746, 20744,          -- wizard oils: Blessed, Brilliant to Minor
				20748, 20747, 20745,                        -- mana oils: Brilliant to Minor
			}},
	},
	HUNTER = {
		-- Hawk, Monkey, Cheetah, Pack, Wild, Beast.
		{key = "ASPECT", label = "ASPECT", spells = {13165, 13163, 5118, 13159, 20043, 13161}},
		{key = "TRUESHOT_AURA", spells = {19506}},
	},
}

-- Each buff knows which list it's in (its settings and last cast are kept
-- under that key).
for owner, buffs in pairs(ns.BUFFS) do
	for _, buff in ipairs(buffs) do
		buff.owner = owner
	end
end

-- The buffs the player's character can have: its class's, then the
-- professions'.
function ns:PlayerBuffs()
	if not ns.playerBuffs then
		local list = {}
		local class = select(2, UnitClass("player"))
		for _, owner in ipairs({class, "PROFESSIONS", "ITEMS"}) do
			for _, buff in ipairs(ns.BUFFS[owner] or {}) do
				table.insert(list, buff)
			end
		end
		ns.playerBuffs = list
	end
	return ns.playerBuffs
end

-- "Arcane Intellect", or "Armor" for a group, or "Dampen Magic / Amplify
-- Magic" for a pair with no group name.
function ns:BuffName(buff)
	if buff.label then return ns.L[buff.label] end
	local names = {}
	for _, spellID in ipairs(buff.spells) do
		table.insert(names, C_Spell.GetSpellName(spellID) or tostring(spellID))
	end
	return table.concat(names, " / ")
end

-- Every spell that counts as the buff, by name.
function ns:BuffSpellNames(buff)
	local names = {}
	for _, list in ipairs({buff.spells or {}, buff.also or {}}) do
		for _, spellID in ipairs(list) do
			local name = C_Spell.GetSpellName(spellID)
			if name and not tContains(names, name) then
				table.insert(names, name)
			end
		end
	end
	return names
end
