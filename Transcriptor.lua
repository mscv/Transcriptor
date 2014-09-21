-----------------------------------------------------------------------------------------------
-- Transcriptor an encounter logging tool for bossmod developers
-- Inspired by the WoW addon with the same name
-- by Caleb calebzor@gmail.com
-----------------------------------------------------------------------------------------------

local gameVersion, buildVersion = "Live", "1.0.0.6879"

require "Window"
require "GameLib"
require "ChatSystemLib"

-----------------------------------------------------------------------------------------------
-- Upvalues
-----------------------------------------------------------------------------------------------

local Apollo = Apollo
local setmetatable = setmetatable
local ipairs = ipairs

local GetDate = os.date
local GetTime = GameLib.GetGameTime
local tostring = tostring
local Print = Print
local GameLib = GameLib

-----------------------------------------------------------------------------------------------
-- Module Definition and variables
-----------------------------------------------------------------------------------------------
local Transcriptor = {}
local addon = Transcriptor
local tSessionDB
local chatFilter = {
	[ChatSystemLib.ChatChannel_NPCSay] 		= true, --20
	[ChatSystemLib.ChatChannel_NPCYell] 	= true, --21
	[ChatSystemLib.ChatChannel_NPCWhisper] 	= true, --22
	[ChatSystemLib.ChatChannel_Datachron] 	= true, --23
	--[ChatSystemLib.ChatChannel_Say] 		= true, -- 4
	[ChatSystemLib.ChatChannel_System] 		= true, -- 2 
	[ChatSystemLib.ChatChannel_Zone] 		= true, -- 9
	[ChatSystemLib.ChatChannel_Instance] 	= true, --32
	[ChatSystemLib.ChatChannel_Realm] 		= true, --25
}
local tooltipText = "\
<T Font='CRB_InterfaceMedium_B' TextColor='ffffffff'>\
<T TextColor='ffffff00'>Left click</T> to toggle logging on or off\n\
<T TextColor='ffffff00'>Alt + Left click</T> to reset all sessions data\n\
</T>\
"

-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------
function addon:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	return o
end

local tMissmatchingArgs = {}

function addon:Init()
	Apollo.RegisterAddon(self)
end
-----------------------------------------------------------------------------------------------
-- OnLoad and Enabling stuff
-----------------------------------------------------------------------------------------------
function addon:OnLoad()
	-- load our forms
	self.wndMain = Apollo.LoadForm("Transcriptor.xml", "TranscriptorForm", nil, self)
	self.wndMain:Show(true)
	self.wndAnchor = Apollo.LoadForm("Transcriptor.xml", "Anchor", nil, self)
	self.wndAnchor:Show(false)
	self.wndMain:FindChild("Button"):SetTooltip(tooltipText)
	self.bLogging = false
	self.tPrevDB = {}
	self.tDB = {}
	tSessionDB = self.tDB
	self.tUnits = {}
end

function addon:EnableLogging()
	local zone = "Unknown Zone"
	if GameLib.GetCurrentZoneMap() then
		zone = GameLib.GetCurrentZoneMap().strName
	end
	self.sSession = ("%s - %s/%s/%s/%s/%s/%s/%s"):format(GetDate(), "map", zone, "subzone", GameLib.GetWorldDifficulty(), "revision", gameVersion, buildVersion) -- XXX fill these out
	self.tDB[self.sSession] = {}
	self.bLogging = true
	self.wndMain:GetChildren()[1]:SetText("Transcriptor: On")

	-- register events
	Apollo.RegisterEventHandler("CombatLogDamage", 					"OnCombatLogDamage", self)
	Apollo.RegisterEventHandler("CombatLogCCState", 				"OnCombatLogCCState", self)
	Apollo.RegisterEventHandler("CombatLogCCStateBreak", 			"OnCombatLogCCStateBreak", self)
	Apollo.RegisterEventHandler("CombatLogFallingDamage", 			"OnCombatLogFallingDamage", self)
	Apollo.RegisterEventHandler("CombatLogHeal", 					"OnCombatLogHeal", self)
	Apollo.RegisterEventHandler("CombatLogDispel", 					"OnCombatLogDispel", self)
	Apollo.RegisterEventHandler("CombatLogTransference", 			"OnCombatLogTransference", self)
	Apollo.RegisterEventHandler("CombatLogVitalModifier", 			"OnCombatLogVitalModifier", self)
	Apollo.RegisterEventHandler("CombatLogDeflect", 				"OnCombatLogDeflect", self)
	Apollo.RegisterEventHandler("CombatLogImmunity", 				"OnCombatLogImmunity", self)
	Apollo.RegisterEventHandler("CombatLogInterrupted", 			"OnCombatLogInterrupted", self)
	Apollo.RegisterEventHandler("CombatLogDeath", 					"OnCombatLogDeath", self)
	Apollo.RegisterEventHandler("CombatLogResurrect", 				"OnCombatLogResurrect", self)
	Apollo.RegisterEventHandler("CombatLogPet", 					"OnCombatLogPet", self)
	Apollo.RegisterEventHandler("UnitEnteredCombat", 				"OnEnteredCombat", self)
	Apollo.RegisterEventHandler("ChatMessage", 						"OnChatMessage", self)
	Apollo.RegisterEventHandler("CombatLogModifyInterruptArmor", 	"OnCombatLogModifyInterruptArmor", self)
	Apollo.RegisterEventHandler("CombatLogDelayDeath", 				"OnCombatLogDelayDeath", self)
	Apollo.RegisterEventHandler("CombatLogStealth", 				"OnCombatLogStealth", self)
	Apollo.RegisterEventHandler("NextFrame", 						"OnUpdate", self)
