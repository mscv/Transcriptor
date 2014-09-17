-----------------------------------------------------------------------------------------------
-- Transcriptor an encounter logging tool for bossmod developers
-- Inspired by the WoW addon with the same name
-- by Caleb calebzor@gmail.com
-----------------------------------------------------------------------------------------------

local gameVersion, buildVersion = "Live", "1.0.0.6851"

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

local tMissmatchingArgs = {}

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
	Apollo.RegisterEventHandler("CombatLogModifyInterruptArmor", 	"OnCombatLogModifyInterruptArmor", self)
	-- figure these out
	Apollo.RegisterEventHandler("CombatLogDelayDeath", 				"OnCombatLogDelayDeath", self)
	Apollo.RegisterEventHandler("CombatLogStealth", 				"OnCombatLogStealth", self)
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
	--GroupLib.GetInstanceDifficulty
	--GroupLib.GetInstanceGameMode
	self.sSession = ("%s - %s/%s/%s/%s/%s/%s/%s"):format(os.date(), "map", zone, "subzone", GameLib.GetWorldDifficulty(), "revision", gameVersion, buildVersion) -- XXX fill these out
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

	for k, v in pairs(tSessionDB) do
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
	local s = ("%s#%s"):format(os.date("%H:%M:%S"), sEvent)

	if not t[1] then -- not an indexed table that we generated
		for k, v in pairs(t) do
			s = ("%s#%s:%s"):format(s, tostring(k), tostring(v) or "")
		end
	end

	for k, v in ipairs(t) do
		s = ("%s#%s"):format(s, tostring(v) or "")
	end
	return s
end

