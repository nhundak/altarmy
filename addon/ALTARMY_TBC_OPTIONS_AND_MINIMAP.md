# AltArmy TBC — Options and Minimap

This document describes **options** and the **minimap button** in minimal form. Tooltips (“owned by” / “crafted by”) are deprioritized and not specified here.

---

## 1. Options

- **Location**: Blizzard Interface Options → Addons → AltArmy TBC (or equivalent category). Optionally a shortcut from the Summary tab (e.g. “Options” button).
- **DataStore options**: Accessed via Interface Options (DataStore category) or a link from the AltArmy TBC options; control what DataStore stores (e.g. which modules are enabled, scan behavior).

### AltArmy TBC options (minimal)

- **Minimap**: Show/hide minimap button; position via LibDBIcon (`minimap.minimapPos`, `minimap.hide`). Legacy keys `minimapAngle` / `showMinimapButton` are migrated on load.
- **UI**: Minimal settings (e.g. which tabs to show, sort defaults) if needed. No account-sharing or tooltip options in the initial version.

No account sharing, no “show alts on tooltip” / “show crafted by” in v1; those are deprioritized.

---

## 2. Minimap Button

- **Left-click**: Open or close the main AltArmy TBC window.
- **Drag**: Reposition via LibDBIcon (respects square minimaps when `GetMinimapShape` is provided, e.g. by SexyMap).
- **Left-click**: Open/close main window.
- **Tooltip**: Short text, e.g. “Left-click: open AltArmy TBC. Right-click + drag: move icon.”

No extra menu or right-click actions required for the minimal version.