end

function addon:DisableLogging()
	self.sSession = nil
	self.bLogging = false
	self.wndMain:GetChildren()[1]:SetText("Transcriptor: Off")

	-- unregister events
	Apollo.RemoveEventHandler("CombatLogDamage",				self)
	Apollo.RemoveEventHandler("CombatLogCCState",				self)
	Apollo.RemoveEventHandler("CombatLogCCStateBreak",			self)
	Apollo.RemoveEventHandler("CombatLogFallingDamage",			self)
	Apollo.RemoveEventHandler("CombatLogHeal",					self)
	Apollo.RemoveEventHandler("CombatLogDispel",				self)
	Apollo.RemoveEventHandler("CombatLogTransference",			self)
	Apollo.RemoveEventHandler("CombatLogVitalModifier",			self)
	Apollo.RemoveEventHandler("CombatLogDeflect",				self)
	Apollo.RemoveEventHandler("CombatLogImmunity",				self)
	Apollo.RemoveEventHandler("CombatLogInterrupted",			self)
	Apollo.RemoveEventHandler("CombatLogDeath",					self)
	Apollo.RemoveEventHandler("CombatLogResurrect",				self)
	Apollo.RemoveEventHandler("CombatLogPet",					self)
	Apollo.RemoveEventHandler("UnitEnteredCombat",				self)
	Apollo.RemoveEventHandler("ChatMessage",					self)
	Apollo.RemoveEventHandler("CombatLogModifyInterruptArmor",	self)
	Apollo.RemoveEventHandler("CombatLogDelayDeath",			self)
	Apollo.RemoveEventHandler("CombatLogStealth",				self)
	Apollo.RemoveEventHandler("NextFrame",						self)
end

-----------------------------------------------------------------------------------------------
-- GUI and SavedVariables
-----------------------------------------------------------------------------------------------

-- when the Cancel button is clicked
function addon:OnButton()
	if Apollo.IsAltKeyDown() then
		if self.bLogging then
			Print("Transcriptor: you can only clear data if you are not logging!")
		else
			self.tPrevDB = {}
			for k, v in next, tSessionDB do
				tSessionDB[k] = nil
			end
			Print("Transcriptor: cleared all sessions data.")
		end
	else
		if self.bLogging then
			self:DisableLogging()
		else
			self:EnableLogging()
		end
	end
end

function addon:AnchorWindowMove()
	local l,t,r,b = self.wndAnchor:GetAnchorOffsets()
	self.wndMain:SetAnchorOffsets(l,t,r+30,b) -- +30 because of the lock button
end

function addon:OnLockClick()
	if self.wndAnchor:IsShown() then
		self.wndMain:FindChild("Button"):Show(true)
		self.wndAnchor:Show(false)
	else
		self.wndMain:FindChild("Button"):Show(false)
		-- always set the anchor to be at the TranscriptorFrame before displaying it
		local l,t,r,b = self.wndMain:GetAnchorOffsets()
		self.wndAnchor:SetAnchorOffsets(l,t,r-30,b) -- -30 because of the lock button
		self.wndAnchor:Show(true)
	end
end

