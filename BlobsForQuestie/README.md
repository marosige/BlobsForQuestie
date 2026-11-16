# Blobs for Questie

A companion addon for **Questie** that declutters the map. It never changes Questie's files; it only decides which of Questie's own icons are shown.

## Features

- **Blobs instead of far icons:** quest objectives far from you turn into soft blobs that follow their spawn points, so the map stays readable with a full quest log. Walking mobs include their whole patrol route.
- **Questie's own icons where it matters:** near your character and around the mouse pointer you see the normal Questie icons, with Questie's own tooltips. Both distances are yours to set. You can also show all icons everywhere.
- **Colors:** blobs can be colored by quest level (like quest titles in the game), by objective (kill, loot, other) or all in one color. Loot can be shaded by drop rate in three colors you choose, so you see where farming is slow.
- **Grouping:** one blob per quest, unified blobs, or unified blobs by color.
- **Continent and world map:** one blob per zone.
- **Minimap:** optional blobs on the minimap too.
- **Available quests:** show them everywhere or only nearby, leave out quests started by a dropped item, PvP, repeatable and dungeon quests, and color the ! by difficulty.
- **Filters:** hide the icons of neighbouring zones and of dungeon quests that Questie draws at dungeon entrances.
- **Mouse over:** point at a Questie icon to see that objective in every blob. Hold Shift to show only it, with no other icons, quest givers or turn-ins. The same works in the quest log: hold Shift and point at a quest to show only its icons on the map. Opening a quest's details does the same. All three can be switched on the Questie icons tab. Blobs always stay.

## Install

Requires Questie. Copy the `BlobsForQuestie` folder into `World of Warcraft/<version>/Interface/AddOns/` and restart the game.

## Use

- `/blob` (also `/bq`, `/blobs`) lists the commands. `/blob gui` opens the settings, as does the Blobs for Questie entry in Options > AddOns. The minimap button does the same; right-click turns the addon on or off.
- **Map buttons:** a checkbox in the settings adds a round button under Questie's own button at the top left of the world map, with a small bar next to it. Hover a button to see what it does. The buttons switch the addon, available quests, quests started by a drop, the blob color and the grouping. The arrow next to the first button folds the rest away.
- **Macros:** the same switches work as commands. Add `on` or `off`, or leave it out to flip the setting.
  - `/blob on`, `/blob off`, `/blob toggle`: the addon itself
  - `/blob buttons [on|off]`: the map buttons
  - `/blob avail [on|off]`: all available quests (off: only nearby ones)
  - `/blob drop [on|off]`: quests started by a dropped item
  - `/blob color [one|level|kind]`: how blobs are colored (no word: next)
  - `/blob group [quest|all|color]`: how blobs are grouped (no word: next)
  - `/blob debug`: what the addon found (Questie, map libraries, last scan). Paste it when reporting a problem.

## Files

`Core` (settings, hiding rules), `Geometry` (blob shapes), `Layer` (drawing, mouse over), `Scan` (what to show, minimap), `Widgets` and `Settings` (settings window), `MapButtons`, `Commands`, `Main` (startup). They share one table, so the load order in the `.toc` matters.

## Notes

- Questie asks at the start which objective style to use. Blobs for Questie works with the Questie and pfQuest styles. With the Blizzard style Questie draws no objectives, so there is nothing to show; the addon tells you in chat. You can change the style later in Questie's icon options.
- Blizzard's own map pins (not drawn by Questie) cannot be hidden by this addon.
- If something looks wrong, `/blob off` brings Questie back to normal at once.
