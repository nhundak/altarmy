# Guildmates' recipes from profession links

Status: built 2026-10-04 (`AltArmy_TBC/Data/Guild/GuildLinkRead.lua` on the reader in
`Data/DataStore/OwnRecipeRead.lua`; the design is in `AltArmy_TBC/Data/DESIGN.md`, "Guildmates' recipes
read by link"). The in-game checks at the end are still to run.

## The technique

A hidden tooltip's `SetHyperlink("trade:<player GUID>:<profession spell>:<skill line>")`, called from
a timer with no click, makes the client fetch that player's profession from the server. The client
then opens it as a linked profession window. While the window is concealed, `C_TradeSkillUI`
(`GetBaseProfessionInfo`, `GetAllRecipeIDs`, `GetRecipeInfo`) returns that player's recipes and skill.

Linked Inn (github.com/sanredz/Linked-Inn, `Reader.lua`, `Clues.lua`, `Data.lua`) does this for
every player it sees. Its findings:

- The server answers only while the player is **online** and on **your own backend server**.
  Linked Inn's `OtherServer` compares the server number in the GUID. A timeout means offline.
- Build links with each profession's **Apprentice** rank spell (e.g. Tailoring 3908 / skill line
  197). The server then answers players of every rank.
- Pace reads 1-2 s apart, one at a time, and pause after a run of timeouts.
- Check `IsTradeSkillLinked()`'s name against the player you asked for, because other addons and
  chat clicks open linked windows too.

## What was built

1. **Guildmates without Alt Army.** The guild roster (`GetGuildRosterInfo`; the GUID is its 17th
   return, the online flag its 9th) gives every member's GUID. Any member who is online is read,
   whether or not they run the addon: each linkable skill line is tried with its Apprentice spell,
   Cooking and First Aid first (nearly everyone has them; when both go unanswered the member is
   unreachable for a while), and lines that never answer back off for days. A member is read again
   after three days or when their roster level moved.
2. **Guildmates with Alt Army.** Those who share get their recipes by the guild share messages as
   before (`P`/`PR`, `CQ`/`CC`, `RQ`/`RC`) and are never read by link. A guildmate whose addon shares
   nothing (sharing off: an empty presence) is read by link like someone without the addon. No wire
   change, no version bump. (A first version read sharing users' logged-in characters by link instead
   of `RQ`; dropped 2026-10-04 in favour of the messages.)
3. **Where it shows.** The results go into `AltArmyTBC_GuildData` in the shape the Guild tab and
   Search already read, with no label saying how they were read. Search shows guildmates' recipes
   whether or not the player shares their own.

## Decisions taken

- Reads are not gated by the sharing opt-in or any other option; the opt-in covers what the player
  sends about their own characters (grouping, main, display name). The one engine switch, "Read
  recipes in the background" (Options > General > Advanced), stops own and guild reads alike.
- No read attempts to silence Blizzard's profession window: it is concealed and closed. Its sound
  may play.
- Every read is logged through the "Guild sharing traffic (verbose)" debug flag (`LINK …` lines).
- Linked data is stored as recipe ids, rank and max rank only: difficulty colours are relative to the
  linked player, and cooldowns and reagents aren't theirs to read.
- Forever only. TBC Anniversary has no `C_TradeSkillUI`; its 2.x-style trade links carried the
  recipe bitmask inside the link and would need separate research.

## Still to check in game

See `docs/WOW_FOREVER_COMPATIBILITY_RESEARCH.md`, "Eighth", the 2026-10-04 update: whether the
server answers a link for a guildmate who never linked anything (and the Apprentice spell at any
rank), whether the roster's GUIDs are readable (not Secret Values), the linked window's name shape,
and whether the retail guild profession roster exists on Forever (`/altarmy debug apicheck`), which
would replace probing. Each is a constant (`R.APPRENTICE_SPELLS`, `R.REQUIRE_LINKED_NAME`,
`R._NamesMatch`) or a dev dump (`guildRosterGuid`) to adjust.
