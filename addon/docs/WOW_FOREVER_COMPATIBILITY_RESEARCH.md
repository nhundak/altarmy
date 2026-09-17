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
| Item Info / Spell Info | Cross-cutting, ~20 files (`Data/Gear/ItemStats.lua`, `ItemUsability.lua`, `GearScore.lua`, `GearUpgrade*.lua`, `GearCompare.lua`, `DataStoreProfessions.lua`, `Data/Search/*`, `GuildTabData.lua`, several `Tabs/*`/`UI/*`) | No dedicated Thaoky module — same ad-hoc inline lookups we already use, seen in `DataStore_Containers.lua`/`DataStore_Spells.lua` | `C_Item.GetItemInfo`/`GetItemInfoInstant`/`GetItemStats`, `C_Spell.GetSpellName`/`GetSpellInfo`(table return)/`GetSpellLink` | Highest fan-out; mechanical once call shapes are confirmed — plan is a small number of shared compat helpers, not 20 inline patches | **Partial** — compat layer + `DataStore/` layer done, ~15 UI files still open |
| Professions + Crafting | `Data/DataStore/DataStoreProfessions.lua` (`ScanProfessionLinks`, `ScanRecipes`, `ScanCraftRecipes`, reagent-capture helpers) — recipes already recipeID-keyed | `DataStore_Crafts/DataStore_Crafts_Retail.lua` — full rewrite, recipeID-native, already cited above in this doc | `C_TradeSkillUI.GetAllRecipeIDs`, `GetRecipeInfo`, `GetCategories`/`GetCategoryInfo`, `GetRecipeCooldown`, `GetBaseProfessionInfo` | Largest, but best-scouted — this doc already named the target APIs before this pass | **Deferred** (documented decision — `resultItemID`/reagents unresolved) |
| Auctions | `Data/DataStore/DataStoreAuctions.lua` (`ScanAuctions`, `ScanBids`) — synchronous index loop | `DataStore_Auctions/DataStore_Auctions.lua` — `isRetail = type(C_AuctionHouse) == "table"`, `API_*` wrappers | `C_AuctionHouse.GetNumOwnedAuctions`, `GetOwnedAuctionInfo`, `GetNumBids`, `GetBidInfo` | Turned out lower-risk than expected — see below, still synchronous | **Done** |

**Planned order:** Reputations → Talents → Item Info/Spell Info → Professions/Crafting → Auctions (roughly lowest-risk/clearest-template first, most invasive/lowest-traffic last). Each will be its own scoped follow-up: read the relevant Thaoky file in full (not just grep hits), add existence-checked `C_*` candidates to the matching `DataStore/` module and to `Data/ApiCheck.lua`'s `MANIFEST`, bump `Data/DATA_VERSIONS.md` only if the stored shape actually changes, and run `npm run check`. (Executed in a different order than listed — Auctions before the Item Info UI-layer sweep and before Professions/Crafting — once the Auctions Thaoky reference turned out simpler than Professions/Crafting's; the roadmap's ordering rationale still holds, just re-prioritized by actual grounding once each was read in full.)

**Caution carried into that follow-up work:** Thaoky's actively-maintained retail `DataStore_Containers.lua` still calls the plain global `GetItemInfo` directly, unguarded — real retail hasn't dropped that global. Forever reporting it fully `missing` in apicheck may be a Forever-beta-specific quirk rather than proof retail's `C_Item` namespace is the only path forward; worth a direct `/dump GetItemInfo` / `/dump C_Item and C_Item.GetItemInfo` check in Forever itself before committing to the `C_Item` design, not just inferring it from Thaoky's retail code.

