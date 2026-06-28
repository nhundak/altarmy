# Compare dump sync (local only)

This folder holds a copy of `AltArmy_TBC.lua` from your WoW SavedVariables, synced for offline / agent debugging.

**Not committed to git.** Populate with:

```bash
npm run dump:sync
```

Requires `.cursor/local.json` (copy from `.cursor/local.json.example`).

After syncing, search `AltArmy_TBC.lua` here for `comparePanelDumps`. See [docs/COMPARE_PANEL_DEBUG_DUMP.md](../../docs/COMPARE_PANEL_DEBUG_DUMP.md).
