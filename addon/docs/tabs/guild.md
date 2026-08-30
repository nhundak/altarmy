# Guild tab

Opt-in guild data sharing: browse guildmate characters and recipes grouped by main.

## Visibility

- Tab button appears only when guild sharing is enabled (feature / settings) **and** at least one character on the current realm is in a guild.
- If sharing is off for the player, the tab shows a message with a link to enable sharing options.

## Purpose

See who is playing which alts in the guild, open their shared professions/recipes, and annotate chat so unfamiliar alts show their main name.

## Layout

- Header: guild name / tabard, search for characters or professions.
- Scroll list: one row per main (preferred name, character count, last online); expand for characters (class-colored name, level, primary professions).
- Recipe detail: back + character title, profession tabs, recipe search, sortable recipe list.
- Footer / settings for sharing preferences, notes wizard, pin-style UI prefs.

## Sharing

- Opt-in (`AltArmyTBC_SharingSettings`); defaults off.
- Broadcasts shareable character cards and recipes over guild addon messages (AceComm).
- Received data in `AltArmyTBC_GuildData`.
- Onboarding dialog when appropriate (queued with other onboarding prompts).
- Chat main-name insertion (channels configurable): prefixes messages / online-offline lines with the poster’s group display label when it differs from the sender.

## Search integration

Guildmate recipes can appear in Search (with guild tagging and online/whisper helpers). See [search.md](search.md).

## Data source

`GuildShareSettings`, `GuildShareComm`, `GuildShareData`, `GuildTabData`, `GuildChatMainName`, `GuildManualGroups`, `GuildNoteAltParser`.
