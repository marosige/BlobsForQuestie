# Changelog

## 1.1.0

### New
- **Quest markers:** the ! and ? get an outline in the color of the quest's difficulty (a green ? : turn it in before it goes grey), also on the minimap. Quests new in WoW Classic Forever get a small badge.
- **Neighbouring zones** can be shown like your own zone (blobs and icons) or left empty. New map bar switch and `/blob zones`.
- **Quest details:** a quest ready to turn in takes the map to its ?, and only its icons stay (Shift shows all).
- **Colors:** kill blue, other white, loot green / yellow / red by drop rate. Grouping: None, By color, All together.
- **Map bar:** right-click steps back; buttons have pictures and update their tooltips.

### Changed
- Settings text and layout written again for clarity; the radius sliders can be dragged.

### Fixed
- Icons stuck hidden or without tooltip after Questie redraws; `/blob off` not restoring every icon.
- Thin lines and grey fill in blobs; much less CPU load.
- Minimap blobs now slide smoothly instead of jumping.
- Shift + click on an icon no longer moves the map.

## 1.0

First release.