function addon:OnSave(eLevel)
	if eLevel ~= GameLib.CodeEnumAddonSaveLevel.Character then return end

	for k, v in next, tSessionDB do
		self.tPrevDB[k] = v
	end
	local l,t,r,b = self.wndMain:GetAnchorOffsets()
	self.tPrevDB.tPos = { l = l, t = t, r = r, b = b}
	self.tPrevDB.bLogOnLogin = self.bLogging

	self.tPrevDB.tMissmatchingArgs = tMissmatchingArgs
	return self.tPrevDB
end

function addon:OnRestore(eLevel, tData)
	if eLevel ~= GameLib.CodeEnumAddonSaveLevel.Character then return end
	-- just store this and use it later
	self.tPrevDB = tData
	if tData.tPos then
		self.wndMain:SetAnchorOffsets(tData.tPos.l, tData.tPos.t, tData.tPos.r, tData.tPos.b)
	end
	if tData.bLogOnLogin then
		self:EnableLogging()
	end
end

-----------------------------------------------------------------------------------------------
-- Utility
-----------------------------------------------------------------------------------------------

local function getLineFromIndexedTable(t, sEvent)
	local s = GetTime() .. '#' .. sEvent

	if not t[1] then -- not an indexed table that we generated
		s = s .. '#nil#nil#nil#nil#nil#nil#nil#nil#MISSING_ARGUEMENTS'
		for k, v in next, t do
			s = ("%s#%s:%s"):format(s, tostring(k), tostring(v) or "")
		end
	else
		for _, v in ipairs(t) do -- cannot use table.concat, because non strings :/
			s = ("%s#%s"):format(s, tostring(v) or 'nil')
		end
	end
	return s
end

