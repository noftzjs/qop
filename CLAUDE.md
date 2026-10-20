# Quest Objectives+: quest tracker addon for WoW Forever

Project notes for Claude. Scaffolded 17 Oct 2026 from Blizzard's `forever`
branch sources. First in-game run 17 Oct 2026 (build 70450): the section
header and party lines work; the probe report is at the end of this file.
The beta closes 21 Oct 2026, launch is 4 Nov 2026.

## Who and what

- Author line in every TOC: `## Author: Cyklades`. Never the Windows username.
- Addon name: `QuestObjectivesPlus` (folder and TOC), title "Quest Objectives+",
  short name QOP. Saved variables: `QuestObjectivesPlusDB`. Slash
  command `/qop`. CurseForge slug (quest-objectives-plus) not checked (curl gets 403 from CurseForge).
- Goal: improve Blizzard's default quest tracker without replacing it. Finished
  quests in a collapsible "Ready for turn-in" section, party members' progress
  under each quest, move/resize without Edit Mode. Earlier ideas (nameplate
  marks, world markers, pings) were researched and dropped: pings are
  protected (`C_Ping.*` secure-only), world markers need a cursor click, and
  game objects have no readable position.
- Style: dependency-free Lua, no Ace3, same house style as `no_sir` and `Boon`
  (`Print`, `Accessible`, `Safe`, `CopyDefaults`).
- The user leaves work uncommitted for review and wants a commit message
  offered. Read-only git is fine. This folder is not a git repo yet.

## Layout

- `QuestObjectivesPlus/`: the addon (`.toc`, `QuestObjectivesPlus.lua`).
- `QuestObjectivesPlus_probe/`: dev-only probe, `/qopprobe`, copyable report
  window (copied from `no_sir_probe`). Not shipped.
- Both are junctioned into
  `C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns`
  (done 17 Oct 2026; `New-Item -ItemType Junction` works without elevation).
- Blizzard reference sources used for the design were downloaded from
  `https://github.com/Gethe/wow-ui-source` branch `forever`, folder
  `Interface/AddOns/Blizzard_ObjectiveTracker` (plus `Camelot/` overrides) and
  `Blizzard_EditMode/Shared`. Re-fetch them rather than guessing.

## The client (verified by the no_sir project, 9 Oct 2026)

WoW Forever beta 1.60.1, TOC `## Interface: 16001`, modern 12.1.5 API with
Midnight secret values. See `C:\Users\noftz\Dev\no_sir\CLAUDE.md` for the
API facts (missing globals, `canaccessvalue`, Settings panel registration,
scroll frame pattern, luaparser syntax check).

## Verified in game (probe, 17 Oct 2026, build 1.60.1.70450)

- Every API the addon uses exists: `C_TooltipInfo.GetQuestPartyProgress`,
  `QuestObjectiveTracker.EndLayout/UpdateHeight/BuildQuestWatchInfos`,
  `ObjectiveTrackerFrame.SetPointBase/ClearAllPointsBase/BreakFromFrameManager/
  ApplySystemAnchor/IsInDefaultPosition`, `C_XMLUtil.GetTemplateInfo`.
  `ObjectiveTrackerModuleHeaderTemplate` is 260x26.
- Module constants: headerHeight 25, fromHeaderOffsetY -10, fromBlockOffsetY
  -10, blockOffsetX 20, lineSpacing 4, bottomSpacing 0. A one-line block is
  28.07 high, a two-line block 40.10. `MAX_QUEST_WATCHES` = 25.
- Container dirty field is `dirtyCallback` (plus `SetDirtyMethod`). **Never
  hooksecurefunc it**: the hook wrapper is rejected by `C_Timer.After` in
  `DirtiableMixin:MarkDirty` ("bad argument #2"), which silently breaks
  every dirty update of the tracker (18 Oct 2026). For "after any
  container layout" hook the quest module's `EndLayout`, or the specific
  widget method Blizzard calls (e.g. `NineSlice.Show`).
- Module order: Scenario, UIWidget, CampaignQuest, Quest, Adventure,
  Achievement, MonthlyActivities, InitiativeTasks, ProfessionsRecipe, Bonus,
  WorldQuest. Only Quest was shown.
- The user's tracker was already off the default position (Edit Mode layout
  "def", not a preset, anchor RIGHT/RIGHT -233.7/34.1, editModeHeight 400).
  With 12 watches only 7 blocks fit (availableHeight 332): **Blizzard picks
  which blocks fit in watch order before our reflow runs**. Re-adding a
  watch (`RemoveQuestWatch` + `AddQuestWatch`) did not move it in the list
  (after a reload with 8 finished quests first, both active quests were
  missing), so the frame is kept tall instead; see Design.
- `GetQuestPartyProgress(id, true, true)` line shape: type 18 = member name
  (gold, `guid`), followed by type 8 lines: "Ready for turn-in" /
  "Not on quest" / "On quest" / "0/1 Sit near the campfire" (with `completed`,
  `numFulfilled`, `numRequired`, `wrapText`). With `omitTitle=false` a type 17
  title line comes first; with `ignoreActivePlayer=false` our own entry is
  included. No `rightText` anywhere. `GetQuestTagText` returned nothing for
  every quest tested.
- `C_Secrets.HasSecretRestrictions()` is true even out of combat; no value
  was secret during the probe (open world, no combat).
- Second run (solo, width 392 after a resize, 4 blocks): the quest log
  links **no** special item to "A Lesson in Divinity"
  (`GetQuestLogSpecialItemInfo(logIndex)` returns nothing, as it does for
  every quest tested), so Blizzard's tracker cannot show the Symbol of Life
  and neither can we from quest data; RestedXP shows it from its own
  quest-to-item database. `C_QuestLog.IsPushableQuest` is false for the
  three complete quests and true for the active one, which matches the
  share line's conditions.

## How the tracker works on this client (from source)

- `ObjectiveTrackerFrame` is a container; `QuestObjectiveTracker` is the quest
  module (global frame, `ObjectiveTrackerModuleTemplate`). A layout is
  `module:Update()` -> `BeginLayout` -> `LayoutContents` (iterates
  `BuildQuestWatchInfos()`, which sorts by callings/override/watch index, then
  `UpdateSingle` per quest -> `GetBlock`, `AddObjective`, `LayoutBlock`) ->
  `EndLayout` (frees unused blocks, `UpdateHeight`, Show/Hide).
- Displayed blocks form a chain `module.firstBlock` -> `block.nextBlock`,
  each anchored `TOP` to the previous block's `BOTTOM` with
  `fromBlockOffsetY` (-10); the first to `ContentsFrame` with
  `fromHeaderOffsetY` (-10). `block.height` is the text height, `block.id`
  the questID. Module height = `headerHeight` (25) + sum(block.height + 10) +
  `bottomSpacing` + `heightModifiers`.
- Right-edge frames (quest item button, find-group button) and timer/progress
  bars are parented to `module.ContentsFrame`, not the block, and listed in
  `block.addedRegions`. Blizzard only calls `Show()` on a right-edge frame when
  it is newly acquired.
