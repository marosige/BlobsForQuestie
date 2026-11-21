# Changelog

## 1.1.0

### New
- **Quest markers** (Available quests tab): the ! of an available quest and the ? of a quest to turn in get an outline in the color of the quest's difficulty, like quest titles: grey (easy) to red (very hard). A green ? means: turn it in before it goes grey. They are the addon's own pictures and sit above Questie's icon, so another addon's tint does not cover them. They also work on the minimap ("Show these markers on the minimap too").
- **New in Forever badge:** quests that are not in the original Classic get a small teal badge on their ! and ?.
- **Neighbouring zones:** a zone map can show the neighbouring zones like your own zone (their objectives as blobs, near you and the mouse as icons, plus Questie's town icons), or leave them empty. A city always shows in its own zone.
- **Map bar:** a new switch for the neighbouring zones (`/blob zones [on|off]`), right-click on the color and grouping buttons steps back, the buttons have pictures that say what they do, and their tooltips show the new state right after a click.
- **Quest details:** opening the details of a quest that is ready to turn in takes the map to the zone of its ?, and only that quest's icons stay (Questie's town icons step aside too). Hold Shift to see everything.
- **Objective colors:** kill blue, other white, loot by drop rate like a traffic light (green good, yellow mid, red poor).
- **Grouping:** None (every objective its own blob), By color, All together.

### Changed
- "Color the ! by difficulty" is now the outline on the ! and ?; the ! itself is no longer recolored.
- Settings text written again: clearer labels, tooltips that say what happens and what "off" means, sections named for what is under them, more room between sections.
- Settings: the radius sliders can be dragged, the two sections of the Questie icons tab are one under the other, the preview strips match the map.
- Colors you never changed move to the new defaults; colors you chose stay.

### Fixed
- Icons that stayed hidden or showed without a tooltip after Questie redrew them.
- Turn-in ? and city icons that stayed hidden after another zone had been viewed; `/blob off` did not bring every icon back.
- With minimap blobs off, the minimap is left exactly as Questie draws it; no leftover blobs on the minimap inside instances.
- Questie's town icons (flight masters, innkeepers...) were not hidden with the neighbouring zones.
- Thin lines in the blob fill; small blobs filled grey instead of the quest's color.
- Much less CPU when Questie redraws icons: the blobs are no longer built and drawn again every time.
- Minimap blobs slide smoothly with you instead of jumping, and cost far less; the markers no longer jitter on the minimap.
- Shift + click on an icon opens the quest's details without moving the map.
- The tooltip of Questie's icon shows again over a marker.

## 1.0

First release.
