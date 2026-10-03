---
name: dev-dump
description: >-
  Use AltArmy.Debug.Dump(label, payload) to capture live-client/SavedVariables
  state when debugging an AltArmy TBC bug that can't be diagnosed from reading
  code alone. Use when investigating any bug where you'd otherwise ask the
  person to paste chat debug output, when addon behavior depends on live WoW
  API results, or when working with a non-standard client (e.g. WoW Forever)
  where API behavior is uncertain.
---
# Dev dumps (general-purpose live-client debug capture)

Full reference: [docs/DEV_DUMPS.md](../../../docs/DEV_DUMPS.md).

## When to use this instead of chat debug logging

Reach for this whenever you need to see live client/game-data state to diagnose a bug, and either:
- the data doesn't fit in one or two short chat lines, or
- the person testing has no easy way to copy text out of the WoW chat window (this is the common case — **assume they can't copy chat text unless they say otherwise**).

Chat debug logging (`AltArmy.Debug.LogSearch` and friends) is still fine for quick one-line checks the person can read and describe back to you in their own words.

## The tool

`AltArmy.Debug.Dump(label, payload)` in [`AltArmy_TBC/Data/Debug.lua`](../../../AltArmy_TBC/Data/Debug.lua):
- No-op unless `/altarmy debug on` is active — safe to leave calls in code.
- Writes `payload` to `AltArmyTBC_Options.debug.devDumps[label]` (SavedVariables), overwriting any previous dump under that label.
- Fires a center-screen alert (`Alt Army dev dump: <label>`) so the person knows it captured.

## Workflow

1. **Insert `AltArmy.Debug.Dump("myLabel", { ...whatever fields matter for this bug... })`** at the point in the code where the interesting state exists (e.g. right before/after the suspect computation). Use a distinct label per call site if you need more than one snapshot from the same repro.
2. **Tell the person to**: `/altarmy debug on` (if not already), reproduce the issue, then `/reload`.
3. **Sync and read it yourself** — do not ask the person to paste anything:
   ```bash
   npm run dump:sync
   ```
   Then read `debug/compare-dump-source/AltArmy_TBC.lua` (grep for `devDumps`, or the specific label). Requires `.cursor/local.json` to point at their WoW SavedVariables path — if missing/stale, find the right file yourself: it's `WTF/Account/<ACCOUNT>/SavedVariables/AltArmy_TBC.lua` under *some* WoW client folder (`_classic_`, `_classic_beta_`, `_anniversary_`, etc.) — don't assume which one; check `LastWriteTime` to find the one that was just modified if multiple clients are installed.
4. **Iterate**: if the first dump doesn't have what you need, adjust the payload/add another label, ask for another repro + reload, re-sync.
5. **Clean up when done**: remove the `Dump(...)` call(s) you added for this task once the bug is understood (they're task-specific instrumentation), but never remove `Dump`/`ShowCenterAlert` themselves from `Debug.lua` — that's permanent infrastructure for the next task.

## Don't

- Don't ask the person to copy/paste chat output for anything more than a short one-liner — use a dump instead.
- Don't guess at the SavedVariables path — verify it exists and was recently modified before running `npm run dump:sync`.
- Don't leave task-specific `Dump` calls or their payload-building code in the codebase after the bug is fixed.
