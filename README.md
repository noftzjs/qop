# Quest Objectives+

A WoW Forever addon that tidies the default quest tracker: finished quests drop into a collapsible "Ready for turn-in" section, each quest shows how far your party members are, and the tracker can be dragged and resized without opening Edit Mode.

It keeps Blizzard's tracker rather than replacing it. Quest items, map pins and
clicks all work exactly as before; the addon only rearranges what is already
there and adds a few lines of its own.

## What it does

- **Finished quests at the bottom.** Quests that are ready to turn in move
  under a "Ready for turn-in (n)" header. Click the header to collapse or
  expand them. The "Quests" header shows how many are still active, and
  when the tracker is too short for everything, the room is shared evenly:
  one quest from each section in turn until one runs out.
- **Party progress under each quest.** When you are grouped, each quest lists
  what your party members still need, grouped by status so four members at
  the same point take one line (`Emilton, Dinna, Uwot: Ready for turn-in`),
  in class colours. Nobody else needs the addon:
  the data is what the game's own party-progress tooltip uses. Quests the
  whole party has finished sink to the bottom of the turn-in section.
- **Share with one click.** A quest you could share that a party member
  doesn't have gets a `Not on quest: Fump` line with a Share button.
- **Party progress on the map.** Hovering a quest marker on the world map
  shows the same per-member lines under the quest's objectives.
- **Where you are comes first.** The quests for the zone you are in move
  to the top of each section, and untracked ones get tracked when you
  arrive; the header reads `Quests (4) - The Barrens`. Inside a dungeon or
  raid the same happens for the instance. Each section can also be sorted
  by level, lowest or highest first (`/qop sort`).
- **Optional: usable quest items beside the tracker.** Blizzard's own item
  button next to each quest is untouched and is the normal way to use quest
  items. For the rare quest the game does not link its item to, `/qop items`
  adds a column of buttons built from your bags instead.
- **How far your turn-ins will take you.** A green segment on the XP bar
  shows the XP waiting in finished quests; hover the bar or the "Ready for
  turn-in" header for the number and the share of the level it covers.
- **Move and resize without Edit Mode.** Drag the "All Objectives" bar to move
  the tracker and drag the grip at its bottom-right corner to change its
  width and height. The addon remembers both.

## Options

Right-click the "All Objectives" bar for the options menu: lock the position
and size once you are happy with them, switch each feature on or off, or
reset the saved position and size.

The same switches exist as commands: `/qop` lists them. `/qop lock`,
`/qop group`, `/qop party`, `/qop compact`, `/qop share`, `/qop counts`,
`/qop maptip`, `/qop xp`, `/qop items`, `/qop instance`, `/qop zone`, `/qop sort none|asc|desc`,
`/qop collapse`, `/qop reset`.

## Status

Beta. Built for World of Warcraft: Forever (interface 16001).
