# AltArmy TBC

Account-wide alt management for **World of Warcraft: The Burning Crusade Classic**.

AltArmy collects character data while you play and presents it in tabbed dashboards: character summary, gear and reputation grids, profession cooldowns and raid lockouts, item/recipe search, leveling graphs, and optional guild data sharing.

## Docs

- **[docs/README.md](docs/README.md)** — document map (features, architecture, per-tab details)
- **[TESTING.md](TESTING.md)** — unit tests (`npm test`)
- **[LINTING.md](LINTING.md)** — luacheck and Lua 5.1 compile checks (`npm run check`)
- **[AGENTS.md](AGENTS.md)** — conventions for AI agents working in this repo

## Quick start (dev)

```bash
npm run setup:dev   # one-time: local Lua 5.1, busted, luacheck
npm test
npm run check
```

Addon source lives under [`AltArmy_TBC/`](AltArmy_TBC/).
