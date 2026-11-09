--[[
	Quest Objectives+
	Tidies Blizzard's quest tracker on WoW Forever without replacing it:
	  * finished quests move under a collapsible "Ready for turn-in" header
	  * party members' progress is listed under each quest, read from the same
	    party-progress data the game's tooltip uses (nobody else needs the addon)
	  * the tracker can be dragged by its title bar and resized with a grip

	How it stays safe: Blizzard lays the tracker out exactly as before, so the
	quest item buttons keep their secure state. Afterwards this addon only
	re-anchors, shows, hides and resizes frames. It never writes into Blizzard's
	tracker tables, never calls MarkDirty and never goes through the Edit Mode
	SetPoint override, because tainting the layout would block quest items in
	combat.

	Slash commands: /qop  (type /qop for help)
]]

local ADDON_NAME = ...

local QOP = CreateFrame("Frame", "QuestObjectivesPlusFrame")
_G.QuestObjectivesPlus = QOP

-------------------------------------------------------------------------------
-- Settings
-------------------------------------------------------------------------------

local DEFAULTS = {
	enabled   = true,
	group     = true,   -- finished quests under a "Ready for turn-in" header
	collapsed = false,  -- that header's state, remembered across sessions
	questsCollapsed = false,  -- our own collapse of the Quests section (click its header)
	party     = true,   -- party members' progress under each quest
	compact   = true,   -- one line per status with the members on it, not one per member
	share     = true,   -- "Not on quest: Name [Share]" line on shareable quests
	counts    = true,   -- active-quest count on the "Quests" header
	maptip    = true,   -- party progress on world map quest pin tooltips
	xp        = true,   -- pending turn-in XP on the XP bar and the section header
	items     = false,  -- column of usable quest items from your bags beside the tracker (fallback; Blizzard's own item buttons are the default)
	instance  = true,   -- inside a dungeon, its quests first in each section
	zone      = true,   -- outside, the current zone's quests first in each section
	sort      = "none", -- within each section: "none" (Blizzard's order), "asc" or "desc" by level
	unshareable = {},   -- questID -> { [first name] = reason }: members who can never take it (completed, class, race, faction)
	locked    = false,  -- true disables dragging and resizing
	position  = false,  -- { point, relativePoint, x, y } from the last drag
	height    = false,  -- from the last resize
	width     = false,  -- from the last resize
}

local settings
local debug = false
local tracker, questModule   -- ObjectiveTrackerFrame, QuestObjectiveTracker

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function Print(fmt, ...)
	if select("#", ...) > 0 then fmt = fmt:format(...) end
	print("|cff66ccffQOP:|r " .. fmt)
end

local function Debug(fmt, ...)
	if debug then Print("|cff999999" .. fmt .. "|r", ...) end
end

-- Some values come back secret in combat. A secret cannot even be tested with
-- "if", so every such read goes through here.
local function Accessible(v)
	if v == nil then return false end
	if type(canaccessvalue) == "function" then return canaccessvalue(v) end
	return true
end

local function Safe(default, fn, ...)
	if type(fn) ~= "function" then return default end
	local ok, v = pcall(fn, ...)
	if not ok or not Accessible(v) then return default end
	return v
end

-- pcall that records the error for /qop err and returns a default, so one
-- bad quest's data cannot abort a whole layout pass
local function Guarded(default, fn, ...)
	local ok, v = pcall(fn, ...)
	if ok then return v end
	QOP.lastError = tostring(v)
	if debug then Print("error: %s", tostring(v)) end
	return default
end

local function CopyDefaults(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			CopyDefaults(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

-- Blizzard lays blocks out in watch order and stops at the first one that
-- does not fit the frame, so finished quests early in the list could crowd
-- active ones out before we ever saw them. The frame is therefore kept tall
-- enough for every tracked quest (LAYOUT_HEIGHT) and the height the user sees
-- and resizes (db.height) is enforced by the reflow, which cuts finished
-- quests first. See ApplyFrameHeight.
local LAYOUT_HEIGHT = 2500
local DEFAULT_VISIBLE_HEIGHT = 600

-- move/resize state (see "Move and resize"); `bounds` is the visible
-- rectangle and the frame the grip actually resizes
local dragHandle, resizeGrip, resizeOutline, visibleBounds, isSizing, isDragging

local function VisibleHeight()
	if isSizing and visibleBounds then return visibleBounds:GetHeight() end
	return (settings and settings.height) or DEFAULT_VISIBLE_HEIGHT
end

local READY_TEXT = QUEST_WATCH_QUEST_READY or "Ready for turn-in"
local QUESTS_TEXT = TRACKER_HEADER_QUESTS or "Quests"

local Reflow -- defined further down, used by the section header and events
local IsCompleteForMe -- defined further down, used by CanShare above its definition
local UpdateGrip -- defined further down, used by the collapse hook in SetupMoveResize
local RequestReflow -- defined further down, used by the share-reply handler

-------------------------------------------------------------------------------
-- Party progress (C_TooltipInfo.GetQuestPartyProgress)
-------------------------------------------------------------------------------

local partyProgressCache = {}   -- questID -> lines from the last readable call
local reportedStatus = {}   -- status texts already dumped by /qop debug

-- Line types seen in the probe (17 Oct 2026): 18 = a party member's name
-- (gold, carries .guid), 8 = a status or objective line under that member
-- ("Ready for turn-in", "Not on quest", "0/1 Sit near the campfire") with
-- .completed and, for objectives, .numFulfilled/.numRequired.
local LINE_MEMBER, LINE_STATUS = 18, 8

-- "Not on quest" is matched by text. The game's string is
-- QUEST_PROGRESS_TOOLTIP_NOT_ON_QUEST = "|cff7f7f7fNot on quest|r" (Forever
-- GlobalStrings, 18 Oct 2026): a colour code is baked into it, which is why
-- the literal never matched. Keys drop colour codes and keep lowercase
-- letters only; the global is used when present so other locales work.
local function StatusKey(s)
	s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	return (s:lower():gsub("[^%a]", ""))
end

local NOT_ON_QUEST_KEYS = { [StatusKey("Not on quest")] = true }
for _, key in ipairs({ "QUEST_PROGRESS_TOOLTIP_NOT_ON_QUEST", "QUEST_PARTY_PROGRESS_NOT_ON_QUEST", "QUEST_TOOLTIP_NOT_ON_QUEST" }) do
	if type(_G[key]) == "string" then NOT_ON_QUEST_KEYS[StatusKey(_G[key])] = true end
end

local NOT_ON_QUEST_LABEL = "Not on quest:"

local COLOR_DONE, COLOR_PROGRESS, COLOR_NAME = "|cff66dd66", "|cffdddddd", "|cffffd100"

local function ColoredName(name, guid)
	if type(guid) == "string" and Accessible(guid) and type(GetPlayerInfoByGUID) == "function" then
		local ok, _, class = pcall(GetPlayerInfoByGUID, guid)
		if ok and type(class) == "string" and Accessible(class) then
			local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
			if c and c.colorStr then return "|c" .. c.colorStr .. name .. "|r" end
		end
	end
	return COLOR_NAME .. name .. "|r"
end

-------------------------------------------------------------------------------
-- Share results: who cannot take a quest
-------------------------------------------------------------------------------

-- After a share the game answers in system messages ("Caracca Ghoulhunter
-- has completed that quest."). They name no quest, so they are matched to
-- the quest shared most recently (ours or from the quest log) within a few
-- seconds. Replies that can never change for that character (completed,
-- wrong class, race or faction) are remembered in settings.unshareable;
-- ones that can (level, prerequisites, reputation, eligibility) only for
-- the session. Such members leave the Not-on-quest line, the Share button
-- goes when nobody shareable is left, and a member who can never take the
-- quest no longer blocks "party all done". Global names checked against
-- Forever's GlobalStrings on 18 Oct 2026 (ALREADY_DONE, not ALLDONE).

local lastShare = { questID = nil, at = 0 }
local cannotTake = {}   -- questID -> { [first name] = reason }, session only
local SHARE_REPLY_WINDOW = 15

local function FirstName(name)
	return type(name) == "string" and name:match("^(%S+)") or name
end

local function NoteShare(questID)
	if type(questID) == "number" then
		lastShare.questID, lastShare.at = questID, GetTime()
	end
end

-- "%s has completed that quest." -> "^(.+) has completed that quest%.$"
local function PatternFromGlobal(key)
	local text = _G[key]
	if type(text) ~= "string" then return nil end
	text = text:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
	text = text:gsub("%%%%s", "(.+)")
	return "^" .. text .. "$"
end

local shareReplies   -- built on first use, after globals are loaded
local function ShareReplies()
	if shareReplies then return shareReplies end
	shareReplies = {}
	local function add(key, reason)
		local pattern = PatternFromGlobal(key)
		if pattern then shareReplies[#shareReplies + 1] = { pattern = pattern, reason = reason } end
	end
	-- permanent for that character
	add("ERR_QUEST_PUSH_ALREADY_DONE_S", "completed")
	add("ERR_QUEST_PUSH_CLASS_S", "class")
	add("ERR_QUEST_PUSH_RACE_S", "race")
	add("ERR_QUEST_PUSH_WRONG_FACTION_S", "faction")
	-- may change later: session only. Level replies are deliberately not
	-- remembered: a member close to levelling should stay shareable (user
	-- choice, 18 Oct 2026).
	add("ERR_QUEST_PUSH_PREREQUISITE_S", "prerequisite")
	add("ERR_QUEST_PUSH_LOW_FACTION_S", "reputation")
	add("ERR_QUEST_PUSH_HIGH_FACTION_S", "reputation")
	add("ERR_QUEST_PUSH_INVALID_S", "ineligible")
	add("ERR_QUEST_PUSH_EXPANSION_S", "ineligible")
	if #shareReplies == 0 then
		-- no globals found (unexpected): fall back to the English texts
		shareReplies[1] = { pattern = "^(.+) has completed that quest%.$", reason = "completed" }
		shareReplies[2] = { pattern = "^(.+) is not eligible for that quest%.$", reason = "ineligible" }
	end
	return shareReplies
end

local PERMANENT_REASONS = { completed = true, class = true, race = true, faction = true }

local function OnSystemMessage(text)
	if type(text) ~= "string" or not Accessible(text) then return end
	local questID = lastShare.questID
	if not questID or GetTime() - lastShare.at > SHARE_REPLY_WINDOW then return end
	for _, reply in ipairs(ShareReplies()) do
		local name = text:match(reply.pattern)
		if name then
			local first = FirstName(name)
			local store = PERMANENT_REASONS[reply.reason] and settings.unshareable or cannotTake
			store[questID] = store[questID] or {}
			store[questID][first] = reply.reason
			Debug("share reply for quest %d: %s %s", questID, first, reply.reason)
			RequestReflow()
			return
		end
	end
end

-- a member who can never take this quest on this character
local function PermanentlyUnshareable(questID, firstName)
	local byQuest = settings and settings.unshareable and settings.unshareable[questID]
	return byQuest ~= nil and byQuest[firstName] ~= nil
end

local function CannotBeShared(questID, firstName)
	if PermanentlyUnshareable(questID, firstName) then return true end
	local byQuest = cannotTake[questID]
	return byQuest ~= nil and byQuest[firstName] ~= nil
end

-- Party progress for this quest, built from the data the game's own
-- party-progress tooltip uses, without the title and without our own entry.
-- Returns three values, or nil when the data cannot be read right now
-- (missing API, secret values):
--   lines    list of { text }: compact mode gives one line per status with
--            the members on it ("Emilton, Dinna: Ready for turn-in"), else
--            one per member ("Fump: 0/1 Sit near the campfire"); empty when
--            nobody else in the party is on the quest
--   notOn    members not on the quest, as { text = coloured name, name = first name }
--   allDone  true when every party member is on it and has finished it
--   working  true when at least one member is on it and has not finished
local function ReadPartyLines(questID)
	if not C_TooltipInfo or type(C_TooltipInfo.GetQuestPartyProgress) ~= "function" then return nil end
	local ok, data = pcall(C_TooltipInfo.GetQuestPartyProgress, questID, true, true)
	if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end

	local membersOnQuest, notOnQuest, member = {}, {}, nil
	local function flush()
		if member then
			if not member.on then
				notOnQuest[#notOnQuest + 1] = { text = member.name, name = member.plain }
			elseif #member.status > 0 then
				membersOnQuest[#membersOnQuest + 1] = member
			end
		end
		member = nil
	end

	for _, line in ipairs(data.lines) do
		local text = line.leftText
		if text ~= nil and not Accessible(text) then return nil end
		if type(text) ~= "string" or text == "" then
			-- nothing to show
		elseif line.type == LINE_MEMBER then
			flush()
			member = { name = ColoredName(text, line.guid), plain = FirstName(text), status = {}, on = true, complete = true }
		elseif member and (line.type == LINE_STATUS or line.type == nil) then
			local key = StatusKey(text)
			if NOT_ON_QUEST_KEYS[key] then
				member.on = false
			else
				if debug and not reportedStatus[text] then
					-- what does a status we did not recognise really contain?
					reportedStatus[text] = true
					Debug("status %q key=%q type=%s bytes=%s", text, key, tostring(line.type),
						(text:gsub(".", function(c) return ("%02X "):format(c:byte()) end)))
				end
				local done = Accessible(line.completed) and line.completed == true
				member.status[#member.status + 1] = (done and COLOR_DONE or COLOR_PROGRESS) .. text .. "|r"
				if not done then member.complete = false end
			end
		end
	end
	flush()

	-- members who can never take the quest (completed it, wrong class...) do
	-- not hold it back
	local stillMissing = 0
	for _, entry in ipairs(notOnQuest) do
		if not PermanentlyUnshareable(questID, entry.name) then stillMissing = stillMissing + 1 end
	end
	local partyAllDone = #membersOnQuest > 0 and stillMissing == 0
	local lines = {}
	if settings and settings.compact then
		-- members with the same status share a line, in first-seen order
		local membersByStatus, statusOrder = {}, {}
		for _, eachMember in ipairs(membersOnQuest) do
			local key = table.concat(eachMember.status, ", ")
			if not membersByStatus[key] then
				membersByStatus[key] = {}
				statusOrder[#statusOrder + 1] = key
			end
			table.insert(membersByStatus[key], eachMember.name)
		end
		for _, key in ipairs(statusOrder) do
			lines[#lines + 1] = { text = table.concat(membersByStatus[key], ", ") .. ": " .. key }
		end
	else
		for _, eachMember in ipairs(membersOnQuest) do
			lines[#lines + 1] = { text = eachMember.name .. ": " .. table.concat(eachMember.status, ", ") }
		end
	end
	local partyWorking = false
	for _, eachMember in ipairs(membersOnQuest) do
		if not eachMember.complete then
			partyAllDone = false
			partyWorking = true
		end
	end
	return lines, notOnQuest, partyAllDone, partyWorking
end

local function PartyLines(questID)
	local lines, notOnQuest, partyAllDone, partyWorking = ReadPartyLines(questID)
	if lines then
		partyProgressCache[questID] = { lines = lines, notOnQuest = notOnQuest, partyAllDone = partyAllDone, partyWorking = partyWorking }
	else
		local cached = partyProgressCache[questID]
		if cached then lines, notOnQuest, partyAllDone, partyWorking = cached.lines, cached.notOnQuest, cached.partyAllDone, cached.partyWorking end
	end
	return lines, notOnQuest, partyAllDone, partyWorking
end

-- What Blizzard's own "Share Quest" context-menu entry does.
local function ShareQuest(questID)
	if type(questID) ~= "number" then return end
	NoteShare(questID)
	if QuestUtil and type(QuestUtil.ShareQuest) == "function" then
		pcall(QuestUtil.ShareQuest, questID)
	elseif C_QuestLog.SetSelectedQuest and QuestLogPushQuest then
		pcall(C_QuestLog.SetSelectedQuest, questID)
		pcall(QuestLogPushQuest)
	end
end

local function CanShare(questID)
	return type(questID) == "number" and not IsCompleteForMe(questID) and Safe(false, C_QuestLog.IsPushableQuest, questID)
end

-------------------------------------------------------------------------------
-- Extra lines under a block (our own frames, parented to Blizzard's block)
-------------------------------------------------------------------------------

local partyLineFrames = {}        -- block -> frame holding our lines under that block
local PARTY_LINE_INDENT = 10
local PARTY_LINE_SPACING = 2
local PARTY_LINE_PAD = 3      -- above the first and below the last party line

local function GetPartyLinesFrame(block)
	local f = partyLineFrames[block]
	if not f then
		f = CreateFrame("Frame", nil, block)
		f:SetPoint("TOPLEFT", block, "BOTTOMLEFT", 0, 0)
		f:SetPoint("RIGHT", block, "RIGHT", 0, 0)
		f:SetHeight(1)
		f.lines = {}
		partyLineFrames[block] = f
	end
	return f
end

local SHARE_BUTTON_WIDTH = 50

local function GetShareButton(f)
	local btn = f.share
	if btn then return btn end
	-- the quest log's own Share button is a UIPanelButtonTemplate; a small
	-- one of those keeps the game's look (user request, 18 Oct 2026)
	local ok
	ok, btn = pcall(CreateFrame, "Button", nil, f, "UIPanelButtonTemplate")
	if ok and btn and type(btn.SetText) == "function" then
		btn:SetSize(SHARE_BUTTON_WIDTH - 4, 16)
		btn:SetText(SHARE_QUEST_ABBREV or "Share")
		btn:SetNormalFontObject(GameFontNormalSmall)
		btn:SetHighlightFontObject(GameFontHighlightSmall)
		if btn.SetDisabledFontObject then btn:SetDisabledFontObject(GameFontDisableSmall) end
	else
		btn = CreateFrame("Button", nil, f)
		btn:SetSize(SHARE_BUTTON_WIDTH - 4, 14)
		btn.text = btn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		btn.text:SetPoint("CENTER")
		btn.text:SetText(SHARE_QUEST_ABBREV or "Share")
		btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	end
	btn:SetScript("OnClick", function(self) ShareQuest(self.questID) end)
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Share this quest with your party")
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f.share = btn
	return btn
end

-- Fills the lines under a block and returns the height they take (0 = none).
local function FillPartyLines(block, questID, grouped)
	local wanted = {}
	if grouped and type(questID) == "number" then
		local lines, notOnQuest = PartyLines(questID)
		if lines then
			local shareLine
			if settings.share and notOnQuest and #notOnQuest > 0 and CanShare(questID) then
				local names = {}
				for _, entry in ipairs(notOnQuest) do
					if not CannotBeShared(questID, entry.name) then names[#names + 1] = entry.text end
				end
				if #names > 0 then
					shareLine = { text = "|cff8a8a8a" .. NOT_ON_QUEST_LABEL .. "|r " .. table.concat(names, ", "), share = true }
				end
			end
			if settings.party then
				for _, item in ipairs(lines) do wanted[#wanted + 1] = item end
			end
			if shareLine then wanted[#wanted + 1] = shareLine end
		end
	end

	local frame = partyLineFrames[block]
	if #wanted == 0 then
		if frame then frame:Hide() end
		return 0
	end

	frame = GetPartyLinesFrame(block)
	-- shown before measuring: a hidden frame reports text heights of 0, which
	-- left the frame 2 px tall and the next quest drawn over our lines
	frame:Show()
	-- An explicit width makes the wrapped height available at once; with the
	-- width coming from anchors, GetHeight reported the previous text's
	-- height until the next layout pass and the quest below overlapped.
	local frameWidth = frame:GetWidth()
	if not frameWidth or frameWidth <= 0 then frameWidth = (tracker and tracker:GetWidth() or 260) - 20 end
	local offsetY, shareShown = PARTY_LINE_PAD, false
	for i, item in ipairs(wanted) do
		local line = frame.lines[i]
		if not line then
			line = frame:CreateFontString(nil, "ARTWORK", "ObjectiveTrackerLineFont")
			line:SetJustifyH("LEFT")
			line:SetWordWrap(true)
			line:SetMaxLines(2)
			frame.lines[i] = line
		end
		line:ClearAllPoints()
		line:SetPoint("TOPLEFT", frame, "TOPLEFT", PARTY_LINE_INDENT, -offsetY)
		line:SetWidth(math.max(20, frameWidth - PARTY_LINE_INDENT - (item.share and SHARE_BUTTON_WIDTH or 0)))
		line:SetText(item.text)
		line:SetTextColor(item.r or 0.8, item.g or 0.8, item.b or 0.8)
		line:Show()
		local lineHeight = line:GetStringHeight()
		if not lineHeight or lineHeight <= 0 then
			line:SetHeight(0)
			lineHeight = line:GetHeight()
		end
		if not lineHeight or lineHeight <= 0 then lineHeight = 12 end
		line:SetHeight(lineHeight)
		if item.share then
			local btn = GetShareButton(frame)
			btn.questID = questID
			btn:ClearAllPoints()
			-- a little taller than the text line and centred on it, so the
			-- button art gets some room above and below the label
			btn:SetPoint("RIGHT", frame, "TOPRIGHT", 0, -(offsetY + lineHeight / 2))
			btn:SetHeight(lineHeight + 4)
			btn:Show()
			shareShown = true
		end
		offsetY = offsetY + lineHeight + PARTY_LINE_SPACING
	end
	for i = #wanted + 1, #frame.lines do frame.lines[i]:Hide() end
	if frame.share and not shareShown then frame.share:Hide() end
	-- the last line's spacing is swapped for the bottom padding
	offsetY = offsetY - PARTY_LINE_SPACING + PARTY_LINE_PAD
	frame:SetHeight(offsetY)
	return offsetY
end

-------------------------------------------------------------------------------
-- "Ready for turn-in" section header (a Blizzard module header, parented to us)
-------------------------------------------------------------------------------

local turnInSection

local function ToggleTurnInSection()
	settings.collapsed = not settings.collapsed
	if turnInSection and turnInSection.Header and turnInSection.Header.SetCollapsed then
		pcall(turnInSection.Header.SetCollapsed, turnInSection.Header, settings.collapsed)
	end
	Reflow()
end

local function GetTurnInSection()
	if turnInSection then return turnInSection end
	local holder = CreateFrame("Frame", nil, questModule.ContentsFrame)
	holder:SetSize(260, 26)
	holder:SetPoint("LEFT", questModule.ContentsFrame, "LEFT", 0, 0)
	-- The Blizzard header's minimize button calls parent:ToggleCollapsed().
	holder.ToggleCollapsed = ToggleTurnInSection

	local ok, header = pcall(CreateFrame, "Frame", nil, holder, "ObjectiveTrackerModuleHeaderTemplate")
	if ok and header and header.Text then
		header:SetPoint("TOPLEFT")
		if header.SetCollapsed then pcall(header.SetCollapsed, header, settings.collapsed) end
	else
		Debug("module header template unavailable (%s), using a plain header", tostring(header))
		header = CreateFrame("Frame", nil, holder)
		header:SetAllPoints()
		local bg = header:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.3)
		header.Text = header:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		header.Text:SetPoint("LEFT", 7, 0)
	end
	holder.Header = header

	holder:EnableMouse(true)
	holder:SetScript("OnMouseUp", function(_, button)
		if button == "LeftButton" then ToggleTurnInSection() end
	end)
	-- tooltip with the XP the finished quests are worth (defined further down)
	holder:SetScript("OnEnter", function(self) if QOP.ShowSectionTooltip then QOP.ShowSectionTooltip(self) end end)
	holder:SetScript("OnLeave", function() GameTooltip:Hide() end)
	turnInSection = holder
	QOP.ApplyWidth(settings.width or (tracker and tracker:GetWidth()) or 260)
	return holder
end

-------------------------------------------------------------------------------
-- Reflow: rearrange Blizzard's blocks after it has laid them out
-------------------------------------------------------------------------------

local hiddenRightEdgeFrames = {}   -- right-edge frames (item buttons, bars) we hid with a block
local questModuleHeight            -- module height we want; nil = leave Blizzard's
local reflowing = false
local pendingReflow = false

-- Blizzard's displayed blocks, in Blizzard's order.
local function GetBlizzardBlocks()
	local list, b, guard = {}, questModule.firstBlock, 0
	while b and guard < 200 do
		list[#list + 1] = b
		b = b.nextBlock
		guard = guard + 1
	end
	return list
end

-- Item buttons, timer and progress bars are parented to the module, not the
-- block, so hiding a block does not hide them. We track the ones we hide so we
-- can show them again: Blizzard only shows a right-edge frame when it is new.
local function SetBlockShown(block, shown)
	if shown then
		if not block:IsShown() then block:Show() end
		if block.addedRegions then
			for region in pairs(block.addedRegions) do
				if hiddenRightEdgeFrames[region] then
					hiddenRightEdgeFrames[region] = nil
					region:Show()
				end
			end
		end
	else
		if block:IsShown() then block:Hide() end
		if block.addedRegions then
			for region in pairs(block.addedRegions) do
				if region:GetParent() ~= block and region:IsShown() then
					region:Hide()
					hiddenRightEdgeFrames[region] = true
				end
			end
		end
		local f = partyLineFrames[block]
		if f then f:Hide() end
	end
end

local function AnchorBelow(frame, prev)
	if prev then
		frame:SetPoint("TOP", prev, "BOTTOM", 0, questModule.fromBlockOffsetY or -10)
	else
		frame:SetPoint("TOP", questModule.ContentsFrame, "TOP", 0, questModule.fromHeaderOffsetY or -10)
	end
end

local function BlizzardHeightModifiers()
	local mod = 0
	if questModule.heightModifiers then
		for _, h in pairs(questModule.heightModifiers) do mod = mod + h end
	end
	return mod
end

-- Also runs after Blizzard's own UpdateHeight (slide animations call it).
local function ApplyQuestModuleHeight()
	if questModuleHeight then
		questModule:SetHeight(questModuleHeight + BlizzardHeightModifiers())
	end
end

IsCompleteForMe = function(questID)
	if type(questID) ~= "number" then return false end
	if Safe(false, C_QuestLog.IsComplete, questID) then return true end
	-- a block for a quest that just left the log (turned in) is fading out;
	-- type() is safe on secrets, "==" is not
	if type(C_QuestLog.GetLogIndexForQuestID) ~= "function" then return false end
	local ok, index = pcall(C_QuestLog.GetLogIndexForQuestID, questID)
	return ok and type(index) == "nil"
end

-- A quest you have finished but a party member is still working on stays
-- in the Quests section: the group will keep playing it. It moves to the
-- turn-in section when they finish or leave, and back if they rejoin, since
-- this is recomputed on every pass. Counts and pending XP use it too.
local function IsFinished(questID)
	if not IsCompleteForMe(questID) then return false end
	if not IsInGroup() then return true end
	local _, _, _, partyWorking = PartyLines(questID)
	return not partyWorking
end

-- Finished quests in the whole log, tracked or not: the turn-in header's
-- count, so untracking a finished quest hides its entry but not the number.
local function CountFinishedInLog()
	local n = 0
	if type(C_QuestLog.GetNumQuestLogEntries) == "function" and type(C_QuestLog.GetInfo) == "function" then
		for i = 1, Safe(0, C_QuestLog.GetNumQuestLogEntries) do
			local info = Safe(nil, C_QuestLog.GetInfo, i)
			if type(info) == "table" and not info.isHeader and type(info.questID) == "number" and IsFinished(info.questID) then
				n = n + 1
			end
		end
	end
	return n
end

-------------------------------------------------------------------------------
-- Current area first: dungeon or zone
-------------------------------------------------------------------------------

-- The quests that belong to where you are go to the top of their section.
-- Inside a dungeon or raid that is the instance (`settings.instance`);
-- outside it is the zone (`settings.zone`). A quest belongs to the area
-- when the quest log files it under a header with the area's name (Classic
-- sorts quests that way, and it holds for finished quests too, whose map is
-- the turn-in spot), or, for active quests, when it has a marker on the
-- current map (plus, for dungeons, when its map is a floor of the same
-- instance). Untracked quests of the area are tracked once per visit, under
-- the watch limit; nothing is untracked on leaving. Everything else keeps
-- its order, and leaving the area restores it.

local instanceQuests = {}   -- questID -> true, rebuilt each pass while in an instance
local zoneQuests = {}       -- questID -> true, rebuilt each pass while in a zone
local autoTrackedFor = nil  -- area name whose quests were auto-tracked this visit
local areaName = nil        -- the area the header names, nil when none applies

-- the highest dungeon-type map above `mapID` (floors share an instance map)
local function TopInstanceMap(mapID)
	local top, guard = mapID, 0
	while guard < 10 do
		local info = Safe(nil, C_Map.GetMapInfo, top)
		if type(info) ~= "table" or type(info.parentMapID) ~= "number" or info.parentMapID == 0 then break end
		local parent = Safe(nil, C_Map.GetMapInfo, info.parentMapID)
		if type(parent) ~= "table" or parent.mapType ~= (Enum and Enum.UIMapType and Enum.UIMapType.Dungeon or 4) then break end
		top = info.parentMapID
		guard = guard + 1
	end
	return top
end

-- Marks quests filed under the area's header in the quest log into `set`,
-- and tracks the untracked ones once per visit of that area.
local function CollectByHeader(name, set)
	local want = StatusKey(name)
	local toTrack = {}
	local header
	for i = 1, Safe(0, C_QuestLog.GetNumQuestLogEntries) do
		local info = Safe(nil, C_QuestLog.GetInfo, i)
		if type(info) == "table" then
			if info.isHeader then
				header = (type(info.title) == "string" and Accessible(info.title)) and StatusKey(info.title) or nil
			elseif header == want and type(info.questID) == "number" then
				set[info.questID] = true
				if autoTrackedFor ~= name and Safe(nil, C_QuestLog.GetQuestWatchType, info.questID) == nil then
					toTrack[#toTrack + 1] = info.questID
				end
			end
		end
	end
	if autoTrackedFor ~= name then
		autoTrackedFor = name
		local max = (Constants and Constants.QuestWatchConsts and Constants.QuestWatchConsts.MAX_QUEST_WATCHES) or 25
		for _, id in ipairs(toTrack) do
			if Safe(0, C_QuestLog.GetNumQuestWatches) < max then
				if pcall(C_QuestLog.AddQuestWatch, id) then Debug("tracked %d for %s", id, name) end
			end
		end
	end
end

-- Marks quests with a marker on the player's current map into `set`.
local function CollectByMap(set, dungeonFloors)
	local mapID = Safe(nil, C_Map.GetBestMapForUnit, "player")
	if type(mapID) ~= "number" then return end
	if C_QuestLog and type(C_QuestLog.GetQuestsOnMap) == "function" then
		local list = Safe(nil, C_QuestLog.GetQuestsOnMap, mapID)
		if type(list) == "table" then
			for _, q in ipairs(list) do
				if type(q) == "table" and type(q.questID) == "number" then set[q.questID] = true end
			end
		end
	end
	if dungeonFloors and type(GetQuestUiMapID) == "function" then
		local top = TopInstanceMap(mapID)
		for i = 1, Safe(0, C_QuestLog.GetNumQuestWatches) do
			local id = Safe(nil, C_QuestLog.GetQuestIDForQuestWatchIndex, i)
			if id then
				local qm = Safe(nil, GetQuestUiMapID, id)
				if type(qm) == "number" and qm > 0 and (qm == mapID or TopInstanceMap(qm) == top) then set[id] = true end
			end
		end
	end
end

local function RefreshAreaQuests()
	wipe(instanceQuests)
	wipe(zoneQuests)
	areaName = nil
	if not settings then return end
	local inInstance, kind = IsInInstance()
	if inInstance and (kind == "party" or kind == "raid") then
		if not settings.instance then autoTrackedFor = nil return end
		local name = Safe(nil, GetInstanceInfo)
		if type(name) == "string" and name ~= "" then
			areaName = name
			CollectByHeader(name, instanceQuests)
		end
		CollectByMap(instanceQuests, true)
	else
		if not settings.zone then autoTrackedFor = nil return end
		local name = Safe(nil, GetRealZoneText)
		if type(name) == "string" and name ~= "" then
			areaName = name
			CollectByHeader(name, zoneQuests)
		end
		CollectByMap(zoneQuests, false)
	end
end

-- number of tracked, unfinished quests of the current area
local function CountAreaQuests()
	local n = 0
	for i = 1, Safe(0, C_QuestLog.GetNumQuestWatches) do
		local id = Safe(nil, C_QuestLog.GetQuestIDForQuestWatchIndex, i)
		if id and (instanceQuests[id] or zoneQuests[id]) and not IsFinished(id) then n = n + 1 end
	end
	return n
end

-- A quest's level as the tracker shows it ("[12] ..."), for level sorting.
local function QuestLevel(block)
	local id = block.id
	if type(id) == "number" then
		local level = Safe(nil, C_QuestLog.GetQuestDifficultyLevel, id)
		if type(level) == "number" and level > 0 then return level end
	end
	local title = block.HeaderText and block.HeaderText:GetText()
	if type(title) == "string" and Accessible(title) then
		local level = tonumber(title:match("^%[(%d+)%]"))
		if level then return level end
	end
	return 0
end

-- Orders a section's blocks: current-area quests first (dungeon inside one,
-- zone outside), then
-- in the turn-in section quests the whole party has finished last, then by
-- level if `settings.sort` is "asc" or "desc", then Blizzard's own order.
-- `partyFinishedSet` is block -> true for the party-done rule (optional).
local function OrderBlocks(list, partyFinishedSet)
	local sortMode = settings.sort or "none"
	local keyed = {}
	for i, block in ipairs(list) do
		keyed[i] = {
			block = block,
			instance = instanceQuests[block.id] and 0 or (zoneQuests[block.id] and 1 or 2),
			partyDone = (partyFinishedSet and partyFinishedSet[block]) and 1 or 0,
			level = sortMode ~= "none" and QuestLevel(block) or 0,
			index = i,
		}
	end
	table.sort(keyed, function(a, b)
		if a.instance ~= b.instance then return a.instance < b.instance end
		if a.partyDone ~= b.partyDone then return a.partyDone < b.partyDone end
		if a.level ~= b.level then
			if sortMode == "asc" then return a.level < b.level end
			if sortMode == "desc" then return a.level > b.level end
		end
		return a.index < b.index
	end)
	local out = {}
	for i, k in ipairs(keyed) do out[i] = k.block end
	return out
end

local function CountTrackedQuests()
	local active, done = 0, 0
	local n = Safe(0, C_QuestLog.GetNumQuestWatches)
	for i = 1, n do
		local id = Safe(nil, C_QuestLog.GetQuestIDForQuestWatchIndex, i)
		if id then
			if IsFinished(id) then done = done + 1 else active = active + 1 end
		end
	end
	return active, done
end

-- Header text: "Quests (12)" normally; with area-first on and an area
-- known, "Quests (4) - The Barrens" where 4 counts that area's quests. If
-- the full text would not fit the header at normal size, a leading "The "
-- is dropped from the name, then the name itself; the count always stays.
-- Blizzard's header font string auto-shrinks, so the candidates are
-- measured with a plain font string of our own at the normal size.
local headerMeasure
local function HeaderTextFits(header, text)
	if not headerMeasure then
		headerMeasure = UIParent:CreateFontString(nil, "ARTWORK", "ObjectiveTrackerHeaderFont")
		headerMeasure:Hide()
	end
	headerMeasure:SetText(text)
	local available = header.Text:GetWidth()
	if not available or available <= 0 then return true end
	return (headerMeasure:GetStringWidth() or 0) <= available
end

local function SetQuestHeader()
	local header = questModule.Header
	if not header or not header.Text then return end
	local text = QUESTS_TEXT
	if settings.enabled and settings.counts then
		local inInstance = IsInInstance()
		local areaOn = areaName ~= nil and ((inInstance and settings.instance) or (not inInstance and settings.zone))
		if areaOn then
			local count = ("%s (%d)"):format(QUESTS_TEXT, CountAreaQuests())
			local candidates = { count .. " - " .. areaName }
			local short = areaName:gsub("^The ", "")
			if short ~= areaName then candidates[#candidates + 1] = count .. " - " .. short end
			candidates[#candidates + 1] = count
			text = candidates[#candidates]
			for _, candidate in ipairs(candidates) do
				if HeaderTextFits(header, candidate) then text = candidate break end
			end
		else
			text = ("%s (%d)"):format(QUESTS_TEXT, CountTrackedQuests())
		end
	end
	header.Text:SetText(text)
end

local function RearrangeBlocks()
	local blocks = GetBlizzardBlocks()
	Guarded(nil, RefreshAreaQuests)
	SetQuestHeader()

	local enabled = settings.enabled
	local moduleShown = questModule:IsShown() and not questModule:IsCollapsed()
	if #blocks == 0 or not moduleShown then
		-- hand the height back to Blizzard (our UpdateHeight hook may have
		-- just reapplied a stale value)
		questModuleHeight = nil
		local blizzardHeight = questModule.contentsHeight or questModule.headerHeight or 25
		questModule:SetHeight(blizzardHeight + (questModule.bottomSpacing or 0) + BlizzardHeightModifiers())
		if turnInSection then turnInSection:Hide() end
		return
	end

	-- our own collapse of the Quests section hides the active quests only; the
	-- turn-in section stays (both vanish only with Blizzard's own collapse,
	-- handled above). It never touches Blizzard's collapse state.
	local questsCollapsed = enabled and settings.questsCollapsed

	local grouped = enabled and IsInGroup()
	local activeBlocks, finishedBlocks = {}, {}
	for _, block in ipairs(blocks) do
		if enabled and settings.group and Guarded(false, IsFinished, block.id) then
			finishedBlocks[#finishedBlocks + 1] = block
		else
			activeBlocks[#activeBlocks + 1] = block
		end
	end

	-- ordering within each section: dungeon quests first, party-finished
	-- turn-ins last, then by level if chosen, then Blizzard's order
	local partyFinishedSet = {}
	if grouped then
		for _, block in ipairs(finishedBlocks) do
			if Guarded(false, function() local _, _, a = PartyLines(block.id); return a end) then
				partyFinishedSet[block] = true
			end
		end
	end
	activeBlocks = OrderBlocks(activeBlocks, nil)
	finishedBlocks = OrderBlocks(finishedBlocks, partyFinishedSet)

	local spacing = -(questModule.fromBlockOffsetY or -10)
	local usedHeight = questModule.headerHeight or 25
	local previousFrame

	-- room for this module inside the visible height: the container header
	-- and padding sit above it, a little background below
	local visibleBudget = enabled and (VisibleHeight() - (tracker.topModulePadding or 38) - 10) or math.huge
	local overflow = false
	local function FitsInBudget(blockTotal, limit) return usedHeight + blockTotal + spacing <= (limit or visibleBudget) end

	-- Places a block if it fits within `limit`; once one does not, every later
	-- one in the same run stays hidden. Returns true when shown.
	-- Party lines are filled once per block here, so the snap model and the
	-- placement see the same heights.
	local partyLinesHeightOf = {}
	local function BlockHeight(block)
		if partyLinesHeightOf[block] == nil then
			partyLinesHeightOf[block] = enabled and Guarded(0, FillPartyLines, block, block.id, grouped) or 0
			if not enabled and partyLineFrames[block] then partyLineFrames[block]:Hide() end
		end
		return (block.height or 0) + partyLinesHeightOf[block]
	end

	local function PlaceBlock(block, limit)
		local blockTotal = BlockHeight(block)
		local partyLinesHeight = partyLinesHeightOf[block]
		if overflow or not FitsInBudget(blockTotal, limit) then
			overflow = true
			SetBlockShown(block, false)
			return false
		end
		SetBlockShown(block, true)
		AnchorBelow(block, previousFrame)
		previousFrame = (partyLinesHeight > 0) and partyLineFrames[block] or block
		usedHeight = usedHeight + blockTotal + spacing
		return true
	end

	-- The turn-in header is always shown, so its room is reserved up front.
	-- When not everything fits, the room is shared equally: one quest from
	-- Quests, one from Ready for turn-in, and so on until a section runs out,
	-- then the rest of the other (user choice, 18 Oct 2026). The visual order
	-- stays active, header, finished; the round-robin only decides which
	-- quests are shown. Placement and the resize snap points use the same
	-- sequence, so every stop ends flush with the content.
	local finishedInLog = (enabled and settings.group) and Guarded(0, CountFinishedInLog) or 0
	local sectionFrame = (enabled and settings.group and (finishedInLog > 0 or #finishedBlocks > 0)) and GetTurnInSection() or nil
	local sectionHeaderHeight = sectionFrame and (sectionFrame:GetHeight() + spacing) or 0

	local fillOrder = {}
	do
		local i, j = 1, 1
		while i <= #activeBlocks or j <= #finishedBlocks do
			if i <= #activeBlocks then fillOrder[#fillOrder + 1] = { block = activeBlocks[i], isFinished = false }; i = i + 1 end
			if j <= #finishedBlocks then fillOrder[#fillOrder + 1] = { block = finishedBlocks[j], isFinished = true }; j = j + 1 end
		end
	end

	-- Snap points for the vertical resize, from the fully expanded model
	-- whatever is collapsed right now: the adjusted height is the capacity,
	-- a collapsed section just uses less of it until it is expanded again.
	local snapPoints, runningHeight = {}, usedHeight + sectionHeaderHeight
	for _, entry in ipairs(fillOrder) do
		runningHeight = runningHeight + BlockHeight(entry.block) + spacing
		snapPoints[#snapPoints + 1] = runningHeight
	end

	-- what fits right now: the longest prefix of the sequence, skipping the
	-- entries of a collapsed section
	local shownBlocks = {}
	local modelHeight = usedHeight + sectionHeaderHeight
	for _, entry in ipairs(fillOrder) do
		local skip = (entry.isFinished and settings.collapsed) or (not entry.isFinished and questsCollapsed)
		if not skip then
			local blockTotal = BlockHeight(entry.block) + spacing
			if modelHeight + blockTotal > visibleBudget then break end
			modelHeight = modelHeight + blockTotal
			shownBlocks[entry.block] = true
		end
	end

	for _, block in ipairs(activeBlocks) do
		if shownBlocks[block] then PlaceBlock(block, visibleBudget) else SetBlockShown(block, false) end
	end

	if sectionFrame then
		sectionFrame.Header.Text:SetText(("%s (%d)"):format(READY_TEXT, math.max(finishedInLog, #finishedBlocks)))
		AnchorBelow(sectionFrame, previousFrame)
		sectionFrame:Show()
		previousFrame = sectionFrame
		usedHeight = usedHeight + sectionFrame:GetHeight() + spacing
		overflow = false
		local shownFinished = 0
		for _, block in ipairs(finishedBlocks) do
			if shownBlocks[block] and PlaceBlock(block, visibleBudget) then
				shownFinished = shownFinished + 1
			else
				SetBlockShown(block, false)
			end
		end
		-- "+" when collapsed by the user or squeezed out by the visible height
		if sectionFrame.Header.SetCollapsed then pcall(sectionFrame.Header.SetCollapsed, sectionFrame.Header, settings.collapsed or shownFinished == 0) end
	elseif turnInSection then
		turnInSection:Hide()
	end

	usedHeight = usedHeight + (questModule.bottomSpacing or 0)
	questModuleHeight = usedHeight
	ApplyQuestModuleHeight()

	-- visible heights at which the panel ends exactly on a boundary (the
	-- inverse of `visibleBudget`)
	local pad = (tracker.topModulePadding or 38) + 10 + (questModule.bottomSpacing or 0) + 1
	QOP.snapHeights = {}
	for i, v in ipairs(snapPoints) do QOP.snapHeights[i] = v + pad end
end

-- One frame after a layout, re-measure the party lines; if any frame's
-- height disagrees with its lines (text that re-wrapped after we measured),
-- lay out once more. Capped so it can never loop.
local verifyPending, verifyCount = false, 0
local function VerifyPartyLineHeights()
	verifyPending = false
	local mismatch = false
	for _, frame in pairs(partyLineFrames) do
		if frame:IsShown() then
			local total = PARTY_LINE_PAD * 2 - PARTY_LINE_SPACING
			local any = false
			for _, line in ipairs(frame.lines) do
				if line:IsShown() then
					any = true
					total = total + (line:GetStringHeight() or 0) + PARTY_LINE_SPACING
				end
			end
			if any and math.abs(total - frame:GetHeight()) > 1 then mismatch = true break end
		end
	end
	if mismatch and verifyCount < 2 then
		verifyCount = verifyCount + 1
		Reflow()
	else
		verifyCount = 0
	end
end

Reflow = function()
	if not settings or not questModule or reflowing then return end
	reflowing = true
	local ok, err = pcall(RearrangeBlocks)
	reflowing = false
	if ok and not verifyPending then
		verifyPending = true
		C_Timer.After(0, VerifyPartyLineHeights)
	end
	if not ok then
		QOP.lastError = tostring(err)
		-- loud on purpose: a pass that dies leaves Blizzard's anchors under our
		-- frames, which looks like a spacing bug rather than an error
		local now = GetTime()
		if debug or not QOP.lastErrorPrint or now - QOP.lastErrorPrint > 30 then
			QOP.lastErrorPrint = now
			Print("layout error (type /qop err for the full text): %s", tostring(err))
		end
	end
end

RequestReflow = function()
	if pendingReflow then return end
	pendingReflow = true
	C_Timer.After(0.1, function()
		pendingReflow = false
		Reflow()
	end)
end

-------------------------------------------------------------------------------
-- Pending turn-in XP
-------------------------------------------------------------------------------

local function RewardXP(questID)
	local fn = _G.GetQuestLogRewardXP or (C_QuestLog and C_QuestLog.GetQuestLogRewardXP)
	local xp = Safe(0, fn, questID)
	return type(xp) == "number" and xp or 0
end

-- XP from finished quests: the tracked ones (what the section lists) and
-- every finished quest in the log (what you would actually gain).
local function PendingTurnInXP()
	local tracked, all, trackedCount, allCount = 0, 0, 0, 0
	for i = 1, Safe(0, C_QuestLog.GetNumQuestWatches) do
		local id = Safe(nil, C_QuestLog.GetQuestIDForQuestWatchIndex, i)
		if id and IsFinished(id) then
			tracked = tracked + RewardXP(id)
			trackedCount = trackedCount + 1
		end
	end
	if type(C_QuestLog.GetNumQuestLogEntries) == "function" and type(C_QuestLog.GetInfo) == "function" then
		for i = 1, Safe(0, C_QuestLog.GetNumQuestLogEntries) do
			local info = Safe(nil, C_QuestLog.GetInfo, i)
			if type(info) == "table" and not info.isHeader and type(info.questID) == "number" and IsFinished(info.questID) then
				all = all + RewardXP(info.questID)
				allCount = allCount + 1
			end
		end
	else
		all, allCount = tracked, trackedCount
	end
	return tracked, trackedCount, all, allCount
end

local function FormatNumber(n)
	if type(BreakUpLargeNumbers) == "function" then return BreakUpLargeNumbers(n) end
	return tostring(n)
end

-- "1,240 XP (31% of this level)" plus a level-up note when it crosses the bar.
local function XPText(xp)
	local cur, max = Safe(0, UnitXP, "player"), Safe(0, UnitXPMax, "player")
	if max <= 0 then return FormatNumber(xp) .. " XP" end
	local text = ("%s XP (%d%% of this level)"):format(FormatNumber(xp), math.floor(xp / max * 100 + 0.5))
	if cur + xp >= max then text = text .. ", enough to level up" end
	return text
end

local function AtMaxLevel()
	if GameRulesUtil and type(GameRulesUtil.IsPlayerAtEffectiveMaxLevel) == "function" then
		return Safe(false, GameRulesUtil.IsPlayerAtEffectiveMaxLevel)
	end
	return Safe(false, IsPlayerAtEffectiveMaxLevel)
end

function QOP.ShowSectionTooltip(owner)
	if not settings or not settings.enabled or not settings.xp or AtMaxLevel() then return end
	local tracked, trackedCount, all, allCount = PendingTurnInXP()
	if trackedCount == 0 and allCount == 0 then return end
	GameTooltip:SetOwner(owner, "ANCHOR_NONE")
	GameTooltip:ClearAllPoints()
	GameTooltip:SetPoint("TOPRIGHT", owner, "TOPLEFT", -4, 0)
	GameTooltip:SetText(READY_TEXT)
	if trackedCount > 0 then
		GameTooltip:AddLine(("Tracked (%d): %s"):format(trackedCount, XPText(tracked)), 0.8, 0.8, 0.8, true)
	end
	if allCount > trackedCount then
		GameTooltip:AddLine(("All finished quests (%d): %s"):format(allCount, XPText(all)), 0.8, 0.8, 0.8, true)
	end
	GameTooltip:Show()
end

-- Segment on the XP bar for the pending XP. The bar's StatusBar is a child
-- frame with an opaque Background, so a texture on the bar frame itself (the
-- way Blizzard draws the rested fill) stays hidden. Ours lives inside the
-- StatusBar instead, one sublevel under its fill texture and anchored to the
-- fill's right edge, so it starts exactly at your current XP and follows the
-- fill as it animates.
local xpSegments = {}   -- bar -> texture
-- bright gold, chosen in game with the (since removed) colour picker, 18 Oct 2026
local XP_SEGMENT_COLOR = { r = 1.0, g = 0.863, b = 0.239, a = 0.9 }
local xpBarsHooked = {}
local pendingXPUpdate = false

local function ExpBars()
	local bars = {}
	local index = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum and StatusTrackingBarInfo.BarsEnum.Experience
	for _, container in ipairs({ _G.MainStatusTrackingBarContainer, _G.SecondaryStatusTrackingBarContainer }) do
		if container and type(container.bars) == "table" then
			local bar = index and container.bars[index]
			if bar and bar.isExpBar then bars[#bars + 1] = bar end
		end
	end
	return bars
end

local function UpdateXPOverlay()
	local expBars = ExpBars()
	local show = settings and settings.enabled and settings.xp and not AtMaxLevel() and not Safe(false, IsXPUserDisabled)
	local pending = show and select(3, PendingTurnInXP()) or 0
	local currentXP, maxXP = Safe(0, UnitXP, "player"), Safe(0, UnitXPMax, "player")
	for _, bar in ipairs(expBars) do
		local statusBar = bar.StatusBar
		local fill = statusBar and type(statusBar.GetStatusBarTexture) == "function" and statusBar:GetStatusBarTexture()
		local segment = xpSegments[bar]
		if not segment and statusBar then
			-- BORDER is the fill's layer; -1 keeps the fill's edge on top of ours.
			-- A plain colour: Blizzard's prediction atlas is dark by design and
			-- any tint on it came out as muddy shading (17 Oct 2026).
			segment = statusBar:CreateTexture(nil, "BORDER", nil, -1)
			xpSegments[bar] = segment
		end
		if not xpBarsHooked[bar] then
			xpBarsHooked[bar] = true
			-- bar refreshes (show, resize, level change) re-run after Blizzard's
			if type(bar.Update) == "function" then hooksecurefunc(bar, "Update", function() QOP.RequestXPUpdate() end) end
			if type(bar.UpdateTick) == "function" then hooksecurefunc(bar, "UpdateTick", function() QOP.RequestXPUpdate() end) end
			if bar.ExhaustionTick and type(bar.ExhaustionTick.ExhaustionToolTipText) == "function" then
				hooksecurefunc(bar.ExhaustionTick, "ExhaustionToolTipText", function()
					if not settings or not settings.enabled or not settings.xp or not GameTooltip:IsShown() then return end
					local _, _, all, allCount = PendingTurnInXP()
					if allCount == 0 then return end
					GameTooltip:AddLine(("Finished quests (%d): %s"):format(allCount, XPText(all)), 1.0, 0.78, 0.15, true)
					GameTooltip:Show()
				end)
			end
		end
		if not segment then
			-- no StatusBar on this bar; nothing to draw on
		elseif pending <= 0 or maxXP <= 0 or not fill then
			segment:Hide()
		else
			-- share of the bar the pending XP covers, clamped at the level's end
			local share = math.min(pending / maxXP, math.max(1 - currentXP / maxXP, 0))
			local width = share * statusBar:GetWidth()
			local c = XP_SEGMENT_COLOR
			segment:SetColorTexture(c.r, c.g, c.b, c.a)
			segment:ClearAllPoints()
			-- a pixel inside the fill on every side: the fill texture is a touch
			-- taller than the visible bar art and the segment showed past it
			segment:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, -1)
			segment:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", 0, 1)
			segment:SetWidth(math.max(0, width - 1))
			segment:SetShown(width > 1.5)
		end
	end
end

function QOP.RequestXPUpdate()
	if pendingXPUpdate then return end
	pendingXPUpdate = true
	C_Timer.After(0.2, function()
		pendingXPUpdate = false
		local ok, err = pcall(UpdateXPOverlay)
		if not ok then Debug("xp overlay error: %s", tostring(err)) end
	end)
end

-------------------------------------------------------------------------------
-- Usable quest items from the bags
-------------------------------------------------------------------------------

-- A column of secure item buttons docked to the left of the tracker, one per
-- quest-class item in the bags that has a Use effect. Independent of quest
-- data, so it covers quests the log links no item to (the Symbol of Life
-- case). The buttons are SecureActionButtons: the game runs the click, so
-- they work in combat, but their attributes and visibility may only change
-- out of combat; a bag change mid-fight is applied at PLAYER_REGEN_ENABLED.

local ITEM_BUTTON_SIZE, ITEM_BUTTON_GAP, MAX_ITEM_BUTTONS = 30, 4, 8
local itemStrip, itemButtons = nil, {}
local itemsPending = false

local function ScanQuestItems()
	local found = {}
	if not C_Container or type(C_Container.GetContainerItemInfo) ~= "function" then return found end
	local questClass = (Enum and Enum.ItemClass and Enum.ItemClass.Questitem) or 12
	local numBags = NUM_BAG_SLOTS or 4
	for bag = 0, numBags do
		local slots = Safe(0, C_Container.GetNumSlots, bag)
		for slot = 1, slots do
			local info = Safe(nil, C_Container.GetContainerItemInfo, bag, slot)
			local itemID = type(info) == "table" and info.itemID
			if type(itemID) == "number" and Accessible(itemID) then
				local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
				local usable = classID == questClass and Safe(nil, C_Item.GetItemSpell, itemID) ~= nil
				if usable and #found < MAX_ITEM_BUTTONS then
					found[#found + 1] = {
						bag = bag, slot = slot, itemID = itemID,
						icon = Accessible(info.iconFileID) and info.iconFileID or nil,
						count = Accessible(info.stackCount) and info.stackCount or 1,
					}
				end
			end
		end
	end
	return found
end

local function GetItemStrip()
	if itemStrip then return itemStrip end
	itemStrip = CreateFrame("Frame", "QuestObjectivesPlusItems", UIParent)
	itemStrip:SetSize(ITEM_BUTTON_SIZE, ITEM_BUTTON_SIZE)
	itemStrip:SetPoint("TOPRIGHT", tracker, "TOPLEFT", -36, 0)
	itemStrip:Hide()
	return itemStrip
end

local function GetItemButton(i)
	local btn = itemButtons[i]
	if btn then return btn end
	btn = CreateFrame("Button", "QuestObjectivesPlusItem" .. i, GetItemStrip(), "SecureActionButtonTemplate")
	btn:SetSize(ITEM_BUTTON_SIZE, ITEM_BUTTON_SIZE)
	btn:SetPoint("TOP", itemStrip, "TOP", 0, -(i - 1) * (ITEM_BUTTON_SIZE + ITEM_BUTTON_GAP))
	btn:RegisterForClicks("AnyUp", "AnyDown")
	btn:SetAttribute("type", "item")
	btn.border = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
	btn.border:SetPoint("TOPLEFT", -2, 2)
	btn.border:SetPoint("BOTTOMRIGHT", 2, -2)
	btn.border:SetColorTexture(0, 0, 0, 0.6)
	btn.icon = btn:CreateTexture(nil, "BACKGROUND")
	btn.icon:SetAllPoints()
	btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	btn.count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	btn.count:SetPoint("BOTTOMRIGHT", -2, 2)
	btn.cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
	btn.cooldown:SetAllPoints()
	btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	btn:SetScript("OnEnter", function(self)
		if not self.bag then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetBagItem(self.bag, self.slot)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	itemButtons[i] = btn
	return btn
end

local function UpdateItemCooldowns()
	for _, btn in ipairs(itemButtons) do
		if btn.bag and btn:IsShown() then
			local start, duration, enable = C_Container.GetContainerItemCooldown(btn.bag, btn.slot)
			if type(start) == "number" and Accessible(start) and Accessible(duration) then
				CooldownFrame_Set(btn.cooldown, start, duration, enable)
			end
		end
	end
end

-- Rebuilds the strip. Secure attributes and visibility are off limits in
-- combat; then it is marked pending and retried after combat.
local function UpdateQuestItems()
	if not settings or not tracker then return end
	if InCombatLockdown() then
		itemsPending = true
		return
	end
	itemsPending = false
	local strip = GetItemStrip()
	local items = (settings.enabled and settings.items) and ScanQuestItems() or {}
	for i, it in ipairs(items) do
		local btn = GetItemButton(i)
		btn.bag, btn.slot = it.bag, it.slot
		btn:SetAttribute("item", it.bag .. " " .. it.slot)
		btn.icon:SetTexture(it.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
		btn.count:SetText(it.count > 1 and it.count or "")
		btn:Show()
	end
	for i = #items + 1, #itemButtons do
		itemButtons[i].bag = nil
		itemButtons[i]:Hide()
	end
	strip:SetHeight(math.max(1, #items * (ITEM_BUTTON_SIZE + ITEM_BUTTON_GAP) - ITEM_BUTTON_GAP))
	strip:SetShown(#items > 0)
	UpdateItemCooldowns()
	Debug("quest items: %d", #items)
end

local pendingItems = false
function QOP.RequestItemsUpdate()
	if pendingItems then return end
	pendingItems = true
	C_Timer.After(0.3, function()
		pendingItems = false
		local ok, err = pcall(UpdateQuestItems)
		if not ok then
			QOP.lastError = tostring(err)
			Debug("quest items error: %s", tostring(err))
		end
	end)
end

-------------------------------------------------------------------------------
-- Party progress on world map quest pins
-------------------------------------------------------------------------------

-- The quest pin fires this after it has filled and shown GameTooltip, so the
-- party lines land at the bottom. The pin re-runs its OnMouseEnter on the
-- tooltip's update timer, which rebuilds the tooltip, so nothing duplicates.
local function OnQuestPinEnter(_, pin, questID)
	if not settings or not settings.enabled or not settings.maptip or type(questID) ~= "number" then return end
	if not IsInGroup() or not GameTooltip:IsShown() or GameTooltip:GetOwner() ~= pin then return end
	local lines, notOnQuest = PartyLines(questID)
	if not lines then return end
	local hasNotOn = notOnQuest and #notOnQuest > 0
	if #lines == 0 and not hasNotOn then return end
	GameTooltip:AddLine(" ")
	for _, l in ipairs(lines) do GameTooltip:AddLine(l.text, 0.8, 0.8, 0.8, true) end
	if hasNotOn then
		local names = {}
		for _, entry in ipairs(notOnQuest) do
			if not CannotBeShared(questID, entry.name) then names[#names + 1] = entry.text end
		end
		if #names > 0 then
			GameTooltip:AddLine("|cff8a8a8a" .. NOT_ON_QUEST_LABEL .. "|r " .. table.concat(names, ", "), 0.8, 0.8, 0.8, true)
		end
	end
	GameTooltip:Show()
end

local function InstallMapHook()
	if EventRegistry and type(EventRegistry.RegisterCallback) == "function" then
		EventRegistry:RegisterCallback("MapCanvas.QuestPin.OnEnter", OnQuestPinEnter, QOP)
	end
end

-------------------------------------------------------------------------------
-- Move and resize (no Edit Mode)
-------------------------------------------------------------------------------

-- Edit Mode replaces the tracker's SetPoint/ClearAllPoints with overrides that
-- flag its own dirty state. We use the originals it saved so our moves stay
-- out of that machinery.
local function RawMethod(name)
	local saved = tracker[name .. "Base"]
	if type(saved) == "function" then return saved end
	local mt = getmetatable(tracker)
	return mt and mt.__index and mt.__index[name]
end

-- BreakFromFrameManager makes Blizzard re-lay out RightManagedFrameContainer,
-- whose SetSize is protected in combat: pcall does not stop the
-- ADDON_ACTION_BLOCKED report. Edit Mode's ApplySystemAnchor can fire mid-fight
-- and our hook lands here on a timer, so the detach waits for
-- PLAYER_REGEN_ENABLED (9 Nov 2026).
local detachPending = false

local function DetachFromManager()
	if type(tracker.BreakFromFrameManager) ~= "function" then return end
	if InCombatLockdown() then
		detachPending = true
		return
	end
	detachPending = false
	pcall(tracker.BreakFromFrameManager, tracker)
end

-- The modules and headers are a fixed 260 wide by template; the container's
-- width alone changes nothing visible. Blocks anchor LEFT/RIGHT to their
-- module, so widening the module reflows the text at the next layout.
-- The header art (the gold rule) is drawn across the whole shaded panel,
-- which spans 30 px left and 5 px right of the 260-wide header frame, not
-- just across the header (user request, 18 Oct 2026). The art has
-- transparent margins at its ends that scale with it, so the texture is made
-- wider than the target span by that margin share and centred on the span;
-- the margin and a small horizontal nudge were tuned in game and are the
-- constants below.
local HEADER_WIDTH = 260
local ART_LEFT, ART_RIGHT = -28, 3   -- target span relative to the header's edges, 2 px inside the shade
-- tuned in game on 18 Oct 2026 (the tuning commands have since been removed)
local artMargin = 12                 -- transparent px at each end of the 260-wide art
local artShift = 4.5                 -- horizontal nudge so the ends sit symmetrically

local function FitHeader(header, textPad, w)
	if not header then return end
	header:SetWidth(w)
	local bg = header.Background
	if bg then
		local target = w - ART_LEFT + ART_RIGHT
		local artWidth = target * HEADER_WIDTH / math.max(1, HEADER_WIDTH - 2 * artMargin)
		bg:ClearAllPoints()
		bg:SetPoint("CENTER", header, "CENTER", (ART_LEFT + ART_RIGHT) / 2 + artShift, 0)
		bg:SetWidth(artWidth)
	end
	if header.Text then header.Text:SetWidth(w - textPad) end
end

function QOP.ApplyWidth(w)
	if not tracker or not w then return end
	if math.abs(tracker:GetWidth() - w) > 0.5 then tracker:SetWidth(w) end
	FitHeader(tracker.Header, 52, w)
	if type(tracker.modules) == "table" then
		for _, m in ipairs(tracker.modules) do
			m:SetWidth(w)
			FitHeader(m.Header, 60, w)
		end
	end
	if turnInSection then
		turnInSection:SetWidth(w)
		FitHeader(turnInSection.Header, 60, w)
	end
end

-- Pin the frame by its top-left corner at its current spot, clamped onto the
-- screen. Only a TOP anchor keeps the top edge still when the height changes:
-- Edit Mode's default "RIGHT" anchor would slide the content off the top of
-- the screen the moment the frame is made tall (which happened, 17 Oct 2026).
-- Also what makes sizing from the bottom-right grip follow the cursor.
local function AnchorTopLeft()
	local left, top = tracker:GetLeft(), tracker:GetTop()
	if not left or not top then return end
	local scale = tracker:GetScale()
	if not scale or scale == 0 then scale = 1 end
	local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
	left = math.max(0, math.min(left, screenW - tracker:GetWidth()))
	top = math.max(150, math.min(top, screenH))
	local clear, set = RawMethod("ClearAllPoints"), RawMethod("SetPoint")
	if clear and set then
		clear(tracker)
		set(tracker, "TOPLEFT", UIParent, "BOTTOMLEFT", left / scale, top / scale)
	end
end

local function EnsureTopAnchor()
	local point = tracker:GetPoint(1)
	if type(point) == "string" and point:find("^TOP") then return end
	AnchorTopLeft()
end

local clampWasOn   -- the tracker's screen clamping before we turned it off, nil while untouched

local function InEditMode()
	return EditModeManagerFrame ~= nil and Safe(false, EditModeManagerFrame.IsEditModeActive, EditModeManagerFrame)
end

-- The frame's real height is what Blizzard lays out into, so it is kept tall
-- enough for every tracked quest; the height the user sees and resizes is
-- db.height, enforced by the reflow and mirrored by the `bounds` frame the
-- grip and outline hang from. In Edit Mode the real height is the visible
-- one, so Edit Mode's box makes sense. Dragging the grip resizes `bounds`,
-- never this frame, so Blizzard's layout is undisturbed while sizing.
-- Screen clamping is off while the frame is tall, or it would be shoved up.
local function IsTrackerCollapsed()
	return type(tracker.IsCollapsed) == "function" and tracker:IsCollapsed() == true
end

-- "All Objectives" collapsed: Blizzard keeps the modules laid out (hidden)
-- and anchors the background to them, so with our tall frame a huge empty
-- shade stayed on screen. The frame keeps its geometry (shrinking it, or
-- re-enabling screen clamping, shoves it to the top of the screen); only
-- the background is hidden, after each of Blizzard's layouts, while
-- collapsed. Blizzard shows it again itself on expand (18 Oct 2026).
local function HideShadeWhileCollapsed()
	if tracker and tracker.NineSlice and IsTrackerCollapsed() then
		tracker.NineSlice:Hide()
	end
end

local function ApplyTrackerHeight()
	if not tracker then return end
	if visibleBounds then visibleBounds:SetHeight(VisibleHeight()) end
	if not settings or not settings.enabled then
		if settings and settings.height then tracker:SetHeight(settings.height) end
		return
	end
	if InEditMode() then
		if clampWasOn ~= nil then
			tracker:SetClampedToScreen(clampWasOn)
			clampWasOn = nil
		end
		tracker:SetHeight(VisibleHeight())
	else
		if clampWasOn == nil then
			clampWasOn = tracker:IsClampedToScreen() and true or false
			tracker:SetClampedToScreen(false)
		end
		EnsureTopAnchor()
		tracker:SetHeight(LAYOUT_HEIGHT)
	end
end

local function ApplySaved()
	if not settings then return end
	local p = settings.position
	if p and p.point then
		DetachFromManager()
		local clear, set = RawMethod("ClearAllPoints"), RawMethod("SetPoint")
		if clear and set then
			clear(tracker)
			set(tracker, p.point, UIParent, p.relativePoint or p.point, p.x or 0, p.y or 0)
		end
	end
	QOP.ApplyWidth(settings.width or tracker:GetWidth())
	ApplyTrackerHeight()
end

local function SavePosition()
	AnchorTopLeft()
	local point, _, relativePoint, x, y = tracker:GetPoint(1)
	if not point then return end
	settings.position = { point = point, relativePoint = relativePoint or point, x = x or 0, y = y or 0 }
	DetachFromManager()
	Debug("position saved: %s %s %.0f %.0f", point, settings.position.relativePoint, settings.position.x, settings.position.y)
end

local function SetupMoveResize()
	if dragHandle or not tracker.Header then return end

	-- the visible rectangle: the frame itself is much taller (see ApplyFrameHeight)
	visibleBounds = CreateFrame("Frame", nil, tracker)
	visibleBounds:SetPoint("TOPLEFT", tracker, "TOPLEFT", 0, 0)
	visibleBounds:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", 0, 0)
	visibleBounds:SetHeight(VisibleHeight())
	visibleBounds:SetResizable(true)
	if visibleBounds.SetResizeBounds then visibleBounds:SetResizeBounds(200, 120, 600, 2000) end
	-- while the grip is dragged: width follows live, content refits to the height
	visibleBounds:SetScript("OnSizeChanged", function(self)
		if not isSizing then return end
		QOP.ApplyWidth(self:GetWidth())
		RequestReflow()
	end)

	-- drag handle over the "All Objectives" title (leaves the minimize button free)
	dragHandle = CreateFrame("Frame", nil, tracker.Header)
	dragHandle:SetPoint("TOPLEFT", tracker.Header, "TOPLEFT", 0, 0)
	dragHandle:SetPoint("BOTTOMLEFT", tracker.Header, "BOTTOMLEFT", 0, 0)
	if tracker.Header.MinimizeButton then
		dragHandle:SetPoint("RIGHT", tracker.Header.MinimizeButton, "LEFT", -2, 0)
	else
		dragHandle:SetPoint("RIGHT", tracker.Header, "RIGHT", -30, 0)
	end
	dragHandle:EnableMouse(true)
	dragHandle:RegisterForDrag("LeftButton")
	dragHandle:SetScript("OnDragStart", function()
		if settings.locked or not settings.enabled then return end
		tracker:SetMovable(true)
		tracker:StartMoving()
		isDragging = true
	end)
	dragHandle:SetScript("OnDragStop", function()
		if not isDragging then return end
		isDragging = false
		tracker:StopMovingOrSizing()
		SavePosition()
	end)
	-- right-click: options menu (defined with the slash commands below)
	dragHandle:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" and QOP.ShowMenu then QOP.ShowMenu(self) end
	end)

	-- outline shown while resizing so the real bounds are visible
	resizeOutline = CreateFrame("Frame", nil, tracker, BackdropTemplateMixin and "BackdropTemplate" or nil)
	-- anchored to the bounds, not to the panel background: anchoring to the
	-- NineSlice broke resizing outright (18 Oct 2026, cause not yet known)
	resizeOutline:SetPoint("TOPLEFT", visibleBounds, "TOPLEFT", -30, 0)
	resizeOutline:SetPoint("BOTTOMRIGHT", visibleBounds, "BOTTOMRIGHT", 5, 0)
	resizeOutline:SetFrameStrata("MEDIUM")
	resizeOutline:SetFrameLevel(tracker:GetFrameLevel() + 10)
	if resizeOutline.SetBackdrop then
		resizeOutline:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
		resizeOutline:SetBackdropBorderColor(1, 0.82, 0, 0.7)
	end
	resizeOutline:Hide()

	-- resize grip at the frame's bottom-right corner
	resizeGrip = CreateFrame("Button", nil, tracker)
	resizeGrip:SetSize(20, 20)
	resizeGrip:SetPoint("BOTTOMRIGHT", visibleBounds, "BOTTOMRIGHT", 6, -4)
	resizeGrip:SetFrameStrata("MEDIUM")
	resizeGrip:SetFrameLevel(tracker:GetFrameLevel() + 11)
	-- the bright "highlight" grabber as the resting texture; the plain one is too faint
	resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	-- the stock grabber is faint; tint it gold so it reads against any backdrop
	local normal = resizeGrip:GetNormalTexture()
	if normal then normal:SetVertexColor(1, 0.82, 0) end
	resizeGrip:SetScript("OnEnter", function()
		if normal then normal:SetVertexColor(1, 1, 1) end
		resizeOutline:Show()
	end)
	resizeGrip:SetScript("OnLeave", function()
		if normal then normal:SetVertexColor(1, 0.82, 0) end
		if not isSizing then resizeOutline:Hide() end
	end)
	resizeGrip:SetScript("OnMouseDown", function(_, button)
		if button ~= "LeftButton" or settings.locked or not settings.enabled then return end
		EnsureTopAnchor()
		-- size the visible rectangle; a single anchor lets it resize freely
		visibleBounds:ClearAllPoints()
		visibleBounds:SetPoint("TOPLEFT", tracker, "TOPLEFT", 0, 0)
		visibleBounds:SetSize(tracker:GetWidth(), VisibleHeight())
		isSizing = true
		visibleBounds:StartSizing("BOTTOMRIGHT")
		resizeOutline:Show()
	end)
	resizeGrip:SetScript("OnMouseUp", function()
		if not isSizing then return end
		visibleBounds:StopMovingOrSizing()
		isSizing = false
		resizeOutline:Hide()
		settings.width = math.floor(visibleBounds:GetWidth() + 0.5)
		settings.height = math.floor(visibleBounds:GetHeight() + 0.5)
		-- vertical snaps to whole quests, like Blizzard's panel; width stays free
		local snapsList = QOP.snapHeights
		if snapsList and #snapsList > 0 then
			local best, smallest
			for _, v in ipairs(snapsList) do
				if v <= settings.height + 1 and (not best or v > best) then best = v end
				if not smallest or v < smallest then smallest = v end
			end
			settings.height = math.floor((best or smallest) + 0.5)
		end
		visibleBounds:ClearAllPoints()
		visibleBounds:SetPoint("TOPLEFT", tracker, "TOPLEFT", 0, 0)
		visibleBounds:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", 0, 0)
		SavePosition()
		ApplySaved()
		Reflow()
		Debug("size saved: %d x %d", settings.width, settings.height)
	end)

	-- Hold the saved width whenever the frame's size changes for other reasons
	-- (while the grip is dragged, `bounds` drives the width instead).
	if type(tracker.OnSizeChanged) == "function" then
		hooksecurefunc(tracker, "OnSizeChanged", function()
			if not settings or not settings.enabled or isSizing then return end
			QOP.ApplyWidth(settings.width or tracker:GetWidth())
		end)
	end

	-- Blizzard recomputes the height on show and on layout changes; put ours back.
	if type(tracker.UpdateHeight) == "function" then
		hooksecurefunc(tracker, "UpdateHeight", ApplyTrackerHeight)
	end
	-- Collapsing or expanding "All Objectives" switches between Blizzard's
	-- header-only height and our tall layout height (and hides the grip).
	if type(tracker.SetCollapsed) == "function" then
		hooksecurefunc(tracker, "SetCollapsed", function()
			HideShadeWhileCollapsed()
			UpdateGrip()
		end)
	end
	-- Blizzard re-shows the background on every layout, so the background's
	-- own Show is hooked and undoes itself while collapsed. (Hooking the
	-- container's stored dirty callback instead broke MarkDirty: the hook
	-- wrapper is not accepted by C_Timer.After. 18 Oct 2026.)
	if tracker.NineSlice and type(tracker.NineSlice.Show) == "function" then
		hooksecurefunc(tracker.NineSlice, "Show", function(self)
			if IsTrackerCollapsed() then self:Hide() end
		end)
	end
	-- Edit Mode gets the visible height while it is open, the tall one after.
	if type(tracker.OnEditModeEnter) == "function" then
		hooksecurefunc(tracker, "OnEditModeEnter", ApplyTrackerHeight)
	end
	if type(tracker.OnEditModeExit) == "function" then
		hooksecurefunc(tracker, "OnEditModeExit", function() C_Timer.After(0, ApplySaved) end)
	end
	-- Edit Mode re-anchors the tracker when a layout is applied; put ours back.
	if type(tracker.ApplySystemAnchor) == "function" then
		hooksecurefunc(tracker, "ApplySystemAnchor", function()
			if settings and settings.position then C_Timer.After(0, ApplySaved) end
		end)
	end
end

UpdateGrip = function()
	if resizeGrip then resizeGrip:SetShown(settings.enabled and not settings.locked and not IsTrackerCollapsed()) end
end

-------------------------------------------------------------------------------
-- Click on the "Quests" header: our own collapse
-------------------------------------------------------------------------------

-- Blizzard's minimize button must not be clicked from addon code (its
-- ToggleCollapsed marks the module dirty, which would taint the next layout),
-- so the header text toggles a flag of ours that the reflow honours. Only
-- the header art is touched, which SetCollapsed does with texture calls.

local questsHeaderHandle

local function SetQuestsHeaderArt()
	local header = questModule and questModule.Header
	if header and header.SetCollapsed then
		pcall(header.SetCollapsed, header, settings.questsCollapsed or questModule:IsCollapsed())
	end
end

function QOP.ToggleQuests()
	if not settings then return end
	settings.questsCollapsed = not settings.questsCollapsed
	SetQuestsHeaderArt()
	Reflow()
end

local function SetupQuestsHeader()
	local header = questModule.Header
	if questsHeaderHandle or not header then return end
	-- The overlay covers the whole header, minimize button included: Blizzard's
	-- button collapses the entire module, which hides the turn-in section
	-- inside it, so its click is taken over and does our collapse instead
	-- (user request, 18 Oct 2026). The button's art still shows our state.
	questsHeaderHandle = CreateFrame("Frame", nil, header)
	questsHeaderHandle:SetAllPoints(header)
	questsHeaderHandle:SetFrameLevel(header:GetFrameLevel() + 5)
	questsHeaderHandle:EnableMouse(true)
	questsHeaderHandle:SetScript("OnMouseUp", function(_, button)
		if button == "LeftButton" and settings and settings.enabled then QOP.ToggleQuests() end
	end)
	-- expanding with Blizzard's own button also clears our collapse
	if type(questModule.SetCollapsed) == "function" then
		hooksecurefunc(questModule, "SetCollapsed", function(_, collapsed)
			if not collapsed and settings and settings.questsCollapsed then settings.questsCollapsed = false end
		end)
	end
	SetQuestsHeaderArt()
end

-------------------------------------------------------------------------------
-- Hooks and events
-------------------------------------------------------------------------------

local hooked = false

local function InstallHooks()
	if hooked then return end
	tracker = _G.ObjectiveTrackerFrame
	questModule = _G.QuestObjectiveTracker
	if not tracker or not questModule or not questModule.ContentsFrame then
		Print("Blizzard's objective tracker was not found; nothing to do.")
		return
	end
	if type(questModule.EndLayout) ~= "function" or type(questModule.UpdateHeight) ~= "function" then
		Print("QuestObjectiveTracker.EndLayout/UpdateHeight not found; the tracker code changed. Run /qopprobe.")
		return
	end
	hooked = true
	-- EndLayout is the last step of every quest-module layout. A layout that
	-- Blizzard skips (nothing dirty) leaves our arrangement untouched.
	hooksecurefunc(questModule, "EndLayout", function() Reflow() end)
	hooksecurefunc(questModule, "UpdateHeight", ApplyQuestModuleHeight)
	-- Blizzard's completion/removal animations slide the module and re-anchor
	-- its own first block to the top every frame; once a slide ends, lay out
	-- again so our order wins.
	if type(questModule.EndSlide) == "function" then
		hooksecurefunc(questModule, "EndSlide", function() RequestReflow() end)
	end
	SetupMoveResize()
	UpdateGrip()
	SetupQuestsHeader()
	InstallMapHook()
	-- shares made from the quest log or Blizzard's context menu count too
	if QuestUtil and type(QuestUtil.ShareQuest) == "function" then
		hooksecurefunc(QuestUtil, "ShareQuest", NoteShare)
	end
	if type(QuestLogPushQuest) == "function" and C_QuestLog.GetSelectedQuest then
		hooksecurefunc("QuestLogPushQuest", function() NoteShare(Safe(nil, C_QuestLog.GetSelectedQuest)) end)
	end
	Debug("hooks installed")
end

QOP:RegisterEvent("ADDON_LOADED")
QOP:RegisterEvent("PLAYER_LOGIN")
QOP:RegisterEvent("PLAYER_ENTERING_WORLD")
QOP:RegisterEvent("GROUP_ROSTER_UPDATE")
QOP:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
QOP:RegisterEvent("PLAYER_REGEN_ENABLED")
QOP:RegisterEvent("QUEST_LOG_UPDATE")
QOP:RegisterEvent("CHAT_MSG_SYSTEM")
QOP:RegisterEvent("BAG_UPDATE_DELAYED")
QOP:RegisterEvent("BAG_UPDATE_COOLDOWN")
QOP:RegisterEvent("PLAYER_XP_UPDATE")
QOP:RegisterEvent("PLAYER_LEVEL_UP")
QOP:RegisterEvent("UPDATE_EXHAUSTION")

QOP:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then return end
		QuestObjectivesPlusDB = QuestObjectivesPlusDB or {}
		settings = QuestObjectivesPlusDB
		CopyDefaults(settings, DEFAULTS)
		-- one-time migration (18 Oct 2026): the items strip shipped on, and is now off by default
		if not settings.migratedItemsOff then
			settings.migratedItemsOff = true
			settings.items = false
		end
		settings.xpColor = nil   -- the colour is fixed now; drop the old saved value
		settings.completedBy = nil   -- superseded by settings.unshareable (18 Oct 2026)
		settings.tag = nil           -- the "Only you" tag was removed (18 Oct 2026)
		if type(settings.sort) ~= "string" then settings.sort = "none" end   -- an older boolean `sort` setting
		self:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_LOGIN" then
		InstallHooks()
		-- safety net: party progress has no event of its own for every change
		-- (and can be unavailable right when a quest completes), so while
		-- grouped the lines are refreshed every few seconds regardless
		C_Timer.NewTicker(5, function()
			if settings and settings.enabled and settings.party and IsInGroup() then RequestReflow() end
		end)
	elseif event == "PLAYER_ENTERING_WORLD" then
		C_Timer.After(0.5, function()
			ApplySaved()
			Reflow()
			QOP.RequestXPUpdate()
			QOP.RequestItemsUpdate()
		end)
	elseif event == "CHAT_MSG_SYSTEM" then
		OnSystemMessage(arg1)
	elseif event == "BAG_UPDATE_DELAYED" then
		QOP.RequestItemsUpdate()
	elseif event == "BAG_UPDATE_COOLDOWN" then
		UpdateItemCooldowns()
	elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_REGEN_ENABLED" then
		if event == "PLAYER_REGEN_ENABLED" and detachPending then
			detachPending = false
			ApplySaved()
		end
		RequestReflow()
		QOP.RequestXPUpdate()
		if event == "PLAYER_REGEN_ENABLED" and itemsPending then QOP.RequestItemsUpdate() end
	elseif event == "UNIT_QUEST_LOG_CHANGED" then
		if arg1 ~= "player" then
			RequestReflow()
			QOP.RequestXPUpdate()
		end
	elseif event == "QUEST_LOG_UPDATE" then
		-- party progress for a quest that just changed can lag the event by a
		-- moment; a second pass shortly after catches it
		RequestReflow()
		QOP.RequestXPUpdate()
	elseif event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" or event == "UPDATE_EXHAUSTION" then
		QOP.RequestXPUpdate()
	end
end)

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------

local function OnOff(v) return v and "|cff44ff44on|r" or "|cffff4444off|r" end

local TOGGLES = {
	group  = "finished quests under a \"Ready for turn-in\" header",
	party  = "party members' progress under each quest",
	compact = "one line per status listing the members on it (off: one line per member)",
	share  = "\"Not on quest\" line with a Share button on shareable quests",
	counts = "active-quest count on the Quests header",
	maptip = "party progress on world map quest pin tooltips",
	xp     = "pending turn-in XP on the XP bar and the section header",
	items  = "usable quest items from your bags beside the tracker",
	instance = "inside a dungeon, its quests first in each section",
	zone   = "outside, the current zone's quests first in each section",
	lock   = "lock position and size (no dragging, grip hidden)",
}

local function Help()
	Print("Quest Objectives+ commands (or right-click the \"All Objectives\" bar):")
	Print("  /qop on | off       enable or disable the whole addon (%s)", OnOff(settings.enabled))
	Print("  /qop group          %s (%s)", TOGGLES.group, OnOff(settings.group))
	Print("  /qop party          %s (%s)", TOGGLES.party, OnOff(settings.party))
	Print("  /qop compact        %s (%s)", TOGGLES.compact, OnOff(settings.compact))
	Print("  /qop share          %s (%s)", TOGGLES.share, OnOff(settings.share))
	Print("  /qop maptip         %s (%s)", TOGGLES.maptip, OnOff(settings.maptip))
	Print("  /qop xp             %s (%s)", TOGGLES.xp, OnOff(settings.xp))
	Print("  /qop items          %s (%s)", TOGGLES.items, OnOff(settings.items))
	Print("  /qop instance       %s (%s)", TOGGLES.instance, OnOff(settings.instance))
	Print("  /qop zone           %s (%s)", TOGGLES.zone, OnOff(settings.zone))
	Print("  /qop sort none|asc|desc   order within each section: unsorted, level lowest first, level highest first (%s)", settings.sort or "none")
	Print("  /qop counts         %s (%s)", TOGGLES.counts, OnOff(settings.counts))
	Print("  /qop collapse       collapse or expand the turn-in section (%s)", settings.collapsed and "collapsed" or "expanded")
	Print("  /qop lock           %s (%s)", TOGGLES.lock, OnOff(settings.locked))
	Print("  /qop reset          forget the saved position and size (takes effect after /reload)")
	Print("  /qop debug          chat messages about what the addon does (%s)", OnOff(debug))
end

local function SetToggle(key, value)
	settings[key] = value
	if key == "zone" or key == "instance" then autoTrackedFor = nil end   -- re-run the once-per-visit tracking
	Reflow()
	QOP.RequestXPUpdate()
	QOP.RequestItemsUpdate()
end

local function ResetPosition()
	settings.position = false
	settings.height = false
	settings.width = false
	Print("saved position and size forgotten; /reload puts the tracker back where Edit Mode has it.")
end

-- Right-click menu on the "All Objectives" bar: the same switches as the
-- slash commands, so nothing needs typing once the tracker is set up.
function QOP.ShowMenu(owner)
	if not MenuUtil or type(MenuUtil.CreateContextMenu) ~= "function" then
		Help()
		return
	end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle("Quest Objectives+")
		root:CreateCheckbox("Lock position and size",
			function() return settings.locked end,
			function()
				settings.locked = not settings.locked
				UpdateGrip()
			end)
		root:CreateDivider()
		local function Toggle(key, label)
			root:CreateCheckbox(label,
				function() return settings[key] end,
				function() SetToggle(key, not settings[key]) end)
		end
		Toggle("group", "Finished quests in a \"Ready for turn-in\" section")
		Toggle("party", "Party members' progress under each quest")
		Toggle("compact", "Group members by status (fewer lines)")
		Toggle("share", "Share button on quests a party member lacks")
		Toggle("maptip", "Party progress on map quest pin tooltips")
		Toggle("xp", "Pending turn-in XP on the XP bar")
		Toggle("items", "Usable quest items beside the tracker")
		Toggle("instance", "Dungeon quests first while inside it")
		Toggle("zone", "Zone quests first while in it")
		root:CreateDivider()
		-- one "Sort" entry showing the current choice; its submenu holds the options
		local SORT_LABELS = { none = "Unsorted", asc = "Level, lowest first", desc = "Level, highest first" }
		local current = SORT_LABELS[settings.sort or "none"] or SORT_LABELS.none
		local sortMenu = root:CreateButton("Sort: " .. current)
		local function SortChoice(label, mode)
			local isOn = function() return (settings.sort or "none") == mode end
			local pick = function() settings.sort = mode; Reflow() end
			if sortMenu.CreateRadio then sortMenu:CreateRadio(label, isOn, pick) else sortMenu:CreateCheckbox(label, isOn, pick) end
		end
		SortChoice(SORT_LABELS.none, "none")
		SortChoice(SORT_LABELS.asc, "asc")
		SortChoice(SORT_LABELS.desc, "desc")
		Toggle("counts", "Active-quest count on the Quests header")
		root:CreateDivider()
		root:CreateButton("Reset position and size (needs /reload)", ResetPosition)
	end)
end

SLASH_QUESTOBJECTIVESPLUS1 = "/qop"
SlashCmdList.QUESTOBJECTIVESPLUS = function(msg)
	local cmd = strtrim((msg or ""):lower())
	if cmd == "on" or cmd == "off" then
		settings.enabled = (cmd == "on")
		Print("addon %s", OnOff(settings.enabled))
		UpdateGrip()
		if settings.enabled then ApplySaved() end
		Reflow()
		QOP.RequestXPUpdate()
		QOP.RequestItemsUpdate()
	elseif cmd == "group" or cmd == "party" or cmd == "compact" or cmd == "share" or cmd == "counts" or cmd == "maptip" or cmd == "xp" or cmd == "items" or cmd == "instance" or cmd == "zone" then
		SetToggle(cmd, not settings[cmd])
		Print("%s: %s", TOGGLES[cmd], OnOff(settings[cmd]))
	elseif cmd:match("^sort") then
		local mode = cmd:match("^sort%s+(%a+)")
		if mode == "none" or mode == "asc" or mode == "desc" then
			settings.sort = mode
			Reflow()
		end
		Print("sort: %s (none = unsorted, asc = level lowest first, desc = level highest first)", settings.sort or "none")
	elseif cmd == "lock" then
		settings.locked = not settings.locked
		Print("%s: %s", TOGGLES.lock, OnOff(settings.locked))
		UpdateGrip()
	elseif cmd == "collapse" then
		ToggleTurnInSection()
	elseif cmd == "reset" then
		ResetPosition()
	elseif cmd == "err" then
		-- the last layout error in short pieces, since chat clips long lines
		local e = QOP.lastError or "no layout error so far"
		for i = 1, #e, 70 do Print("%s", e:sub(i, i + 69)) end
	elseif cmd == "debug" then
		debug = not debug
		Print("debug %s", OnOff(debug))
	else
		Help()
	end
end