- **The quest item button is a plain Button whose OnClick calls the protected
  `UseQuestLogSpecialItem`, reading `questLogIndex` from an attribute set
  during layout.** Any taint in the layout path (overriding
  `BuildQuestWatchInfos`, calling `MarkDirty`, inserting our own module into
  `container.modules`) would make those attributes tainted and block quest
  items in combat. The whole design follows from this.
- The dirty-update path captures `Update` in a closure at load
  (`SetDirtyMethod(GenerateClosure(self.Update, ...))`), so hooking
  `ObjectiveTrackerFrame.Update` misses most updates. `DirtiableMixin` was not
  found in the forever branch folders searched; the probe lists any
  `*dirty*` keys on the frame.
- Edit Mode owns the tracker position. `EditModeSystemMixin:OnSystemLoad`
  replaces `SetPoint`/`ClearAllPoints` with overrides that set
  `EditModeManagerFrame.editModeSystemAnchorDirty`; a later secure pass calls
  `ObjectiveTrackerFrame:Update()` for every system. The originals are saved
  as `SetPointBase` / `ClearAllPointsBase`. `UpdateHeight` uses
  `editModeHeight` only when not in the default position, otherwise it
  computes height from the first anchor's y offset. The Edit Mode Height
  slider is 400..1000 step 10. Preset layouts ("Modern") cannot be saved to.
- `C_TooltipInfo.GetQuestPartyProgress(questID, omitTitle, ignoreActivePlayer)`
  is listed for Forever 1.60.1 and allowed from addon code. Blizzard's own
  tracker calls `GameTooltip:SetQuestPartyProgress(block.id)` on block hover
  when grouped. Line layout unknown until the probe runs.
- Camelot override: `QuestObjectiveTrackerMixin:GetQuestTagText(questID)`
  returns `QuestUtilsOverrides.GetQuestTagText(questID)`, appended to titles.
  May reveal class/dungeon tags; the probe prints it.

## Design as built (0.1.0)

Naming pass 18 Oct 2026: identifiers were renamed for readability with no
behaviour change (`settings` was `db`, `RearrangeBlocks` was `DoReflow`,
`FillPartyLines` was `FillExtra`, `IsCompleteForMe`/`IsFinished` were
`IsQuestDone`/`QuestDone`). Older notes in the probe results section may
still use the old names.

Lua rule that bit us: a `local function` used above its definition resolves
to a nil global. `Reflow` and `IsCompleteForMe` are forward-declared for that
reason; `tools/scan_forward.py` reports new cases (run it after any edit
that adds or moves a local; it exits 1 on a hit). The
"grouped-only layout error" (18 Oct 2026) was exactly this: `CanShare` ->
`IsCompleteForMe`, only reachable with a party member lacking a quest.

