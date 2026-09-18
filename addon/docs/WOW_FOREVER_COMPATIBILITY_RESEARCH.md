# WoW Forever compatibility — research notes

Status: **preliminary planning**, written 2026-09-14. Blizzard announced *World of Warcraft: Forever* at BlizzCon 2026 (2026-09-12); beta is expected to begin 2026-09-17, full release 2026-11-04. Forever expands the vanilla (1–60) experience — new zones (Mount Hyjal, Zephras Isle, The Riverglades), ~1,000 new quests, 9 dungeons, 10/20-player raids, a new playable race (Skyborne), an SD/HD toggle, and new reputations — and runs **alongside** Classic and Retail rather than replacing either. No addon API details are public yet; this doc captures how the addon ecosystem generally handles multiple game versions today, so we have a plan ready once the beta client (and its `## Interface` number / `WOW_PROJECT_ID`) is available.

This is research only — no code changes. Nothing here is user-visible, so it doesn't trigger the CLAUDE.md "update docs in the same task" rule; it's meant to seed that work once Forever specifics are known.

## How WoW addons support multiple game versions today

Every retail/Classic/Cata Classic/etc. client build is still Lua 5.1 with the same addon-loading model (`.toc` → ordered file list → `SavedVariables`). What differs between versions is the **API surface** (functions added/removed/renamed, e.g. `C_Container` vs. old `GetContainerItemInfo`) and the **`## Interface` number** each client accepts. Addons bridge that gap with a mix of three mechanisms, almost always used together rather than as alternatives:

### 1. Multi-TOC, single codebase (the dominant pattern)

One repo, one set of `.lua` files, multiple `.toc` files — one per "flavor." The client picks the most specific `.toc` for the running build and falls back to the base name:

```
MyAddon/
  MyAddon.toc            -- fallback / retail default
  MyAddon_Vanilla.toc     -- Classic Era
  MyAddon_TBC.toc          -- TBC Classic (also matches "Anniversary" clients)
  MyAddon_Wrath.toc
  MyAddon_Cata.toc
  MyAddon_Mists.toc
  MyAddon_Mainline.toc    -- retail (lower-priority fallback name)
```

Recognized suffixes today: `_Mainline`/`_Standard` (retail), `_Vanilla` (Classic Era, alias `_Classic`), `_TBC` (alias `_BCC`, and reportedly matches Anniversary/TBC-Anniversary clients), `_Wrath` (alias `_WOTLKC`), `_Cata`, `_Mists`. Each `.toc` lists its own `## Interface:` number but otherwise `#include`s the same `.lua` files, so there is exactly one implementation to maintain — the `.toc` files just select which files load and under what interface number.

As of Patch 10.2.7, a **single** `.toc` can also declare several interface numbers comma-delimited (`## Interface: 120100, 50504, 38002, 20506, 11509`), letting very simple addons skip multiple `.toc` files entirely and rely on runtime checks (below) for any behavior differences. `.toc` file lists also support `[Family]`/`[Game]` path expansion (e.g. `[Family]\File.lua` loads `Mainline\File.lua` or `Classic\File.lua` automatically), letting a `.toc` route to per-version files without listing them per flavor.

**Pros:** one codebase, one PR fixes all flavors, easiest to keep behavior consistent. **Cons:** every shared file must tolerate every flavor's API at once (lots of defensive/branchy code), and a bug in shared logic ships to every flavor simultaneously.

### 2. Runtime version detection (small branches inside shared files)

For differences that don't justify a separate file, addons branch at runtime using client-provided globals:

```lua
local isRetail = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)
local isTBC = (WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC)
```

Known `WOW_PROJECT_ID` values: `MAINLINE=1`, `CLASSIC=2` (legacy/Classic Era), `WOWLABS=3` (Plunderstorm), `BURNING_CRUSADE_CLASSIC=5`, `WRATH_CLASSIC=11`, `CATACLYSM_CLASSIC=14`, `MISTS_CLASSIC=19`. Blizzard assigns a new, non-sequential ID for each new client rather than reusing/extending an existing one — Forever will almost certainly get its own new `WOW_PROJECT_ID` and its own `## Interface` range, discoverable once the beta ships. `select(4, GetBuildInfo())` (the TOC/interface number of the running client) is the other common runtime check, and is already the verification method noted in our own `.toc` (`# TBC Classic; verify in-game with: /dump select(4, GetBuildInfo())`).

The community view (and ours already, per `Data/DESIGN.md` → "TBC Compatibility") favors **existence checks over version checks** wherever possible: `if C_AddOns and C_AddOns.IsAddOnLoaded then ... else ... end` rather than `if isRetail then ...`. Existence checks degrade gracefully to *any* future client without edits, including ones released after the addon's last update — which matters a lot for a brand-new, spec-unknown client like Forever.

### 3. Build-time preprocessing (conditional comments)

Larger multi-flavor addons (WeakAuras, BigWigs/LittleWigs, and everything using the community "packager" tooling: `BigWigsMods/packager`, used by CurseForge/WoWInterface/Wago/GitHub Actions release pipelines) mark flavor-specific code with special comments that the packager strips or uncomments per build, leaving line numbers unchanged (so error/stack traces still map to source):

```lua
--@retail@
local supportsTransmog = true
--@end-retail@
--[===[@non-retail@
local supportsTransmog = false
--@end-non-retail@]===]
```

Keywords: `retail`, `version-retail`, `version-classic`, `version-bcc` (TBC), `version-wrath`, `version-cata`, `version-mists`, each invertible with a `non-` prefix; `do-not-package` and `alpha`/`debug` for build hygiene. The `.toc` file supports the same `#@keyword@ … #@end-keyword@` block syntax. This is the most powerful option (true dead-code elimination per flavor, zero runtime cost) but requires adopting the packager as part of the release pipeline — it's a tooling investment, not just a coding convention.

## Examples reviewed

| Addon | Approach |
|---|---|
| **WeakAuras** | Multi-`.toc` (`WeakAuras.toc`, `WeakAuras_Vanilla.toc`, `WeakAuras_TBC.toc`, `WeakAuras_Wrath.toc`, `WeakAuras_Cata.toc`) + BigWigs packager conditional comments inside shared Lua for the many small API differences (aura/spell APIs move around a lot between flavors); releases are packaged per-flavor and distributed as separate CurseForge/GitHub downloads. |
| **ElvUI** | Single codebase across TBC/Wrath/Cata/Mists Classic and retail, using multi-`.toc` selection plus per-flavor folders/modules that are conditionally loaded — large UI surface, so version-specific chunks are isolated into their own files rather than branching inline everywhere. |
| **BigWigs / LittleWigs** | The reference implementation for the packager/conditional-comment approach described above; maintains one repo across every flavor. |
| **TOC/packager tooling ecosystem** (`wow-addon-packager`/`wap`, `BigWigsMods/packager`) | Confirms this is a standardized, third-party-tooled convention, not something each addon reinvents — worth adopting if/when we go multi-flavor rather than hand-rolling. |

We did not find a case of a well-established addon maintaining genuinely **separate codebases** per flavor (e.g. a hard fork) as the default approach; forks tend to happen only when a maintainer abandons Classic support and a third party picks it up independently, not as a deliberate strategy.

## Our codebase, and where Forever would bite

- **Single `.toc`, single `## Interface: 20506` today** ([AltArmy_TBC.toc](../AltArmy_TBC/AltArmy_TBC.toc)) — no multi-flavor scaffolding exists yet.
- **We already lean on the "existence check" convention** in a few places — `Data/Integrations/RestedXpIntegration.lua`, `Data/Gear/GearScore.lua`, and `Data/DataStore/DataStoreLevelHistory.lua` all guard `C_AddOns`/`IsAddOnLoaded` this way, and [`Data/DESIGN.md`](../AltArmy_TBC/Data/DESIGN.md) documents it as the house style ("WoW API usage is defensive... so the addon runs on TBC Classic even when some APIs differ or are missing"). That's the right instinct to extend, not a new pattern to introduce.
- **The real risk surface is the `DataStore/` scan layer**, not the UI. `DataStoreContainers`, `DataStoreEquipment`, `DataStoreCurrencies`, `DataStoreProfessions`, `DataStoreReputations`, `DataStoreMail`, `DataStoreAuctions`, `DataStoreTalents`, and `DataStoreLockouts` each call WoW scanning APIs directly (bags, currency, professions, etc.) — this is exactly the API surface that has historically diverged hardest between Classic-family clients and retail (e.g. `GetContainerItemInfo` vs. `C_Container.GetContainerItemInfo`). Forever's actual API surface is unknown, but since it's built on the vanilla 1–60 engine it more plausibly resembles Classic Era/TBC's older-style APIs than retail's `C_*` namespace migration — that assumption needs verifying in beta, not assumed.
- **Domain data, separate from API compatibility:** cooldown/lockout tables (`Data/Cooldowns/*`), reputation lists (`ReputationFactionFilter.lua`/`ReputationFactionSort.lua`), and gear scaling (`Data/Gear/PawnScales.lua`) are hand-authored for TBC's specific raids/factions/item levels. Forever's new zones, reputations, and raids will need their own data tables regardless of how we solve the *API* compatibility question — this is content work, not addon-architecture work, and will be a bigger lift than the API bridging itself.
- **Lint/compile tooling is already version-agnostic**: `.luacheckrc` targets `std = "lua51"` (true for every WoW client, Forever included) and `npm run check` does a Lua 5.1 compile pass — no tooling changes needed there. Per-file `-- luacheck: globals ...` annotations would need extending if we start referencing flavor-specific globals (`WOW_PROJECT_*`, new `C_*` namespaces) conditionally.
- **`OptionalDeps`** (Auctionator, CraftLib, TacoTip, GearScoreTBCClassic, RXPGuides, Questie, Zygor...) are all TBC-Classic-specific addons; none of them are confirmed to exist for Forever yet. Our integration code already guards their absence, so this degrades gracefully, but a Forever build would ship with most optional integrations inert until/unless those addons (or equivalents) target Forever too.

## Addon-development specifics (checked 2026-09-14, three days before beta)

