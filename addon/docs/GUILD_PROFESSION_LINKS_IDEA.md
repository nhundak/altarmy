# Idea: read guildmates' recipes from profession links

Status: idea, not started (noted 2026-10-04). Depends on the background own-recipe read
(`Data/DataStore/OwnRecipeRead.lua`), which proved the technique on WoW: Forever.

## The technique

A hidden tooltip's `SetHyperlink("trade:<player GUID>:<profession spell>:<skill line>")`, called from
a timer with no click, makes the client fetch that player's profession from the server. The client
then opens it as a linked profession window. While the window is hidden and Blizzard's frame is
silenced, `C_TradeSkillUI` (`GetBaseProfessionInfo`, `GetAllRecipeIDs`, `GetRecipeInfo`) returns
that player's recipes and skill.

Linked Inn (github.com/sanredz/Linked-Inn, `Reader.lua`, `Clues.lua`, `Data.lua`) does this for
every player it sees. Its findings:

- The server answers only while the player is **online** and on **your own backend server**.
  Linked Inn's `OtherServer` compares the server number in the GUID. A timeout means offline.
- Build links with each profession's **Apprentice** rank spell (e.g. Tailoring 3908 / skill line
  197). The server then answers players of every rank.
- Pace reads 1-2 s apart, one at a time, and pause after a run of timeouts.
- Check `IsTradeSkillLinked()`'s name against the player you asked for, because other addons and
  chat clicks open linked windows too.

## What it would give us

1. **Guildmates without Alt Army.** The guild roster (`GetGuildRosterInfo`; the GUID and the online
   flag are among its returns) gives every member's GUID. We can read the professions of any
   member who is online, whether or not they run the addon.
   - We don't know which professions a non-user has, so try each primary profession's Apprentice
     link. Stop once two primaries answer, then try Cooking, First Aid and Fishing. A wrong guess
     costs one timeout.
   - Re-read a member only when their data is older than a few days, the way Linked Inn does
     (`STALE`).
2. **A simpler guild share protocol.** Today `GuildShareComm` / `GuildShareProtocol` send presence
   (`P`/`PR`) and then pull recipe lists (`RQ`/`RC`) and profession cards (`CQ`/`CC`) by whisper,
   chunked with AceComm. For any character that is online, a link read gets the same recipes
   straight from the server, with no payload, no checksum and no version skew between clients.
   - The protocol could shrink to presence alone: identity, main and display name, item level,
     and which alts belong together.
   - Recipe transfer would be kept only for the case below.

## Limits to design around

- **Offline alts can't be read.** Today a user shares all their opted-in alts at once, from their
  SavedVariables. A link read sees only the character logged in right now. Options:
  - keep recipe transfer (`RC`/`CC`) for the user's offline alts;
  - or accept that each alt is filled in the first time it is online at the same time as you, and
    cache it with a "read at" date.
- **Privacy and opt-in.** Guild sharing is opt-in and off by default (`GuildShareSettings`). Reading
  a profession by link is something any player can do with a chat link, but we'd be doing it for
  everyone, unasked. Decide whether reads of non-users show in the Guild tab, whether the opt-in
  should still gate who *we* read, and say clearly in the UI where the data came from.
- **Cost.** Every read is a hidden profession window, with the same rules as the own read: not in
  combat, no panel open, and the player's own window never hijacked. A large guild with 50 online
  members and about 3 tries each is around 150 reads. Spread them over minutes, prioritise members
  with no data, and share the read queue with `OwnRecipeRead`.
- **Linked data differs from own data.** Difficulty colours are relative to the linked player's
  skill. Cooldowns and reagent counts aren't meaningful. Store only recipe ids, rank and max rank.
- **Forever only.** TBC Anniversary has no `C_TradeSkillUI`; its 2.x-style trade links carried the
  recipe bitmask inside the link and would need separate research.

## Rough shape if we build it

- Generalise `OwnRecipeRead` into a reader that takes `(guid, professions, onResult)` jobs. Own
  reads get the highest priority; guild reads use the Apprentice spell table.
- Add a `GuildLinkRead` module that walks the online roster, skips other-server GUIDs and fresh
  data, and stores results in `AltArmyTBC_GuildData` with `source = "link"` and `readAt`.
- Have `GuildTabData` / Search merge link-read characters with addon-shared ones by GUID. When both
  exist, prefer the newer.
- Then trim the protocol: stop sending recipes for online characters, and later drop `RQ`/`RC`
  entirely if offline alts are handled by caching.