Also checked `Altoholic_Forever` (a repo with that exact name under Thaoky's account) as a possible ready-made Forever reference — it's an empty scaffold (README + CI workflow only, created 2026-09-13), no source yet. Worth re-checking later, not usable now.

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

## Phase B progress: Auctions implemented, Professions/Crafting deferred by design (2026-09-17)

**Auctions — implemented,** and the roadmap's own risk rating above turned out too pessimistic. Fetched the complete [`DataStore_Auctions/DataStore_Auctions.lua`](https://github.com/Thaoky/DataStore_Auctions) (not just grep hits this time) and it shows `C_AuctionHouse.GetNumOwnedAuctions`/`GetOwnedAuctionInfo`/`GetNumBids`/`GetBidInfo` are **synchronous reads of client-cached data**, not an async query API — the client pushes `OWNED_AUCTIONS_UPDATED`/`BIDS_UPDATED`/`AUCTION_HOUSE_AUCTION_CREATED` events and the scan is still a plain `for i = 1, numAuctions do ... end` loop, same shape as the legacy `GetNumAuctionItems`/`GetAuctionItemInfo` pair. No async rewrite needed after all, and no `DATA_VERSIONS.md` bump — the stored `char.Auctions[]`/`char.Bids[]` shape is unchanged.

[`DataStoreAuctions.lua`](../AltArmy_TBC/Data/DataStore/DataStoreAuctions.lua) now has `API_GetOwnedAuctionInfo`/`API_GetBidAuctionInfo` wrapper functions (legacy first, `C_AuctionHouse` fallback, exact field mapping ported from Thaoky's working retail code — `info.itemKey.itemID`, `info.quantity`, `info.bidAmount`, `info.buyoutAmount`, `info.timeLeftSeconds` for owned auctions; `info.timeLeft` and `info.bidder` for bids) and two new existence checks, `DS.HasOwnedAuctionsApi()`/`DS.HasBidAuctionsApi()`, used both internally and by `DataStore.lua`'s dispatch (which now also registers/handles `OWNED_AUCTIONS_UPDATED`, `AUCTION_HOUSE_AUCTION_CREATED`, `BIDS_UPDATED` alongside the legacy `AUCTION_OWNED_LIST_UPDATE`/`AUCTION_BIDDER_LIST_UPDATE`). `Data/ApiCheck.lua` gained matching `C_AuctionHouse.*` candidates, including two new manifest rows (`GetNumBids`/`GetBidInfo`) since the legacy side collapses both onto one `GetNumAuctionItems`/`GetAuctionItemInfo` pair but the `C_AuctionHouse` side doesn't. Covered by new `ScanAuctions`/`ScanBids` tests in [`DataStoreAuctions_spec.lua`](../spec/Data/DataStoreAuctions_spec.lua) exercising both the legacy and `C_AuctionHouse` paths (including the sold-row skip). All 2317 tests and `npm run check` pass.

One inherited Blizzard-side quirk, ported as-is rather than "fixed": owned-auction rows get `timeLeftSeconds` (real seconds) from `C_AuctionHouse.GetOwnedAuctionInfo`, but bid rows get `timeLeft` (a coarse 1-4 short/medium/long/verylong band) from `C_AuctionHouse.GetBidInfo` — the same unit mismatch the legacy `GetAuctionItemTimeLeft` API already has (it's also a 1-4 band). Thaoky's code doesn't normalize this, so neither does ours; documented in the code as a known quirk, not treated as a bug.

**Professions + Crafting — deliberately not implemented this pass.** Fetched the complete [`DataStore_Crafts_Retail.lua`](https://github.com/Thaoky/DataStore_Crafts) (1018 lines) to ground this properly rather than guess from the function names already cited in this doc. What it confirms: `C_TradeSkillUI.GetAllRecipeIDs()` + `GetRecipeInfo(recipeID)` (fields `.categoryID`, `.name`, `.learned`, `.relativeDifficulty`) + `GetCategories()`/`GetCategoryInfo(id)` (fields `.categoryID`, `.name`, `.skillLineCurrentLevel`, `.skillLineMaxLevel`) + `GetRecipeCooldown(recipeID)` are real and well-grounded for recipe **presence, category, learned-state, and cooldown**. But two things this codebase's `ScanRecipes()` actually needs aren't answered by that file:
- **`resultItemID`** (the crafted item, stored per recipe today) — Thaoky's retail scan doesn't extract this at all; the function to get it (something like `GetRecipeOutputItemData`/`GetRecipeOutputItemID`, if it even matches that name) isn't demonstrated anywhere in the reference.
- **Reagents** (`CaptureTradeSkillReagentsForIndex`'s job) — Thaoky's retail path **doesn't scan reagents either**; only the non-retail branch in the same file does (via the legacy `GetTradeSkillNumReagents`/`GetTradeSkillReagentInfo`). Modern retail reagent data lives in a schematic-shaped API (`C_TradeSkillUI.GetRecipeSchematic`, reagent slots/reagent lists) that this reference simply doesn't use — so there's no working example to port from, our own or Thaoky's.

Guessing at those two pieces' field/function names — unlike Reputations' `C_Reputation` or Item Info's `C_Item`/`C_Spell`, which are long-stable, well-known shapes — risks writing code that reports `"ok"`/`"fallback"` in apicheck (implying success) while silently storing wrong or missing `resultItemID`/reagent data. That's worse than today's honest, existence-guarded no-op. Also relevant: `relativeDifficulty` is an enum (`Enum.TradeskillRelativeDifficulty` or similar) and its exact value-to-color mapping against this codebase's `SkillTypeToColor` (header/optimal/medium/easy/trivial → 0-4) isn't confirmed either.

**Decision:** defer, same rationale as Talents. Recipe presence/category/cooldown scanning via `C_TradeSkillUI` is implementable with reasonable confidence whenever this is revisited, but `resultItemID` and reagents need either live Forever verification (`/dump C_TradeSkillUI.GetRecipeOutputItemData` and friends) or a newer Thaoky/community reference that actually implements the retail reagent path, neither of which exists yet. Tracked as the one remaining open area from the original six.

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
