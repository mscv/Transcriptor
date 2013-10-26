-----------------------------------------------------------------------------------------------
-- Transcriptor an encounter logging tool for bossmod developers
-- by Caleb calebzor@gmail.com
-----------------------------------------------------------------------------------------------

require "Window"
require "GameLib"
require "ChatSystemLib"

-----------------------------------------------------------------------------------------------
-- Upvalues
-----------------------------------------------------------------------------------------------

local Apollo = Apollo
local setmetatable = setmetatable
local ipairs = ipairs
local pairs = pairs
local os = os
local tostring = tostring
local Print = Print
local GameLib = GameLib

-----------------------------------------------------------------------------------------------
-- Module Definition and variables
-----------------------------------------------------------------------------------------------
local Transcriptor = {}
local addon = Transcriptor
local tSession
local chatFilter = {
	ChatSystemLib.ChatChannel_NPCSay,     --20
	ChatSystemLib.ChatChannel_NPCYell,    --21
	ChatSystemLib.ChatChannel_NPCWhisper, --22
	ChatSystemLib.ChatChannel_Datachron,  --23
	--ChatSystemLib.ChatChannel_Say,        --4
	ChatSystemLib.ChatChannel_System,     --2
	ChatSystemLib.ChatChannel_Zone,       --9
	ChatSystemLib.ChatChannel_Instance,   --32
	ChatSystemLib.ChatChannel_Realm,      --25
}
-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------
function addon:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	return o
end

function addon:Init()
	Apollo.RegisterAddon(self)
end
-----------------------------------------------------------------------------------------------
-- OnLoad
-----------------------------------------------------------------------------------------------
function addon:OnLoad()
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
	-- figure these out
	Apollo.RegisterEventHandler("CombatLogDelayDeath", 				"OnCombatLogDelayDeath", self)
	Apollo.RegisterEventHandler("CombatLogStealth", 				"OnCombatLogStealth", self)
	Apollo.RegisterEventHandler("CombatLogModifyInterruptArmor", 	"OnCombatLogModifyInterruptArmor", self)

	-- this must be really resource heavy
	Apollo.RegisterEventHandler("UnitCreated", 						"OnUnitCreated", self)
	Apollo.RegisterEventHandler("UnitDestroyed", 					"OnUnitDestroyed", self)
	self.tUnits = {}
	--tUnits = self.tUnits

	Apollo.RegisterEventHandler("NextFrame", 						"OnUpdate", self)

	-- load our forms
	self.wndMain = Apollo.LoadForm("Transcriptor.xml", "TranscriptorForm", nil, self)
	self.wndMain:Show(true)
	self.tPrevDB = {}
	self.tDB = {}
	self.sSession = ("%s - map/zone/subzone/difficulty/revision/gameVersion/buildVersion"):format(os.date()) -- XXX fill these out
	self.tDB[self.sSession] = {}
	tSession = self.tDB[self.sSession]

end

-----------------------------------------------------------------------------------------------
-- Utility
-----------------------------------------------------------------------------------------------

local function getLineFromIndexedTable(t, strEvent)
	local s = ("%s#%s"):format(os.date("%H:%M:%S"), strEvent)
	for k, v in ipairs(t) do
		s = ("%s#%s"):format(s, tostring(v) or "")
	end
	return s
end

