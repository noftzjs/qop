--[[
	Quest Objectives+ probe (dev only)
	/qopprobe        -> run all probes, open a copyable window with the report
	/qopprobe chat   -> same, but also print every line to chat

	Before running: be in a party with at least one member who shares a quest
	with you, track a few quests (some finished), and stand out of combat.
	Run it again in combat and in a dungeon to see which values go secret.
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

local function Run(arg)
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
