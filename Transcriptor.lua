-----------------------------------------------------------------------------------------------
-- Transcriptor an encounter logging tool for bossmod developers
-- Inspired by the WoW addon with the same name
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
local tSessionDB
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

function addon:Init()
	Apollo.RegisterAddon(self)
end
-----------------------------------------------------------------------------------------------
-- OnLoad and Enabling stuff
-----------------------------------------------------------------------------------------------
function addon:OnLoad()
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
	-- figure these out
	Apollo.RegisterEventHandler("CombatLogDelayDeath", 				"OnCombatLogDelayDeath", self)
	Apollo.RegisterEventHandler("CombatLogStealth", 				"OnCombatLogStealth", self)
	Apollo.RegisterEventHandler("CombatLogModifyInterruptArmor", 	"OnCombatLogModifyInterruptArmor", self)
	-- this must be really resource heavy
	Apollo.RegisterEventHandler("UnitCreated", 						"OnUnitCreated", self)
	Apollo.RegisterEventHandler("UnitDestroyed", 					"OnUnitDestroyed", self)
	Apollo.RegisterEventHandler("NextFrame", 						"OnUpdate", self)
	-- load our forms
	self.wndMain = Apollo.LoadForm("Transcriptor.xml", "TranscriptorForm", nil, self)
	self.wndMain:Show(true)
	self.wndAnchor = Apollo.LoadForm("Transcriptor.xml", "Anchor", nil, self)
	self.wndAnchor:Show(false)
	self.wndMain:FindChild("Button"):SetTooltip(tooltipText)
	self.bLogging = false
	self.bLocked = true
	self.tPrevDB = {}
	self.tDB = {}
	tSessionDB = self.tDB
	self.tUnits = {}
	-- XXX for now start logging from start
	--self:EnableLogging()
end

function addon:EnableLogging()
	local zone = "Unknown Zone"
	if GameLib.GetCurrentZoneMap() then
		zone = GameLib.GetCurrentZoneMap().strName
	end
	--GroupLib.GetInstanceDifficulty
	--GroupLib.GetInstanceGameMode
	self.sSession = ("%s - map/%s/subzone/difficulty/revision/gameVersion/buildVersion"):format(os.date(), zone) -- XXX fill these out
	self.tDB[self.sSession] = {}
	self.bLogging = true
	self.wndMain:GetChildren()[1]:SetText("Transcriptor: On")
end

function addon:DisableLogging()
	self.sSession = nil
	self.bLogging = false
	self.wndMain:GetChildren()[1]:SetText("Transcriptor: Off")
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
			for k, v in pairs(tSessionDB) do
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
	if self.bLocked then
		self.wndMain:FindChild("Button"):Show(false)
		-- always set the anchor to be at the TranscriptorFrame before displaying it
		local l,t,r,b = self.wndMain:GetAnchorOffsets()
		self.wndAnchor:SetAnchorOffsets(l,t,r-30,b) -- -30 because of the lock button
		self.wndAnchor:Show(true)
		self.bLocked = false
	else
		self.wndMain:FindChild("Button"):Show(true)
		self.wndAnchor:Show(false)
		self.bLocked = true
	end
end

function addon:OnSave(eLevel)
	if eLevel ~= GameLib.CodeEnumAddonSaveLevel.Character then return end

	for k, v in pairs(tSessionDB) do
		self.tPrevDB[k] = v
	end
	local l,t,r,b = self.wndMain:GetAnchorOffsets()
	self.tPrevDB.tPos = { l = l, t = t, r = r, b = b}
	return self.tPrevDB
end

function addon:OnRestore(eLevel, tData)
	if eLevel ~= GameLib.CodeEnumAddonSaveLevel.Character then return end
	-- just store this and use it later
	self.tPrevDB = tData
	if tData.tPos then
		self.wndMain:SetAnchorOffsets(tData.tPos.l, tData.tPos.t, tData.tPos.r, tData.tPos.b)
	end
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

