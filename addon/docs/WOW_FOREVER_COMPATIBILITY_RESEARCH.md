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

**Still needed:** the specific version `id` for "1.60.1" under `gameVersionTypeID` 88568. Not discoverable by scraping the website (only the type ID is exposed there) — requires the authenticated endpoint, which only the repo owner can call:

```bash
curl -s "https://wow.curseforge.com/api/game/versions" -H "X-Api-Token: $CURSEFORGE_API_TOKEN" \
  | jq '.[] | select(.gameVersionTypeID == 88568)'
```

Once known, add it to `CURSEFORGE_GAME_VERSIONS` alongside `16533` (comma-separated, per `release.yml`'s existing parsing).

Wago's `WAGO_BC_PATCH`-equivalent field for Forever is still unresolved (no documented field name) — not addressed by this change.

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
