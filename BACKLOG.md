# Quest Objectives+ backlog

## Inbox
- [ ] Update the Profession section to behave like the other sections: clicking its header expands and collapses it. *(idea 2026-11-09)*
- [ ] Update Quest Objectives+ with more useful features: Wowhead links for some quests, searching old/completed quests, maybe a robust audit that checks you and your party's quests are all synced; adjust font size and look into window adjustment bugs. *(idea 2026-11-09)*
- [ ] Auto share quests you pick up with party members. *(idea 2026-11-09)*
- [ ] Info box for quests that are part of a chain, which can be expanded to show the list of quests in that chain. *(idea 2026-11-09)*


## Done

- [x] Research: no existing Forever addon enhances the default tracker; party counts available via C_TooltipInfo.GetQuestPartyProgress (17 Oct 2026)
- [x] Read Blizzard's forever-branch tracker and Edit Mode code; chose the post-layout reflow design to keep quest item buttons untainted (17 Oct 2026)
- [x] Project scaffold: README, backlog, CLAUDE.md, addon and probe folders junctioned into the beta client (17 Oct 2026)
- [x] Core 0.1.0: reflow engine, "Ready for turn-in" section, party progress lines, solo tag, drag and resize, /qop commands
- [x] First in-game run: `/qopprobe` in a party, report pasted into CLAUDE.md; section and party lines confirmed working (17 Oct 2026)
- [x] Party lines reformatted from the real line types: one line per member on the quest, class colours, "Not on quest" members dropped
- [x] Active quests never cut off: the frame handed to Blizzard is kept tall (every tracked quest gets a block) and the reflow enforces the visible height, dropping finished quests first. Replaces the watch-list reorder, which did nothing on this client (17 Oct 2026)
- [x] Width resizing (grip sizes both axes; modules and headers follow); verified in game, survives /reload and Edit Mode open/close (17 Oct 2026)
- [x] Header art scaled from its native width so the minimize buttons stay on the art when widened; verified at a wide setting (17 Oct 2026)
- [x] Right-click options menu on the "All Objectives" bar (lock, feature toggles, reset)
- [x] Resize grip made visible: 20 px, opaque, gold, white on hover
- [x] Share line: "Not on quest: Name" with a Share button on pushable, unfinished quests a party member lacks (`/qop share`)
- [x] Probe prints GetQuestLogSpecialItemInfo / QuestShowsItemByIndex / IsPushableQuest per tracked quest
- [x] Clicking a quest title in combat opens the quest log with no addon error (17 Oct 2026)
- [x] Quest item missing for "A Lesson in Divinity" explained: the quest log links no item to it (`GetQuestLogSpecialItemInfo` returns nothing); RestedXP shows it from its own database (17 Oct 2026)
- [x] Party progress on world map quest pin tooltips (`/qop maptip`), via the pin's `MapCanvas.QuestPin.OnEnter` registry event
- [x] Pending turn-in XP (`/qop xp`): green segment on the XP bar, line in the XP bar tooltip, tooltip on the "Ready for turn-in" header
- [x] "Not on quest" finally matched: the game's string is `QUEST_PROGRESS_TOOLTIP_NOT_ON_QUEST` = `|cff7f7f7fNot on quest|r` (colour code inside); keys now strip colour codes, and the global is used for other locales. Unblocks the Share line and the party-aware done rule (18 Oct 2026)
- [x] Party-aware done: a finished quest a party member is still on stays in Quests (count, XP, position), re-evaluated on roster and party quest-log changes; turn-in header always shown with the log-wide finished count (17 Oct 2026)
- [x] Click on the "Quests" header collapses/expands the section (own flag, never Blizzard's dirty path); turn-in header always shown, active quests shrink first when the visible height is short (17 Oct 2026)
- [x] XP segment is a plain colour; picker used to settle on gold (1.0, 0.863, 0.239, a 0.9), then removed along with its settings and commands; segment inset 1 px so it stays inside the bar art (18 Oct 2026)
- [x] Header art spans the shaded panel at any width; margin 12 / shift 4.5 tuned in game and baked in, tuning commands removed (18 Oct 2026)
- [x] Grouped-only layout error found and fixed: `CanShare` called `IsCompleteForMe` (then `IsQuestDone`) before that local was defined, so the call hit a nil global whenever a share line was possible; the pass died after updating text and before re-anchoring, leaving Blizzard's anchors under our frames (the "spacing" and "Only you overlap" reports). Forward-declared; a scan confirms no other local is used before its definition (18 Oct 2026)
- [x] Equal-share filling: when the height cannot hold everything, one quest from each section in turn until one runs out (replaces active-first with a promised share); snaps follow the same sequence (18 Oct 2026)
- [x] Usable quest items strip (`/qop items`): secure buttons for quest-class bag items with a Use effect, docked left of the tracker; built 18 Oct 2026, unverified. Now OFF by default: Blizzard's own per-quest item button is preferred, the strip is the fallback for unlinked items (A Lesson in Divinity is likely a new-quest outlier)
- [x] Zone quests first (`/qop zone`, on by default): outside instances the current zone's quests (quest-log header match, map marker backup) top each section and untracked ones are tracked once per visit; header reads `Quests (4) - The Barrens` with "The " dropped, then the name, when it would not fit; dungeon rule unchanged and separate (designed with /grill-me, 19 Oct 2026, unverified)
- [x] "Only you" tag removed from the panel, the map tooltip, the menu and settings: the Not-on-quest line covers it (user decision, 18 Oct 2026)
- [x] Level sort (`/qop sort none|asc|desc`, menu radio): within each section, after instance-first and party-done-last, then Blizzard's order as tiebreak; applies inside dungeons (18 Oct 2026, unverified)
- [x] Share button restyled as a small quest-log style `UIPanelButtonTemplate` (18 Oct 2026, unverified)
- [x] Share replies remembered: after a share (ours, quest log or context menu) the system messages are matched to that quest for 15 s; "has completed" is saved per character (`settings.completedBy`), "cannot take" for the session. Such members leave the Not-on-quest line, the Share button goes when nobody is left, and completed members no longer block "party all done" (18 Oct 2026, from a live party test)
- [x] Instance quests first (`/qop instance`): inside a dungeon or raid, quests with a marker on the current map or whose map is a floor of the instance go to the top of their section; built 18 Oct 2026, unverified
- [x] Compact party lines (`/qop compact`): members grouped by status, name first, objective-size font; quests the whole party has finished sink to the bottom of the turn-in section (5-man screenshot, 17 Oct 2026)
## Next

Needs an in-game look:
- [ ] Verify the quest items strip: appears with a usable quest item in bags (Symbol of Life), click uses it, cooldown shows, hides when the item is gone, survives a bag change during combat (applied after), no "action blocked" errors
- [ ] Verify instance-first ordering in RFC: "The Power to Destroy" (finished) tops the turn-in section and an untracked RFC quest gets tracked on entry. Matching is by quest-log header name vs `GetInstanceInfo()`; `/qopprobe` prints the headers, the map chain, `GetQuestsOnMap` and `GetQuestUiMapID`. Decide on exit: keep auto-tracked quests tracked (current) or untrack them
- [ ] Verify zone-first: header text and trimming at narrow widths, auto-tracking on zone entry, zone count, switching the setting off restores the total count
- [ ] Verify level sort in both directions, including inside RFC (dungeon quests on top, in the chosen order), and the new Share button look
- [ ] Verify equal-share filling: with a short panel, quests alternate from each section; collapse one and the other fills; snaps still flush
- [ ] Verify the XP bar segment draws past the current XP (and under it when rested XP overlaps), updates on turn-in, hides at max level; `/qopprobe` now prints `GetQuestLogRewardXP` per quest and the exp bar layout
- [ ] Verify the map pin tooltip lines (grouped, hover a quest marker on the world map); minimap markers are drawn by the engine and not covered yet

Needs a questing partner:
- [ ] Verify per-member progress lines on a shared quest in progress
- [ ] Verify the Share line and button (partner without one of your quests)
- [ ] Verify vertical resize snapping to whole quests (outline and panel bottom now agree by construction); the earlier NineSlice-anchored outline broke resizing outright and was reverted (18 Oct 2026)
- [ ] Verify the tall-frame layout: active quests always show, the grip/outline match the visible content, Edit Mode shows a sane box, nothing is clamped or shoved up the screen

Needs a quest with a usable item:
- [ ] Verify the quest item button (square icon right of a title) still works in combat after the addon rearranged blocks

Code:
- [ ] Before the friends beta: revisit every switch in the right-click menu and `/qop` (group, party, compact, share, counts, maptip, xp, items, instance, sort, lock, collapse, reset) and prune or merge. Candidates: fold `counts` into `group` (nobody will toggle it alone), hide `items` unless needed, keep `lock`, `reset` and the feature-level switches. Done already: `tag` and `xpcolor` removed. Aim for a menu that fits on one screen with no explanation needed (18 Oct 2026)
- [ ] dist zip for testers

## Ideas

- [ ] Party progress on minimap quest markers: their tooltips come from the engine; check `Enum.TooltipDataType.MinimapMouseover` and whether its data carries a questID
- [ ] Loot reminder for boss drops (reviewed 18 Oct 2026). Goal: after a boss dies, flag quests that still need an item from it, until everyone on the quest has looted or the quest completes. Findings: there is no drop-table API, and the combat log is unavailable on Forever, so "which boss drops it" and "a kill happened" cannot come from there. What is available: (a) `ENCOUNTER_END(encounterID, name, difficulty, size, success)` fires for instance bosses (Forever has the Encounter Journal, so bosses should be flagged); (b) loot window events: `LOOT_OPENED`, then `GetNumLootItems()` / `GetLootSlotInfo(i)` return `isQuestItem` and `questID` per slot, and `LOOT_CLOSED`; (c) party counts via the existing party lines (`numFulfilled` per member). Plan in phases: 1. "Left on the corpse": on LOOT_CLOSED, if a quest item was still in the window, warn in chat and flash the quest in the tracker; reliable and needs no boss data. 2. Boss reminder: on a successful ENCOUNTER_END in an instance, highlight every instance quest with an incomplete item objective ("may need loot from this boss"); clear when the player's objective count rises, the quest completes, or after a timeout / leaving the instance. 3. Party: keep the highlight while any member on the quest has not progressed since the kill, and name them on the party line. Caveats: names and party data may be secret in instances (Midnight rules); test in a dungeon first.
- [ ] Raids (10-40 players): the party lines were designed for five names and will not scale. In a raid, grouping by status still helps, but a line like "Name, Name, ... x30: 3/8 Boar" is unreadable and the Share line could name 30 people. Options to decide between: counts instead of names above some size ("12 on quest, 7 ready, 21 not on quest") with names on hover; names for your own group only, counts for the rest of the raid; or party lines off in raids by default with a raid summary line. Also check `GetQuestPartyProgress` actually returns raid members and whether raid-size data is slow or secret (thought of 18 Oct 2026).
- [ ] Dungeon quest flair: make dungeon quests recognisable at a glance. The title already carries "(Dungeon)" from `QuestUtilsOverrides.GetQuestTagText` (Camelot override); options are a small icon (the quest-log dungeon tag atlas) before the title, a tinted title, or grouping them. Detect via the tag text or `C_QuestLog.GetQuestTagInfo(questID)`.
- [ ] Scrollable tracker: all blocks are anchored by the addon already, so a wheel-scrolled offset on the first block plus `ContentsFrame:SetClipsChildren(true)` would scroll everything (item/POI buttons are children of ContentsFrame and clip too). Considered 17 Oct 2026; the 40% split for the turn-in section was chosen first as it keeps Blizzard's fixed feel.
- [ ] Highlight the quest a party member is currently super-tracking
- [ ] Hide quests from other zones behind a second collapsible section
- [ ] Right-click the "Ready for turn-in" header for "abandon all" / "share all"