local function putLineBuffApplied(unit, id, nCount, fTimeRemaining, spell, bHarmful, strEventType)
	if fTimeRemaining and fTimeRemaining == 4294967.5 then -- assume this is infinite (~50 days)
		fTimeRemaining = "inf"
	end

	local tTextInfo = {os.time(), unit:GetName(), unit:GetId(), spell:GetName(), spell:GetId(), id, nCount, fTimeRemaining, spell:GetIcon(), spell:GetSchool(), spell:GetCastTime(), spell:GetBaseSpellId(), spell:GetCastMethod(), spell:IsFreeformTarget(), spell:GetAOETargetInfo().eSelectionType, spell:GetClass(), spell:GetMinimumRange(), (#spell:GetPrerequisites() > 0) and spell:GetPrerequisites() or "" } -- might want to remove OR add more stuff
	-- XXX need to figure out if GetAOETargetInfo has more than eSelectionType
	if #spell:GetAOETargetInfo() > 1 then
		for k, v in pairs(spell:GetAOETargetInfo()) do
			Print(("[%s] = %s,"):format(k, v))
		end
	end
	if #spell:GetPrerequisites() > 0 then
		for k, v in pairs(spell:GetPrerequisites()) do
			Print(("[%s] = %s,"):format(k, v))
		end
	end
	-- XXX look into GetAOETargetInfo and GetPrerequisites
	local strEvent = (bHarmful and "Debuff" or "Buff") .. strEventType
	tSession[#tSession+1] = getLineFromIndexedTable(tTextInfo, strEvent)
end

local function checkForMissingBuffById(unit, id)
	local unitBuffs = unit:GetBuffs()
	for strBuffType, buffTypeValue  in pairs(unitBuffs) do
		for _, s in pairs(buffTypeValue) do
			if id == s.id then
				return false
			end
		end
	end
	return true
end

local tCasterTargetSpell = { "unitCaster", "unitTarget", "splCallingSpell" }

function addon:HelperParseEvent(tEventArgs, tEventSpecificValues)
	-- sSourceName, nSourceId, sDestName, nDestId, sSpellName, nSpellId,
	-- bTargetKilled, nOverkill, eEffectType, nDamageAmount, bPeriodic, nShield, nRawDamage, eDamageType, nAbsorption, bTargetVulnerable, eCombatResult
	local tInfo = {}
	for k, v in ipairs(tCasterTargetSpell) do
		tInfo[#tInfo+1] = self:HelperGetName(tEventArgs[v])
		tInfo[#tInfo+1] = self:HelperGetId(tEventArgs[v])
		if k == "splCallingSpell"  then
			if v and v:GetSchool() then
				Info[#tInfo+1] = v:GetSchool()
			else
				Info[#tInfo+1] = ""
			end
		end
	end
	for k, v in ipairs(tEventSpecificValues) do
		tInfo[#tInfo+1] = tEventArgs[v]
	end
	return tInfo
end

function addon:HelperGetName(nArg)
	if nArg and nArg:GetName() then
		return nArg:GetName()
	end
	return ""
end

function addon:HelperGetId(nArg)
	if nArg and nArg:GetId() then
		return nArg:GetId()
	end
	return ""
end

local function checkChatFilter(channelType)
	for _, v in ipairs(chatFilter) do
		if v == channelType then
			return true
		end
	end
	return false
end

-----------------------------------------------------------------------------------------------
-- Event handlers
-----------------------------------------------------------------------------------------------

function addon:OnChatMessage(channelCurrent, bGM, bSelf, strSender, strRealmName, arMessageSegments, unitSource, bBubble)
	if checkChatFilter(channelCurrent:GetType()) then
		local strMessage = ""
		for _, tSegment in ipairs(arMessageSegments) do
			strMessage = strMessage .. tSegment.strText
		end
		local tTextInfo = {channelCurrent:GetType(), bGM, bSelf, strSender, strRealmName, strMessage, unitSource and unitSource:GetId() or "", bBubble}
		tSession[#tSession+1] = getLineFromIndexedTable(tTextInfo, "OnChatMessage")
	end
end

function addon:OnUpdate()
	--local pId = GameLib.GetPlayerUnit():GetId()
	for k, v in pairs(self.tUnits) do
		local unit = v.unit
		-- casting
		if unit:IsCasting() and unit:GetType() and unit:GetType() == "NonPlayer" then -- XXX only track non player casts
			if unit:GetCastDuration() and not unit:ShouldShowCastBar() then self.tUnits[k].shouldTrack = 1 end
			if unit:GetCastDuration() and unit:GetCastDuration() > 0 and not unit:ShouldShowCastBar() then return end
			if self.tUnits[k].shouldTrack and self.tUnits[k].shouldTrack == 0 then return end
			self.tUnits[k].shouldTrack = 0
			local target = unit:GetTarget()
			local sTargetName, sTargetId = "", ""
			if target then
				sTargetName, sTargetId = target:GetName(), target:GetId()
			end
			local tTextInfo = {os.time(), unit:GetName(), unit:GetId(), sTargetName, sTargetId, unit:IsCasting(), unit:GetCastBarType(), unit:GetCastDuration(), unit:GetCastElapsed(), unit:GetCastName(), unit:GetCastTotalPercent(), unit:GetSpellMechanicId(), unit:GetSpellMechanicPercentage(), unit:ShouldShowCastBar()}
			tSession[#tSession+1] = getLineFromIndexedTable(tTextInfo, "OnTimerCasting")
		end
		-- buffs applied
		local unitBuffs = unit:GetBuffs()
--		unit = GameLib.GetPlayerUnit(); D(unit:GetBuffs().arBeneficial)             [1].spell:GetPrerequisites())
		for strBuffType, buffTypeValue  in pairs(unitBuffs) do
			local harmful = (strBuffType == "arHarmful") and true
			local unitType = unit:GetType()
			if unitType and ((harmful and unitType == "Player") or (not harmful and unitType == "NonPlayer")) then -- XXX only track player debuffs and non player buffs
				for _, s in pairs(buffTypeValue) do
					--if pId ~= unit:GetId() then return end
					if self.tUnits[k].buffs[s.id] then -- refresh
						if s.fTimeRemaining > self.tUnits[k].buffs[s.id].fTimeRemaining then
							putLineBuffApplied(unit, s.id, s.nCount, s.fTimeRemaining, s.spell, harmful, "AppliedRenewed")
						elseif s.nCount ~= self.tUnits[k].buffs[s.id].nCount then -- this for when an aura has no duration but has stacks
							putLineBuffApplied(unit, s.id, s.nCount, s.fTimeRemaining, s.spell, harmful, "Dose")
						end
						-- XXX probably don't need to keep track of everything, remove some that is not needed to improve performance
						-- nCount and fTimeRemaining is needed so far
						self.tUnits[k].buffs[s.id] = {
							["unit"] = unit,
							["id"] = s.id,
							["nCount"] = s.nCount,
							["fTimeRemaining"] = s.fTimeRemaining,
							["spell"] = s.spell,
							["harmful"] = harmful,
						}
					else -- first application
						self.tUnits[k].buffs[s.id] = {
							["unit"] = unit,
							["id"] = s.id,
							["nCount"] = s.nCount,
							["fTimeRemaining"] = s.fTimeRemaining,
							["spell"] = s.spell,
							["harmful"] = harmful,
						}
						putLineBuffApplied(unit, s.id, s.nCount, s.fTimeRemaining, s.spell, harmful, "Applied")
					end
				end
			end
		end
		-- buffs removed
		for buffId, buffData in pairs(v.buffs) do
			-- remember right now only player debuffs and non player buffs are tracked
			if checkForMissingBuffById(unit, buffId) then
				putLineBuffApplied(unit, buffData.id, buffData.nCount, buffData.fTimeRemaining, buffData.spell, buffData.harmful, "Removed")
				self.tUnits[k].buffs[buffId] = nil
			end
		end
	end
end

function addon:OnUnitCreated(unit)
	self.tUnits[unit:GetId()] = {}
	self.tUnits[unit:GetId()]["unit"] = unit
	self.tUnits[unit:GetId()].buffs = {}
	self.tUnits[unit:GetId()].debuffs = {}
end

function addon:OnUnitDestroyed(unit)
	self.tUnits[unit:GetId()] = nil
end

local tCombatLogDamage = { "bTargetKilled", "nOverkill", "eEffectType", "nDamageAmount", "bPeriodic", "nShield", "nRawDamage", "eDamageType", "nAbsorption", "bTargetVulnerable", "eCombatResult" }
function addon:OnCombatLogDamage(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogDamage)
	tSession[#tSession+1] = getLineFromIndexedTable(tTextInfo, "CombatLogDamage")
end

local tCombatLogCCState = { "eResult", "strState", "eState", "nInterruptArmorHit", "eCombatResult", "bRemoved" }
function addon:OnCombatLogCCState(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogDamage)
	tSession[#tSession+1] = getLineFromIndexedTable(tTextInfo, "CombatLogCCState")
end

local tCombatLogCCStateBreak = { "strState", "eState" }
function addon:OnCombatLogCCStateBreak(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogCCStateBreak)
	tSession[#tSession+1] = getLineFromIndexedTable(tTextInfo, "CombatLogCCStateBreak")
end

local tCombatLogFallingDamage = { "nDamageAmount" }
function addon:OnCombatLogFallingDamage(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogFallingDamage)
	tSession[#tSession+1] = getLineFromIndexedTable(tTextInfo, "CombatLogFallingDamage")
end

local tCombatLogHeal = { "nOverheal", "nHealAmount", "eCombatResult", "eEffectType" }
function addon:OnCombatLogHeal(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogDamage)
	tSession[#tSession+1] = getLineFromIndexedTable(tTextInfo, "CombatLogHeal")
end

function addon:OnEnteredCombat(unit, bInCombat)
	if unit == GameLib.GetPlayerUnit() then
		tSession[#tSession+1] = ("%s#%s#%s"):format(os.date("%H:%M:%S"), "PlayerEnteredCombat", tostring(bInCombat))
	end
end

local tCombatLogVitalModifier = { "bShowCombatLog", "nAmount", "eCombatResult", "eVitalType" }
function addon:OnCombatLogVitalModifier(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogDamage)
	tSession[#tSession+1] = getLineFromIndexedTable(tTextInfo, "CombatLogVitalModifier")
end

local tCombatLogInterrupted = { "eCastResult", "eCombatResult", "strCastResult" }
function addon:OnCombatLogInterrupted(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogDamage)
	tSession[#tSession+1] = getLineFromIndexedTable(tTextInfo, "CombatLogInterrupted")
end

local tCombatLogDeflect = { "eCombatResult" }
function addon:OnCombatLogDeflect(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogDamage)
	tSession[#tSession+1] = getLineFromIndexedTable(tTextInfo, "CombatLogDeflect")
end

local tCombatLogPet = { "bDismissed", "eCombatResult", "bKilled" }
function addon:OnCombatLogPet(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogPet)
	tSession[#tSession+1] = getLineFromIndexedTable(tTextInfo, "CombatLogPet")
end

local tCombatLogDeath = { "" }
function addon:OnCombatLogDeath(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogDeath)
	tSession[#tSession+1] = getLineFromIndexedTable(tTextInfo, "CombatLogDeath")
end

local tCombatLogResurrect = { "" }
function addon:OnCombatLogResurrect(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogResurrect)
	tSession[#tSession+1] = getLineFromIndexedTable(tTextInfo, "CombatLogResurrect")
end

local tCombatLogDispel = { "nInstancesRemoved", "bRemovesSingleInstance", "eCombatResult" }
function addon:OnCombatLogDispel(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogDispel)
	tSession[#tSession+1] = getLineFromIndexedTable(tTextInfo, "CombatLogDispel")
end

local tCombatLogTransference = { "nOverheal", "nOverkill", "nDamageAmount", "eVitalType", "nAbsorption", "nHealAmount", "eCombatResult", "eDamageType", "bTargetVulnerable", "nShield" }
function addon:OnCombatLogTransference(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogTransference)
	tSession[#tSession+1] = getLineFromIndexedTable(tTextInfo, "CombatLogTransference")
end

-- figure out these
function addon:OnCombatLogDelayDeath(tEventArgs)
	tEventArgs["strEventName"] = "CombatLogDelayDeath"
	tSession[#tSession+1] = tEventArgs
end

function addon:OnCombatLogModifyInterruptArmor(tEventArgs)
	tEventArgs["strEventName"] = "CombatLogModifyInterruptArmor"
	tSession[#tSession+1] = tEventArgs
end

function addon:OnCombatLogImmunity(tEventArgs)
	tEventArgs["strEventName"] = "CombatLogImmunity"
	tSession[#tSession+1] = tEventArgs
end


function addon:OnCombatLogStealth(tEventArgs)
	tEventArgs["strEventName"] = "CombatLogStealth"
	tSession[#tSession+1] = tEventArgs
end

-----------------------------------------------------------------------------------------------
-- GUI and SavedVariables
-----------------------------------------------------------------------------------------------

-- when the Cancel button is clicked
function addon:OnButton()
	self.tPrevDB = {}
	Print("Transcriptor cleared previous sessions data")
end

function addon:OnSave(eLevel)
	if eLevel ~= GameLib.CodeEnumAddonSaveLevel.Character then return end

	self.tPrevDB[self.sSession] = tSession
	return self.tPrevDB
end

function addon:OnRestore(eLevel, tData)
	-- just store this and use it later
	self.tPrevDB = tData
end


-----------------------------------------------------------------------------------------------
-- Instance
-----------------------------------------------------------------------------------------------
local TranscriptorInst = addon:new()
TranscriptorInst:Init()