function addon:putLine(str)
	self.tDB[self.sSession][#self.tDB[self.sSession]+1] = str
end

local function checkForMissingBuffById(unit, id)
	local unitBuffs = unit:GetBuffs()
	for strBuffType, buffTypeValue  in next, unitBuffs do
		for _, s in next, buffTypeValue do
			if id == s.idBuff then
				return false
			end
		end
	end
	return true
end

local function trackMissmatchingArg(sEvent, sArg, sFrom)
	if not tMissmatchingArgs[sEvent] then
		tMissmatchingArgs[sEvent] = {}
	end
	tMissmatchingArgs[sEvent][sArg] = sFrom
end

local function checkForMissingKeysIn_tEventSpecificValues(tEventArgs, tEventSpecificValues, sEvent)
	local bKeysMissing = false
	for k, _ in next, tEventArgs do
		local bKeyNotMissing
		for _, sEventArgKey in next, tEventSpecificValues do
			if k == sEventArgKey then
				bKeyNotMissing = true
				break
			end
		end
		if k == "unitCaster" or k == "unitTarget" or k == "unitCasterOwner" or k == "unitTargetOwner" then bKeyNotMissing = true end
		if not bKeyNotMissing then
			trackMissmatchingArg(sEvent, k, "tEventSpecificValues") -- aka missing from our indexed list
			bKeysMissing = true
		end
	end
	return bKeysMissing
end

local function checkForRenamedOrRemovedKeysIn_tEventSpecificValues(tEventArgs, tEventSpecificValues, sEvent)
	local bKeysMissing = false
	for _, k in next, tEventSpecificValues do
		local bKeyNotMissing
		for sEventArgKey, _ in next, tEventArgs do
			if sEventArgKey == k then
				bKeyNotMissing = true
				break
			end
		end
		if k == "strTriggerCapCategory" or "bHideFloater" then bKeyNotMissing = true end
		if not bKeyNotMissing then
			trackMissmatchingArg(sEvent, k, "tEventArgs") -- aka it is an extra in our indexed list
			bKeysMissing = true
		end
	end
	return bKeysMissing
end

local function verifyNoEventsArgMissmatch(tEventArgs, tEventSpecificValues, sEvent)
	local somethingMissing

	somethingMissing = checkForMissingKeysIn_tEventSpecificValues(tEventArgs, tEventSpecificValues, sEvent)
	if somethingMissing then
		return tEventArgs
	end

	somethingMissing = checkForRenamedOrRemovedKeysIn_tEventSpecificValues(tEventArgs, tEventSpecificValues, sEvent)
	if somethingMissing then
		return tEventArgs
	end

	return false
end

function addon:HelperParseEvent(tEventArgs, tEventSpecificValues, sEvent)
	local tInfo = {}

	if verifyNoEventsArgMissmatch(tEventArgs, tEventSpecificValues, sEvent) then
		tInfo = verifyNoEventsArgMissmatch(tEventArgs, tEventSpecificValues, sEvent)
	else
		if tEventArgs.unitCaster and not tEventArgs.unitCasterOwner then
			tEventArgs.unitCasterOwner = tEventArgs.unitCaster:GetUnitOwner()
		end
		if tEventArgs.unitTarget and not tEventArgs.unitTargetOwner then
			tEventArgs.unitTargetOwner = tEventArgs.unitTarget:GetUnitOwner()
		end

		tInfo[#tInfo+1] = self:HelperGetName(tEventArgs.unitCaster)
		tInfo[#tInfo+1] = self:HelperGetId(tEventArgs.unitCaster)
		tInfo[#tInfo+1] = self:HelperGetName(tEventArgs.unitCasterOwner)
		tInfo[#tInfo+1] = self:HelperGetId(tEventArgs.unitCasterOwner)

		tInfo[#tInfo+1] = self:HelperGetName(tEventArgs.unitTarget)
		tInfo[#tInfo+1] = self:HelperGetId(tEventArgs.unitTarget)
		tInfo[#tInfo+1] = self:HelperGetName(tEventArgs.unitTargetOwner)
		tInfo[#tInfo+1] = self:HelperGetId(tEventArgs.unitTargetOwner)
		
		for k, v in ipairs(tEventSpecificValues) do
			if v == "splInterruptingSpell" or v == "splRemovedSpell" or v == "splCallingSpell" then
				tInfo[#tInfo+1] = self:HelperGetName(tEventArgs[v])
				tInfo[#tInfo+1] = self:HelperGetId(tEventArgs[v])
			elseif v == "tHealData" then
				tInfo[#tInfo+1] = tEventArgs[v].nHealAmount
				tInfo[#tInfo+1] = tEventArgs[v].nOverHeal
				tInfo[#tInfo+1] = tEventArgs[v].eVitalType
			else
				tInfo[#tInfo+1] = tEventArgs[v]
			end
		end
	end
	return tInfo
end

function addon:HelperGetName(nArg)
	return nArg and nArg:GetName() or 'nil' -- on purpose
end

function addon:HelperGetId(nArg)
	return nArg and nArg:GetId() or 'nil' -- on purpose
end


-----------------------------------------------------------------------------------------------
-- Event handlers
-----------------------------------------------------------------------------------------------

function addon:OnChatMessage(channelCurrent, tMessage)
	if not chatFilter[channelCurrent:GetType()] then return end
	
	local strMessage = ""
	for _, tSegment in ipairs(tMessage.arMessageSegments) do
		strMessage = strMessage .. tSegment.strText
	end
	
	local tTextInfo = {
		tMessage.unitSource and tMessage.unitSource:GetName() or tMessage.strSender,
		tMessage.unitSource and tMessage.unitSource:GetId() or 'nil',
		'nil',
		'nil',
		'nil',
		'nil',
		'nil',
		'nil',
		channelCurrent:GetType(),
		strMessage,
		tMessage.nPresenceState,
	}
	self:putLine(getLineFromIndexedTable(tTextInfo, "OnChatMessage"))
end


local tBuff = {"splCallingSpell", "bHarmful", "nCount", "fTimeRemaining"}
local tSpellData = { "strSpellName", "strSpellId", "fCastDuration", "fCastElapsed" }
function addon:OnUpdate()

	for k, v in next, self.tUnits do
		local unit = v.unit
		if not unit:IsValid() then
			self.tUnits[k] = nil
		else
			-- casting
			if unit:IsCasting() and unit:GetType() == "NonPlayer" then -- XXX only track non player casts
				if not self.tUnits[k].lastSpellName or ( unit:GetCastName() ~= self.tUnits[k].lastSpellName ) then
					self.tUnits[k].lastSpellName = unit:GetCastName()
					
					local tTextInfo = self:HelperParseEvent( { unitCaster = unit, unitCasterOwner = unit:GetUnitOwner(), unitTarget = unit:GetTarget(), unitTargetOwner = unit:GetTarget() and unit:GetTarget():GetUnitOwner() or nil, strSpellName = unit:GetCastName(), strSpellId = 'nil', fCastDuration = unit:GetCastDuration(), fCastElapsed = unit:GetCastElapsed() }, tSpellData, 'SpellCastStart')
					self:putLine(getLineFromIndexedTable(tTextInfo, 'SpellCastStart'))
				end
			end
			-- buffs applied
			local unitBuffs = unit:GetBuffs()
			for strBuffType, buffTypeValue  in next, unitBuffs do
				local bHarmful = (strBuffType == "arHarmful") and true or false
				local unitType = unit:GetType()
				if unitType and ((bHarmful and unitType == "Player") or (not bHarmful and unitType == "NonPlayer")) then -- XXX only track player debuffs and non player buffs
					for _, buffData in next, buffTypeValue do
						
						if self.tUnits[k].buffs[buffData.idBuff] then -- refresh
							if buffData.fTimeRemaining > self.tUnits[k].buffs[buffData.idBuff].fTimeRemaining and buffData.nCount == self.tUnits[k].buffs[buffData.idBuff].nCount then
								local sEvent = 'AuraRenewed'
								local tTextInfo = self:HelperParseEvent( { unitTarget = unit, splCallingSpell = buffData.splEffect, nCount = buffData.nCount, fTimeRemaining = buffData.fTimeRemaining, bHarmful = bHarmful }, tBuff, sEvent)
								self:putLine(getLineFromIndexedTable(tTextInfo, sEvent))
							elseif buffData.nCount ~= self.tUnits[k].buffs[buffData.idBuff].nCount then -- this for when an aura has no duration but has stacks
								local sEvent = 'AuraAppliedDose'
								local tTextInfo = self:HelperParseEvent( { unitTarget = unit, splCallingSpell = buffData.splEffect, nCount = buffData.nCount, fTimeRemaining = buffData.fTimeRemaining, bHarmful = bHarmful }, tBuff, sEvent)
								self:putLine(getLineFromIndexedTable(tTextInfo, sEvent))
							end
							self.tUnits[k].buffs[buffData.idBuff] = {
								["unit"] = unit,
								["nCount"] = buffData.nCount,
								["fTimeRemaining"] = buffData.fTimeRemaining,
								["splEffect"] = buffData.splEffect,
								["bHarmful"] = bHarmful,
							}
						else -- first application
							self.tUnits[k].buffs[buffData.idBuff] = {
								["unit"] = unit,
								["nCount"] = buffData.nCount,
								["fTimeRemaining"] = buffData.fTimeRemaining,
								["splEffect"] = buffData.splEffect,
								["bHarmful"] = bHarmful,
							}
							local sEvent = 'AuraApplied'
							local tTextInfo = self:HelperParseEvent( { unitTarget = unit, splCallingSpell = buffData.splEffect, nCount = buffData.nCount, fTimeRemaining = buffData.fTimeRemaining, bHarmful = bHarmful }, tBuff, sEvent)
							self:putLine(getLineFromIndexedTable(tTextInfo, sEvent))
						end
					end
				end
			end
			-- buffs removed
			for buffId, buffData in next, v.buffs do
				-- remember right now only player debuffs and non player buffs are tracked
				if checkForMissingBuffById(unit, buffId) then
					local sEvent = 'AuraRemoved'
					local tTextInfo = self:HelperParseEvent( { unitTarget = unit, splCallingSpell = buffData.splEffect, nCount = buffData.nCount, fTimeRemaining = buffData.fTimeRemaining, bHarmful = bHarmful }, tBuff, sEvent)
					self:putLine(getLineFromIndexedTable(tTextInfo, sEvent))
					self.tUnits[k].buffs[buffId] = nil
				end
			end
		end
	end
end

local tCombatLogTransference = { "splCallingSpell", "eDamageType", "nDamageAmount", "nShield", "nAbsorption", "nOverkill", "eCombatResult", "bTargetVulnerable", "tHealData" }
function addon:OnCombatLogTransference(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogTransference, "CombatLogTransference")
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogTransference"))
end


local tCombatLogDamage = { "splCallingSpell", "eDamageType", "nDamageAmount", "nShield", "nAbsorption", "nOverkill", "eCombatResult", "bTargetVulnerable", "bTargetKilled", "eEffectType", "bPeriodic", "nRawDamage" }
function addon:OnCombatLogDamage(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogDamage, "CombatLogDamage")
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogDamage"))
end

local tCombatLogCCState = { "splCallingSpell", "strState", "eState", "bRemoved", "nInterruptArmorHit", "eResult", "eCombatResult", "strTriggerCapCategory", "bHideFloater" }
function addon:OnCombatLogCCState(tEventArgs)

	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogCCState, "CombatLogCCState")
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogCCState"))
end

local tCombatLogCCStateBreak = { "strState", "eState" }
function addon:OnCombatLogCCStateBreak(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogCCStateBreak, "CombatLogCCStateBreak")
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogCCStateBreak"))
end

local tCombatLogFallingDamage = { "nDamageAmount" }
function addon:OnCombatLogFallingDamage(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogFallingDamage, "CombatLogFallingDamage")
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogFallingDamage"))
end

local tCombatLogHeal = { "splCallingSpell", "nHealAmount", "nOverheal", "eEffectType", "eCombatResult" }
function addon:OnCombatLogHeal(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogHeal, "CombatLogHeal")
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogHeal"))
end

local tUnitEnteredCombat = { "bInCombat" }
function addon:OnEnteredCombat(unit, bInCombat)
	local tTextInfo = self:HelperParseEvent( { unitCaster = unit, bInCombat = bInCombat }, tUnitEnteredCombat, "UnitEnteredCombat")
	self:putLine(getLineFromIndexedTable(tTextInfo, "UnitEnteredCombat"))

	if bInCombat and not self.tUnits[unit:GetId()] then
		self.tUnits[unit:GetId()] = { unit = unit, buffs = {}, debuffs = {} }
	elseif not bInCombat then
		self.tUnits[unit:GetId()] = nil
	end
end

local tCombatLogVitalModifier = { "splCallingSpell", "nAmount", "eVitalType", "eCombatResult", "bShowCombatLog" }
function addon:OnCombatLogVitalModifier(tEventArgs)
	-- ignore resource gains from players and resource gains where no actors are available
	if not tEventArgs or not tEventArgs.unitCaster or tEventArgs.unitCaster:IsACharacter() then
		return
	end

	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogVitalModifier, "CombatLogVitalModifier")
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogVitalModifier"))
end

local tCombatLogInterrupted = { "splCallingSpell", "splInterruptingSpell", "strCastResult" , "eCastResult", "eCombatResult" }
function addon:OnCombatLogInterrupted(tEventArgs)
	-- ignore self interrupts (i.e. jumping midcast etc.)
	if not tEventArgs or not tEventArgs.unitCaster or tEventArgs.unitCaster == tEventArgs.unitTarget then
		return
	end
	
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogInterrupted, "CombatLogInterrupted")
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogInterrupted"))
end

local tCombatLogDeflect = { "splCallingSpell", "eCombatResult" }
function addon:OnCombatLogDeflect(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogDeflect, "CombatLogDeflect")
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogDeflect"))
end

local tCombatLogPet = { "splCallingSpell", "bKilled", "bDismissed", "eCombatResult" }
function addon:OnCombatLogPet(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogPet, "CombatLogPet")
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogPet"))
end

local tCombatLogDeath = {}
function addon:OnCombatLogDeath(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogDeath, "CombatLogDeath")
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogDeath"))
end

local tCombatLogResurrect = {}
function addon:OnCombatLogResurrect(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogResurrect, "CombatLogResurrect")
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogResurrect"))
end

local tCombatLogDispel = { "splCallingSpell", "splRemovedSpell", "bRemovesSingleInstance", "nInstancesRemoved", "eCombatResult" }
function addon:OnCombatLogDispel(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogDispel, "CombatLogDispel")
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogDispel"))
end

local tCombatLogModifyInterruptArmor = { "splCallingSpell", "nAmount", "eCombatResult" }
function addon:OnCombatLogModifyInterruptArmor(tEventArgs)
	-- fix for event w/o actors or nAmount
	if not tEventArgs.unitCaster or not tEventArgs.unitTarget or not tEventArgs.nAmount then return end
	
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogModifyInterruptArmor, "CombatLogModifyInterruptArmor")
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogModifyInterruptArmor"))
end

-- XXX figure out these

local tCombatLogDelayDeath = { 'NoClue' }
function addon:OnCombatLogDelayDeath(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogDelayDeath, "CombatLogDelayDeath")
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogDelayDeath"))
end

local tCombatLogImmunity = { 'NoClue' }
function addon:OnCombatLogImmunity(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogImmunity, "CombatLogImmunity")
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogImmunity"))
end

local tCombatLogStealth = { 'NoClue' }
function addon:OnCombatLogStealth(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogStealth, "CombatLogStealth")
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogStealth"))
end

-----------------------------------------------------------------------------------------------
-- Instance
-----------------------------------------------------------------------------------------------
local TranscriptorInst = addon:new()
TranscriptorInst:Init()
