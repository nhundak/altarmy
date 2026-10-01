import type { Characters, Status } from '../api/client'

/** A status with game data, prices, and Alt Army characters with Classic Beta PvE (Horde) selected. */
export const status = (over: Partial<Status> = {}): Status => ({
  build: '1.60.1.69913',
  items: 3,
  recipes: 1,
  prices: 2,
  characters: 3,
  selection: { realm: 'Classic Beta PvE', faction: 'Horde' },
  auction_house_id: 1,
  data_version: 1,
  price_version: 0,
  ...over,
})

export const characters: Characters = {
  arcane_salvager: false,
  groups: [
    {
      realm: 'Classic Beta PvE',
      faction: 'Horde',
      characters: [
        {
          name: 'Tailor Guy',
          class_file: 'MAGE',
          level: 20,
          professions: [
            { name: 'Cooking', rank: 1, max_rank: 75, recipes: 0 },
            { name: 'Tailoring', rank: 50, max_rank: 75, recipes: 1 },
          ],
          talents: [], vendor_discounts: [],
        },
      ],
    },
    {
      realm: 'Dreamscythe',
      faction: 'Horde',
      characters: [
        { name: 'Frell', class_file: 'WARLOCK', level: 70, professions: [], talents: [], vendor_discounts: [] },
        { name: 'Newbie', class_file: '', level: 0, professions: [], talents: [], vendor_discounts: [] },
      ],
    },
  ],
  selection: { realm: 'Classic Beta PvE', faction: 'Horde' },
}

/** `characters` with an enchanter beside the tailor on Classic Beta PvE (Horde). */
export const withEnchanter: Characters = {
  ...characters,
  groups: characters.groups.map((g, i) =>
    i === 0
      ? {
          ...g,
          characters: [
            ...g.characters,
            {
              name: 'Enchy',
              class_file: 'PRIEST',
              level: 20,
              professions: [{ name: 'Enchanting', rank: 60, max_rank: 75, recipes: 0 }],
              talents: [], vendor_discounts: [],
            },
          ],
        }
      : g,
  ),
}
