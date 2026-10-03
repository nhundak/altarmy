import type { CharacterGroup, Coverage, Selection } from '../api/client'

// Realms may contain spaces but never tabs (WoW realm names have none).
export const toKey = (s: Selection) => `${s.realm}\t${s.faction}`
export const fromKey = (key: string): Selection => {
  const [realm = '', faction = ''] = key.split('\t')
  return { realm, faction }
}

/** "Realm (Faction)", or "Realm (both factions)" for an auction house the factions share. */
export const realmLabel = ({ realm, faction }: Selection) => `${realm} (${faction || 'both factions'})`

export type RealmOption = { value: string; label: string; section: 'Your characters' | 'Browse a realm' }

/**
 * What the realm picker offers: the realm/factions with characters, then every other auction house with prices
 * (to browse without characters). A group's own auction house is its faction's, else its realm's shared one, so
 * that one is not offered twice.
 */
export function realmOptions(groups: readonly CharacterGroup[], coverage: readonly Coverage[]): RealmOption[] {
  const houses = new Set(coverage.map(toKey))
  const covered = new Set(
    groups.map((g) => (houses.has(toKey(g)) ? toKey(g) : toKey({ realm: g.realm, faction: '' }))),
  )
  return [
    ...groups.map((g) => ({
      value: toKey(g),
      label: `${realmLabel(g)} · ${g.characters.length} ${g.characters.length === 1 ? 'character' : 'characters'}`,
      section: 'Your characters' as const,
    })),
    ...coverage
      .filter((c) => c.prices > 0 && !covered.has(toKey(c)))
      .map((c) => ({ value: toKey(c), label: realmLabel(c), section: 'Browse a realm' as const })),
  ]
}