function addon:putLine(str)
	if not self.bLogging then return end
	self.tDB[self.sSession][#self.tDB[self.sSession]+1] = str
end

function addon:getLineBuff(unit, id, nCount, fTimeRemaining, spell, bHarmful, strEventType)
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
	self:putLine(getLineFromIndexedTable(tTextInfo, strEvent))
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
				tInfo[#tInfo+1] = v:GetSchool()
			else
				tInfo[#tInfo+1] = ""
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
		self:putLine(getLineFromIndexedTable(tTextInfo, "OnChatMessage"))
	end
end

function addon:OnUpdate()
	if not self.bLogging then return end
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
			self:putLine(getLineFromIndexedTable(tTextInfo, "OnTimerCasting"))
		end
		-- buffs applied
		local unitBuffs = unit:GetBuffs()
		for strBuffType, buffTypeValue  in pairs(unitBuffs) do
			local bHarmful = (strBuffType == "arHarmful") and true or false
			local unitType = unit:GetType()
			if unitType and ((bHarmful and unitType == "Player") or (not bHarmful and unitType == "NonPlayer")) then -- XXX only track player debuffs and non player buffs
				for _, s in pairs(buffTypeValue) do
					--if pId ~= unit:GetId() then return end
					if self.tUnits[k].buffs[s.id] then -- refresh
						if s.fTimeRemaining > self.tUnits[k].buffs[s.id].fTimeRemaining then
							self:getLineBuff(unit, s.id, s.nCount, s.fTimeRemaining, s.spell, bHarmful, "AppliedRenewed")
						elseif s.nCount ~= self.tUnits[k].buffs[s.id].nCount then -- this for when an aura has no duration but has stacks
							self:getLineBuff(unit, s.id, s.nCount, s.fTimeRemaining, s.spell, bHarmful, "Dose")
						end
						-- XXX probably don't need to keep track of everything, remove some that is not needed to improve performance
						-- nCount and fTimeRemaining is needed so far
						self.tUnits[k].buffs[s.id] = {
							["unit"] = unit,
							["id"] = s.id,
							["nCount"] = s.nCount,
							["fTimeRemaining"] = s.fTimeRemaining,
							["spell"] = s.spell,
							["bHarmful"] = bHarmful,
						}
					else -- first application
						self.tUnits[k].buffs[s.id] = {
							["unit"] = unit,
							["id"] = s.id,
							["nCount"] = s.nCount,
							["fTimeRemaining"] = s.fTimeRemaining,
							["spell"] = s.spell,
							["bHarmful"] = bHarmful,
						}
						self:getLineBuff(unit, s.id, s.nCount, s.fTimeRemaining, s.spell, bHarmful, "Applied")
					end
				end
			end
		end
		-- buffs removed
		for buffId, buffData in pairs(v.buffs) do
			-- remember right now only player debuffs and non player buffs are tracked
			if checkForMissingBuffById(unit, buffId) then
				self:getLineBuff(unit, buffData.id, buffData.nCount, buffData.fTimeRemaining, buffData.spell, buffData.bHarmful, "Removed")
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
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogDamage"))
end

local tCombatLogCCState = { "eResult", "strState", "eState", "nInterruptArmorHit", "eCombatResult", "bRemoved" }
function addon:OnCombatLogCCState(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogDamage)
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogCCState"))
end

local tCombatLogCCStateBreak = { "strState", "eState" }
function addon:OnCombatLogCCStateBreak(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogCCStateBreak)
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogCCStateBreak"))
end

local tCombatLogFallingDamage = { "nDamageAmount" }
function addon:OnCombatLogFallingDamage(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogFallingDamage)
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogFallingDamage"))
end

local tCombatLogHeal = { "nOverheal", "nHealAmount", "eCombatResult", "eEffectType" }
function addon:OnCombatLogHeal(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogDamage)
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogHeal"))
end

function addon:OnEnteredCombat(unit, bInCombat)
	if unit == GameLib.GetPlayerUnit() then
		self:putLine(("%s#%s#%s"):format(os.date("%H:%M:%S"), "PlayerEnteredCombat", tostring(bInCombat)))
	end
end

local tCombatLogVitalModifier = { "bShowCombatLog", "nAmount", "eCombatResult", "eVitalType" }
function addon:OnCombatLogVitalModifier(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogDamage)
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogVitalModifier"))
end

local tCombatLogInterrupted = { "eCastResult", "eCombatResult", "strCastResult" }
function addon:OnCombatLogInterrupted(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogDamage)
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogInterrupted"))
end

local tCombatLogDeflect = { "eCombatResult" }
function addon:OnCombatLogDeflect(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogDamage)
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogDeflect"))
end

local tCombatLogPet = { "bDismissed", "eCombatResult", "bKilled" }
function addon:OnCombatLogPet(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogPet)
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogPet"))
end

local tCombatLogDeath = { "" }
function addon:OnCombatLogDeath(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogDeath)
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogDeath"))
end

local tCombatLogResurrect = { "" }
function addon:OnCombatLogResurrect(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogResurrect)
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogResurrect"))
end

local tCombatLogDispel = { "nInstancesRemoved", "bRemovesSingleInstance", "eCombatResult" }
function addon:OnCombatLogDispel(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogDispel)
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogDispel"))
end

local tCombatLogTransference = { "nOverheal", "nOverkill", "nDamageAmount", "eVitalType", "nAbsorption", "nHealAmount", "eCombatResult", "eDamageType", "bTargetVulnerable", "nShield" }
function addon:OnCombatLogTransference(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogTransference)
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogTransference"))
end

-- figure out these
function addon:OnCombatLogDelayDeath(tEventArgs)
	tEventArgs["strEventName"] = "CombatLogDelayDeath"
	self:putLine(tEventArgs)
end

function addon:OnCombatLogModifyInterruptArmor(tEventArgs)
	tEventArgs["strEventName"] = "CombatLogModifyInterruptArmor"
	self:putLine(tEventArgs)
end

function addon:OnCombatLogImmunity(tEventArgs)
	tEventArgs["strEventName"] = "CombatLogImmunity"
	self:putLine(tEventArgs)
end

function addon:OnCombatLogStealth(tEventArgs)
	tEventArgs["strEventName"] = "CombatLogStealth"
	self:putLine(tEventArgs)
end

-----------------------------------------------------------------------------------------------
-- Instance
-----------------------------------------------------------------------------------------------
local TranscriptorInst = addon:new()
TranscriptorInst:Init()
