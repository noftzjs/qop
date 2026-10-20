# Quest Objectives+

Blizzard's quest tracker, with the party in it. For World of Warcraft: Forever.

Quest Objectives+ keeps the default objective tracker and adds the things it
is missing for group play. Nothing is replaced: quest item buttons, map pins,
right-click menus and Edit Mode all work exactly as before. Nobody else in
your party needs the addon.

[IMAGE 1: the tracker in a 5-man, Quests above, Ready for turn-in below, party lines under each quest]

## Features

1. **Ready for turn-in section.** Finished quests move out of the quest list
   into their own collapsible section, so what is left under "Quests" is what
   you still have to do. The header shows how many are waiting.

2. **Party progress under each quest.** While grouped, each quest lists
   where your party members are, grouped by status: `Wind, Holymoly: 3/8
   Razormane Hunter slain`, `Ranini: Ready for turn-in`. Members who are not
   on the quest are left out. The data is what the game's own tooltip uses,
   read from the tracker, so it works with any party.

3. **A finished quest stays active while the group needs it.** If you have
   finished a quest but a party member is still working on it, it stays in
   the quest list with the party's progress, and moves to turn-in when they
   finish or leave.

4. **Share from the tracker.** A quest you can share that someone in the
   group does not have gets a line naming them and a Share button.

[IMAGE 2: a quest with "Not on quest: Name" and the Share button]

5. **Move and resize without Edit Mode.** Drag the "All Objectives" bar to
   move the tracker, drag the grip in the corner to resize it. Height snaps
   to whole quests. When there is not enough room, quests and turn-ins share
   the space one for one; collapse a section and the other gets the room.
   Click "Quests" or "Ready for turn-in" to collapse that section.

[IMAGE 3: a short tracker with both sections partly shown and the grip]

6. **Quest items, two ways.** Blizzard's own item button next to each quest
   is untouched. For the occasional quest the game does not link its item to,
   `/qop items` adds a column of usable quest items from your bags beside
   the tracker, with cooldowns.

7. **Where you are comes first.** The quests for the zone you are in move
   to the top of each section and untracked ones get tracked when you
   arrive; the header shows the zone and how many of its quests you have.
   Inside a dungeon or raid the same happens for the instance.

8. **Party progress on the map.** Hovering a quest marker on the world map
   shows the same party lines under the objectives.

9. **Turn-in XP on the XP bar.** A segment on the experience bar shows how
   far the quests you are ready to turn in will take you; hover the bar or
   the turn-in header for the numbers.

[IMAGE 4: the XP bar with the segment and its tooltip]

10. **Options where you need them.** Right-click the "All Objectives" bar to
    lock the position, switch any feature off, or reset. Everything is also a
    `/qop` command.

## How it works

Blizzard lays the tracker out as it always has. Quest Objectives+ runs after
each layout and only rearranges what is already there: it re-anchors the
quest blocks, adds its own lines beneath them and sizes the panel. It never
changes Blizzard's data or clicks Blizzard's buttons for you, so the quest
item buttons keep working in combat and nothing is tainted.

## Commands

`/qop` lists them.

- `/qop lock` – lock position and size
- `/qop group`, `/qop party`, `/qop compact`, `/qop share`, `/qop counts`,
  `/qop maptip`, `/qop xp`, `/qop items`, `/qop instance`, `/qop zone`, `/qop sort` –
  switch a feature on or off
- `/qop collapse` – collapse or expand the turn-in section
- `/qop reset` – forget the saved position and size

## Notes

- Built and tested on the Forever beta (1.60.1). Classic Era, Anniversary
  and Retail are not supported; the tracker code is different there.
- Party progress is read from the game, so it shows what the game knows:
  a member who has already turned a quest in shows the same as one who never
  had it.
- Minimap quest markers are drawn by the game engine and do not get party
  lines; the world map does.
- Inside instances the game may hide some values from addons; party lines
  then show the last readable state until you leave combat.

## Bugs and requests

Use the Issues tab. Include what you were doing, whether you were grouped,
and the output of `/qop err` if the layout looked wrong.
