--[[
	Quest Objectives+ probe (dev only)
	/qopprobe        -> run all probes, open a copyable window with the report
	/qopprobe chat   -> same, but also print every line to chat

	Before running: be in a party with at least one member who shares a quest
	with you, track a few quests (some finished), and stand out of combat.
	Run it again in combat and in a dungeon to see which values go secret.

	Design checks for auto-share, the party audit and completed-quest search.
	These write to a running log; /qopprobe report opens it.
	/qopprobe share [now]     -> Q1: share without a click (next accepted quest, or now)
	/qopprobe notheld [id]    -> Q2: party data for a quest you do not hold
	/qopprobe access          -> Q3: one snapshot of party data and addon messages
	/qopprobe watch           -> Q3: snapshot on every pull, boss and loading screen
	/qopprobe completed [n]   -> Q4: completed IDs and how fast n names load (default 200)
	/qopprobe report | clear  -> open or empty the running log
]]

local lines = {}
local toChat = false

-------------------------------------------------------------------------------
-- Output helpers (same shape as the no_sir probe)
-------------------------------------------------------------------------------

local function out(fmt, ...)
	local s = fmt
	if select("#", ...) > 0 then
		local ok, r = pcall(string.format, fmt, ...)
		s = ok and r or (fmt .. " (format error: " .. tostring(r) .. ")")
	end
	lines[#lines + 1] = s
	if toChat then print("|cff66ccffQOPP:|r " .. s) end
end

local function accessible(v)
	if type(canaccessvalue) == "function" then
		local ok, r = pcall(canaccessvalue, v)
		if ok then return r end
	end
	return true
end

local function fmtv(v, depth)
	depth = depth or 0
	if not accessible(v) then return "<secret>" end
	local t = type(v)
	if t == "string" then return ("%q"):format(v) end
	if t ~= "table" then
		local ok, s = pcall(tostring, v)
		return ok and s or "<unprintable>"
	end
	if depth > 1 then return "{...}" end
	local entries = {}
	for k, val in pairs(v) do entries[#entries + 1] = { k = k, v = val } end
	table.sort(entries, function(a, b) return tostring(a.k) < tostring(b.k) end)
	local parts = {}
	for i, e in ipairs(entries) do
		if i > 25 then parts[#parts + 1] = "..."; break end
		parts[#parts + 1] = tostring(e.k) .. "=" .. fmtv(e.v, depth + 1)
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end

local function call(label, fn, ...)
	if type(fn) ~= "function" then out("%s -> <no such function>", label); return end
	local res = { pcall(fn, ...) }
	if not res[1] then out("%s -> ERROR %s", label, tostring(res[2])); return end
	local parts = {}
	for i = 2, #res do parts[#parts + 1] = fmtv(res[i]) end
	if #parts == 0 then parts[1] = "<nothing>" end
	out("%s -> %s", label, table.concat(parts, ", "))
	return select(2, unpack(res))
end

local function lookup(path)
	local cur = _G
	for part in path:gmatch("[^%.]+") do
		if type(cur) ~= "table" then return nil end
		cur = cur[part]
	end
	return cur
end

local function section(title)
	out("")
	out("===== %s =====", title)
end

local function keys(t, max)
	if type(t) ~= "table" then return "<" .. type(t) .. ">" end
	local names = {}
	for k, v in pairs(t) do names[#names + 1] = tostring(k) .. ":" .. type(v) end
	table.sort(names)
	max = max or 40
	if #names > max then
		local extra = #names - max
		for i = #names, max + 1, -1 do names[i] = nil end
		names[#names + 1] = "(+" .. extra .. " more)"
	end
	return table.concat(names, " ")
end

-------------------------------------------------------------------------------
-- Probes
-------------------------------------------------------------------------------

local API_NAMES = {
	"canaccessvalue", "issecretvalue", "C_Secrets.HasSecretRestrictions",
	"C_TooltipInfo.GetQuestPartyProgress", "GameTooltip.SetQuestPartyProgress",
	"C_QuestLog.GetNumQuestWatches", "C_QuestLog.GetQuestIDForQuestWatchIndex", "C_QuestLog.SortQuestWatches",
	"C_QuestLog.IsComplete", "C_QuestLog.GetLogIndexForQuestID", "C_QuestLog.GetTitleForQuestID",
	"C_QuestLog.AddQuestWatch", "C_QuestLog.RemoveQuestWatch", "C_QuestLog.GetQuestObjectives",
	"Constants.QuestWatchConsts.MAX_QUEST_WATCHES", "C_QuestLog.GetMaxNumQuestsCanAccept",
	"QuestUtilsOverrides.GetQuestTagText", "QuestCache.Get",
	"ObjectiveTrackerFrame", "ObjectiveTrackerManager", "QuestObjectiveTracker",
	"QuestObjectiveTracker.EndLayout", "QuestObjectiveTracker.UpdateHeight", "QuestObjectiveTracker.BuildQuestWatchInfos",
	"QuestObjectiveTracker.ContentsFrame", "QuestObjectiveTracker.Header",
	"ObjectiveTrackerFrame.Header", "ObjectiveTrackerFrame.Header.MinimizeButton", "ObjectiveTrackerFrame.NineSlice",
	"ObjectiveTrackerFrame.UpdateHeight", "ObjectiveTrackerFrame.ApplySystemAnchor", "ObjectiveTrackerFrame.BreakFromFrameManager",
	"ObjectiveTrackerFrame.SetPointBase", "ObjectiveTrackerFrame.ClearAllPointsBase", "ObjectiveTrackerFrame.IsInDefaultPosition",
	"ObjectiveTrackerFrame.OnSystemPositionChange", "ObjectiveTrackerFrame.SetResizeBounds",
	"EditModeManagerFrame", "EditModeManagerFrame.SaveLayouts", "EditModeManagerFrame.IsActiveLayoutPreset",
	"EditModeManagerFrame.OnSystemPositionChange", "EditModeManagerFrame.OnSystemSettingChange",
	"Enum.EditModeObjectiveTrackerSetting.Height", "C_EditMode.SaveLayouts",
	"C_XMLUtil.GetTemplateInfo", "ObjectiveTrackerLineFont", "ObjectiveTrackerHeaderFont",
	"QUEST_WATCH_QUEST_READY", "TRACKER_HEADER_QUESTS", "BackdropTemplateMixin",
	"GetQuestLogRewardXP", "C_QuestLog.GetQuestLogRewardXP", "C_QuestLog.GetNumQuestLogEntries", "C_QuestLog.GetInfo",
	"UnitXP", "UnitXPMax", "GetXPExhaustion", "IsXPUserDisabled", "GameRulesUtil.IsPlayerAtEffectiveMaxLevel", "BreakUpLargeNumbers",
	"StatusTrackingBarManager", "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer",
	"StatusTrackingBarInfo.BarsEnum.Experience", "EventRegistry.RegisterCallback", "WorldMapFrame", "QuestPinMixin",
	"GetQuestUiMapID", "C_QuestLog.GetQuestsOnMap", "C_Map.GetBestMapForUnit", "C_Map.GetMapInfo", "Enum.UIMapType",
	"GetNumLootItems", "GetLootSlotInfo", "C_Container.GetContainerItemInfo", "C_Item.GetItemInfoInstant", "C_Item.GetItemSpell",
	"EJ_GetEncounterInfo", "C_EncounterJournal.GetEncountersOnMap",
}

local function ProbeBuild()
	section("Build")
	call("GetBuildInfo()", GetBuildInfo)
	call("IsInInstance()", IsInInstance)
	call("GetZoneText()", GetZoneText)
	call("InCombatLockdown()", InCombatLockdown)
	call("IsInGroup()", IsInGroup)
	call("GetNumGroupMembers()", GetNumGroupMembers)
	if C_Secrets then call("C_Secrets.HasSecretRestrictions()", C_Secrets.HasSecretRestrictions) end
end

local function ProbeApiPresence()
	section("API presence")
	for _, name in ipairs(API_NAMES) do
		local v = lookup(name)
		out("%-58s %s", name, v == nil and "MISSING" or type(v))
	end
	if C_XMLUtil and C_XMLUtil.GetTemplateInfo then
		call("GetTemplateInfo(ObjectiveTrackerModuleHeaderTemplate)", C_XMLUtil.GetTemplateInfo, "ObjectiveTrackerModuleHeaderTemplate")
		call("GetTemplateInfo(ObjectiveTrackerBlockTemplate)", C_XMLUtil.GetTemplateInfo, "ObjectiveTrackerBlockTemplate")
	end
end

local function ProbeTrackerFrame()
	section("ObjectiveTrackerFrame")
	local f = ObjectiveTrackerFrame
	if not f then out("missing"); return end
	out("keys: %s", keys(f, 120))
	local dirty = {}
	for k, v in pairs(f) do
		if type(k) == "string" and k:lower():find("dirty") then dirty[#dirty + 1] = k .. ":" .. type(v) end
	end
	table.sort(dirty)
	out("dirty-related keys: %s", #dirty > 0 and table.concat(dirty, " ") or "none")
	call("GetPoint(1)", f.GetPoint, f, 1)
	call("GetNumPoints()", f.GetNumPoints, f)
	call("GetHeight()", f.GetHeight, f)
	call("GetWidth()", f.GetWidth, f)
	call("GetScale()", f.GetScale, f)
	call("IsInDefaultPosition()", f.IsInDefaultPosition, f)
	out("editModeHeight = %s   system = %s   systemIndex = %s", fmtv(f.editModeHeight), fmtv(f.system), fmtv(f.systemIndex))
	out("isCollapsed = %s   topModulePadding = %s", fmtv(f.isCollapsed), fmtv(f.topModulePadding))
	if type(f.systemInfo) == "table" then
		out("systemInfo.isInDefaultPosition = %s", fmtv(f.systemInfo.isInDefaultPosition))
		out("systemInfo.anchorInfo = %s", fmtv(f.systemInfo.anchorInfo))
		out("systemInfo.settings = %s", fmtv(f.systemInfo.settings))
	end
	if f.Header then
		out("Header keys: %s", keys(f.Header, 60))
		call("Header:GetSize()", f.Header.GetSize, f.Header)
	end
	if EditModeManagerFrame then
		call("EditModeManagerFrame:IsEditModeActive()", EditModeManagerFrame.IsEditModeActive, EditModeManagerFrame)
		call("EditModeManagerFrame:IsActiveLayoutPreset()", EditModeManagerFrame.IsActiveLayoutPreset, EditModeManagerFrame)
		local ok, info = pcall(EditModeManagerFrame.GetActiveLayoutInfo, EditModeManagerFrame)
		if ok and type(info) == "table" then
			out("active layout: name=%s type=%s", fmtv(info.layoutName), fmtv(info.layoutType))
		end
	end
	local modules = f.modules
	if type(modules) == "table" then
		local names = {}
		for i, m in ipairs(modules) do
			local okN, n = pcall(m.GetName, m)
			names[#names + 1] = ("%d:%s(order=%s,shown=%s)"):format(i, okN and tostring(n) or "?", fmtv(m.uiOrder), fmtv(m:IsShown()))
		end
		out("modules: %s", table.concat(names, " "))
	end
end

local function ProbeQuestModule()
	section("QuestObjectiveTracker")
	local m = QuestObjectiveTracker
	if not m then out("missing"); return end
	out("keys: %s", keys(m, 120))
	out("headerHeight=%s fromHeaderOffsetY=%s fromBlockOffsetY=%s blockOffsetX=%s lineSpacing=%s bottomSpacing=%s",
		fmtv(m.headerHeight), fmtv(m.fromHeaderOffsetY), fmtv(m.fromBlockOffsetY), fmtv(m.blockOffsetX), fmtv(m.lineSpacing), fmtv(m.bottomSpacing))
	out("contentsHeight=%s availableHeight=%s state=%s isCollapsed=%s hasContents=%s", fmtv(m.contentsHeight), fmtv(m.availableHeight), fmtv(m.state), fmtv(m.isCollapsed), fmtv(m.hasContents))
	call("GetHeight()", m.GetHeight, m)
	call("IsShown()", m.IsShown, m)
	if m.Header and m.Header.Text then call("Header.Text:GetText()", m.Header.Text.GetText, m.Header.Text) end
	local b, i = m.firstBlock, 0
	while b and i < 60 do
		i = i + 1
		local regions = 0
		local regionInfo = {}
		if type(b.addedRegions) == "table" then
			for region, managed in pairs(b.addedRegions) do
				regions = regions + 1
				local okN, n = pcall(region.GetObjectType, region)
				regionInfo[#regionInfo + 1] = ("%s(parentIsBlock=%s managed=%s)"):format(okN and n or "?", tostring(region:GetParent() == b), tostring(managed))
			end
		end
		local okT, title = pcall(C_QuestLog.GetTitleForQuestID, b.id)
		out("block %d: id=%s height=%s used=%s cached=%s shown=%s poi=%s title=%s", i, fmtv(b.id), fmtv(b.height), fmtv(b.used), fmtv(b.cached), fmtv(b:IsShown()), tostring(b.poiButton ~= nil), okT and fmtv(title) or "?")
		if regions > 0 then out("   regions: %s", table.concat(regionInfo, " ")) end
		b = b.nextBlock
	end
	out("%d blocks in the firstBlock chain", i)
end

local function ProbeWatches()
	section("Tracked quests and party progress")
	local n = call("C_QuestLog.GetNumQuestWatches()", C_QuestLog.GetNumQuestWatches) or 0
	if Constants and Constants.QuestWatchConsts then
		out("MAX_QUEST_WATCHES = %s", fmtv(Constants.QuestWatchConsts.MAX_QUEST_WATCHES))
	end
	local grouped = IsInGroup()
	for i = 1, n do
		local okI, questID = pcall(C_QuestLog.GetQuestIDForQuestWatchIndex, i)
		if okI and questID then
			local okT, title = pcall(C_QuestLog.GetTitleForQuestID, questID)
			local okC, complete = pcall(C_QuestLog.IsComplete, questID)
			local okL, logIndex = pcall(C_QuestLog.GetLogIndexForQuestID, questID)
			out("-- watch %d: questID=%s title=%s complete=%s logIndex=%s", i, fmtv(questID), okT and fmtv(title) or "?", okC and fmtv(complete) or "?", okL and fmtv(logIndex) or "?")
			if QuestUtilsOverrides and QuestUtilsOverrides.GetQuestTagText then
				call("   GetQuestTagText", QuestUtilsOverrides.GetQuestTagText, questID)
			end
			if okL and type(logIndex) == "number" then
				call("   GetNumQuestLeaderBoards", GetNumQuestLeaderBoards, logIndex)
				call("   GetQuestLogLeaderBoard(1)", GetQuestLogLeaderBoard, 1, logIndex, true)
				-- quest item button: link, icon, charges, showItemWhenComplete
				call("   GetQuestLogSpecialItemInfo", GetQuestLogSpecialItemInfo, logIndex)
				if QuestUtil and QuestUtil.QuestShowsItemByIndex then
					call("   QuestUtil.QuestShowsItemByIndex(logIndex, complete)", QuestUtil.QuestShowsItemByIndex, logIndex, okC and complete)
				end
			end
			call("   C_QuestLog.IsPushableQuest", C_QuestLog.IsPushableQuest, questID)
			call("   GetQuestLogRewardXP", GetQuestLogRewardXP, questID)
			if C_TooltipInfo and C_TooltipInfo.GetQuestPartyProgress then
				for _, args in ipairs({ { false, false }, { true, true } }) do
					local okP, data = pcall(C_TooltipInfo.GetQuestPartyProgress, questID, args[1], args[2])
					if not okP then
						out("   GetQuestPartyProgress(omitTitle=%s, ignoreActivePlayer=%s) -> ERROR %s", tostring(args[1]), tostring(args[2]), tostring(data))
					elseif type(data) ~= "table" then
						out("   GetQuestPartyProgress(omitTitle=%s, ignoreActivePlayer=%s) -> %s", tostring(args[1]), tostring(args[2]), fmtv(data))
					else
						out("   GetQuestPartyProgress(omitTitle=%s, ignoreActivePlayer=%s) -> type=%s id=%s lines=%d", tostring(args[1]), tostring(args[2]), fmtv(data.type), fmtv(data.id), type(data.lines) == "table" and #data.lines or -1)
						if type(data.lines) == "table" then
							for li, line in ipairs(data.lines) do
								local color = "-"
								if type(line.leftColor) == "table" and type(line.leftColor.GetRGB) == "function" then
									local okR, r, g, b = pcall(line.leftColor.GetRGB, line.leftColor)
									if okR and accessible(r) then color = ("%.2f,%.2f,%.2f"):format(r, g, b) end
								end
								out("      line %d: type=%s left=%s right=%s leftColor=%s keys=%s", li, fmtv(line.type), fmtv(line.leftText), fmtv(line.rightText), color, keys(line, 20))
								-- exact bytes of short status lines, to see what "Not on quest" really contains
								if type(line.leftText) == "string" and accessible(line.leftText) and #line.leftText <= 24 then
									out("         bytes: %s", (line.leftText:gsub(".", function(c) return ("%02X "):format(c:byte()) end)))
								end
							end
						end
					end
				end
			end
		end
	end
	if not grouped then
		out("")
		out("NOTE: not in a group. Party progress lines only appear while grouped; invite someone and run again.")
	end
end

local function ProbeInstance()
	section("Instance and maps")
	call("IsInInstance()", IsInInstance)
	call("GetInstanceInfo()", GetInstanceInfo)
	-- quest log headers and which quests sit under them
	local header
	for i = 1, (C_QuestLog.GetNumQuestLogEntries() or 0) do
		local ok, info = pcall(C_QuestLog.GetInfo, i)
		if ok and type(info) == "table" then
			if info.isHeader then
				header = info.title
				out("  header %s", fmtv(info.title))
			else
				out("     quest %s %s", fmtv(info.questID), fmtv(info.title))
			end
		end
	end
	local mapID = call("C_Map.GetBestMapForUnit(player)", C_Map.GetBestMapForUnit, "player")
	if type(mapID) == "number" then
		local guard, m = 0, mapID
		while type(m) == "number" and guard < 8 do
			local info = C_Map.GetMapInfo(m)
			if type(info) ~= "table" then break end
			out("  map %s: name=%s type=%s parent=%s", tostring(m), fmtv(info.name), fmtv(info.mapType), fmtv(info.parentMapID))
			m = info.parentMapID
			guard = guard + 1
		end
		if C_QuestLog.GetQuestsOnMap then
			local ok, list = pcall(C_QuestLog.GetQuestsOnMap, mapID)
			if ok and type(list) == "table" then
				out("  quests on map: %d", #list)
				for i = 1, math.min(#list, 10) do out("    %s", fmtv(list[i])) end
			else
				out("  GetQuestsOnMap -> %s", ok and fmtv(list) or ("ERROR " .. tostring(list)))
			end
		end
	end
	for i = 1, (C_QuestLog.GetNumQuestWatches() or 0) do
		local id = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
		if id and type(GetQuestUiMapID) == "function" then
			call(("  GetQuestUiMapID(%d)"):format(id), GetQuestUiMapID, id)
		end
	end
end

local function ProbeXPBar()
	section("XP bar")
	call("UnitXP", UnitXP, "player")
	call("UnitXPMax", UnitXPMax, "player")
	call("GetXPExhaustion", GetXPExhaustion)
	call("UnitLevel", UnitLevel, "player")
	if GameRulesUtil then call("GameRulesUtil.IsPlayerAtEffectiveMaxLevel", GameRulesUtil.IsPlayerAtEffectiveMaxLevel) end
	local index = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum and StatusTrackingBarInfo.BarsEnum.Experience
	out("BarsEnum.Experience = %s", fmtv(index))
	for _, name in ipairs({ "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }) do
		local c = _G[name]
		if not c then
			out("%s: missing", name)
		else
			out("-- %s shown=%s shownBarIndex=%s bars=%s", name, fmtv(c:IsShown()), fmtv(c.shownBarIndex), type(c.bars) == "table" and keys(c.bars) or "<none>")
			local bar = index and type(c.bars) == "table" and c.bars[index]
			if bar then
				out("   exp bar: shown=%s isExpBar=%s size=%.1fx%.1f keys=%s", fmtv(bar:IsShown()), fmtv(bar.isExpBar), bar:GetWidth(), bar:GetHeight(), keys(bar, 40))
				if bar.ExhaustionLevelFillBar then
					local okL, layer, sub = pcall(bar.ExhaustionLevelFillBar.GetDrawLayer, bar.ExhaustionLevelFillBar)
					out("   ExhaustionLevelFillBar: shown=%s width=%.1f layer=%s/%s", fmtv(bar.ExhaustionLevelFillBar:IsShown()), bar.ExhaustionLevelFillBar:GetWidth(), okL and tostring(layer) or "?", okL and tostring(sub) or "?")
				end
				out("   ExhaustionTick=%s StatusBar=%s", type(bar.ExhaustionTick), type(bar.StatusBar))
			end
		end
	end
end

local function ProbeParty()
	section("Party members")
	for i = 1, 4 do
		local unit = "party" .. i
		local ok, exists = pcall(UnitExists, unit)
		if ok and accessible(exists) and exists then
			call(unit .. " UnitName", UnitName, unit)
			call(unit .. " UnitClass", UnitClass, unit)
			call(unit .. " UnitLevel", UnitLevel, unit)
		end
	end
end

-------------------------------------------------------------------------------
-- Copy window (plain ScrollFrame + MinimalScrollBar; UIPanelScrollFrameTemplate is gone)
-------------------------------------------------------------------------------

local win
local function ShowWindow(text)
	if not win then
		win = CreateFrame("Frame", "QuestObjectivesPlusProbeWindow", UIParent, "BackdropTemplate")
		win:SetSize(760, 520)
		win:SetPoint("CENTER")
		win:SetFrameStrata("DIALOG")
		win:SetMovable(true); win:EnableMouse(true)
		win:RegisterForDrag("LeftButton")
		win:SetScript("OnDragStart", win.StartMoving)
		win:SetScript("OnDragStop", win.StopMovingOrSizing)
		if win.SetBackdrop then
			win:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
		end
		local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		title:SetPoint("TOP", 0, -16)
		title:SetText("Quest Objectives+ probe  (Ctrl+A, Ctrl+C to copy, Esc to close)")
		local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -8, -8)

		local scroll = CreateFrame("ScrollFrame", "QuestObjectivesPlusProbeScroll", win)
		scroll:SetPoint("TOPLEFT", 20, -40)
		scroll:SetPoint("BOTTOMRIGHT", -40, 20)
		local edit = CreateFrame("EditBox", nil, scroll)
		edit:SetMultiLine(true)
		edit:SetFontObject(ChatFontSmall)
		edit:SetWidth(690)
		edit:SetAutoFocus(false)
		edit:SetScript("OnEscapePressed", function() win:Hide() end)
		scroll:SetScrollChild(edit)
		scroll:SetScript("OnSizeChanged", function(_, width) edit:SetWidth(width) end)

		local okBar, bar = pcall(CreateFrame, "EventFrame", nil, win, "MinimalScrollBar")
		if okBar and bar and ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar then
			bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
			bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
			ScrollUtil.InitScrollFrameWithScrollBar(scroll, bar)
		else
			scroll:EnableMouseWheel(true)
			scroll:SetScript("OnMouseWheel", function(self, delta)
				local maxScroll = math.max(0, edit:GetHeight() - self:GetHeight())
				local target = self:GetVerticalScroll() - delta * 40
				self:SetVerticalScroll(math.max(0, math.min(maxScroll, target)))
			end)
		end
		win.edit = edit
		tinsert(UISpecialFrames, "QuestObjectivesPlusProbeWindow")
	end
	win.edit:SetText(text)
	win:Show()
	win.edit:SetFocus()
	win.edit:HighlightText()
end

-------------------------------------------------------------------------------

-- Design checks (9 Nov 2026)
-------------------------------------------------------------------------------

local trail = {}
local PREFIX = "QOPP"
local SHARE_WATCH_SECONDS = 20
local WATCH_MIN_GAP = 10
local NAME_BATCH, NAME_TICK, NAME_IDLE_TIMEOUT = 20, 0.25, 15

local function note(fmt, ...)
	local s = fmt
	if select("#", ...) > 0 then
		local ok, r = pcall(string.format, fmt, ...)
		s = ok and r or (fmt .. " (format error: " .. tostring(r) .. ")")
	end
	trail[#trail + 1] = ("[%.1f] %s"):format(GetTime(), s)
end

local function say(fmt, ...)
	note(fmt, ...)
	print("|cff66ccffQOP probe:|r " .. trail[#trail])
end

local function context(label)
	local inInstance, kind = IsInInstance()
	local restricted = C_Secrets and C_Secrets.HasSecretRestrictions and C_Secrets.HasSecretRestrictions()
	note("--- %s: combat=%s instance=%s/%s group=%s members=%s secretRestrictions=%s", label,
		fmtv(InCombatLockdown()), fmtv(inInstance), fmtv(kind), fmtv(IsInGroup()), fmtv(GetNumGroupMembers()), fmtv(restricted))
end

local function titleOf(questID)
	local ok, title = pcall(C_QuestLog.GetTitleForQuestID, questID)
	return ok and fmtv(title) or "?"
end

-- quest IDs in the log, without the headers, at most `max`
local function LogQuests(max)
	local ids = {}
	for i = 1, (C_QuestLog.GetNumQuestLogEntries() or 0) do
		local ok, info = pcall(C_QuestLog.GetInfo, i)
		if ok and type(info) == "table" and not info.isHeader and type(info.questID) == "number" then
			ids[#ids + 1] = info.questID
			if max and #ids >= max then break end
		end
	end
	return ids
end

local function DumpPartyData(questID, verbose)
	if not (C_TooltipInfo and C_TooltipInfo.GetQuestPartyProgress) then
		note("GetQuestPartyProgress is missing")
		return
	end
	local ok, data = pcall(C_TooltipInfo.GetQuestPartyProgress, questID, true, true)
	if not ok then
		note("quest %s %s: ERROR %s", tostring(questID), titleOf(questID), tostring(data))
		return
	end
	if type(data) ~= "table" or type(data.lines) ~= "table" then
		note("quest %s %s: no line data (%s)", tostring(questID), titleOf(questID), fmtv(data))
		return
	end
	local secret = 0
	for i, line in ipairs(data.lines) do
		if not accessible(line.leftText) then secret = secret + 1 end
		if verbose then
			note("   line %d: type=%s left=%s completed=%s", i, fmtv(line.type), fmtv(line.leftText), fmtv(line.completed))
		end
	end
	note("quest %s %s: %d lines, %d secret", tostring(questID), titleOf(questID), #data.lines, secret)
end

-- Q1: share from code, with no click anywhere in the call chain ---------------

local shareArmed = false
local shareWatchUntil = 0

local function ListPushMessages()
	local names = {}
	for k, v in pairs(_G) do
		if type(k) == "string" and k:find("^ERR_QUEST_PUSH") then
			names[#names + 1] = k .. " = " .. fmtv(v)
		end
	end
	table.sort(names)
	note("%d ERR_QUEST_PUSH globals", #names)
	for _, entry in ipairs(names) do note("   %s", entry) end
end

-- the same path the addon's Share button uses
local function PushFromCode(questID)
	context("share attempt")
	note("quest %s %s pushable=%s", tostring(questID), titleOf(questID), fmtv(C_QuestLog.IsPushableQuest(questID)))
	shareWatchUntil = GetTime() + SHARE_WATCH_SECONDS
	local path, ok, err
	if QuestUtil and type(QuestUtil.ShareQuest) == "function" then
		path = "QuestUtil.ShareQuest"
		ok, err = pcall(QuestUtil.ShareQuest, questID)
	else
		path = "SetSelectedQuest + QuestLogPushQuest"
		pcall(C_QuestLog.SetSelectedQuest, questID)
		ok, err = pcall(QuestLogPushQuest)
	end
	say("%s from code -> ok=%s err=%s. Did the party member get the offer? Replies are logged for %d s.",
		path, tostring(ok), fmtv(err), SHARE_WATCH_SECONDS)
end

local function CmdShare(rest)
	if not IsInGroup() then say("share: join a party first; the offer needs someone to reach"); return end
	ListPushMessages()
	if rest == "now" then
		for _, id in ipairs(LogQuests()) do
			if C_QuestLog.IsPushableQuest(id) and not C_QuestLog.IsComplete(id) then
				say("share: sharing %s %s in 3 s from a timer", tostring(id), titleOf(id))
				C_Timer.After(3, function() PushFromCode(id) end)
				return
			end
		end
		say("share: no shareable, unfinished quest in your log")
		return
	end
	shareArmed = true
	say("share: armed. Accept a shareable quest; it is shared 2 s later, once.")
end

-- Q2: party data for a quest you do not hold -----------------------------------

local recentlyRemoved = {}

local function CmdNotHeld(rest)
	context("not-held check")
	local control = LogQuests(1)[1]
	if control then
		note("control, a quest you hold:")
		DumpPartyData(control, true)
	end
	local given = tonumber(rest)
	local targets = given and { given } or recentlyRemoved
	if #targets == 0 then
		say("notheld: abandon a quest your party member still has, then run this again (or pass a quest ID)")
		return
	end
	for _, id in ipairs(targets) do
		note("not held: %s", tostring(id))
		note("   still in my log = %s", fmtv(C_QuestLog.GetLogIndexForQuestID(id)))
		DumpPartyData(id, true)
	end
	say("notheld: checked %d quest(s). The member's progress in the lines means the audit can see it without addon messages.", #targets)
end

-- Q3: what still works in combat and in instances -------------------------------

local pingSeq = 0
-- Marks our own messages when they echo back. Comparing the sender with
-- UnitName failed on a First Last character name (ping answered itself).
local SESSION_MARK = (":from=%05d"):format(math.random(0, 99999))

local function GroupChannel()
	if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
	if IsInGroup() then return "PARTY" end
	return nil
end

local function Send(text)
	local channel = GroupChannel()
	if not channel then note("addon message not sent: not in a group"); return end
	text = text .. SESSION_MARK
	local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, channel)
	note("sent %d bytes on %s -> ok=%s result=%s", #text, channel, tostring(ok), fmtv(result))
end

local function SendPing()
	pingSeq = pingSeq + 1
	Send(("ping:%d:combat=%d:instance=%d"):format(pingSeq, InCombatLockdown() and 1 or 0, IsInInstance() and 1 or 0))
end

local function Snapshot(label, verbose)
	context(label)
	for _, id in ipairs(LogQuests(3)) do DumpPartyData(id, verbose) end
	SendPing()
end

local function CmdAccess()
	Snapshot("access check", true)
	-- about the size of one packet of a quest-list message
	Send("long:" .. string.rep("12345,", 39))
	say("access: snapshot logged. A party member running the probe answers pings automatically.")
end

local watching = false
local lastWatch = 0

local function CmdWatch()
	watching = not watching
	say("watch: %s", watching and "on, a snapshot on every pull, boss and loading screen" or "off")
end

local function OnWatchTrigger(label)
	if not watching or GetTime() - lastWatch < WATCH_MIN_GAP then return end
	lastWatch = GetTime()
	C_Timer.After(1, function() Snapshot(label, false) end)
end

local function OnAddonMessage(prefix, text, channel, sender)
	if not accessible(prefix) then note("addon message with a secret prefix"); return end
	if prefix ~= PREFIX then return end
	local readable = accessible(text) and accessible(sender)
	local mine = readable and text:find(SESSION_MARK, 1, true) ~= nil
	local shown = readable and ("%d bytes %q"):format(#text, text:sub(1, 40)) or "<secret>"
	context("addon message received")
	-- how names arrive matters for the audit: First Last characters
	note("names: sender=%s UnitName(player)=%s", fmtv(sender), fmtv(UnitName("player")))
	if mine then
		note("own echo on %s: %s", fmtv(channel), shown)
		return
	end
	say("from %s on %s: %s", fmtv(sender), fmtv(channel), shown)
	local seq = readable and text:match("^ping:(%d+)")
	if seq then Send("pong:" .. seq) end
end

-- Q4: completed quests and loading their names ----------------------------------

local nameLoad

local function FinishNameLoad()
	local run = nameLoad
	nameLoad = nil
	run.ticker:Cancel()
	local elapsed = GetTime() - run.started
	local titled, samples = 0, {}
	for _, id in ipairs(run.sample) do
		local title = C_QuestLog.GetTitleForQuestID(id)
		if type(title) == "string" and accessible(title) and title ~= "" then
			titled = titled + 1
			if #samples < 15 then samples[#samples + 1] = ("%d=%s"):format(id, title) end
		end
	end
	local rate = run.loaded > 0 and run.loaded / math.max(elapsed, 0.01) or 0
	note("requested %d: loaded=%d failed=%d no reply=%d, titled afterwards=%d, in %.1f s",
		#run.sample, run.loaded, run.failed, #run.sample - run.loaded - run.failed, titled, elapsed)
	note("sample titles: %s", table.concat(samples, " | "))
	say("completed: %.0f names per second; the %d unnamed quests would take about %.0f s",
		rate, run.uncached, rate > 0 and run.uncached / rate or -1)
end

local function CmdCompleted(rest)
	if nameLoad then say("completed: already running"); return end
	context("completed quests")
	local started = debugprofilestop()
	local ids = C_QuestLog.GetAllCompletedQuestIDs()
	note("GetAllCompletedQuestIDs -> %s ids in %.1f ms", type(ids) == "table" and #ids or fmtv(ids), debugprofilestop() - started)
	if type(ids) ~= "table" then return end
	local uncached = {}
	started = debugprofilestop()
	for _, id in ipairs(ids) do
		local title = C_QuestLog.GetTitleForQuestID(id)
		if not (type(title) == "string" and accessible(title) and title ~= "") then uncached[#uncached + 1] = id end
	end
	note("named already: %d, not loaded: %d (scan %.1f ms)", #ids - #uncached, #uncached, debugprofilestop() - started)
	if #uncached == 0 then say("completed: every name is already loaded"); return end
	-- spread across the list, so low and high IDs are both represented
	local want = math.min(tonumber(rest) or 200, #uncached)
	local sample, inSample, step = {}, {}, #uncached / want
	for i = 1, want do
		local id = uncached[math.floor((i - 1) * step) + 1]
		sample[#sample + 1] = id
		inSample[id] = true
	end
	local nextIndex = 1
	nameLoad = { sample = sample, inSample = inSample, loaded = 0, failed = 0, uncached = #uncached, started = GetTime(), lastReply = GetTime() }
	nameLoad.ticker = C_Timer.NewTicker(NAME_TICK, function()
		for _ = 1, NAME_BATCH do
			if nextIndex > #sample then break end
			pcall(C_QuestLog.RequestLoadQuestByID, sample[nextIndex])
			nextIndex = nextIndex + 1
		end
		local replied = nameLoad.loaded + nameLoad.failed
		if replied >= #sample or (nextIndex > #sample and GetTime() - nameLoad.lastReply > NAME_IDLE_TIMEOUT) then
			FinishNameLoad()
		end
	end)
	say("completed: %d ids, %d without a name; loading %d now", #ids, #uncached, want)
end

local DESIGN_COMMANDS = {
	share = CmdShare,
	notheld = CmdNotHeld,
	access = CmdAccess,
	watch = CmdWatch,
	completed = CmdCompleted,
	report = function()
		ShowWindow(#trail > 0 and table.concat(trail, "\n") or "The log is empty.")
	end,
	clear = function()
		wipe(trail)
		print("|cff66ccffQOP probe:|r log cleared")
	end,
}

local checks = CreateFrame("Frame")
for _, event in ipairs({
	"QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_DATA_LOAD_RESULT", "CHAT_MSG_SYSTEM", "CHAT_MSG_ADDON",
	"ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "PLAYER_REGEN_DISABLED", "ENCOUNTER_START", "PLAYER_ENTERING_WORLD",
}) do
	checks:RegisterEvent(event)
end
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
	C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end

checks:SetScript("OnEvent", function(_, event, a, b, c, d)
	if event == "QUEST_ACCEPTED" then
		local questID = type(b) == "number" and b or a
		if shareArmed and type(questID) == "number" then
			shareArmed = false
			note("QUEST_ACCEPTED args: %s, %s", fmtv(a), fmtv(b))
			C_Timer.After(2, function() PushFromCode(questID) end)
		end
	elseif event == "QUEST_REMOVED" then
		if type(a) == "number" then
			table.insert(recentlyRemoved, 1, a)
			recentlyRemoved[6] = nil
		end
	elseif event == "QUEST_DATA_LOAD_RESULT" then
		if nameLoad and nameLoad.inSample[a] then
			nameLoad.inSample[a] = nil
			nameLoad.lastReply = GetTime()
			if b then nameLoad.loaded = nameLoad.loaded + 1 else nameLoad.failed = nameLoad.failed + 1 end
		end
	elseif event == "CHAT_MSG_SYSTEM" then
		if GetTime() < shareWatchUntil then note("system message: %s", fmtv(a)) end
	elseif event == "CHAT_MSG_ADDON" then
		OnAddonMessage(a, b, c, d)
	elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
		if GetTime() < shareWatchUntil then say("%s: %s tried %s", event, fmtv(a), fmtv(b)) end
	else
		OnWatchTrigger(event)
	end
end)

-------------------------------------------------------------------------------

local function Run(arg)
	local command, rest = arg:match("^(%S+)%s*(.*)$")
	if command and DESIGN_COMMANDS[command] then
		DESIGN_COMMANDS[command](rest)
		return
	end
	lines = {}
	toChat = (arg == "chat")
	ProbeBuild()
	ProbeApiPresence()
	ProbeTrackerFrame()
	ProbeQuestModule()
	ProbeWatches()
	ProbeInstance()
	ProbeXPBar()
	ProbeParty()
	ShowWindow(table.concat(lines, "\n"))
	print("|cff66ccffQOP probe:|r " .. #lines .. " lines collected; copy them from the window.")
end

SLASH_QOPPROBE1 = "/qopprobe"
SlashCmdList.QOPPROBE = function(msg)
	local ok, err = pcall(Run, strtrim((msg or ""):lower()))
	if not ok then print("|cffff4444QOP probe error:|r " .. tostring(err)) end
end
