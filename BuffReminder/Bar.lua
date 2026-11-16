-- Bar: the row of missing buffs. Each button casts its buff. The buttons are
-- secure: in combat they can't be added, moved or hidden, only faded.
local addonName, ns = ...

local L = ns.L

local BUTTON_SIZE, BUTTON_SPACING = 45, 6
local TITLE_HEIGHT = 18
local DEFAULT_POINT = {"CENTER", 0, 160}

-- ---------------------------------------------------------------- buttons
BuffReminderButtonMixin = {}

function BuffReminderButtonMixin:OnLoad()
	-- Secure buttons act on the press or the release, following the "cast on
	-- key down" option (ActionButtonUseKeyDown); listen for both.
	self:RegisterForClicks("AnyDown", "AnyUp")
	self:RegisterForDrag("LeftButton")
end

-- What a button does: cast a spell, or apply an item from the bags to a
-- weapon (stones, oils, poisons: use it, then pick the weapon's slot).
local APPLY_MACRO = "/use item:%d\n/use %d"

-- The plain left click acts; "type1" is only read with no modifier held,
-- so shift-dragging the row never casts.
function BuffReminderButtonMixin:Init(buff, castID)
	self.buff, self.castID = buff, castID
	self.itemID = not castID and buff.useItem or nil
	if castID then
		self.Icon:SetTexture(C_Spell.GetSpellTexture(castID))
		self:SetAttribute("type1", "spell")
		self:SetAttribute("spell", C_Spell.GetSpellName(castID))
		self:SetAttribute("macrotext", nil)
	elseif self.itemID then
		self.Icon:SetTexture(C_Item.GetItemIconByID(self.itemID))
		self:SetAttribute("type1", "macro")
		self:SetAttribute("macrotext", APPLY_MACRO:format(self.itemID, buff.useSlot))
		self:SetAttribute("spell", nil)
	else
		-- Nothing to apply in the bags: show the weapon that needs it.
		self.Icon:SetTexture(GetInventoryItemTexture("player", buff.useSlot or INVSLOT_MAINHAND) or 134400)
		self:SetAttribute("type1", nil)
		self:SetAttribute("spell", nil)
		self:SetAttribute("macrotext", nil)
	end
end

function BuffReminderButtonMixin:OnEnter()
	-- A faded combat button: its buff is on.
	if self:GetAlpha() == 0 then return end
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	if self.castID then
		GameTooltip:SetSpellByID(self.castID)
		GameTooltip_AddInstructionLine(GameTooltip, L.CLICK_TO_CAST)
	elseif self.itemID then
		GameTooltip:SetItemByID(self.itemID)
		local weapon = GetInventoryItemID("player", self.buff.useSlot)
		GameTooltip_AddInstructionLine(GameTooltip, L.CLICK_TO_APPLY:format(weapon and C_Item.GetItemNameByID(weapon) or ""))
	else
		GameTooltip_SetTitle(GameTooltip, ns:BuffName(self.buff))
		GameTooltip_AddNormalLine(GameTooltip, L.CLICK_NONE)
	end
	GameTooltip_AddDisabledLine(GameTooltip, L.SHIFT_DRAG)
	GameTooltip:Show()
end

function BuffReminderButtonMixin:OnDragStart()
	if IsShiftKeyDown() and not InCombatLockdown() then
		BuffReminderBar:StartMoving()
	end
end

function BuffReminderButtonMixin:OnDragStop()
	BuffReminderBar:StopMovingOrSizing()
	BuffReminderBar:SavePosition()
end

-- ---------------------------------------------------------------- row
BuffReminderBarMixin = {}

function BuffReminderBarMixin:OnLoad()
	self.Title:SetText(L.MISSING)
	self.buttons = {}
end

-- Saved by its center, so the row stays centered as buttons come and go.
function BuffReminderBarMixin:SavePosition()
	local x, y = self:GetCenter()
	if x then
		ns.db.position = {x = x, y = y}
		self:ApplyPosition()
	end
end

function BuffReminderBarMixin:ApplyPosition()
	self:ClearAllPoints()
	local position = ns.db.position
	if position then
		self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", position.x, position.y)
	else
		self:SetPoint(DEFAULT_POINT[1], UIParent, DEFAULT_POINT[1], DEFAULT_POINT[2], DEFAULT_POINT[3])
	end
end

-- One button per buff in the list, in order.
function BuffReminderBarMixin:Layout(buffs, casts)
	for i, buff in ipairs(buffs) do
		local button = self.buttons[i]
		if not button then
			button = CreateFrame("Button", nil, self, "BuffReminderButtonTemplate")
			button:SetPoint("TOPLEFT", (i - 1) * (BUTTON_SIZE + BUTTON_SPACING), -TITLE_HEIGHT)
			self.buttons[i] = button
		end
		button:Init(buff, casts[i] or nil)
		button:SetAlpha(1)
		button:Show()
	end
	for i = #buffs + 1, #self.buttons do
		self.buttons[i]:Hide()
	end
	self.Title:SetAlpha(1)
	local count = math.max(#buffs, 1)
	self:SetSize(count * BUTTON_SIZE + (count - 1) * BUTTON_SPACING, TITLE_HEIGHT + BUTTON_SIZE)
end

-- In combat: the buttons stay where they are; the ones whose buff is on
-- turn invisible (alpha is the one thing the game lets change).
local missingSet = {}
function BuffReminderBarMixin:Fade()
	wipe(missingSet)
	for _, buff in ipairs(ns.missing) do
		missingSet[buff] = true
	end
	local any = false
	for _, button in ipairs(self.buttons) do
		local missing = button:IsShown() and missingSet[button.buff] or false
		button:SetAlpha(missing and 1 or 0)
		any = any or missing
	end
	self.Title:SetAlpha(any and 1 or 0)
end

-- Called after every check (Watch.lua). Out of combat: the missing buffs.
function ns:UpdateBar()
	local bar = BuffReminderBar
	if ns.inCombat then
		if bar:IsShown() then bar:Fade() end
	elseif not InCombatLockdown() then
		if (ns.db.bar or ns.preview) and #ns.missing > 0 then
			bar:Layout(ns.missing, ns.missingCast)
			bar:Show()
		else
			bar:Hide()
		end
	end
end

function ns:ResetBarPosition()
	if InCombatLockdown() then return end
	ns.db.position = nil
	BuffReminderBar:ApplyPosition()
end

ns:On("ADDON_LOADED", function(name)
	if name == addonName then
		BuffReminderBar:ApplyPosition()
	end
end)

-- The last moment the secure buttons can change: lay out one per buff that
-- warns in combat, all faded until the check this event queues (Watch.lua)
-- shows the missing ones.
local combatBuffs, combatCasts = {}, {}
ns:On("PLAYER_REGEN_DISABLED", function()
	local bar = BuffReminderBar
	ns:FillCombatBuffs(combatBuffs, combatCasts)
	if ns.db.bar and #combatBuffs > 0 then
		bar:Layout(combatBuffs, combatCasts)
		bar:Show()
		bar:Fade()
	else
		bar:Hide()
	end
end)