Per-block party lookups in the reflow (`IsFinished`, `PartyLines`,
`FillPartyLines`, `CountFinishedInLog`) run through `Guarded`, a pcall that records the
error in `QOP.lastError` (`/qop err`) and returns a default, so one quest's
bad data cannot abort the pass (added 18 Oct 2026 after a grouped-only
error left Blizzard's layout showing under ours).

Post-layout reflow. `hooksecurefunc(QuestObjectiveTracker, "EndLayout")`
runs `Reflow()` after every quest-module layout; a layout Blizzard skips
leaves our arrangement in place. `Reflow` only calls frame methods
(`SetPoint`, `Show`, `Hide`, `SetHeight`, `SetText`) and keeps its own state
in addon-local tables keyed by block (`partyLineFrames`, `hiddenRightEdgeFrames`). It never
writes a field on a Blizzard table.

- Blocks are split by `IsFinished(id)`: `IsCompleteForMe` (`C_QuestLog.IsComplete`,
  or "no longer in the log" for the fade-out after turn-in) AND, when
  grouped, no party member still working on it (`PartyLines` `partyWorking`).
  So a quest you finished stays in Quests while a member is on it, moves to
  turn-in when they finish or leave, and back if they rejoin; counts and
  pending XP use the same rule (user requirement, 17 Oct 2026). The turn-in
  header shows whenever the log has a finished quest (`CountFinishedInLog`, tracked
  or not) and its count is that log-wide number, so untracking a finished
  quest hides its entry, not the number. Active blocks are re-anchored first,
  then our section holder (a `ObjectiveTrackerModuleHeaderTemplate` header
  parented to our holder, whose `ToggleCollapsed` the header's minimize
  button calls), then the finished blocks, hidden when collapsed. Hiding a
  block also hides its non-child regions and remembers them in
  `hiddenRightEdgeFrames` so they can be shown again.
- Quests header click: a mouse overlay on `questModule.Header` toggles
  `settings.questsCollapsed`; the reflow then hides the active blocks (the
  turn-in section is unaffected). The overlay covers the minimize button
  too (level +5), so Blizzard's own module collapse, which would hide the
  turn-in section inside the module, is no longer reachable by mouse
  (18 Oct 2026); `Header:SetCollapsed` keeps the button art in step. Blizzard's minimize button
  is never clicked from code (its `ToggleCollapsed` -> `MarkDirty` would
  taint the next layout); `Header:SetCollapsed` is only atlas swaps and is
  safe. A post-hook on `questModule.SetCollapsed` clears our flag when
  Blizzard's button expands the module.
- Party lines: our own frame under each block, `ObjectiveTrackerLineFont` font strings (same size as the objectives;
  a smaller font was tried and rejected), built from
  `GetQuestPartyProgress(questID, true, true)`. Compact mode (default,
  `/qop compact`) groups members by their status string:
  `Name, Name: status, status` in first-seen order; off gives one line per
  member `Name: status, status`. Names in class colour (via
  `GetPlayerInfoByGUID(line.guid)`), statuses green when `completed`.
  `ReadPartyLines` also returns `partyAllDone` (every member on the quest with
  every status completed); the reflow uses it to sink party-finished quests
  to the bottom of the turn-in section. The "Only you" tag (shown when no
  member was on a quest) was removed on 18 Oct 2026: the Not-on-quest line
  carries that information. The section itself stays keyed on
  the player's own completion. A member whose only line is "Not on quest" is dropped. The game's string
  is `QUEST_PROGRESS_TOOLTIP_NOT_ON_QUEST` = `|cff7f7f7fNot on quest|r`
  (Forever enUS GlobalStrings via Ketho/BlizzardInterfaceResources, branch
  `forever`), so `StatusKey` strips colour codes then keeps lowercase
  letters; the global is added to the match set for other locales. The
  probe's `%q` print had hidden the colour code (18 Oct 2026). No members left
  while grouped = "Only you" tag. Secret text keeps the last readable lines
  (`partyProgressCache`).
- Share line (`/qop share`): `ReadPartyLines` also returns the coloured
  names of members whose only line is "Not on quest". When the quest is
  pushable (`C_QuestLog.IsPushableQuest`) and not done, `FillPartyLines` adds a
  dim `Not on quest: Name, Name` line with a 50-wide quest-log style
  `UIPanelButtonTemplate` "Share" button at its right (`GetShareButton`,
  one per extra frame; plain button fallback) that calls
  `QuestUtil.ShareQuest(questID)`, the same call as Blizzard's context menu.
  That line replaces the "Only you" tag when both would apply.
- Share replies: the game answers a share with system messages that name
  the member but not the quest (`ERR_QUEST_PUSH_ALLDONE_S` "%s has completed
  that quest.", `ERR_QUEST_PUSH_INVALID_S` "%s cannot take that quest.").
  `NoteShare(questID)` records the last share (our button, a hook on
  `QuestUtil.ShareQuest`, and on `QuestLogPushQuest` with the selected
  quest); `OnSystemMessage` matches replies within 15 s against patterns
  built from the globals (`PatternFromGlobal`), keyed by first name (party
  lines give first names, messages give "First Surname"). The global is
  `ERR_QUEST_PUSH_ALREADY_DONE_S` (an `ALLDONE` guess never matched);
  permanent replies (completed, class, race, faction) are saved in
  `settings.unshareable[questID][first] = reason`; prerequisite,
  reputation and eligibility replies live in `cannotTake` for the session;
  level replies are ignored on purpose so a member about to level stays
  shareable. `CannotBeShared` filters the Not-on-quest
  line (tracker and map tooltip); `PermanentlyUnshareable` keeps such
  members from blocking `partyAllDone` (18 Oct 2026).
- Current area first (`/qop instance` inside dungeons, `/qop zone`
  outside; designed 19 Oct 2026): `RefreshAreaQuests` runs at the start of
  each pass. Inside a party/raid instance the area is `GetInstanceInfo()`'s
  name and matches fill `instanceQuests`; outside it is `GetRealZoneText()`
  and `zoneQuests`. `CollectByHeader` marks every quest filed under the
  quest-log header whose `StatusKey` matches the area name (works for
  finished quests, whose map is the turn-in spot; the map-only version
  missed "The Power to Destroy" in RFC) and, once per area name
  (`autoTrackedFor`, reset when the toggle changes), `AddQuestWatch`es the
  untracked ones under MAX_QUEST_WATCHES; nothing is untracked on leaving.
  `CollectByMap` adds `C_QuestLog.GetQuestsOnMap(playerMap)` and, for
  dungeons, watched quests whose `GetQuestUiMapID` shares the top dungeon
  map (`TopInstanceMap`); both APIs unconfirmed on Forever. Header
  (`SetQuestHeader`): with the relevant toggle on and an area known,
  `Quests (n) - Area` where n = `CountAreaQuests()` (tracked, unfinished,
  in the area); candidates full name, name without a leading "The ", count
  only, measured with a hidden `ObjectiveTrackerHeaderFont` string
  (`HeaderTextFits`) because Blizzard's header text auto-shrinks; with the
  toggle off, `Quests (total)` as before.
  `OrderBlocks` sorts each section with one comparator: dungeon quests
  first, then zone quests, then (turn-in section) party-finished last, then by level when
  `settings.sort` is "asc"/"desc" (`QuestLevel`: `C_QuestLog.
  GetQuestDifficultyLevel`, falling back to the "[12]" in the title), then
  Blizzard's order as the tiebreak (18 Oct 2026). An older boolean `sort`
  saved value is normalised to "none" on load. Leaving the instance clears the set, so
  the old order returns; auto-tracked quests stay tracked (open choice).
- Quest items strip (`/qop items`): `ScanQuestItems` walks bags 0..NUM_BAG_SLOTS
  with `C_Container.GetContainerItemInfo`, keeps items whose
  `C_Item.GetItemInfoInstant` classID is Questitem (12) and that have a
  `C_Item.GetItemSpell`, up to 8. Buttons are `SecureActionButtonTemplate`
  with `type = "item"` and `item = "<bag> <slot>"` (the bag-slot form, so
  names never matter), parented to a plain frame docked to the tracker's
  TOPLEFT (-36). Attributes and visibility change only out of combat
  (`InCombatLockdown` -> `itemsPending`, applied on PLAYER_REGEN_ENABLED);
  icons, counts and cooldowns update any time. Events: BAG_UPDATE_DELAYED
  (rescan, throttled 0.3 s), BAG_UPDATE_COOLDOWN. Unverified in game as of
  18 Oct 2026.
- Map pin tooltips (`/qop maptip`): `QuestPinMixin:OnMouseEnter`
  (Blizzard_SharedMapDataProviders/QuestDataProvider.lua) builds GameTooltip,
  calls `Show()`, then fires `EventRegistry "MapCanvas.QuestPin.OnEnter"`
  with `(pin, questID)`. We register a callback on that event and append the
  party lines, "Only you" or "Not on quest: ..." plus `GameTooltip:Show()`.
  The pin sets `UpdateTooltip = OnMouseEnter`, so the tooltip rebuilds on
  the update timer and our lines are re-added, never duplicated. Minimap
  markers are engine tooltips; not covered.
- Pending XP (`/qop xp`): `PendingTurnInXP()` sums `GetQuestLogRewardXP` over
  finished watched quests and over every finished quest in the log
  (`C_QuestLog.GetNumQuestLogEntries` / `GetInfo`). The XP bar is
  `MainStatusTrackingBarContainer.bars[StatusTrackingBarInfo.BarsEnum.Experience]`
  (and the Secondary container's), created from `ExpStatusBarTemplate` with
  `isExpBar = true`. Blizzard draws rested XP as `ExhaustionLevelFillBar`, a
  parent-level ARTWORK sublevel -1 texture anchored BOTTOMLEFT with width
  `(cur + rested) / max * barWidth` and matching `SetTexCoord`; the StatusBar
  child draws over it so only the part past current XP shows. That recipe
  did NOT work for us (17 Oct 2026): the StatusBar is a child frame with an
  opaque `Background`, so a texture on the bar frame never showed. Our
  segment is created inside `bar.StatusBar` at layer BORDER sublevel -1
  (the fill's layer, just under it), anchored TOPLEFT/BOTTOMLEFT to the
  fill texture's right edge, width `min(pending/max, 1 - cur/max) *
  StatusBar width`; a plain `SetColorTexture` in the constant
  `XP_SEGMENT_COLOR` (gold 1.0/0.863/0.239 at 0.9, chosen with a colour
  picker that was then removed, 18 Oct 2026; the prediction atlas is dark
  by design and tinted muddy). The segment is inset 1 px top, bottom and
  right of the fill so it stays inside the visible bar art. Any saved
  `xpColor` from earlier sessions is cleared on load. Refreshed on XP, level,
  rest and quest-log events and after the bar's own `Update`/`UpdateTick`
  (post-hooks). The bar tooltip is `ExhaustionTick:ExhaustionToolTipText`
  (post-hooked to add a line); the section header has its own tooltip.
- Visible height vs layout height: the frame's real height is
  `LAYOUT_HEIGHT` (2500) whenever the addon is enabled and the user is not
  in Edit Mode or dragging the grip, so Blizzard's `availableHeight` fits
  every tracked quest and every one gets a block. `settings.height` (default 600)
  is the height the user sees: `RearrangeBlocks` stops placing blocks once
  `VisibleHeight() - topModulePadding - 10` is used up and hides the rest.
  The turn-in header's room is reserved before active quests are placed, so
  the header is always visible. When not everything fits, the room is
  shared equally: `fillOrder` interleaves active[1], done[1], active[2],
  done[2], ... until a list runs out, and the longest prefix of that
  sequence that fits the budget is shown (`shownBlocks`), skipping the entries of
  a collapsed section. The visual order stays active, header, finished;
  the sequence only decides which quests are shown; the header shows "+"
  when none of its quests fit (user choice, 18 Oct 2026). Earlier rules,
  "active first, turn-ins promised 40%" and then "promised 3", were
  dropped: a height share cannot snap flush, and the user preferred an
  even split. Our Quests collapse hides the active blocks only; the
  turn-in section stays. A `visibleBounds` frame
  mirrors the visible height and the grip and outline anchor to it.
  `ApplyTrackerHeight` (post-hooked on `UpdateHeight`, `OnEditModeEnter`;
  `OnEditModeExit` reapplies) switches between the two, and turns screen
  clamping off while the frame is tall so it is not shoved up the screen.
  The frame must be TOP-anchored before it is made tall: with Edit Mode's
  default "RIGHT" anchor the content slid off the top of the screen on
  reload (17 Oct 2026). `EnsureTopAnchor` converts any other anchor to a
  TOPLEFT at the same spot (`AnchorTopLeft`, clamped onto the screen) and
  `SavePosition` always saves a TOPLEFT. **The grip resizes `visibleBounds`, not
  the tracker**: resizing the tracker itself let Blizzard re-lay out into the
  shrinking box mid-drag (sections and counts jumped, the outline lagged,
  and at minimum height the container hid itself, 17 Oct 2026). During a
  drag `visibleBounds` has a single TOPLEFT anchor and `StartSizing`; its
  OnSizeChanged applies the width live and requests a reflow, and
  `VisibleHeight()` returns the live bounds height while `isSizing`. On
  release the size is saved, the two-anchor layout of `visibleBounds` restored,
  and the tracker's own OnSizeChanged hook ignores changes while sizing so
  it does not reapply the old width. Vertical size snaps to whole quests:
  each reflow records `QOP.snapHeights`, the visible heights at which the
  panel ends exactly on a boundary, computed from the fully expanded model
  whatever is collapsed at the time (the adjusted height is capacity; a
  collapsed section uses less of it, 18 Oct 2026): the cumulative height
  after each entry of the round-robin `fillOrder`, starting from
  `headerHeight + hdr`, plus `pad = topModulePadding + 10 + bottomSpacing
  + 1` (the inverse of the budget formula). Placement uses the same
  sequence, so every stop is flush. `BlockHeight` fills each block's extras once per pass so the
  model and the placement agree. On release `settings.height` becomes the
  largest snap at or below the dragged height. Width stays pixel-exact (user choice, 18 Oct
  2026).
- Header art: the gold rule under each header is stretched across the
  shaded panel (header edges -28 .. +3; the NineSlice spans -30 .. +5),
  not just the 260-wide header, including at the default width (user
  request, 18 Oct 2026). The art's transparent end margins scale with it,
  so `FitHeader` widens the texture by `260 / (260 - 2 * artMargin)` and
  centres it on the span plus `artShift`. Both are file-level constants
  tuned in game on 18 Oct 2026: `artMargin = 12`, `artShift = 4.5`.
  The tuning commands were removed once the values were settled.
- Width: modules and headers are 260 by template, so `QOP.ApplyWidth(w)` sets
  the width of the container, every module, their headers, header backgrounds
  and header texts, plus our section. Header art: setting the Background
  texture to the header width left the minimize buttons off the end of the
  drawn line, and a guessed margin constant left a gap even near 260, so
  the atlas is probably not natively 260 wide. `FitHeader` now reads each
  Background's native width the first time it sees it (`nativeArtWidth`),
  keeps Blizzard's CENTER anchor and sets `native * w / 260`. `/qop debug`
  prints the native widths; if a gap remains, the drawn part of the atlas
  does not span the header at 260 and the formula needs an offset.
- Options menu: right-click on the drag handle calls `QOP.ShowMenu`
  (`MenuUtil.CreateContextMenu` with `CreateCheckbox`/`CreateButton`), the
  same switches as `/qop`; falls back to printing the help if `MenuUtil` is
  missing. It runs from a
  post-hook on `ObjectiveTrackerFrame.OnSizeChanged` (live while sizing) and
  from `ApplySaved`. Blocks anchor LEFT/RIGHT to their module, so text reflows
  at the next layout; widths are set before layouts, never inside the reflow,
  so `block.height` stays correct.
- Module height is recomputed by us and reapplied in a
  `hooksecurefunc(QuestObjectiveTracker, "UpdateHeight")` so slide animations
  do not undo it. The container stacks later modules and the background on
  the module's real rect, so no container code is touched.
- The "Quests" header shows the active count from the watch list.
- Move/resize: an overlay on `ObjectiveTrackerFrame.Header` drags with
  `StartMoving`; a grip at the frame's bottom-right first re-anchors the
  frame by its TOPLEFT (`AnchorTopLeft`, raw methods) then uses
  `StartSizing("BOTTOMRIGHT")` with bounds 200x120..600x2000 and an outline
  shown meanwhile. Position, width and height live in `QuestObjectivesPlusDB`
  and are reapplied with `SetPointBase` / `ClearAllPointsBase` after login
  and after Edit Mode's `ApplySystemAnchor`, with `BreakFromFrameManager()`
  so the managed-frame system stops moving it. Edit Mode write-back was
  deliberately not used (taints the anchor-dirty flag, and preset layouts
  refuse saves).

## Open questions (after the first run)

1. Tall-frame layout: do active quests always show now, does the grip match
   the content, does Edit Mode show a sane box, and does anything else read
   the tracker's height (ManageFramePositions, buff frame) and misbehave?
2. Does the quest item button still work in combat after the addon
   rearranged, hid and re-showed blocks?
3. Width: does the stretched header atlas look acceptable, and does the
   width survive `/reload` and Edit Mode open/close (Edit Mode may SetSize
   the system frame when applying a layout)?
4. Does `BreakFromFrameManager` + `SetPointBase` hold the position across
   `/reload`, buff changes and Edit Mode open/close? The user's layout was
   already off-default, so the default-position path is untested.
5. Secret values: run the probe in combat and in a dungeon.
6. "On quest" with no objective lines (a quest with only a completion text,
   e.g. "Speak to X") shows as `Name: On quest`; decide if that is wanted.

## Test checklist

1. `/qopprobe` out of combat in a party where someone shares a quest; paste
   the report into this file under "Probe results".
2. Track 3+ quests with at least one finished: the finished one sits under
   "Ready for turn-in (n)"; click the header to collapse and expand.
3. Grouped: each shared quest lists party members' progress; a class quest
   shows "Only you".
4. Drag the "All Objectives" bar; `/reload`; it stays. Drag the grip in both
   directions; the tracker gets wider/taller and shows more quests; `/reload`;
   it stays.
4b. With a short tracker and more watches than fit, the active quest is still
   shown and the finished ones are the ones cut off.
5. Open and close Edit Mode; the tracker should return to our spot.
6. Fight something with a quest item tracked: click the item button in
   combat; no "Interface action failed because of an AddOn".
7. `/qop off` restores Blizzard's own order; `/qop on` brings ours back.
8. `/qop reset` then `/reload` puts the tracker back where Edit Mode has it.

## Install for development

```powershell
New-Item -ItemType Junction `
  -Path "C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\QuestObjectivesPlus" `
  -Target "C:\Users\noftz\Dev\better_group_tracking\QuestObjectivesPlus"
```

Syntax check (no Lua interpreter on this machine):
`python -I -c "import luaparser.ast as a; a.parse(open('QuestObjectivesPlus/QuestObjectivesPlus.lua', encoding='utf-8').read())"`.

## Probe results


===== Build =====
GetBuildInfo() -> "1.60.1", "70450", "Oct 15 2026", 16001, "", " "
IsInInstance() -> false, "none"
GetZoneText() -> "Tirisfal Glades"
InCombatLockdown() -> false
IsInGroup() -> false
GetNumGroupMembers() -> 0
C_Secrets.HasSecretRestrictions() -> true

===== API presence =====
canaccessvalue                                             function
issecretvalue                                              function
C_Secrets.HasSecretRestrictions                            function
C_TooltipInfo.GetQuestPartyProgress                        function
GameTooltip.SetQuestPartyProgress                          function
C_QuestLog.GetNumQuestWatches                              function
C_QuestLog.GetQuestIDForQuestWatchIndex                    function
C_QuestLog.SortQuestWatches                                function
C_QuestLog.IsComplete                                      function
C_QuestLog.GetLogIndexForQuestID                           function
C_QuestLog.GetTitleForQuestID                              function
C_QuestLog.AddQuestWatch                                   function
C_QuestLog.RemoveQuestWatch                                function
C_QuestLog.GetQuestObjectives                              function
Constants.QuestWatchConsts.MAX_QUEST_WATCHES               number
C_QuestLog.GetMaxNumQuestsCanAccept                        function
QuestUtilsOverrides.GetQuestTagText                        function
QuestCache.Get                                             function
ObjectiveTrackerFrame                                      table
ObjectiveTrackerManager                                    table
QuestObjectiveTracker                                      table
QuestObjectiveTracker.EndLayout                            function
QuestObjectiveTracker.UpdateHeight                         function
QuestObjectiveTracker.BuildQuestWatchInfos                 function
QuestObjectiveTracker.ContentsFrame                        table
QuestObjectiveTracker.Header                               table
ObjectiveTrackerFrame.Header                               table
ObjectiveTrackerFrame.Header.MinimizeButton                table
ObjectiveTrackerFrame.NineSlice                            table
ObjectiveTrackerFrame.UpdateHeight                         function
ObjectiveTrackerFrame.ApplySystemAnchor                    function
ObjectiveTrackerFrame.BreakFromFrameManager                function
ObjectiveTrackerFrame.SetPointBase                         function
ObjectiveTrackerFrame.ClearAllPointsBase                   function
ObjectiveTrackerFrame.IsInDefaultPosition                  function
ObjectiveTrackerFrame.OnSystemPositionChange               function
ObjectiveTrackerFrame.SetResizeBounds                      function
EditModeManagerFrame                                       table
EditModeManagerFrame.SaveLayouts                           function
EditModeManagerFrame.IsActiveLayoutPreset                  function
EditModeManagerFrame.OnSystemPositionChange                function
EditModeManagerFrame.OnSystemSettingChange                 function
Enum.EditModeObjectiveTrackerSetting.Height                number
C_EditMode.SaveLayouts                                     function
C_XMLUtil.GetTemplateInfo                                  function
ObjectiveTrackerLineFont                                   table
ObjectiveTrackerHeaderFont                                 table
QUEST_WATCH_QUEST_READY                                    string
TRACKER_HEADER_QUESTS                                      string
BackdropTemplateMixin                                      table
GetTemplateInfo(ObjectiveTrackerModuleHeaderTemplate) -> {height=26.000001907349, keyValues={1={...}, 2={...}}, sourceLocation="Interface/AddOns/Blizzard_ObjectiveTracker/Blizzard_ObjectiveTrackerModule.xml:14", type="Frame", width=260}
GetTemplateInfo(ObjectiveTrackerBlockTemplate) -> {height=0, keyValues={}, sourceLocation="Interface/AddOns/Blizzard_ObjectiveTracker/Blizzard_ObjectiveTrackerBlock.xml:4", type="Frame", width=0}

===== ObjectiveTrackerFrame =====
keys: 0:userdata AddExtraButtons:function AddModule:function AddSnappedFrame:function AddTopPaddingProvider:function AnchorSelectionFrame:function AnySettingsDirty:function ApplySystemAnchor:function AreAllSystemSettingsDefault:function BindQuestItemFromTracker:function BreakFrameSnap:function BreakFromFrameManager:function BreakSnappedFrames:function CanBeMoved:function ClearAllPoints:function ClearAllPointsBase:function ClearAllPointsOverride:function ClearDirtySetting:function ClearDownKeys:function ClearFrameSnap:function ClearHighlight:function ConvertSettingDisplayValueToRawValue:function DoesSettingDisplayValueEqual:function DoesSettingValueEqual:function FocusGamepad:function FocusQuestFromTracker:function ForEachModule:function ForceExpand:function GetAvailableHeight:function GetBottomOffset:function GetCombinedCenterOffset:function GetCombinedSelectionOffset:function GetCompositeNumberSettingValue:function GetFrameMagneticEligibility:function GetHeightToModule:function GetLeftOffset:function GetManagedFrameContainer:function GetRightOffset:function GetScaledCenter:function GetScaledSelectionCenter:function GetScaledSelectionSides:function GetSelectionOffset:function GetSettingValue:function GetSettingValueBool:function GetSettingsDialogAnchor:function GetSnapOffsets:function GetSystemName:function GetTopOffset:function HasActiveChanges:function HasAnyModules:function HasCompositeNumberSetting:function HasModule:function HasSetting:function HasValidSelectionRect:function Header:table Hide:function HideBase:function HideOverride:function HighlightSystem:function Init:function InitializeGamepad:function IsAboveFrame:function IsBelowFrame:function IsCollapsed:function IsEditModeDragging:function IsFrameAnchoredToMe:function IsHorizontallyAlignedWithFrame:function IsInDefaultPosition:function IsInitialized:function IsSettingDirty:function IsShiftKeyDown:function IsSystemSettingDefault:function IsToTheLeftOfFrame:function IsToTheRightOfFrame:function IsVerticallyAlignedWithFrame:function MarkAllSettingsDirty:function MarkDirty:function MinimizeTrackerModule:function NineSlice:table OnAdded:function OnAnyEditModeSystemAnchorChanged:function OnDragStart:function OnDragStop:function OnEditModeEnter:function OnEditModeExit:function OnEvent:function OnHide:function OnKeyDown:function OnKeyUp:function OnLoad:function OnShow:function OnSizeChanged:function OnSmartNavFocus:function OnSystemHide:function OnSystemLoad:function OnSystemPositionChange:function OnUpdateSystem:function OpenQuestDetailsFromTracker:function OpenQuestOptionsFromTracker:function PrepareForSave:function ProcessMovementKey:function QuestTimerFrame:table RegisterForTransitions:function RemoveAllModules:function RemoveModule:function RemoveSnappedFrame:function ResetToDefaultPosition:function SelectFirstButton:function SelectSystem:function Selection:table SetBackgroundAlpha:function SetCollapsed:function SetDirtyMethod:function SetHasActiveChanges:function SetPoint:function SetPointBase:function SetPointOverride:function SetScale:function SetScaleBase:function SetScaleOverride:function (+70 more)
dirty-related keys: AnySettingsDirty:function ClearDirtySetting:function IsSettingDirty:function MarkAllSettingsDirty:function MarkDirty:function SetDirtyMethod:function UpdateDirtySettings:function dirtyCallback:function dirtySettings:table
GetPoint(1) -> "RIGHT", {0=userdata: 0000021473675AA8, GamepadMainActionBarFrame={0=userdata: 00000213ECA9FA68, AddExtraButtons=function: 00000213C0678668, AddSnappedFrame=function: 00000213C06789E8, AnchorSelectionFrame=function: 00000213C0677EC0, AnySettingsDirty=function: 00000213C0678080, ApplySystemAnchor=function: 00000213C0678240, AreAllSystemSettingsDefault=function: 00000213C0678128, AssignActionBarUsableConditionalFunc=function: 000002131EF23ED0, BreakFrameSnap=function: 00000213C0678B38, BreakFromFrameManager=function: 00000213C0678208, BreakSnappedFrames=function: 00000213C0678A58, CanBeMoved=function: 00000213C0678DD8, ClearAllPoints=function: 00000213C0677DE0, ClearAllPointsBase=function: 00000213C0A92828, ClearAllPointsOverride=function: 00000213C0677DE0, ClearDirtySetting=function: 00000213C0678048, ClearDownKeys=function: 00000213C0677CC8, ClearFrameSnap=function: 00000213C0678B00, ClearHighlight=function: 00000213C0678C50, ConvertSettingDisplayValueToRawValue=function: 00000213C0677F30, CycleActionBarPages=function: 000002131EEEB0A8, DoesSettingDisplayValueEqual=function: 00000213C0678550, DoesSettingValueEqual=function: 00000213C0678518, GetActionBars=function: 000002131EEEAEE8, GetBottomOffset=function: 00000213E91720B0, ...}, GamepadPersistentInputLegend={0=userdata: 000002145E605628, AddToGroup=function: 000002131EE6B530, CreateBackground=function: 000002131EE6B568, CreateEntry=function: 000002131EE79F20, DoesGroupUseHeader=function: 000002131EE6B450, GetColumnWidth=function: 000002131EE6B4C0, GetGroupWidth=function: 00000213E4C614D0, HideAllGroups=function: 000002131EE6B680, OnGamepadShowPersistentInputLegendChanged=function: 000002131EE6B6F0, OnLoad=function: 000002131EE6B990, PostVariableSetUp=function: 000002131EE94F40, RefreshFriendlyTargetingModifierIcons=function: 00000213C08DDE60, RefreshHostileTargetingModifierIcons=function: 00000213C08DDEB0, RefreshTargetingModifiers=function: 000002131EE6B728, RefreshVisibility=function: 000002131EE79D20, SetEntryPromptText=function: 000002131EE6B648, SetGroupColumns=function: 000002131EE6B418, SetGroupUsesHeader=function: 000002131EE6B488, ShowGroup=function: 000002131EE6B6B8, columns={...}, friendlyDpadEntries={...}, friendlyFaceEntries={...}, friendlyShortcutsEntry={...}, friendlyTargetingHeader={...}, groups={...}, ...}, SettingsCheckboxDropdownControlinputLegend={0=userdata: 0000021487010D08, AddModifierSection=function: 00000213E3568A80, ApplyDefaultPromptPositioning=function: 00000213E359DA70, ApplyDefaultStyle=function: 00000213E359DA20, ApplyEnabledStyleToModifierSection=function: 00000213E359DB10, ApplyFocusedStyleToModifierSection=function: 00000213E359DAC0, ApplyFocusedStyleToPromptContainer=function: 00000213E359DB60, ApplyNeutralStyleToPromptContainer=function: 00000213E359DBB0, ApplyWideStyle=function: 000002145E4ED200, GetOrCreatePromptFrameUsingTemplateAndInputs=function: 000002145E4F5B50, InitializePrompts=function: 000002145E4ED270, OnBackgroundAlphaChanged=function: 000002145E4ED5F0, RefreshWithPromptedBindings=function: 000002145E4ED1C8, SetLegendWidth=function: 000002145E4ED2A8, actions={...}, promptContainerFrame={...}, promptFrames={...}, promptFramesAddOrder={...}, promptMap={...}, wrapAroundRowWidth=false}, SettingsCheckboxSliderControlinputLegend={0=userdata: 00000213038B8168, AddModifierSection=function: 00000213E3568A80, ApplyDefaultPromptPositioning=function: 00000213E359DA70, ApplyDefaultStyle=function: 00000213E359DA20, ApplyEnabledStyleToModifierSection=function: 00000213E359DB10, ApplyFocusedStyleToModifierSection=function: 00000213E359DAC0, ApplyFocusedStyleToPromptContainer=function: 00000213E359DB60, ApplyNeutralStyleToPromptContainer=function: 00000213E359DBB0, ApplyWideStyle=function: 000002145E4ED200, GetOrCreatePromptFrameUsingTemplateAndInputs=function: 000002145E4F5B50, InitializePrompts=function: 000002145E4ED270, OnBackgroundAlphaChanged=function: 000002145E4ED5F0, RefreshWithPromptedBindings=function: 000002145E4ED1C8, SetLegendWidth=function: 000002145E4ED2A8, actions={...}, promptContainerFrame={...}, promptFrames={...}, promptFramesAddOrder={...}, promptMap={...}, wrapAroundRowWidth=false}, SettingsCheckboxWithColorSwatchControlinputLegend={0=userdata: 000002131EEB7DE8, AddModifierSection=function: 00000213E3568A80, ApplyDefaultPromptPositioning=function: 00000213E359DA70, ApplyDefaultStyle=function: 00000213E359DA20, ApplyEnabledStyleToModifierSection=function: 00000213E359DB10, ApplyFocusedStyleToModifierSection=function: 00000213E359DAC0, ApplyFocusedStyleToPromptContainer=function: 00000213E359DB60, ApplyNeutralStyleToPromptContainer=function: 00000213E359DBB0, ApplyWideStyle=function: 000002145E4ED200, GetOrCreatePromptFrameUsingTemplateAndInputs=function: 000002145E4F5B50, InitializePrompts=function: 000002145E4ED270, OnBackgroundAlphaChanged=function: 000002145E4ED5F0, RefreshWithPromptedBindings=function: 000002145E4ED1C8, SetLegendWidth=function: 000002145E4ED2A8, actions={...}, promptContainerFrame={...}, promptFrames={...}, promptFramesAddOrder={...}, promptMap={...}, wrapAroundRowWidth=false}, SettingsDropdownControlinputLegend={0=userdata: 00000213C0A1B1E8, AddModifierSection=function: 00000213E3568A80, ApplyDefaultPromptPositioning=function: 00000213E359DA70, ApplyDefaultStyle=function: 00000213E359DA20, ApplyEnabledStyleToModifierSection=function: 00000213E359DB10, ApplyFocusedStyleToModifierSection=function: 00000213E359DAC0, ApplyFocusedStyleToPromptContainer=function: 00000213E359DB60, ApplyNeutralStyleToPromptContainer=function: 00000213E359DBB0, ApplyWideStyle=function: 000002145E4ED200, GetOrCreatePromptFrameUsingTemplateAndInputs=function: 000002145E4F5B50, InitializePrompts=function: 000002145E4ED270, OnBackgroundAlphaChanged=function: 000002145E4ED5F0, RefreshWithPromptedBindings=function: 000002145E4ED1C8, SetLegendWidth=function: 000002145E4ED2A8, actions={...}, promptContainerFrame={...}, promptFrames={...}, promptFramesAddOrder={...}, promptMap={...}, wrapAroundRowWidth=false}, SettingsSliderControlinputLegend={0=userdata: 000002145DD8DC88, AddModifierSection=function: 00000213E3568A80, ApplyDefaultPromptPositioning=function: 00000213E359DA70, ApplyDefaultStyle=function: 00000213E359DA20, ApplyEnabledStyleToModifierSection=function: 00000213E359DB10, ApplyFocusedStyleToModifierSection=function: 00000213E359DAC0, ApplyFocusedStyleToPromptContainer=function: 00000213E359DB60, ApplyNeutralStyleToPromptContainer=function: 00000213E359DBB0, ApplyWideStyle=function: 000002145E4ED200, GetOrCreatePromptFrameUsingTemplateAndInputs=function: 000002145E4F5B50, InitializePrompts=function: 000002145E4ED270, OnBackgroundAlphaChanged=function: 000002145E4ED5F0, RefreshWithPromptedBindings=function: 000002145E4ED1C8, SetLegendWidth=function: 000002145E4ED2A8, actions={...}, promptContainerFrame={...}, promptFrames={...}, promptFramesAddOrder={...}, promptMap={...}, wrapAroundRowWidth=false}, Tabs={1={...}, 10={...}, 2={...}, 3={...}, 4={...}, 5={...}, 6={...}, 7={...}, 8={...}, 9={...}}}, "RIGHT", -101.32476806641, 53.792373657227
GetNumPoints() -> 1
GetHeight() -> 360.00009155273
GetWidth() -> 392.00009155273
GetScale() -> 1
IsInDefaultPosition() -> false
editModeHeight = 400   system = 12   systemIndex = nil
isCollapsed = false   topModulePadding = 38
systemInfo.isInDefaultPosition = false
systemInfo.anchorInfo = {offsetX=-233.69999694824, offsetY=34.099998474121, point="RIGHT", relativePoint="RIGHT", relativeTo="UIParent"}
systemInfo.settings = {1={setting=0, value=0}, 2={setting=1, value=0}, 3={setting=2, value=0}}
Header keys: 0:userdata Background:table FilterButton:table MinimizeButton:table OnLoad:function OnToggle:function SetCollapsed:function Text:table
Header:GetSize() -> 392.00009155273, 32.000026702881
EditModeManagerFrame:IsEditModeActive() -> <nothing>
EditModeManagerFrame:IsActiveLayoutPreset() -> false
active layout: name="def" type=1
modules: 1:ScenarioObjectiveTracker(order=1,shown=false) 2:UIWidgetObjectiveTracker(order=2,shown=false) 3:CampaignQuestObjectiveTracker(order=3,shown=false) 4:QuestObjectiveTracker(order=4,shown=true) 5:AdventureObjectiveTracker(order=5,shown=false) 6:AchievementObjectiveTracker(order=6,shown=false) 7:MonthlyActivitiesObjectiveTracker(order=7,shown=false) 8:InitiativeTasksObjectiveTracker(order=8,shown=false) 9:ProfessionsRecipeTracker(order=9,shown=false) 10:BonusObjectiveTracker(order=10,shown=false) 11:WorldQuestObjectiveTracker(order=11,shown=false)

===== QuestObjectiveTracker =====
keys: 0:userdata AcquireFrame:function AddAutoQuestObjectives:function AddAutoQuestPopUp:function AddBlock:function AddBlockToCache:function AddTag:function AdjustSlideAnchor:function AnchorBlock:function BeginLayout:function BuildQuestWatchInfos:function CallOnCreateFunction:function CanFitBlock:function CanShowTimerBar:function CanUpdate:function CheckCachedBlocks:function ClearFanfares:function ClearHeightModifier:function ClearSelection:function ContentsFrame:table DoQuestObjectives:function EndLayout:function EndSlide:function EnumQuestWatchData:function EnumerateActiveBlocks:function FindButtonByQuestID:function FindButtonByTrackable:function ForceExpand:function ForceRemoveBlock:function FreeBlock:function FreeUnusedBlocks:function FreeUnusedProgressBars:function FreeUnusedRightEdgeFrames:function FreeUnusedTimerBars:function GetBlock:function GetButtonForAreaPOI:function GetButtonForQuest:function GetButtonForQuestInternal:function GetButtonForStyleInternal:function GetButtonForTrackable:function GetContentsHeight:function GetContextMenuParent:function GetDebugReportInfo:function GetExistingBlock:function GetLastBlock:function GetNextBlockAnchoring:function GetProgressBar:function GetQuestTagText:function GetRightEdgeFrame:function GetTag:function GetTimerBar:function HasContents:function HasSkippedBlocks:function Header:table HideAllButtons:function Init:function InitModule:function InternalAddBlock:function IsCollapsed:function IsComplete:function IsDirty:function IsDisplayable:function IsFullyDisplayable:function IsSliding:function IsTruncated:function LayoutBlock:function LayoutContents:function MarkBlocksUnused:function MarkDirty:function MarkProgressBarsUnused:function MarkRightEdgeFramesUnused:function MarkTimerBarsUnused:function MatchesTag:function NeedsFanfare:function OnBlockHeaderClick:function OnBlockHeaderEnter:function OnBlockHeaderLeave:function OnEndSlide:function OnEvent:function OnFreeBlock:function OnHide:function OnLoad:function OnSlideUpdate:function PostInitButtonInternal:function RemoveAutoQuestPopUp:function RemoveBlockFromCache:function ResetUsage:function SelectButton:function SelectButtonByQuestID:function SelectButtonByTrackable:function SelectSuperTrackedButton:function SetCollapsed:function SetContainer:function SetHeader:function SetHeightModifier:function SetNeedsFanfare:function ShouldDisplayAutoQuest:function ShouldDisplayQuest:function Slide:function ToggleCollapsed:function Update:function UpdateCachedOrderList:function UpdateHeight:function UpdateSingle:function UpdateSlideProgress:function WatchMoney:function availableHeight:number blockOffsetX:number blockTemplate:string bottomSpacing:number contentsHeight:number events:table findGroupButtonSettings:table firstBlock:table fromBlockOffsetY:number fromHeaderOffsetY:number hasContents:boolean hasDisplayPriority:boolean hasSkippedBlocks:boolean hasTriedBlocks:boolean (+23 more)
headerHeight=25 fromHeaderOffsetY=-10 fromBlockOffsetY=-10 blockOffsetX=20 lineSpacing=4 bottomSpacing=0
contentsHeight=229.41033554077 availableHeight=322.00009155273 state=5 isCollapsed=false hasContents=true
GetHeight() -> 265.41030883789
IsShown() -> true
Header.Text:GetText() -> "Quests (1)"
block 1: id=94438 height=40.102548599243 used=true cached=nil shown=true poi=true title="A Lesson in Divinity"
block 2: id=405 height=40.102619171143 used=true cached=nil shown=true poi=true title="The Prodigal Lich"
block 3: id=445 height=40.102619171143 used=true cached=nil shown=true poi=true title="Delivery to Silverpine Forest"
block 4: id=372 height=44.102548599243 used=true cached=nil shown=true poi=true title="At War With The Scarlet Crusade"
4 blocks in the firstBlock chain

===== Tracked quests and party progress =====
C_QuestLog.GetNumQuestWatches() -> 4
MAX_QUEST_WATCHES = 25
-- watch 1: questID=94438 title="A Lesson in Divinity" complete=true logIndex=6
   GetQuestTagText -> <nothing>
   GetNumQuestLeaderBoards -> 0
   GetQuestLogLeaderBoard(1) -> <nothing>
   GetQuestLogSpecialItemInfo -> <nothing>
   QuestUtil.QuestShowsItemByIndex(logIndex, complete) -> <nothing>
   C_QuestLog.IsPushableQuest -> false
   GetQuestPartyProgress(omitTitle=false, ignoreActivePlayer=false) -> type=24 id=94438 lines=2
      line 1: type=17 left="A Lesson in Divinity" right=nil leftColor=1.00,0.82,0.00 keys=id:number leftColor:table leftText:string type:number
      line 2: type=8 left="On quest" right=nil leftColor=1.00,1.00,1.00 keys=completed:boolean leftColor:table leftText:string type:number
   GetQuestPartyProgress(omitTitle=true, ignoreActivePlayer=true) -> type=24 id=94438 lines=0
-- watch 2: questID=405 title="The Prodigal Lich" complete=true logIndex=2
   GetQuestTagText -> <nothing>
   GetNumQuestLeaderBoards -> 1
   GetQuestLogLeaderBoard(1) -> "Present Sevren's Orders to Bethor Iceshard in the Undercity.", "log", true
   GetQuestLogSpecialItemInfo -> <nothing>
   QuestUtil.QuestShowsItemByIndex(logIndex, complete) -> <nothing>
   C_QuestLog.IsPushableQuest -> false
   GetQuestPartyProgress(omitTitle=false, ignoreActivePlayer=false) -> type=24 id=405 lines=2
      line 1: type=17 left="The Prodigal Lich" right=nil leftColor=1.00,0.82,0.00 keys=id:number leftColor:table leftText:string type:number
      line 2: type=8 left="Ready for turn-in" right=nil leftColor=1.00,1.00,1.00 keys=completed:boolean leftColor:table leftText:string type:number
   GetQuestPartyProgress(omitTitle=true, ignoreActivePlayer=true) -> type=24 id=405 lines=0
-- watch 3: questID=445 title="Delivery to Silverpine Forest" complete=true logIndex=3
   GetQuestTagText -> <nothing>
   GetNumQuestLeaderBoards -> 1
   GetQuestLogLeaderBoard(1) -> "Take Apothecary Johaan's findings to Apothecary Renferrel in Silverpine Forest.", "log", true
   GetQuestLogSpecialItemInfo -> <nothing>
   QuestUtil.QuestShowsItemByIndex(logIndex, complete) -> <nothing>
   C_QuestLog.IsPushableQuest -> false
   GetQuestPartyProgress(omitTitle=false, ignoreActivePlayer=false) -> type=24 id=445 lines=2
      line 1: type=17 left="Delivery to Silverpine Forest" right=nil leftColor=1.00,0.82,0.00 keys=id:number leftColor:table leftText:string type:number
      line 2: type=8 left="Ready for turn-in" right=nil leftColor=1.00,1.00,1.00 keys=completed:boolean leftColor:table leftText:string type:number
   GetQuestPartyProgress(omitTitle=true, ignoreActivePlayer=true) -> type=24 id=445 lines=0
-- watch 4: questID=372 title="At War With The Scarlet Crusade" complete=false logIndex=4
   GetQuestTagText -> <nothing>
   GetNumQuestLeaderBoards -> 2
   GetQuestLogLeaderBoard(1) -> "0/1 Captain Melrache slain", "monster", false
   GetQuestLogSpecialItemInfo -> <nothing>
   QuestUtil.QuestShowsItemByIndex(logIndex, complete) -> <nothing>
   C_QuestLog.IsPushableQuest -> true
   GetQuestPartyProgress(omitTitle=false, ignoreActivePlayer=false) -> type=24 id=372 lines=3
      line 1: type=17 left="At War With The Scarlet Crusade" right=nil leftColor=1.00,0.82,0.00 keys=id:number leftColor:table leftText:string type:number
      line 2: type=8 left="0/1 Captain Melrache slain" right=nil leftColor=1.00,1.00,1.00 keys=completed:boolean leftColor:table leftText:string numFulfilled:number numRequired:number type:number wrapText:boolean
      line 3: type=8 left="0/2 Scarlet Bodyguard slain" right=nil leftColor=1.00,1.00,1.00 keys=completed:boolean leftColor:table leftText:string numFulfilled:number numRequired:number type:number wrapText:boolean
   GetQuestPartyProgress(omitTitle=true, ignoreActivePlayer=true) -> type=24 id=372 lines=0

NOTE: not in a group. Party progress lines only appear while grouped; invite someone and run again.

===== Party members =====