Re-verified the premise of this doc against independent outlets (Blizzard's own news post, Variety, Kotaku, Vice, Wikipedia, MMO-Champion) since the original notes cited sources that were worth double-checking — the announcement and dates are real and corroborated, not a hallucination.

On addon development specifically, every source agrees on one point: **Blizzard has published no addon/API documentation for Forever yet.** No interface number, no `WOW_PROJECT_ID`, no addon-folder path, no supported/blocked list. [Blizzard's own BlizzCon recap article](https://news.blizzard.com/en-us/article/24301145/world-of-warcraft-at-blizzcon-2026-discover-whats-next) contains zero developer-facing technical detail. The [`Gethe/wow-ui-source`](https://github.com/Gethe/wow-ui-source) mirror (the usual place a new `Forever`/`classic_era`-style branch would show up once the client exists) has no Forever branch yet as of this check.

What we could find:

- **Community expectation, not confirmation:** since Forever is built on the vanilla 1–60 engine rather than Retail, the consensus guess (echoed independently by a [PEWPEWSHOP addon-compatibility post](https://pewpewshop.pro/wow-boost/blog~addons-for-wow-forever-what-is-known-so-far) and an addon dev's own [Forever port-assessment tracking issue](https://github.com/nazumods/wow/issues/942)) is that it will expose something closer to the **Classic Era API surface** (smaller, no `C_*` namespace sprawl) than Retail's, and possibly closer to Classic Era than to TBC's own incremental API additions. This is an assumption to verify in beta, not a fact — it's the same caution our existing "Domain data" section above already carries into the `DataStore/` risk assessment.
  - This slightly updates (doesn't contradict) the note above under "Our codebase, and where Forever would bite" — the existing text says Forever "more plausibly resembles Classic Era/TBC's older-style APIs than retail's"; the new sources lean specifically toward Classic Era rather than TBC, for whatever that's worth pre-beta.
- **One unconfirmed, speculative interface-number guess:** a third-party addon developer ([GitHub issue](https://github.com/danielcosta42/guildos/issues/11)) reasoned from Blizzard's `%d%02d%02d` interface-numbering convention and an internal build string reported as `1.60.x` to guess Forever's interface number will be **16000 or 16001**, and suggested beta builds declare `## Interface: 20506, 16000, 16001` (i.e., comma-delimited alongside TBC's own 20506) to hedge. This is one person's inference from a leaked/observed build string, not an official number — treat as a placeholder to test against, not something to hardcode with confidence.
- **No addon-store support yet:** CurseForge, Wago, and WoWInterface have no "Forever" flavor/channel as of this check, so the multi-TOC pattern's flavor-suffix convention (section 1 above) has no established `_Forever` (or similar) suffix yet either — that will need confirming once one of those platforms adds it.
- **Addon policy itself is an open question**, not just addon compatibility: Blizzard's own forums have a dedicated "WoW: Forever" category with an active "Should Blizzard block addons?" thread (387 replies as of 2026-09-14). Nothing suggests Blizzard is planning an addon lockout, but it means "will third-party addons be allowed at all, and under what API" isn't 100% settled the way it is for existing Classic-family clients.
- **Beta (2026-09-17) is the real starting line.** Every source converges on the same advice: nothing meaningful can be confirmed about addon compatibility until the beta client is in hand and `select(4, GetBuildInfo())` / `WOW_PROJECT_ID` can be read directly.

None of this changes the recommendation below — if anything it reinforces starting with multi-TOC + existence checks rather than the packager, since we don't even have a confirmed flavor suffix to build tooling around yet.

## Recommendation for when the beta lands

1. Confirm the `## Interface` number and `WOW_PROJECT_ID` for Forever in-game (same `/dump select(4, GetBuildInfo())` check already noted in our `.toc`), and confirm whether it shares Classic Era's/TBC's container/equipment API shape or retail's.
2. Start with the **multi-TOC + existence-check** combination (sections 1 and 2 above) rather than adopting the packager/conditional-comment tooling (section 3) up front — it's zero new tooling, fits our current "defensive API usage" convention, and is enough unless the shared `.lua` files end up needing large blocks of flavor-only code.
3. Reserve the packager/conditional-comment approach as a fallback if `DataStore/` scan modules end up needing substantially different implementations per flavor rather than small branches — that's the threshold where inline `if` branches stop being maintainable.
4. Treat new zones/reputations/raids as a content workstream separate from the API-compatibility workstream; they don't block each other.

**Implemented (2026-09-15):** step 1's "confirm the API surface in-game" now has a tool — `/altarmy debug apicheck` (`AltArmy_TBC/Data/ApiCheck.lua`). It checks ~90 Blizzard API functions/tables the addon depends on for existence, prints a one-line status to chat, and writes the full per-entry results to `AltArmyTBC_Options.debug.apiCheckSnapshot` for offline review after `/reload`. It's manual-only (no login auto-run) and standalone (doesn't require `/altarmy debug on` first), so it's usable immediately on a first, unfamiliar login.

**Implemented (2026-09-15): level cap.** Separately from the API-surface question above, Forever's 1–60 leveling range (vs. TBC's 70 cap) needed its own fix. `AltArmy.DataStore.MAX_LEVEL` (`AltArmy_TBC/Data/DataStore/DataStore.lua`) now reads `GetMaxPlayerLevel()` when the client exposes it, falling back to the hardcoded `70` when it doesn't — the same existence-check convention as everything else in this doc, so it needs no Forever-specific branch and degrades to today's TBC behavior if Forever's client doesn't expose that API. `AC.MANIFEST` in `ApiCheck.lua` now tracks `GetMaxPlayerLevel` too, so `/altarmy debug apicheck` will report whether it's actually present once beta is in hand. The wand-leveling gear-scale cutoff in `Data/Gear/PawnScales.lua` (previously hardcoded to `69`, "one below TBC's cap") was also switched to derive from `MAX_LEVEL - 1` so it clears at the right level regardless of which cap is active. Whether `GetMaxPlayerLevel()` exists on Forever's client, and what it returns, is still unverified pre-beta — same caveat as the rest of this document.

## Confirmed: Interface number (2026-09-17, beta day)

Forever's `## Interface` number is confirmed as **`16001`**, derived from its build version `1.60.1` via Blizzard's standard `%d%02d%02d` interface-numbering convention. This matches the speculative 16000/16001 guess logged above (from the `danielcosta42/guildos` issue) — it turned out correct.

Ground truth: [RPGLootFeed PR #617](https://github.com/McTalian-WoW-Addons/RPGLootFeed/pull/617), a real addon's public GitHub history, merged 2026-09-17. The entire change was a one-line `.toc` edit adding `16001` to the existing comma-delimited `## Interface:` list — no new `.toc` file, no flavor suffix, no source/logic changes:

```diff
-## Interface: 11509, 20506, 50504, 120100, 120105
+## Interface: 11509, 16001, 20506, 50504, 120100, 120105
```

The PR description notes "no per-flavor TOC splitting is involved" — confirms section 1's comma-delimited-interface mechanism (Patch 10.2.7+) is the pattern real addons are using for Forever, not a new `_Forever.toc`.

We also reviewed AtlasLoot Classic Forever (CurseForge, author Sliccer) — a fork of AtlasLootClassic, flavor-tagged **"WoW Forever"**, game version **1.60.1** on CurseForge. No public source repo link was found for it, so we couldn't diff its `.toc` directly; the RPGLootFeed PR above is the actual source evidence. CurseForge's packaged filename for it embeds `11601` (a packager-internal build tag distinct from the Interface number — don't confuse the two).

**Implemented (2026-09-17):** added `16001` to [`AltArmy_TBC.toc`](../AltArmy_TBC/AltArmy_TBC.toc) (`## Interface: 20506, 16001`), so the client will load the addon on Forever. This only affects load-eligibility — it does **not** confirm `DataStore/` scanning or any other behavior actually works correctly on Forever. Step 1 of the recommendation below (confirm the API surface in-game, ideally via `/altarmy debug apicheck`) is still outstanding and should happen once Forever beta access is in hand.

## Deployment pipeline (2026-09-17): not yet updated, on purpose

[.github/workflows/release.yml](../.github/workflows/release.yml) has two flavor-specific values *separate* from the `.toc` Interface number, both owned by the store platforms rather than derived from our own files:

- `CURSEFORGE_GAME_VERSIONS: "16533"` — a CurseForge-internal numeric game-version-catalog ID for "TBC Classic 2.5.6", not the WoW Interface number. CurseForge has assigned *some* ID for Forever — AtlasLoot Classic Forever is already live on CurseForge tagged flavor "WoW Forever" / version 1.60.1 — but that ID isn't published anywhere we could find (not in CurseForge's multi-TOC support article, not in the public `curseforge-v2` API library), only visible via an authenticated `GET /api/game/versions` call or the web uploader's dropdown.
- `WAGO_BC_PATCH: "2.5.6"` — Wago's upload metadata only documents `supported_retail_patch`, `supported_wotlk_patch`, `supported_bc_patch`, `supported_classic_patch` fields; no Forever-equivalent field exists yet per their current docs.

Real-world precedent for this exact gap: another addon's CI currently ships Forever support only as a beta **pre-release tag that intentionally skips the CurseForge/Wago publish step** (the `.toc` gets the interface number, but the store-upload job isn't triggered), specifically because this store-side flavor plumbing isn't there yet.

**Update (2026-09-17, after first Forever-`.toc` deploy):** the deploy went out with only the `.toc` Interface change — CurseForge's page still showed flavor "Classic TBC" only, game version "2.5.6" only, confirming the store-side ID was in fact still missing.

Found CurseForge's `gameVersionTypeId` for "WoW Forever": **`88568`** — read directly off AtlasLoot Classic Forever's CurseForge pages (project page, files listing, and a file detail page all agree). Added it to [`release.yml`](../.github/workflows/release.yml): `CURSEFORGE_GAME_VERSIONS: "16533,88568"`.

**Result: wrong ID space, deploy failed.** `88568` is CurseForge's **game version *type* ID** (the flavor/category — website filter dropdowns use this), not the **game version ID** the upload API's `gameVersions` field actually wants. CurseForge's own API docs confirm the split: `GET /api/game/versions` returns `{ id, gameVersionTypeID, name, slug }` objects, and `gameVersions` in the upload metadata takes `id` (a specific patch, e.g. our working `16533` = the specific version "2.5.6"), not `gameVersionTypeID` (e.g. `88568` = the "WoW Forever" category as a whole, covering every Forever patch). Deploying with `88568` in `gameVersions` failed: `HTTP 400 {"errorCode":1007,"errorMessage":"Invalid game version ID: 88568 does not exist."}`. Reverted `release.yml` to `CURSEFORGE_GAME_VERSIONS: "16533"` (TBC only) to unblock deploys.

**Resolved (2026-09-17):** rather than guess further, added a temporary diagnostic step to `release.yml` that ran the authenticated `/api/game/versions` query inside the GitHub Actions runner (which has the real `CURSEFORGE_API_TOKEN` secret) and then deliberately failed the job so it didn't fall through to a real upload. Result:

```json
{
  "id": 17053,
  "gameVersionTypeID": 88568,
  "name": "1.60.1",
  "slug": "1-60-1",
  "apiVersion": "16001"
}
```

`apiVersion: "16001"` matching the Interface number already in our `.toc` confirmed this was the right entry. `CURSEFORGE_GAME_VERSIONS` is now `"16533,17053"` (TBC 2.5.6 + WoW Forever 1.60.1); the diagnostic step has been removed.

Wago's `WAGO_BC_PATCH`-equivalent field for Forever is still unresolved (no documented field name) — not addressed by this change.

## First real Forever crash, and a data point against the "Classic Era-like" guess (2026-09-17)

First actual in-game error report from Forever beta, day one:

```
Frame:RegisterEvent(): Attempt to register unknown event "TRADE_SKILL_UPDATE"
```

`DataStore.lua` unconditionally called `frame:RegisterEvent("TRADE_SKILL_UPDATE")` at file scope. On Forever's client, that event doesn't exist at all, and `RegisterEvent` on an unrecognized event name throws (hard error, not a silent no-op) — this is a load-time crash, not a soft failure.

**Fixed:** removed the registration and its handler from [`DataStore.lua`](../AltArmy_TBC/Data/DataStore/DataStore.lua). This was safe with zero behavior change on any client, TBC included: the `TRADE_SKILL_UPDATE` handler was already a deliberate no-op (a comment above it explained it existed only to `return` early and *avoid* a rescan-on-every-expand/collapse infinite loop). The actual full profession scan has always been driven by `TRADE_SKILL_SHOW` + a 0.5s deferred timer (`DS:RunDeferredRecipeScan()`), never by `TRADE_SKILL_UPDATE`. `npm run check` passes after the change.

**Why this happened, per Thaoky's `DataStore_Crafts`** (the addon our `Data/DataStore/` layer is modeled on — same module names, same `RegisterEvent`-dispatch structure): its retail file gates this exact event behind a runtime check —

```lua
local isRetail = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)
...
if not isRetail then
    addon:ListenTo("TRADE_SKILL_UPDATE", OnTradeSkillUpdate)   -- only reached on non-retail clients
    ...
end
```

On the real retail engine, `TRADE_SKILL_UPDATE` is never even registered — it doesn't fire there. Forever hitting the identical "unknown event" error is a concrete signal that **Forever's client behaves like the retail engine for the profession API**, not like Classic Era's — this narrows (doesn't yet fully overturn) the "Community expectation" guess logged above under "Addon-development specifics", which leaned toward a Classic-Era-like surface. One API family isn't the whole picture, but it's the first real data point either way.

Retail's actual replacements, per the same source:
- `TRADE_SKILL_DATA_SOURCE_CHANGED` — registered unconditionally at login, drives the full rescan (the role `TRADE_SKILL_SHOW` + our timer already plays for us)
- `TRADE_SKILL_LIST_UPDATE` — drives a lightweight cooldown-only refresh after crafting (the one piece of *actual* behavior the old `TRADE_SKILL_UPDATE` handler provided in Classic-family clients, which we don't currently replicate at all since ours was already a no-op)

**The bigger finding, not yet acted on:** retail's scan function itself (`ScanRecipes_Retail` in Thaoky's code) isn't a small patch on top of the old API — it's a full rewrite around `C_TradeSkillUI`, keyed by `recipeID` (`GetAllRecipeIDs()`, `GetRecipeInfo(recipeID)`, `GetCategories()`/`GetCategoryInfo(id)`, `GetRecipeCooldown(recipeID)`), completely replacing the index-based `GetNumTradeSkills()`/`GetTradeSkillInfo(i)` loop that [`DataStoreProfessions.lua`](../AltArmy_TBC/Data/DataStore/DataStoreProfessions.lua) and `DataStore.lua`'s trade-skill scanning still use throughout. If Forever's engine has actually dropped those legacy globals (not just this one event), profession scanning would currently fail **silently** rather than crash — every call site is already guarded with `if GetNumTradeSkills and ... then`, so it just quietly does nothing instead of erroring.

**Deliberately not implemented now** — a `C_TradeSkillUI`-based rewrite of profession scanning (mirroring `ScanRecipes_Retail`) is real, scoped work: new data shape (recipeID-keyed vs. index-keyed), new category/cooldown APIs, and it would need to coexist with the existing TBC-native path rather than replace it (TBC Classic itself is presumably still on the legacy API). Deferred until:
1. `/altarmy debug apicheck` is run on Forever and the "Professions"/"Crafting" section of the snapshot confirms whether `GetNumTradeSkills`, `GetTradeSkillInfo`, `GetTradeSkillLine`, etc. are actually `missing` there (vs. just this one event) — that's the real go/no-go signal, not speculation.
2. If they *are* missing, this becomes a tracked follow-up task: add `C_TradeSkillUI`-based scanning as an existence-checked alternate path (same "existence check over version check" house style as the rest of this doc), not a Forever-only branch.

## Second crash, and the real fix: `C_EventUtils.IsEventValid` (2026-09-17)

A second, near-identical crash followed within the hour:

```
Frame:RegisterEvent(): Attempt to register unknown event "CRAFT_SHOW"
```

`CRAFT_SHOW` is the old pre-Cata "Craft" UI event (used by Enchanting historically, alongside `GetCraftInfo`/`GetNumCrafts`). Same failure mode as `TRADE_SKILL_UPDATE`: unconditional `frame:RegisterEvent("CRAFT_SHOW")` at file scope in `DataStore.lua`, and the event doesn't exist on Forever's client.

Rather than keep deleting one dead event at a time as each one surfaces in-game (whack-a-mole, and each occurrence is a hard crash for real players until fixed), we went back to Thaoky's `AddonFactory` — the framework underlying `DataStore_Crafts` — to see how it avoids this class of bug entirely. Its `addon:ListenToEvent()` ([`AddonFactory/Core/Addon.lua`](https://github.com/Thaoky/AddonFactory/blob/master/AddonFactory/Core/Addon.lua)) never calls `frame:RegisterEvent` unconditionally:

```lua
if not events[eventName] then
    events[eventName] = {}
    -- DataStore internal events are obviously not known by the game, so don't register them
    if C_EventUtils.IsEventValid(eventName) then
        frame:RegisterEvent(eventName)
    end
end
```

This is why Thaoky's retail `DataStore_Crafts_Retail.lua` can register `CRAFT_SHOW` and even `TRADE_SKILL_UPDATE` **unconditionally**, with no `isRetail` guard at all, at its `OnPlayerLogin` call site — `C_EventUtils.IsEventValid()` silently no-ops the registration for whichever events the running client doesn't recognize, instead of erroring. The `isRetail` branches we found earlier in that file are about *which scan function to run*, not about whether it's safe to register the event — event safety is handled once, generically, in the framework layer.

**Fix applied:** added a `SafeRegisterEvent()` wrapper in [`DataStore.lua`](../AltArmy_TBC/Data/DataStore/DataStore.lua) (right above the event-registration block) and switched every `frame:RegisterEvent(...)` call there to go through it:

```lua
local function SafeRegisterEvent(eventName)
    if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(eventName) then
        return
    end
    pcall(frame.RegisterEvent, frame, eventName)
end
```

This checks existence the same "existence check over version check" way as the rest of this doc, and keeps the `pcall` as a second safety net (in case `C_EventUtils` itself doesn't exist on some client, or a genuinely unexpected event slips through). It replaces the old one-off `pcall(...)` block that had already been hand-added around `PLAYER_INTERACTION_MANAGER_FRAME_SHOW`/`_HIDE` for the same reason — that special case is now just two more calls through the same general helper. `C_EventUtils` is confirmed present on TBC Classic too: it's called unconditionally (no guard) inside `AddonFactory/Core/Addon.lua`, a single shared file Thaoky ships across every flavor from Vanilla through retail, so it isn't a retail-only API. `npm run check` passes (added `C_EventUtils` to the file's `luacheck: globals` line).

**Scope of this fix:** applied only to `DataStore.lua`'s event-registration block, since that's where both crashes originated and it's the doc's already-identified highest-risk file (the `DataStore/` scan layer). Other files across the addon (`TabCooldowns.lua`, `TabGuild.lua`, `GearUpgradeAlerts.lua`, `DataStoreTalents.lua`, etc.) still call `frame:RegisterEvent` directly and unguarded — mostly for core events (`PLAYER_LOGIN`, `ADDON_LOADED`, `BAG_UPDATE`, `QUEST_COMPLETE`) that are very unlikely to be missing on any client, Forever included. If a third crash surfaces from one of those files, apply the same `SafeRegisterEvent` pattern there rather than a one-off deletion — this doc's fix should be the template going forward, not treated as DataStore.lua-specific.

## `/altarmy debug apicheck` results on Forever (2026-09-17)

Ran `/altarmy debug apicheck` in the live Forever beta client for the first time (interface `16001` confirmed in the snapshot header). Result: **57/94 ok, 37 missing, 0 fallback.** Full per-entry results are in `AltArmyTBC_Options.debug.apiCheckSnapshot` in that account's SavedVariables.

Missing, by `ApiCheck.lua` area:

| Area | Missing | Detail |
|---|---|---|
| Item Info | 7/7 (all) | `GetItemInfo`, `GetItemInfoInstant`, `GetItemStats`, `IsUsableItem`, `GetItemQualityColor`, `GetSpellInfo`, `GetSpellLink` |
| Professions | 11/12 | `GetNumTradeSkills`, `GetTradeSkillInfo`, `GetTradeSkillLine`, `GetTradeSkillItemLink`, `GetTradeSkillRecipeLink`, `ExpandTradeSkillSubClass`, `GetTradeSkillNumReagents`, `GetTradeSkillReagentItemLink`, `GetTradeSkillReagentInfo`, `GetNumSkillLines`, `GetSkillLineInfo` (only `GetMacroInfo` survives) |
| Crafting | 6/6 (all) | `GetCraftSkillLine`, `GetNumCrafts`, `GetCraftInfo`, `GetCraftRecipeLink`, `GetCraftNumReagents`, `GetCraftReagentInfo` |
| Reputations | 4/4 (all) | `GetNumFactions`, `GetFactionInfo`, `GetFactionInfoByID`, `ExpandFactionHeader` |
| Auctions | 3/3 (all) | `GetNumAuctionItems`, `GetAuctionItemInfo`, `GetAuctionItemLink` |
| Talents | 2/2 (all) | `GetNumTalentTabs`, `GetTalentTabInfo` |
| Guild | 1/6 | `GuildRoster` |
| Unit Info | 1/14 | `CombatLogGetCurrentEventInfo` |
| Quests | 1/3 | `SelectQuestLogEntry` |
| Misc UI | 1/8 | `ChatFrame_OnHyperlinkClick` |

Everything else — Bags/Containers (all `ok`, resolved via `C_Container`), Inventory/Equipment, Mail, Lockouts, and the rest of Guild/Addon Infra/Unit Info/Misc UI — came back `ok`.

**This overturns, not just narrows, the "Classic Era-like" guess.** The legacy index-based scanning APIs for Professions, Crafting, Reputations, Auctions, and Talents aren't missing a handful of events (as the `TRADE_SKILL_UPDATE`/`CRAFT_SHOW` crashes suggested) — the entire old-style global surface for each of those domains is gone, wholesale, on Forever. Combined with `GetItemInfo`/`GetSpellInfo` also being absent, Forever's client looks like it dropped the pre-`C_*` globals the same way retail eventually did, not like Classic Era (which still has them). This is the "go" signal the doc's earlier "Deliberately not implemented now" section was waiting on.

**Consequence for `DataStore/`:** per the existing guard convention (`if GetNumTradeSkills and ... then`), `DataStoreProfessions.lua` and the rest of `DataStore.lua`'s trade-skill/craft/reputation/auction/talent scanning are not crashing on Forever — they're silently no-ops there, same as predicted. A `C_*`-based alternate scan path (`C_TradeSkillUI`, faction/reputation's own `C_*` replacements, `C_AuctionHouse`, talent-spec APIs) is now a confirmed, scoped follow-up rather than speculative — still deferred, not implemented in this change.

## Fix roadmap for the six missing-API areas (2026-09-17)

Triaged the apicheck results above into a per-area plan, using Thaoky's `DataStore_*` addon suite ([github.com/Thaoky](https://github.com/Thaoky)) as reference — those addons already ship `C_*`-namespaced replacements for the same legacy globals, gated behind existence/`isRetail` checks.

`GetItemQualityColor` needs no fix: it has no call site anywhere in the addon (only appears in `ApiCheck.lua`'s own manifest and `.luacheckrc`), so its "missing" status is inert.

For the other five, one `MANIFEST` entry in `Data/ApiCheck.lua` already models a legacy/`C_*` pair as a single entry with multiple `candidates` (see the existing Bags/Containers rows) — the fix pattern below follows that same convention: add existence-checked `C_*` candidates, don't invent new areas/labels.

| Area | Our call sites | Thaoky reference | Candidate `C_*` APIs | Complexity | Status |
|---|---|---|---|---|---|
| Reputations | `Data/DataStore/DataStoreReputations.lua` (`ScanReputations`, `SaveFactionHeaders`) — already has one `C_*` fallback precedent (`TryFactionNameFromGameAPI` tries `C_Reputation.GetFactionDataByID`) | `DataStore_Reputations/DataStore_Reputations.lua` — single file, `API_*` existence-wrapped locals | `C_Reputation.GetNumFactions`, `ExpandFactionHeader`, `CollapseFactionHeader`, `GetFactionDataByIndex`, `GetFactionDataByID` | Low — clearest template, stored shape (`{s,e,b,t}` by factionID) unaffected | **Done** |
| Talents | `Data/DataStore/DataStoreTalents.lua` (`readTalentTabs`, `ScanTalents`) — already has a no-data fallback (`ResolveSpecKey` guesses a per-class leveling spec) | `DataStore_Talents/DataStore_Talents.lua` — **not a clean reference**: actively pushed (2026-08-16) but genuinely mid-rewrite, large sections commented out | `C_SpecializationInfo.GetTalentInfo` referenced but surrounding code disabled; needs direct in-game exploration of what talent API Forever actually exposes | Design question, not just an API swap — TBC's tab/point model may not map cleanly | **Deferred** (documented decision) |
| Item Info / Spell Info | Cross-cutting, ~20 files (`Data/Gear/ItemStats.lua`, `ItemUsability.lua`, `GearScore.lua`, `GearUpgrade*.lua`, `GearCompare.lua`, `DataStoreProfessions.lua`, `Data/Search/*`, `GuildTabData.lua`, several `Tabs/*`/`UI/*`) | No dedicated Thaoky module — same ad-hoc inline lookups we already use, seen in `DataStore_Containers.lua`/`DataStore_Spells.lua` | `C_Item.GetItemInfo`/`GetItemInfoInstant`/`GetItemStats`, `C_Spell.GetSpellName`/`GetSpellInfo`(table return)/`GetSpellLink` | Highest fan-out; mechanical once call shapes are confirmed — plan is a small number of shared compat helpers, not 20 inline patches | **Done** for `GetItemInfo` call sites (see Phase B below); `GetSpellInfo`/`GetItemStats`/`IsUsableItem` call sites outside `DataStoreProfessions.lua` still open |
| Professions + Crafting | `Data/DataStore/DataStoreProfessions.lua` (`ScanProfessionLinks`, `ScanRecipes`, `ScanCraftRecipes`, reagent-capture helpers) — recipes already recipeID-keyed | `DataStore_Crafts/DataStore_Crafts_Retail.lua` — full rewrite, recipeID-native, already cited above in this doc | `C_TradeSkillUI.GetAllRecipeIDs`, `GetRecipeInfo`, `GetCategories`/`GetCategoryInfo`, `GetRecipeCooldown`, `GetBaseProfessionInfo` | Largest, but best-scouted — this doc already named the target APIs before this pass | **Deferred** (documented decision — `resultItemID`/reagents unresolved) |
| Auctions | `Data/DataStore/DataStoreAuctions.lua` (`ScanAuctions`, `ScanBids`) — synchronous index loop | `DataStore_Auctions/DataStore_Auctions.lua` — `isRetail = type(C_AuctionHouse) == "table"`, `API_*` wrappers | `C_AuctionHouse.GetNumOwnedAuctions`, `GetOwnedAuctionInfo`, `GetNumBids`, `GetBidInfo` | Turned out lower-risk than expected — see below, still synchronous | **Done** |

**Planned order:** Reputations → Talents → Item Info/Spell Info → Professions/Crafting → Auctions (roughly lowest-risk/clearest-template first, most invasive/lowest-traffic last). Each will be its own scoped follow-up: read the relevant Thaoky file in full (not just grep hits), add existence-checked `C_*` candidates to the matching `DataStore/` module and to `Data/ApiCheck.lua`'s `MANIFEST`, bump `Data/DATA_VERSIONS.md` only if the stored shape actually changes, and run `npm run check`. (Executed in a different order than listed — Auctions before the Item Info UI-layer sweep and before Professions/Crafting — once the Auctions Thaoky reference turned out simpler than Professions/Crafting's; the roadmap's ordering rationale still holds, just re-prioritized by actual grounding once each was read in full.)

**Caution carried into that follow-up work:** Thaoky's actively-maintained retail `DataStore_Containers.lua` still calls the plain global `GetItemInfo` directly, unguarded — real retail hasn't dropped that global. Forever reporting it fully `missing` in apicheck may be a Forever-beta-specific quirk rather than proof retail's `C_Item` namespace is the only path forward; worth a direct `/dump GetItemInfo` / `/dump C_Item and C_Item.GetItemInfo` check in Forever itself before committing to the `C_Item` design, not just inferring it from Thaoky's retail code.

Also checked `Altoholic_Forever` (a repo with that exact name under Thaoky's account) as a possible ready-made Forever reference — it's an empty scaffold (README + CI workflow only, created 2026-09-13), no source yet. Worth re-checking later, not usable now.

## Sixth: Summary tab's "Open your Skills window (P)" nag never clears on Forever (2026-09-17)

A user reported that on Forever, the Summary tab's missing-data exclamation mark tells them to "Open your Skills window (P)", but opening the Skills window (`P`) does not clear it — no matter how many times they do it.

**Root cause:** `AltArmy.DataStore:ScanProfessionLinks()` ([`DataStoreProfessions.lua`](../AltArmy_TBC/Data/DataStore/DataStoreProfessions.lua)) is the only code path that ever sets `char.dataVersions.professions`, and it bails out immediately — `if not GetNumSkillLines or not GetSkillLineInfo then return end` — before doing so. Per the `/altarmy debug apicheck` results logged above ("Professions | 11/12"), both `GetNumSkillLines` and `GetSkillLineInfo` are confirmed missing on Forever. So `char.dataVersions.professions` can never be written on that client, `DS:HasModuleData(char, "professions")` is permanently false, and [`SummaryData.lua`](../AltArmy_TBC/Data/Characters/SummaryData.lua)'s `MODULE_INSTRUCTIONS` table shows the "Open your Skills window (P)" line forever — the instruction describes an action that cannot possibly gather the data, regardless of what the player does in-game.

Unlike Reputations/Auctions/Item Info, no `C_*` replacement for "enumerate this character's skill lines with rank/maxRank" has been found anywhere in this doc's research (not in Thaoky's reference addons, not in the apicheck results) — modern retail's Professions UI moved to a wholly different, recipe/schematic-centric model (`C_TradeSkillUI`, `ProfessionsFrame`) rather than exposing a `C_*` analog of the old skill-line list. So there is nothing to fall back to yet, same epistemic position as Talents and Professions/Crafting's `resultItemID`/reagents above — implementing a real scan here would be guessing, not porting a known-good reference.

**Fix applied:** rather than guess at a replacement scan, stopped telling the player to do something that cannot work. Added `DS.HasProfessionsListApi()` (`DataStoreProfessions.lua`) — `GetNumSkillLines ~= nil and GetSkillLineInfo ~= nil` — and gated the "Open your Skills window (P)" instruction in `SummaryData.lua`'s `GetMissingDataInfo` on it: when the API doesn't exist, the professions module is silently skipped in the `MODULE_INSTRUCTIONS` loop instead of nagging forever. Zero behavior change on TBC Classic (`HasProfessionsListApi()` is true there, same instruction shows exactly as before). This is the same "don't warn about things the player can't act on" precedent already used for mail/auctions in that file, applied to a new case where the *reason* is a missing client API rather than a deliberate product decision.

**Scope:** this only fixes the misleading nag — it does not restore profession/recipe scanning on Forever, which remains the deferred, tracked gap from the "Professions + Crafting" roadmap row above. `npm run check` and all 2321 tests pass (added `HasProfessionsListApi` coverage in `DataStoreProfessions_spec.lua` and two `SummaryData_spec.lua` cases covering the API-present and API-missing paths).

## Seventh: candidate replacement for `GetNumSkillLines`/`GetSkillLineInfo` found (2026-09-17, research only)

Went back to Thaoky's addons (as requested) specifically to find a replacement for the skill-line-list pair (profession *presence + rank*, the gap the sixth entry above worked around rather than fixed) — separate from the already-deferred "Professions + Crafting" *recipe* scan gap (`resultItemID`/reagents, still unaddressed).

**Where it lives:** not `DataStore_Crafts` (recipes only) or `DataStore_Characters` (no profession/skill references at all) — the profession-list scan is inside [`DataStore_Crafts_Retail.lua`](https://github.com/Thaoky/DataStore_Crafts/blob/master/DataStore_Crafts/DataStore_Crafts_Retail.lua) itself, as a second `ScanProfessionLinks()` implementation alongside the `GetNumSkillLines`/`GetSkillLineInfo`-based one (`ScanProfessionLinks_NonRetail()`, the direct analog of our own current TBC code). The file picks between them with:

```lua
local hasAdvancedProfessionInfo = (LE_EXPANSION_LEVEL_CURRENT >= LE_EXPANSION_CATACLYSM)
...
local function ScanProfessionLinks()
    if not hasAdvancedProfessionInfo then
        ScanProfessionLinks_NonRetail()
        return
    end
    local prof1, prof2, arch, fish, cook, firstAid = GetProfessions()
    ScanProfessionInfo(prof1, 1)
    ScanProfessionInfo(prof2, 2)
    ScanProfessionInfo(cook, 3)
    ScanProfessionInfo(fish, 4)
    if hasArchaeology then ScanProfessionInfo(arch, 5) end
    if not isRetail then ScanProfessionInfo(firstAid, 6) end
    thisCharacter.lastUpdate = time()
end
```

where `ScanProfessionInfo(index, mainIndex)` is just `GetProfessionInfo(index)` plus a save:

```lua
local name, texture, rank, maxRank, _, _, _, _, _, _, currentLevelName = GetProfessionInfo(index)
```

**The replacement pair: `GetProfessions()` + `GetProfessionInfo(index)`.** Confirmed against [Warcraft Wiki](https://warcraft.wiki.gg/wiki/API_GetProfessionInfo):
- `GetProfessionInfo(index)` — stable since **Patch 4.0.1 (2010)**, 11 return values: `name, icon, skillLevel(=rank), maxSkillLevel(=maxRank), numAbilities, spelloffset, skillLine, skillModifier, specializationIndex, specializationOffset, skillLineName`. `rank`/`maxRank` land in the same positions our own `char.Professions[name].rank`/`.maxRank` already expect.
- `GetProfessions()` — returns up to 5-6 spell-tab indices to feed into the above: `prof1, prof2, archaeology, fishing, cooking[, firstAid]`. Per wiki, **available on "mainline, MoP Classic, BC Anniversary, and Classic Era"** — i.e. it's not retail-exclusive; it's already present on our own live TBC Classic client (BC Anniversary) today, just unused by us since the legacy pair already works there. `firstAid` as a 6th return was removed from real retail in Patch 8.0.1 but Classic-family clients (per Thaoky's `if not isRetail then` guard) still return it — which of those two behaviors Forever follows is unconfirmed.

**Why this is a stronger candidate than the deferred recipe-scan replacement (`C_TradeSkillUI`):** `GetNumTradeSkills`/recipe scanning needed brand-new, unfamiliar retail APIs with unconfirmed field names (`resultItemID`, reagents) — the reason that work was deferred. This is different: `GetProfessions`/`GetProfessionInfo` are old, stable (16 years), well-documented, and — per the wiki — already live on our own production TBC Classic client right now. That means the fallback path can be built and unit-tested today, and even manually verified on a real TBC character (by temporarily forcing the fallback branch), without needing Forever beta access at all to gain confidence in the field mapping. Forever access is only needed to confirm the pair actually exists there and to settle the `firstAid` question.

**What it does and doesn't cover:** gives profession *presence + rank* for primary professions (including the gathering ones — Herbalism/Mining/Skinning occupy the same `prof1`/`prof2` slots as Alchemy/Tailoring, so `PROFESSIONS_NO_WARNING` coverage is unaffected) plus Cooking/Fishing, with First Aid's inclusion unconfirmed and Archaeology out of scope (not in TBC/Forever content). It does **not** touch recipe/reagent data — `DS:ScanRecipes()`'s `GetNumTradeSkills`-based loop is a separate, still-deferred gap (unchanged from the "Professions + Crafting" roadmap entry above).

**Implemented (2026-09-17).** [`DataStoreProfessions.lua`](../AltArmy_TBC/Data/DataStore/DataStoreProfessions.lua)'s `ScanProfessionLinks()` now tries the legacy `GetNumSkillLines`/`GetSkillLineInfo` loop first and falls back to a new `ScanProfessionLinksViaGetProfessions()` when that pair is missing — same "legacy first, fallback second, checked dynamically" convention as `C_Reputation`/`C_AuctionHouse`. The two scan loops were refactored to share one `CollectProfessionEntry()` helper (name/rank/maxRank + primary/secondary bookkeeping, presence-changed tracking) so the logic that decides "did anything change" only exists once. `DS.HasProfessionsListApi()` now returns true if *either* pair exists, and all five `DataStore.lua` dispatch sites (`PLAYER_ENTERING_WORLD`, its delayed late-scan, `SKILL_LINES_CHANGED`, `TRADE_SKILL_SHOW`, `CHAT_MSG_SKILL`) were switched from a raw `GetNumSkillLines and GetSkillLineInfo` guard to `DS.HasProfessionsListApi()` so the fallback actually gets called.

Field mapping ported directly from Thaoky's advanced branch: `GetProfessions()`'s `prof1`/`prof2` indices (which include gathering professions — Mining/Herbalism/Skinning occupy the same slots as Alchemy/Tailoring, so `PROFESSIONS_NO_WARNING` behavior is unaffected) and `cooking`/`fishing` indices are resolved via `GetProfessionInfo(index)` → `name, _, rank, maxRank`. Archaeology is deliberately skipped (not in TBC/Forever content). First Aid is read defensively from `GetProfessions()`'s optional 6th return (`firstAidIndex`) without branching on `isRetail`/expansion level — if it's nil (real-retail-style clients, which dropped it in Patch 8.0.1), First Aid is simply not populated via this path, same honest-gap behavior as everything else in this doc when a field is unconfirmed, rather than guessing which behavior Forever follows.

One nice side effect: unlike the legacy loop, `GetProfessions()`/`GetProfessionInfo()` are direct queries, not a snapshot of an open UI panel — so on a client where this fallback applies, profession data can populate at login (`PLAYER_ENTERING_WORLD`) without the player ever opening the Skills window at all. This doesn't fully close the loop yet: `DS:ScanRecipes()` (the actual per-recipe scan, still `GetNumTradeSkills`-based) remains the separately-deferred "Professions + Crafting" gap above, so a Forever character would show profession *presence and rank* but still no recipes until that's tackled.

Added coverage in `DataStoreProfessions_spec.lua`: three new `HasProfessionsListApi` cases (legacy-only, neither, fallback-only) and a new `ScanProfessionLinks (GetProfessions/GetProfessionInfo fallback)` describe block (primary/gathering professions, secondary professions, `dataVersions` gets marked gathered, dropped-profession pruning, guild-share broadcast on change). `npm run check` and all 2327 tests pass.

**Still open:** whether `GetProfessions`/`GetProfessionInfo` actually exist on Forever, and which `firstAid` behavior it follows, are both unconfirmed — the two new `Data/ApiCheck.lua` manifest rows from the research pass above will answer this on the next in-game `/altarmy debug apicheck` run. The `C_Item`/`C_Spell`/`C_Reputation`/`C_AuctionHouse` fallbacks elsewhere in this doc were all similarly implemented before Forever-side confirmation, on the strength of the API being well-documented and already live elsewhere — same standard applied here.

## Eighth: does opening the profession window still matter, and a partial recipe-scan fix (2026-09-17)

Follow-up question after the Seventh entry landed and successfully cleared the profession-presence nag (user confirmed the Summary tab now correctly asks to open Cooking/Leatherworking specifically — the fallback works): **is opening the profession still required, or does the modern API have a way around it?**

**Answer: still required, and there's no way around it.** Checked `C_TradeSkillUI.OpenTradeSkill` (the modern equivalent of "open this trade skill") — per Warcraft Wiki, it's a function that "requires a hardware event i.e. keyboard/mouse input," the same restricted-call class as other UI-opening APIs. An addon cannot invoke it from a timer, an event handler, or any code path not directly inside a real click/keypress handler. Thaoky's retail code doesn't attempt to; it only ever reacts passively to the window being opened by the player, same as our own legacy code always has. This isn't a Forever-specific limitation — it's a fundamental WoW addon security restriction that predates Forever entirely.

**Refined understanding of the trigger, from a full re-read of `DataStore_Crafts_Retail.lua`:** the actual full recipe scan on retail is *not* wired to `TRADE_SKILL_SHOW` (that event only hooks `C_TradeSkillUI.CraftRecipe` and starts listening for `TRADE_SKILL_CLOSE` on retail). It's wired to `TRADE_SKILL_DATA_SOURCE_CHANGED`, registered unconditionally at login alongside `PLAYER_ENTERING_WORLD` — this fires once a profession's data actually finishes loading, whether that's from opening its window directly or (per Blizzard's newer Crafting Orders feature) viewing someone else's craftable list. Practically: same "opened a window this session" requirement as before, just a different, more precise event name than `TRADE_SKILL_SHOW`.

**What `ScanRecipes_Retail()` reads once that fires,** confirmed field-by-field this time (not just paraphrased from memory):
- `C_TradeSkillUI.GetAllRecipeIDs()` → the recipe ID list
- `C_TradeSkillUI.GetRecipeInfo(recipeID)` → `{ recipeID, categoryID, name, learned, relativeDifficulty, previousRecipeID, nextRecipeID, ... }` (Warcraft Wiki's field dump has ~35 more fields for modern crafting-quality/recraft mechanics that don't apply to TBC/Forever-style recipes)
- `relativeDifficulty` is a small enum: `0=Optimal, 1=Medium, 2=Easy, 3=Trivial` (confirmed via wiki — this doc previously flagged this mapping as unconfirmed; it no longer is)
- `C_TradeSkillUI.GetRecipeCooldown(recipeID)` → cooldown seconds (not yet ported below; see Scope)

**resultItemID: found a real source, independent of Thaoky.** Re-confirmed his retail code has zero reagent/result-item code (`grep`'d the full 1018-line file for `reagent`/`resultItem`/`schematic` — those terms only appear in the non-retail branch). But a direct search turned up `C_TradeSkillUI.GetRecipeOutputItemData(recipeSpellID)` — undocumented in Thaoky's code but real, current Blizzard API — returning `{ icon, hyperlink, itemID }` for a recipe's crafted item. The `reagents` parameter is optional (for modern choice-reagent/quality crafting, Dragonflight-era mechanic that doesn't apply to vanilla-style recipes), so calling it with just the recipe ID should be sufficient for TBC/Forever-style fixed-output recipes.

**Reagents: still no source.** The `CraftingReagentInfo`/`CraftingReagent` structures that come up around `GetRecipeOutputItemData` are for *specifying* reagents when querying a choice-based output, not for *reading* which reagents a recipe fixedly requires. That data lives in the more involved `C_TradeSkillUI.GetRecipeSchematic()` API (reagent slots, quality tiers) — genuinely more complex, no working example anywhere in this doc's research yet. Remains deferred.

**Implemented (partial, by explicit choice — see below).** [`DataStoreProfessions.lua`](../AltArmy_TBC/Data/DataStore/DataStoreProfessions.lua)'s `DS:ScanRecipes()` now branches legacy (`GetNumTradeSkills`/`GetTradeSkillLine`) vs. a new `ScanRecipesViaTradeSkillUI()` fallback, same pattern as every other fallback in this doc. The fallback reads presence/category/learned/cooldown-eligible recipes via `GetAllRecipeIDs`/`GetRecipeInfo`, maps `relativeDifficulty` to our `SkillTypeToColor` scale, and best-effort fills `resultItemID` via `GetRecipeOutputItemData` when that API exists (wrapped in `pcall`, degrades to `nil` on failure — same defensive posture as everywhere else). **Only learned recipes are stored**, deliberately deviating from Thaoky's literal port (which stores every class-wide recipe including locked/unlearned ones, using a `learned` bit) — our own `char.Professions[name].Recipes` table has always meant "recipes this character can craft" (e.g. `DS:GetNumRecipes`'s zero-recipes check drives the Summary nag), and TBC/Forever's vanilla-style trade-skill window has never shown unlearned recipes the way modern Dragonflight's Professions UI does, so storing unlearned rows would both contradict our existing data-model invariant and probably not reflect what Forever's own UI shows anyway.

Dispatch: added `TRADE_SKILL_DATA_SOURCE_CHANGED` to `DataStore.lua`'s `SafeRegisterEvent` calls and its own handler (calls `DS:RunDeferredRecipeScan()`, guarded by the new `DS.HasTradeSkillRecipesApi()`), and switched the existing `TRADE_SKILL_SHOW` deferred-scan guard from a raw `GetNumTradeSkills and GetTradeSkillLine` check to the same existence check. Reagent capture (`CaptureAllTradeSkillReagentsOnly`, the `tradeSkillReagentRetryFrame` retry) stays legacy-only/unguarded by the new check — no fallback exists for it yet, consistent with the deferred status above.

**Scope, deliberately limited:** `resultItemID` is filled but reagents are not — a recipe row on Forever will have a name/category/cooldown/crafted-item-icon but no reagent list, same "partial data, not a guess" tradeoff flagged in the roadmap above, now narrower than before (down from two missing fields to one). `GetRecipeCooldown` wasn't wired into this pass either (cooldown *tracking* is a separate, already-large surface in this file — `ScanTradeSkillCooldownExpiry` et al. — left as its own future pass rather than folded in here). Covered by 8 new spec cases in `DataStoreProfessions_spec.lua` (`HasTradeSkillRecipesApi` existence-check cases, and a `ScanRecipes (C_TradeSkillUI fallback)` block: learned-only filtering, relativeDifficulty→color mapping, resultItemID present/absent, rank update, dataVersions/guild-share on success, no-mark-scanned on empty). Also hardened `DS:ScanRecipes()` with a `char.Professions = char.Professions or {}` guard at the top (previously relied on `ScanProfessionLinks` always running first without ever checking — a latent crash risk on any client where that ordering assumption breaks; same fix already applied to `ScanCraftRecipes` when it was written). `npm run check` and all 2335 tests pass.

**Still open, unverified pre-Forever-access:** whether `C_TradeSkillUI` exists on Forever at all (five new rows added to `Data/ApiCheck.lua`'s `MANIFEST` — `GetAllRecipeIDs`, `GetRecipeInfo`, `GetBaseProfessionInfo`, `GetRecipeOutputItemData`, `GetRecipeCooldown` — so the next `/altarmy debug apicheck` run confirms it), whether calling `GetRecipeOutputItemData` with only a recipe ID (no reagents) actually resolves for TBC/Forever-style fixed recipes, and whether `relativeDifficulty`'s 0-3 mapping holds for pre-Dragonflight-style content. Same epistemic status as everything else in this document until beta access allows a live check.

## Ninth: Skinning has real recipes on Forever, unlike TBC (2026-09-17)

User report from in-game: on Forever, Skinning has an actual recipe window (crafted items, not just the passive gathering skill it is in TBC). This matters because `SummaryData.lua`'s `PROFESSIONS_NO_WARNING` table — which suppresses the "Open your X window" nag for gathering/secondary skills that have no recipe UI at all — hardcoded `Skinning = true` alongside `Fishing`/`Riding`/`Herbalism`/`Mining`. That's correct for TBC (Skinning genuinely has no trade-skill window there) but wrong for Forever: a Skinning-having character there should get the same "you have a rank but no recipes scanned yet, go open the window" prompt every other profession gets.

This isn't an API-existence fact (both clients can enumerate Skinning as a primary-profession slot via `GetProfessions()`/legacy `GetSkillLineInfo` equally fine) — it's a *content* fact that happens to correlate with which client family is running. Rather than add a new client-detection mechanism, reused the signal we already compute: `DS.IsUsingTradeSkillUiFallback()` (new function, `DataStoreProfessions.lua`) reports whether recipe scanning is happening through the C_TradeSkillUI fallback (Forever-shaped) instead of the legacy `GetNumTradeSkills`/`GetTradeSkillLine` pair (TBC-shaped) — same existence-check building block `ScanRecipes` already uses, exposed for a caller that needs to know *which* path is active, not just whether recipes can be scanned at all.

`SummaryData.lua` now has two exclusion tables — `PROFESSIONS_NO_WARNING` (legacy, includes Skinning, unchanged default) and `PROFESSIONS_NO_WARNING_TRADESKILLUI_FALLBACK` (Forever-shaped, Skinning removed) — and picks between them via `DS.IsUsingTradeSkillUiFallback()` in the per-profession missing-recipes loop. Zero behavior change on TBC Classic (legacy API present, same table as before). Added two `SummaryData_spec.lua` cases (Skinning silent on legacy, Skinning warned-about on the fallback) plus confirmed the existing "gathering professions should not warn for stale recipes" Mining test stays green regardless of which table is active (Mining is excluded in both — only Skinning's status actually changed). `npm run check` and all 2337 tests pass.

**Scope note, flagged for a future session:** this only fixes the Summary-tab nag. Whether Forever's Skinning recipes are actually scanned correctly by the Eighth entry's `ScanRecipesViaTradeSkillUI` fallback is unverified — Skinning wasn't specifically tested there, though there's no reason to expect it behaves differently from any other primary profession in that code path. Also unconfirmed: whether *other* TBC-gathering-only skills (Mining, Herbalism, Fishing) also gained recipes on Forever — the user only reported Skinning, so this fix deliberately doesn't guess about the others.

**Centralized same-day, after a follow-up question:** "has the Guild tab been updated too, and can both places share one set of constants?" Checked [`GuildTabData.lua`](../AltArmy_TBC/Data/Guild/GuildTabData.lua) — it has its own, separate crafting-vs-gathering split (`PRIMARY_PROFESSION_KEYS` / `GATHERING_PROFESSION_KEYS`, driving which professions get a recipe tab in the Guild tab's per-member recipe browser) and had *not* been updated; Skinning would have kept showing as gathering-only (no recipe tab) there even after the Summary-tab fix above.

Rather than duplicate the Skinning special-case a second time, moved the actual decision into one place: [`DataStoreProfessions.lua`](../AltArmy_TBC/Data/DataStore/DataStoreProfessions.lua) now exports `DS.NO_RECIPE_PROFESSION_KEYS_LEGACY`/`_TRADESKILLUI_FALLBACK` (canonical lowercase profession-key sets) and `DS.ProfessionHasNoRecipeWindow(profNameOrKey)` — a single case-insensitive predicate, selecting between the two sets via the already-existing `DS.IsUsingTradeSkillUiFallback()`. Both call sites now read from it instead of keeping their own copy:
- `SummaryData.lua`'s per-profession missing-recipes loop: removed its local `PROFESSIONS_NO_WARNING`/`_TRADESKILLUI_FALLBACK` tables entirely, calls `DS.ProfessionHasNoRecipeWindow(profName)` directly.
- `GuildTabData.lua`'s `collectProfessions()`: the gathering-bucket check became `GTD.GATHERING_PROFESSION_KEYS[resolved] and hasNoRecipeWindow(resolved)` — a small local wrapper (not a captured `AltArmy.DataStore` upvalue) that resolves `AltArmy.DataStore` fresh on every call and defaults to `true` (TBC's actual behavior) when it isn't loaded. This mirrors the file's existing `hasItemInfoApi`/`compatGetItemInfo` pattern and for the same documented reason: `GuildTabData.lua` is deliberately self-contained (no `AltArmy.DataStore` dependency) so its unit tests — which stub things directly and never `require("DataStore")` — keep working. `GTD.GATHERING_PROFESSION_KEYS` itself stays as-is: it's still the *structural* fact ("these three occupy a primary-profession slot"), separate from the *dynamic* fact ("does this one currently have a recipe window") that `hasNoRecipeWindow` now answers.

Now Skinning shows as a normal crafting profession (left side, gets its own recipe tab) in the Guild tab whenever `DS.ProfessionHasNoRecipeWindow` says so — same trigger as the Summary-tab fix, zero duplicate logic. Added three new tests: `DataStoreProfessions_spec.lua` already covered `IsUsingTradeSkillUiFallback`; `GuildTabData_spec.lua` gained two new `GetCraftingProfessions` cases (Skinning stays gathering-only when `AltArmy.DataStore` isn't loaded — the existing unit-test environment, unchanged; Skinning promotes to the crafting bucket when a mocked `DS.ProfessionHasNoRecipeWindow` says it has recipes). All existing `GuildTabData_spec.lua`/`SummaryData_spec.lua` cases needed no changes except `SummaryData_spec.lua`'s shared `before_each`, which now seeds a default `DS.ProfessionHasNoRecipeWindow` mock matching TBC's legacy set (since the module no longer has its own hardcoded table for tests to implicitly rely on). `npm run check` and all 2339 tests pass.

## Phase B progress: Reputations implemented, Talents deferred by design (2026-09-17)

**Reputations — implemented.** [`DataStoreReputations.lua`](../AltArmy_TBC/Data/DataStore/DataStoreReputations.lua) now resolves faction scanning through existence-checked wrapper functions (`API_GetNumFactions`, `API_GetFactionInfo`, `API_ExpandFactionHeader`, `API_CollapseFactionHeader`) that try the legacy global first and fall back to `C_Reputation.GetNumFactions`/`GetFactionDataByIndex`/`ExpandFactionHeader`/`CollapseFactionHeader` — mirroring the `TryFactionNameFromGameAPI` fallback already in that file. `DS.HasReputationApi()` is the new single existence check, used both inside the module and by `DataStore.lua`'s three dispatch sites (`PLAYER_ENTERING_WORLD`, the delayed late-scan, `UPDATE_FACTION`) so scanning is actually attempted on clients where only `C_Reputation` exists. `Data/ApiCheck.lua`'s `MANIFEST` gained the matching `C_Reputation.*` candidates on the existing Reputations rows.

One real bug surfaced and was fixed during implementation, worth recording as a lesson for the remaining areas: the first pass captured the wrapper functions as **load-time upvalues** (`local API_GetFactionInfo = GetFactionInfo or ...`), evaluated once when the file loads. This broke `spec/Data/DataStoreReputations_spec.lua`'s alphabetical-sort test, which stubs `_G.GetFactionInfo` *after* the module is already loaded (the same way a real client could theoretically expose an API later than addon-load, though that doesn't happen in practice) — the stale captured value never saw the stub. Fixed by making the wrappers ordinary functions that resolve the underlying API dynamically on every call, matching how every other existence check in this codebase already works (`if GetNumFactions and ... then`, evaluated fresh each time). **This is the pattern to use for every remaining area, not a one-off fix.** `npm run check` and `npm test` both pass (2302/2302) after the fix.

The `C_Reputation.GetFactionDataByIndex` field names used in the fallback (`reaction`, `currentReactionThreshold`, `nextReactionThreshold`, `currentStanding`, `atWarWith`, `canToggleAtWar`, `isHeader`, `isCollapsed`, `hasRep`, `isWatched`, `isChild`, `factionID`) are inferred from the public retail API shape, not yet confirmed against a live Forever snapshot — flagged in the code as unverified pre-beta-access, same epistemic status as the rest of this document until someone can run it in Forever and check `AltArmyTBC_Data.Characters[...].Reputations` actually populates.

**Talents — deliberately not implemented.** Re-read `DataStoreTalents.lua` in full: `readTalentTabs()`/`ScanTalents()` already fail safe (guarded, no partial writes), and `DT.ResolveSpecKey()` already has a designed no-data fallback (guesses a per-class "leveling spec"). Unlike Reputations, there is no well-grounded `C_*` field mapping to reach for here — Thaoky's own `DataStore_Talents.lua` is genuinely mid-rewrite (large sections commented out, referenced `C_SpecializationInfo.GetTalentInfo` sits inside disabled code), and modern retail's actual talent system (trait trees keyed by configID/nodeID via `C_Traits`/`C_ClassTalents`) isn't a simple tab/point-count analog of TBC's 3-tab system — there's nothing to safely fall back to without guessing at an entirely different data model. Shipping speculative `C_Traits` code with unverified field names would risk writing wrong data into `char.talents` (worse than the current honest "no data" state) rather than degrading gracefully like the `C_Reputation` fallback does.

**Decision:** leave Talents as-is. The per-class `ResolveSpecKey` fallback is the intended, permanent Forever behavior for now — not a placeholder awaiting a fix. Revisit only if/when someone can check in-game what talent-related APIs Forever actually exposes (`/altarmy debug apicheck`'s Talents rows, plus manual `/dump` exploration of `C_Traits`/`C_ClassTalents`/`C_SpecializationInfo`), since Thaoky's code doesn't currently answer that question.

## Phase B progress: Item Info / Spell Info — compat layer built, DataStore layer migrated, UI layer still open (2026-09-17)

Added [`DataStoreItemSpellCompat.lua`](../AltArmy_TBC/Data/DataStore/DataStoreItemSpellCompat.lua), a new small module (loaded right after core `DataStore.lua` in the `.toc`, before everything that could use it) exposing `DS.CompatGetItemInfo`, `CompatGetItemInfoInstant`, `CompatGetItemStats`, `CompatIsUsableItem`, `CompatGetSpellInfo`, and `CompatGetSpellLink`. Each tries the legacy global first, falls back to `C_Item`/`C_Spell`, and returns the **same tuple shape** as the legacy call so callers don't need to change their `select()`/destructuring logic — just the function name. `CompatGetSpellInfo` is the one genuine shape change: `C_Spell.GetSpellInfo` returns a table, not a multi-return, so it's unpacked back to the legacy 7-value shape with `rank` always `nil` (spell ranks are a TBC-and-earlier concept with no retail/Forever equivalent). Covered by a new [`DataStoreItemSpellCompat_spec.lua`](../spec/Data/DataStoreItemSpellCompat_spec.lua). `.luacheckrc` gained `C_Item`/`C_Spell`/`IsUsableItem`/`GetItemStats` globals; `Data/ApiCheck.lua`'s Item Info rows gained the matching `C_Item.*`/`C_Spell.*` candidates.

**Migrated so far** (the `DataStore/` scan layer itself — the background data-collection code this whole compatibility effort is about): `DataStoreEquipment.lua:GetAverageItemLevel` (`GetItemInfo` → `DS.CompatGetItemInfo`) and every `GetSpellInfo` call site in `DataStoreProfessions.lua` (profession-name resolution/sorting, Cooking/Fishing/First Aid rank lookups, the French "Secourisme" First Aid alias, and the macro-body spell-name matcher used by cooldown tracking) — all now route through `DS.CompatGetSpellInfo` behind a new `HasSpellInfoApi()` existence check in that file.

**Not yet migrated — cross-cutting UI/presentation layer, ~15 files, left as an enumerated follow-up rather than rushed:** `Data/Gear/ItemStats.lua`, `ItemUsability.lua`, `GearScore.lua`, `GearUpgrade.lua`, `GearUpgradeAlerts.lua`, `GearCompare.lua`, `Data/Search/SearchData.lua`/`SearchPresent.lua`/`RecipeYieldBonus.lua`/`SearchSettings.lua` (item-name/-icon paths since **partially** migrated — see below), `Data/Guild/GuildTabData.lua`, `Data/Characters/NetWorth.lua`, `Data/Integrations/RecipeCraftLib.lua`, `Tabs/TabGear.lua`/`TabCooldowns.lua`/`TabSearch.lua`/`TabGuild.lua` (`TabSearch.lua` item-row icon paths since partially migrated — see below), `UI/ItemActions.lua`/`QuestRewardIndicators.lua`. These are ~90 individual `GetItemInfo`/`GetSpellInfo`/`GetItemStats`/`IsUsableItem` call sites (mostly render-time icon/name/tooltip lookups, some using `select(N, ...)` against specific tuple positions) — mechanical once `DS.CompatGetItemInfo` exists, but genuinely risky to rewrite in bulk without individually verifying each `select()` offset survives the rename. Left for a dedicated follow-up pass rather than a rushed multi-file sweep in this one.

All 2312 tests and `npm run check` pass after this change. Same caveat as the roadmap above: the `C_Item`/`C_Spell` field/return shapes are inferred, not yet confirmed against a live Forever snapshot.

**Search tab migrated (2026-09-17), first real user report.** A user searching for an inventory item (e.g. "Ragged Leather Bracers") on Forever saw the result row's name render as `Item 1370 x1` instead of the real name — but the row's tooltip (which goes through `GameTooltip:SetHyperlink`, not `GetItemInfo`) showed the correct item, confirming the name text (not the underlying item data) was the broken piece. Root cause: `Data/Search/SearchData.lua`'s `ResolveItemName` and `Tabs/TabSearch.lua`'s per-row icon lookups (`fillItemRow`, the tooltip-only group-icon overlay) called the plain `GetItemInfo` global directly — one of the ~15 files this doc's "Not yet migrated" list above already named. Fixed by routing both through `DS.CompatGetItemInfo`, same pattern as the rest of this section. Recipe-name/-icon resolution (`ResolveRecipeName` in `SearchData.lua`, the recipe icon lookups in `SearchPresent.lua`) still calls the plain globals directly and remains on the "not yet migrated" list — left alone since it wasn't the reported bug and recipe scanning is already inert on Forever today (Professions/Crafting APIs are still fully missing, per the apicheck results above). `npm run check` and all 2317 tests pass after this change.

**Full UI/presentation layer migrated (2026-09-17).** Rather than leave the remaining ~90 call sites for a future pass, swept every file named in the "Not yet migrated" list above: `Data/Gear/ItemStats.lua`, `ItemUsability.lua`, `GearScore.lua`, `GearUpgrade.lua`, `GearUpgradeAlerts.lua`, `GearCompare.lua`, `Data/Search/SearchData.lua`'s remaining recipe-name path, `SearchPresent.lua`'s recipe-name/-icon paths, `RecipeYieldBonus.lua`, `Data/Guild/GuildTabData.lua`, `Data/Characters/NetWorth.lua`, `Tabs/TabGear.lua`/`TabCooldowns.lua`/`TabGuild.lua`/`TabSearch.lua`'s remaining recipe-icon path, and `UI/ItemActions.lua`/`QuestRewardIndicators.lua`. `Data/ApiCheck.lua`'s Item Info rows and `Data/Integrations/RecipeCraftLib.lua` were re-checked and had no direct `GetItemInfo` call sites needing a change.

Added `DS.HasItemInfoApi()` to `DataStoreItemSpellCompat.lua` (existence check mirroring `DS.HasReputationApi()`/`DS.HasOwnedAuctionsApi()`) so callers no longer need a bare `if GetItemInfo then` guard.

**One real bug surfaced during this pass, the same "stale upvalue" class as the Reputations lesson above, but from the opposite direction.** The mechanical approach was to route each file through `AltArmy.DataStore.CompatGetItemInfo`/`HasItemInfoApi`, adding `local DS = AltArmy.DataStore` at module scope where it wasn't already present. This broke ~14 spec files with 255 new test errors: many of this addon's unit tests (`ItemUsability_spec.lua`, `GearUpgrade_spec.lua`, `NetWorth_spec.lua`, `GuildTabData_spec.lua`, and others) test a single module in isolation — they stub `_G.GetItemInfo` directly and never `require("DataStore")`/`require("DataStoreItemSpellCompat")` at all, so `AltArmy.DataStore` is nil (or missing `HasItemInfoApi`) in that environment; a module-level `local DS = AltArmy.DataStore` captures that nil once at file-load time and stays nil even if a later test assigns `AltArmy.DataStore = {...}`, unless the spec also re-requires the module afterward (some specs do this — `loadWithMocks`-style helpers in `GearUpgradeAlerts_spec.lua`/`ItemUsability_spec.lua` reload the module right after mocking `DataStore`, which is why those particular files were unaffected; `NetWorth_spec.lua` and `GuildTabData_spec.lua` mock `AltArmy.DataStore` in `before_each` without reloading, which is exactly the pattern that breaks).

**Fix, and the resulting design rule:** the two-line "does GetItemInfo/C_Item.GetItemInfo exist, call whichever does" check does not need `AltArmy.DataStore` at all — it only reads globals. Every touched leaf file (Gear/Search/Guild/Quest-reward modules) now defines its own small, self-contained `hasItemInfoApi()`/`compatGetItemInfo()` pair (same body as `DS.CompatGetItemInfo`, just not namespaced under `DataStore`) instead of calling through `DS`. Files that already had a **pre-existing, function-scoped** `local DS = AltArmy.DataStore` for real character-data lookups (`GetCurrentCharacter`, `ForEachCharacter`, etc.) keep that pattern exactly as it was — those genuinely need the live `AltArmy.DataStore` and are correctly written to resolve it fresh on every call rather than capture it once. `DataStoreItemSpellCompat.lua`'s `DS.CompatGetItemInfo`/`DS.HasItemInfoApi` remain the right choice for files that are already part of the `DataStore/` layer or already require it in their specs (`DataStoreEquipment.lua`, `GearScore.lua`, `TabCooldowns.lua`, `TabGear.lua`, `TabGuild.lua`, `TabSearch.lua`, `SearchData.lua`) — this is a "which files may assume DataStore is loaded" distinction, not a reversal of the compat-wrapper design. All 2317 tests and `npm run check` pass after this pass.

## Phase B progress: Auctions implemented, Professions/Crafting deferred by design (2026-09-17)

**Auctions — implemented,** and the roadmap's own risk rating above turned out too pessimistic. Fetched the complete [`DataStore_Auctions/DataStore_Auctions.lua`](https://github.com/Thaoky/DataStore_Auctions) (not just grep hits this time) and it shows `C_AuctionHouse.GetNumOwnedAuctions`/`GetOwnedAuctionInfo`/`GetNumBids`/`GetBidInfo` are **synchronous reads of client-cached data**, not an async query API — the client pushes `OWNED_AUCTIONS_UPDATED`/`BIDS_UPDATED`/`AUCTION_HOUSE_AUCTION_CREATED` events and the scan is still a plain `for i = 1, numAuctions do ... end` loop, same shape as the legacy `GetNumAuctionItems`/`GetAuctionItemInfo` pair. No async rewrite needed after all, and no `DATA_VERSIONS.md` bump — the stored `char.Auctions[]`/`char.Bids[]` shape is unchanged.

[`DataStoreAuctions.lua`](../AltArmy_TBC/Data/DataStore/DataStoreAuctions.lua) now has `API_GetOwnedAuctionInfo`/`API_GetBidAuctionInfo` wrapper functions (legacy first, `C_AuctionHouse` fallback, exact field mapping ported from Thaoky's working retail code — `info.itemKey.itemID`, `info.quantity`, `info.bidAmount`, `info.buyoutAmount`, `info.timeLeftSeconds` for owned auctions; `info.timeLeft` and `info.bidder` for bids) and two new existence checks, `DS.HasOwnedAuctionsApi()`/`DS.HasBidAuctionsApi()`, used both internally and by `DataStore.lua`'s dispatch (which now also registers/handles `OWNED_AUCTIONS_UPDATED`, `AUCTION_HOUSE_AUCTION_CREATED`, `BIDS_UPDATED` alongside the legacy `AUCTION_OWNED_LIST_UPDATE`/`AUCTION_BIDDER_LIST_UPDATE`). `Data/ApiCheck.lua` gained matching `C_AuctionHouse.*` candidates, including two new manifest rows (`GetNumBids`/`GetBidInfo`) since the legacy side collapses both onto one `GetNumAuctionItems`/`GetAuctionItemInfo` pair but the `C_AuctionHouse` side doesn't. Covered by new `ScanAuctions`/`ScanBids` tests in [`DataStoreAuctions_spec.lua`](../spec/Data/DataStoreAuctions_spec.lua) exercising both the legacy and `C_AuctionHouse` paths (including the sold-row skip). All 2317 tests and `npm run check` pass.

One inherited Blizzard-side quirk, ported as-is rather than "fixed": owned-auction rows get `timeLeftSeconds` (real seconds) from `C_AuctionHouse.GetOwnedAuctionInfo`, but bid rows get `timeLeft` (a coarse 1-4 short/medium/long/verylong band) from `C_AuctionHouse.GetBidInfo` — the same unit mismatch the legacy `GetAuctionItemTimeLeft` API already has (it's also a 1-4 band). Thaoky's code doesn't normalize this, so neither does ours; documented in the code as a known quirk, not treated as a bug.

**Professions + Crafting — deliberately not implemented this pass.** Fetched the complete [`DataStore_Crafts_Retail.lua`](https://github.com/Thaoky/DataStore_Crafts) (1018 lines) to ground this properly rather than guess from the function names already cited in this doc. What it confirms: `C_TradeSkillUI.GetAllRecipeIDs()` + `GetRecipeInfo(recipeID)` (fields `.categoryID`, `.name`, `.learned`, `.relativeDifficulty`) + `GetCategories()`/`GetCategoryInfo(id)` (fields `.categoryID`, `.name`, `.skillLineCurrentLevel`, `.skillLineMaxLevel`) + `GetRecipeCooldown(recipeID)` are real and well-grounded for recipe **presence, category, learned-state, and cooldown**. But two things this codebase's `ScanRecipes()` actually needs aren't answered by that file:
- **`resultItemID`** (the crafted item, stored per recipe today) — Thaoky's retail scan doesn't extract this at all; the function to get it (something like `GetRecipeOutputItemData`/`GetRecipeOutputItemID`, if it even matches that name) isn't demonstrated anywhere in the reference.
- **Reagents** (`CaptureTradeSkillReagentsForIndex`'s job) — Thaoky's retail path **doesn't scan reagents either**; only the non-retail branch in the same file does (via the legacy `GetTradeSkillNumReagents`/`GetTradeSkillReagentInfo`). Modern retail reagent data lives in a schematic-shaped API (`C_TradeSkillUI.GetRecipeSchematic`, reagent slots/reagent lists) that this reference simply doesn't use — so there's no working example to port from, our own or Thaoky's.

Guessing at those two pieces' field/function names — unlike Reputations' `C_Reputation` or Item Info's `C_Item`/`C_Spell`, which are long-stable, well-known shapes — risks writing code that reports `"ok"`/`"fallback"` in apicheck (implying success) while silently storing wrong or missing `resultItemID`/reagent data. That's worse than today's honest, existence-guarded no-op. Also relevant: `relativeDifficulty` is an enum (`Enum.TradeskillRelativeDifficulty` or similar) and its exact value-to-color mapping against this codebase's `SkillTypeToColor` (header/optimal/medium/easy/trivial → 0-4) isn't confirmed either.

**Decision:** defer, same rationale as Talents. Recipe presence/category/cooldown scanning via `C_TradeSkillUI` is implementable with reasonable confidence whenever this is revisited, but `resultItemID` and reagents need either live Forever verification (`/dump C_TradeSkillUI.GetRecipeOutputItemData` and friends) or a newer Thaoky/community reference that actually implements the retail reagent path, neither of which exists yet. Tracked as the one remaining open area from the original six.

## Third crash: `ADDON_ACTION_FORBIDDEN` registering `COMBAT_LOG_EVENT_UNFILTERED` (2026-09-17)

A third crash report, different in kind from the first two (`TRADE_SKILL_UPDATE`/`CRAFT_SHOW`, both "unknown event" hard errors):

```
[ADDON_ACTION_FORBIDDEN] AddOn 'AltArmy_TBC' tried to call the protected function 'UNKNOWN()'.
...
[C]: in function 'pcall'
[AltArmy_TBC/Data/DataStore/DataStore.lua]:198: in function 'SafeRegisterEvent'
[AltArmy_TBC/Data/DataStore/DataStore.lua]:239: in main chunk
```

`COMBAT_LOG_EVENT_UNFILTERED` passes `C_EventUtils.IsEventValid()` (it's a real, recognized event on Forever, unlike the first two crashes), so `SafeRegisterEvent`'s existence-check guard doesn't apply here — the client accepts the event name but treats the registration itself as a protected action. The existing `pcall` around `frame:RegisterEvent` prevents this from becoming a hard error (the addon doesn't crash), but `pcall` does not suppress the `ADDON_ACTION_FORBIDDEN` notification itself — that report is generated by the client's security layer independently of whether the call was wrapped in `pcall`, so BugGrabber still captures and surfaces it as visible noise to players even though nothing actually broke.

**Fix applied:** rather than chase the forbidden-registration behavior itself, skip registering `COMBAT_LOG_EVENT_UNFILTERED` entirely on any client where `CombatLogGetCurrentEventInfo` doesn't exist:

```lua
if CombatLogGetCurrentEventInfo then
    SafeRegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end
```

This is well-grounded, not a guess: the `/altarmy debug apicheck` results already logged above (under "Unit Info | 1/14") confirm `CombatLogGetCurrentEventInfo` is missing on Forever, and the event's `OnEvent` handler in `DataStore.lua` (level-history-from-combat-log, transmute/sphere cooldown tracking) already starts with `if not CombatLogGetCurrentEventInfo or not UnitGUID then return end` — so on Forever the handler was already a guaranteed no-op even when the registration succeeded. Registering an event whose only handler can never do anything without that API serves no purpose except generating this warning; skipping it is a pure removal of dead-end noise, zero behavior change on TBC Classic (where `CombatLogGetCurrentEventInfo` exists and registration proceeds exactly as before). Same "existence check over version check" convention as the rest of this doc. `npm run check` and all 2317 tests pass.

**Not addressed by this fix:** the underlying feature (combat-log-driven level history and transmute/sphere cooldown detection) is still dead on Forever, same as the Professions/Crafting/Talents areas deferred above — `CombatLogGetCurrentEventInfo` has no confirmed `C_*` replacement identified yet. If one surfaces, it belongs in the same "missing-API areas" roadmap as a new tracked row, not folded into this crash fix.

## Fourth issue: minimap icon position not saved (`math.atan2` missing) (2026-09-17)

A user reported that on Forever, the minimap icon (LibDBIcon-1.0, `AltArmy_TBC/UI/Minimap.lua`) always resets to the top of the minimap on login, no matter where it was last dragged — never a crash, just silently-lost position.

Root cause: [`LibDBIcon-1.0.lua`](../AltArmy_TBC/Libs/LibDBIcon-1.0/LibDBIcon-1.0.lua)'s drag handler computes the button's angle every `OnUpdate` frame via `math.atan2(py - my, px - mx)`, then writes that angle to `self.db.minimapPos` (the same table as `AltArmyTBC_Options.minimap`, via [`MinimapSavedVars.lua`](../AltArmy_TBC/UI/MinimapSavedVars.lua)). `math.atan2` is a legacy two-arg-return Lua 5.1 math function; Blizzard's client Lua sandbox has dropped it on the retail-like API surface in favor of the single-function two-argument `math.atan(y, x)` form (Lua 5.3+ style) — consistent with this doc's other findings that Forever's client strips pre-`C_*`/legacy globals the same way retail eventually did. With `atan2` nil, every drag-frame update errors before `self.db.minimapPos` is ever assigned, so the saved position never changes from its default (`90`, i.e. top) and the button appears to "always start at the top" after every reload/login.

**Fix applied:** one-line existence-checked fallback in the vendored library, `local deg, atan2 = math.deg, math.atan2 or math.atan` — same "existence check over version check" convention as the rest of this doc, applied directly to the vendored `Libs/` copy since there's no newer upstream LibDBIcon-1.0 release bundled here to pull from. Zero behavior change on TBC Classic (`math.atan2` still exists there, so `or math.atan` is never reached). `npm run check` passes; `Libs/` is excluded from luacheck so no `globals` annotation was needed.

**Unverified:** whether Forever's `math.atan(y, x)` two-argument form returns the same value as the dropped `math.atan2(y, x)` (they're meant to be equivalent) hasn't been confirmed against a live Forever client — flagged with the same epistemic caveat as the rest of this document until someone can drag the icon in-game and reload to confirm the position sticks.

## Fifth: vendored LibDBIcon-1.0 bumped to upstream minor 56, Forever routed into the mainline sizing branch (2026-09-17)

Bumped the vendored [`LibDBIcon-1.0.lua`](../AltArmy_TBC/Libs/LibDBIcon-1.0/LibDBIcon-1.0.lua) from minor 43 to the current WowAce trunk (`svn revision 162`, minor 56), pulled directly via `curl https://repos.wowace.com/wow/libdbicon-1-0/trunk/LibDBIcon-1.0/LibDBIcon-1.0.lua` and diffed byte-for-byte against the working copy to confirm an exact, unmodified vendor drop. Notable differences from minor 43: Addon Compartment API support (`AddonCompartmentFrame`, guarded by existence checks — inert on TBC/Forever, neither of which has it), `SetFixedFrameStrata`/`SetFixedFrameLevel` calls added to `createButton` (generic Frame widget methods, not game-content API, so expected to exist on every client build), and three `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE` branches (border/background/icon size+anchor) that didn't exist in 43 at all — TBC Classic previously only ever got the one (classic-family) sizing because 43 predates the mainline/classic split entirely. `npm run check` and all 2317 tests pass unchanged against the new vendor drop.

**Experiment, not a confirmed fix:** added a local-only patch (clearly commented in the vendored file, since a future re-vendor will silently drop it) redirecting Forever through the same branch retail takes: `local isMainlineLike = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE) or (select(4, GetBuildInfo()) == 16001)`, used in place of the bare `WOW_PROJECT_ID` check at all three call sites. Uses the confirmed Interface number (16001, from the "Confirmed: Interface number" section above) rather than `WOW_PROJECT_ID`, since Forever's own project ID is still unconfirmed. This only affects the minimap button's own border/background/icon texture sizing and anchor points — it does not touch the drag/position-save code path at all, so it's unrelated to the `math.atan2` fix in the section directly above.

**Important — this vendor swap reset the `math.atan2` fix.** The "no changes" vendor copy is upstream's file exactly as published, which still has the unconditional `math.atan2` (no fallback) documented as broken on Forever above. The one-line `math.atan2 or math.atan` fallback from the previous section is **not present** in the current working tree — it was on top of the old minor-43 file, and copying minor 56 verbatim didn't carry it forward. The minimap-position-not-saving bug is back until that fallback (or equivalent) is reapplied on top of this minor-56 base; this section's mainline-branch experiment only changes button cosmetics and doesn't fix it. Re-applying the fallback is a follow-up, not done as part of this change since the ask was to test the mainline-branch redirect in isolation.

**Experiment result: negative, reverted (2026-09-17).** The mainline-branch redirect (`isMainlineLike`) did not fix the minimap-position-not-saving symptom — expected, per the analysis above, since it only touches button border/background/icon sizing, not the drag/position-save path. Reverted `isMainlineLike` and its three call sites back to the plain upstream `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE` check (Forever falls through to the classic-family sizing, same as TBC), so the vendored file carries no unexplained local deviation in that area. Reapplied the actual fix from the section above — `local deg, atan2 = math.deg, math.atan2 or math.atan` — on top of the minor-56 base. Diffed against the pristine upstream download to confirm that one line is the *only* remaining difference from stock minor 56. `npm run check` (0 warnings/errors, 95 files) and all 2317 tests pass. This is the current, final state: vendored LibDBIcon-1.0 at minor 56 plus the single-line Forever `atan2` compat fix, no other local patches.

**Second experiment result: also negative (2026-09-17).** In-game testing on Forever reported the `math.atan2 or math.atan` fallback did **not** fix the minimap-position-not-saving symptom either. This means the `math.atan2`-removal theory above, despite being well-grounded circumstantially (matches this doc's other findings about Forever dropping legacy globals, and is a documented real-world issue on other clients), is **not actually the root cause here** — or at least not the whole story. Since `math.atan(y, x)` is meant to be numerically equivalent to the dropped `math.atan2(y, x)`, if `atan2` being nil were the only problem, the fallback should have fixed it; it didn't, so either `atan2` isn't actually nil on Forever (the position-loss has some other cause entirely — e.g. `AltArmyTBC_Options.minimap` not persisting/loading correctly, `Minimap:GetCenter()`/`GetCursorPosition()`/`GetEffectiveScale()` behaving unexpectedly, or the drag `OnUpdate` never actually running on Forever's client), or `math.atan` itself errors/misbehaves there too. Neither has been isolated yet — this needs actual in-game diagnostics (e.g. a `/dump math.atan2`, `/dump math.atan`, and confirming `OnDragStart`/`onUpdate` actually fire) rather than more speculative fixes from this doc's collaborator.

**Decision: reverted, deferred.** Per explicit instruction, reverted the vendored [`LibDBIcon-1.0.lua`](../AltArmy_TBC/Libs/LibDBIcon-1.0/LibDBIcon-1.0.lua) to an exact, unmodified copy of upstream minor 56 (diffed byte-for-byte against the pristine download to confirm zero local patches remain — not even the `atan2` fallback). `npm run check` and all 2317 tests pass against the plain vendor file. **The minimap-position-not-saving bug on Forever is unresolved and left for a future session** — both hypotheses tried here (mainline-branch redirect, `atan2` fallback) are now known-wrong/insufficient, so the next attempt should start from in-game diagnostics on Forever itself rather than another theory ported from this doc's other findings.

## Sources

- [Multi-TOC for World of Warcraft Addons — CurseForge support](https://support.curseforge.com/support/solutions/articles/9000209856-multi-toc-for-world-of-warcraft-addons)
- [TOC format — Warcraft Wiki](https://warcraft.wiki.gg/wiki/TOC_format)
- [WOW_PROJECT_ID — Warcraft Wiki](https://warcraft.wiki.gg/wiki/WOW_PROJECT_ID)
- [BigWigsMods/packager README](https://github.com/BigWigsMods/packager/blob/master/README.md)
- [WeakAuras2 repository](https://github.com/WeakAuras/WeakAuras2)
- [ElvUI: TBC, Cataclysm, and Mists Classic — DeepWiki](https://deepwiki.com/tukui-org/ElvUI/4.4-tbc-cataclysm-and-mists-classic)
- [Porting addons to Classic — Wowpedia](https://wowpedia.fandom.com/wiki/Porting_addons_to_Classic)
- [Blizzard Announces World of Warcraft: Forever — Game Informer](https://gameinformer.com/blizzcon-2026/2026/09/12/blizzard-announces-world-of-warcraft-forever-expanding-vanilla-wow-with)
- [World of Warcraft: Forever — Wikipedia](https://en.wikipedia.org/wiki/World_of_Warcraft:_Forever)
- [World of Warcraft at BlizzCon 2026: Discover What's Next — Blizzard News](https://news.blizzard.com/en-us/article/24301145/world-of-warcraft-at-blizzcon-2026-discover-whats-next)
- [Addons for WoW: Forever — What Is Known So Far — PEWPEWSHOP](https://pewpewshop.pro/wow-boost/blog~addons-for-wow-forever-what-is-known-so-far)
- [Beta build: one package that loads on Forever, outside the stores — danielcosta42/guildos#11](https://github.com/danielcosta42/guildos/issues/11) (unofficial interface-number guess: 16000/16001, unconfirmed)
- [Track WoW: Forever (Classic+) beta + Nov 4 launch — addon port assessment — nazumods/wow#942](https://github.com/nazumods/wow/issues/942)
- [`Gethe/wow-ui-source`](https://github.com/Gethe/wow-ui-source) — mirror to watch for a Forever branch once the beta client exists
- [AtlasLoot Classic Forever — CurseForge](https://www.curseforge.com/wow/addons/atlasloot-forever) (author: Sliccer; fork of AtlasLootClassic; no public source repo found)
- [RPGLootFeed PR #617 — toc: add wow forever beta interface version 16001](https://github.com/McTalian-WoW-Addons/RPGLootFeed/pull/617) (merged 2026-09-17; actual source diff confirming Interface 16001)
- [Thaoky/DataStore_Crafts — DataStore_Crafts_Retail.lua](https://github.com/Thaoky/DataStore_Crafts/blob/master/DataStore_Crafts/DataStore_Crafts_Retail.lua) — real source showing `TRADE_SKILL_UPDATE` gated `if not isRetail`, and the `C_TradeSkillUI`-based retail replacement scan
- [Thaoky/DataStore_Crafts — DataStore_Crafts_NonRetail.lua](https://github.com/Thaoky/DataStore_Crafts/blob/master/DataStore_Crafts/DataStore_Crafts_NonRetail.lua) — the Classic-family (TBC/Wrath/Cata) counterpart, still index-based `GetNumTradeSkills`/`GetTradeSkillInfo`
- [Thaoky/AddonFactory — Core/Addon.lua](https://github.com/Thaoky/AddonFactory/blob/master/AddonFactory/Core/Addon.lua) — `addon:ListenToEvent()`, the source of the `C_EventUtils.IsEventValid()` guard pattern all `DataStore_*` addons rely on
- [C_EventUtils.IsEventValid — Warcraft Wiki](https://warcraft.wiki.gg/wiki/API_C_EventUtils.IsEventValid)
- [Thaoky/DataStore_Reputations](https://github.com/Thaoky/DataStore_Reputations) — `isRetail`/`API_*`-wrapper pattern for `C_Reputation`, including the `IsMajorFaction`/`GetFactionParagonInfo` retail-only extras
- [Thaoky/DataStore_Auctions](https://github.com/Thaoky/DataStore_Auctions) — `C_AuctionHouse.GetNumOwnedAuctions`/`GetOwnedAuctionInfo`/`GetNumBids`/`GetBidInfo`, gated on `type(C_AuctionHouse) == "table"`
- [Thaoky/DataStore_Talents](https://github.com/Thaoky/DataStore_Talents) — mid-rewrite as of 2026-08-16; not a clean reference for the talent-API replacement yet
- [Thaoky/DataStore_Spells](https://github.com/Thaoky/DataStore_Spells) — `C_Spell.GetSpellName`/`GetSpellInfo` existence-fallback pattern (`GetSpellInfo or C_Spell.GetSpellName`)
- [Thaoky/DataStore_Containers](https://github.com/Thaoky/DataStore_Containers) — confirms real retail still calls the plain `GetItemInfo` global unguarded, the basis for this doc's "verify in Forever before trusting the `C_Item` port" caution
- [Thaoky/Altoholic_Forever](https://github.com/Thaoky/Altoholic_Forever) — checked as a possible ready-made reference; empty scaffold only (README + CI workflow, created 2026-09-13)