function addon:putLine(str)
	if not self.bLogging then return end
	self.tDB[self.sSession][#self.tDB[self.sSession]+1] = str
end

function addon:getLineBuff(unit, id, nCount, fTimeRemaining, splEffect, bHarmful, sEventType)
	if fTimeRemaining and fTimeRemaining == 4294967.5 then -- assume this is infinite (~50 days)
		fTimeRemaining = "inf"
	end

	local tTextInfo = {os.time(), unit:GetName(), unit:GetId(), splEffect:GetName(), splEffect:GetId(), id, nCount, fTimeRemaining, splEffect:GetIcon(), splEffect:GetSchool(), splEffect:GetCastTime(), splEffect:GetBaseSpellId(), splEffect:GetCastMethod(), splEffect:IsFreeformTarget(), splEffect:GetAOETargetInfo().eSelectionType, splEffect:GetClass(), splEffect:GetMinimumRange() } -- might want to remove OR add more stuff
	-- XXX need to figure out if GetAOETargetInfo has more than eSelectionType
	if #splEffect:GetAOETargetInfo() > 1 then
		for k, v in pairs(splEffect:GetAOETargetInfo()) do
			Print(("[%s] = %s,"):format(k, v))
		end
	end
	--if #splEffect:GetPrerequisites() > 0 then
	--	for k, v in pairs(splEffect:GetPrerequisites()) do
	--		Print(("[%s] = %s,"):format(k, v))
	--	end
	--end
	-- XXX look into GetAOETargetInfo and GetPrerequisites
	local sEvent = (bHarmful and "Debuff" or "Buff") .. sEventType
	self:putLine(getLineFromIndexedTable(tTextInfo, sEvent))
end

local function checkForMissingBuffById(unit, id)
	local unitBuffs = unit:GetBuffs()
	for strBuffType, buffTypeValue  in pairs(unitBuffs) do
		for _, s in pairs(buffTypeValue) do
			if id == s.idBuff then
				return false
			end
		end
	end
	return true
end

local tCasterTargetSpell = { "unitCaster", "unitTarget", "splCallingSpell" }

local function trackMissmatchingArg(sEvent, sArg, sFrom)
	if not tMissmatchingArgs[sEvent] then
		tMissmatchingArgs[sEvent] = {}
	end
	tMissmatchingArgs[sEvent][sArg] = sFrom
end

local function checkForMissingKeysIn_tEventSpecificValues(tEventArgs, tEventSpecificValues, sEvent)
	for k, _ in pairs(tEventArgs) do
		local bKeyNotMissing

		for _, sEventArgKey in ipairs(tEventSpecificValues) do
			if k == sEventArgKey then
				bKeyNotMissing = true
				break
			end
		end
		if k == "unitCaster" or k == "unitTarget" or k == "splCallingSpell" or k == "unitCasterOwner" or k == "unitTargetOwner" then bKeyNotMissing = true end
		if not bKeyNotMissing then
			trackMissmatchingArg(sEvent, k, "tEventSpecificValues") -- aka missing from our indexed list
			return true
		end
	end
	return false
end

local function checkForRenamedOrRemovedKeysIn_tEventSpecificValues(tEventArgs, tEventSpecificValues, sEvent)
	for _, k in ipairs(tEventSpecificValues) do
		local bKeyNotMissing
		for sEventArgKey, _ in pairs(tEventArgs) do
			if sEventArgKey == k then
				bKeyNotMissing = true
				break
			end
		end
		if k == "unitCasterOwner" or k == "strTriggerCapCategory" or k == "unitTargetOwner" or k == "bHideFloater" then bKeyNotMissing = true end
		if sEvent == "CombatLogTransference" and ( k == "nHealAmount" or k == "nOverheal" or k == "eVitalType" ) then bKeyNotMissing = true end
		if not bKeyNotMissing then
			trackMissmatchingArg(sEvent, k, "tEventArgs") -- aka it is an extra in our indexed list
			return true
		end
	end
	return false
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
	-- XXX should do something if there is a missmatch between the tEventSpecificValues and the tEventArgs
	if verifyNoEventsArgMissmatch(tEventArgs, tEventSpecificValues, sEvent) then
		tInfo = verifyNoEventsArgMissmatch(tEventArgs, tEventSpecificValues, sEvent)
	else
		for k, v in ipairs(tEventSpecificValues) do
			if v == "unitTargetOwner" or v == "unitCasterOwner" or v == "splInterruptingSpell" or v == "splRemovedSpell" then
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

function addon:OnChatMessage(channelCurrent, tMessage)
	if checkChatFilter(channelCurrent:GetType()) then
		local strMessage = ""
		for _, tSegment in ipairs(tMessage.arMessageSegments) do
			strMessage = strMessage .. tSegment.strText
		end
		local tTextInfo = {channelCurrent:GetType(), tMessage.bAutoResponse, tMessage.bGM, tMessage.bSelf, tMessage.strSender, tMessage.strRealmName, tMessage.nPresenceState, strMessage, tMessage.unitSource and tMessage.unitSource:GetName() or "", tMessage.bShowChatBubble, tMessage.bCrossFaction}
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
					if self.tUnits[k].buffs[s.idBuff] then -- refresh
						if s.fTimeRemaining > self.tUnits[k].buffs[s.idBuff].fTimeRemaining then
							self:getLineBuff(unit, s.idBuff, s.nCount, s.fTimeRemaining, s.splEffect, bHarmful, "AppliedRenewed")
						elseif s.nCount ~= self.tUnits[k].buffs[s.idBuff].nCount then -- this for when an aura has no duration but has stacks
							self:getLineBuff(unit, s.idBuff, s.nCount, s.fTimeRemaining, s.splEffect, bHarmful, "Dose")
						end
						-- XXX probably don't need to keep track of everything, remove some that is not needed to improve performance
						-- nCount and fTimeRemaining is needed so far
						self.tUnits[k].buffs[s.idBuff] = {
							["unit"] = unit,
							["idBuff"] = s.idBuff,
							["nCount"] = s.nCount,
							["fTimeRemaining"] = s.fTimeRemaining,
							["splEffect"] = s.splEffect,
							["bHarmful"] = bHarmful,
						}
					else -- first application
						self.tUnits[k].buffs[s.idBuff] = {
							["unit"] = unit,
							["idBuff"] = s.idBuff,
							["nCount"] = s.nCount,
							["fTimeRemaining"] = s.fTimeRemaining,
							["splEffect"] = s.splEffect,
							["bHarmful"] = bHarmful,
						}
						self:getLineBuff(unit, s.idBuff, s.nCount, s.fTimeRemaining, s.splEffect, bHarmful, "Applied")
					end
				end
			end
		end
		-- buffs removed
		for buffId, buffData in pairs(v.buffs) do
			-- remember right now only player debuffs and non player buffs are tracked
			if checkForMissingBuffById(unit, buffId) then
				self:getLineBuff(unit, buffData.idBuff, buffData.nCount, buffData.fTimeRemaining, buffData.splEffect, buffData.bHarmful, "Removed")
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

--<N F="26" T="s" V="18:28:51#CombatLogDamage#eEffectType:8#bTargetKilled:false#nOverkill:0#bPeriodic:false#splCallingSpell:userdata: 00000001D75258F0#nDamageAmount:643#unitCasterOwner:userdata: 00000001D75255F0#unitCaster:userdata: 00000001D75250B0#nRawDamage:716#nShield:0#eCombatResult:2#nAbsorption:0#bTargetVulnerable:true#unitTarget:userdata: 00000001D75256F0#eDamageType:2"/>
local tCombatLogDamage = { "unitCasterOwner", "unitTargetOwner", "bTargetKilled", "nOverkill", "nDamageAmount", "bPeriodic", "nShield", "nRawDamage", "nAbsorption", "bTargetVulnerable", "eDamageType", "eEffectType", "eCombatResult" }
function addon:OnCombatLogDamage(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogDamage, "CombatLogDamage")
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogDamage"))
end

local tCombatLogCCState = { "strTriggerCapCategory", "bRemoved", "strState", "eState", "nInterruptArmorHit", "eResult", "eCombatResult", "bHideFloater" }
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

local tCombatLogHeal = { "unitCasterOwner", "nOverheal", "nHealAmount", "eEffectType", "eCombatResult" }
function addon:OnCombatLogHeal(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogHeal, "CombatLogHeal")
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogHeal"))
end

function addon:OnEnteredCombat(unit, bInCombat)
	if unit == GameLib.GetPlayerUnit() then
		self:putLine(("%s#%s#%s"):format(os.date("%H:%M:%S"), "PlayerEnteredCombat", tostring(bInCombat)))
	end
end

local tCombatLogVitalModifier = { "bShowCombatLog", "nAmount", "eVitalType", "eCombatResult" }
function addon:OnCombatLogVitalModifier(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogVitalModifier, "CombatLogVitalModifier")
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogVitalModifier"))
end

local tCombatLogInterrupted = { "splInterruptingSpell", "strCastResult" , "eCastResult", "eCombatResult" } -- unitTarget, unitCaster
function addon:OnCombatLogInterrupted(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogInterrupted, "CombatLogInterrupted")
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogInterrupted"))
end

local tCombatLogDeflect = { "unitCasterOwner", "eCombatResult" }
function addon:OnCombatLogDeflect(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogDeflect, "CombatLogDeflect")
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogDeflect"))
end

local tCombatLogPet = { "unitTargetOwner", "bKilled", "bDismissed", "eCombatResult" }
function addon:OnCombatLogPet(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogPet, "CombatLogPet")
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogPet"))
end

local tCombatLogDeath = { "" }
function addon:OnCombatLogDeath(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogDeath, "CombatLogDeath")
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogDeath"))
end

local tCombatLogResurrect = { "" }
function addon:OnCombatLogResurrect(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogResurrect, "CombatLogResurrect")
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogResurrect"))
end

local tCombatLogDispel = { "splRemovedSpell", "bRemovesSingleInstance", "nInstancesRemoved", "eCombatResult" }
function addon:OnCombatLogDispel(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogDispel, "CombatLogDispel")
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogDispel"))
end

local tCombatLogTransference = { "tHealData", "bTargetVulnerable", "nOverheal", "nOverkill", "nDamageAmount", "nHealAmount", "nAbsorption", "nShield", "eDamageType", "eVitalType", "eCombatResult" }
function addon:OnCombatLogTransference(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogTransference, "CombatLogTransference")
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogTransference"))
end

local tCombatLogModifyInterruptArmor = { "nAmount", "eCombatResult" }
function addon:OnCombatLogModifyInterruptArmor(tEventArgs)
	local tTextInfo = self:HelperParseEvent(tEventArgs, tCombatLogModifyInterruptArmor, "CombatLogModifyInterruptArmor")
	self:putLine(getLineFromIndexedTable(tTextInfo, "CombatLogModifyInterruptArmor"))
end

-- figure out these
function addon:OnCombatLogDelayDeath(tEventArgs)
	tEventArgs["sEventName"] = "CombatLogDelayDeath"
	self:putLine(tEventArgs)
end

function addon:OnCombatLogImmunity(tEventArgs)
	tEventArgs["sEventName"] = "CombatLogImmunity"
	self:putLine(tEventArgs)
end

function addon:OnCombatLogStealth(tEventArgs)
	tEventArgs["sEventName"] = "CombatLogStealth"
	self:putLine(tEventArgs)
end

-----------------------------------------------------------------------------------------------
-- Instance
-----------------------------------------------------------------------------------------------
local TranscriptorInst = addon:new()
TranscriptorInst:Init()
