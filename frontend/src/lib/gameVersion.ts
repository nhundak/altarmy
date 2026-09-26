import type { GameVersion } from '../api/client'

/** The one game the site serves. The API also serves TBC Anniversary (the CLI uses it); the front end does not. */
export const GAME_VERSION: GameVersion = 'forever'
export const GAME_VERSION_LABEL = 'WoW: Forever'
/** The WoW install's folder holding this game's SavedVariables. */
export const GAME_FLAVOR = '_classic_beta_'
