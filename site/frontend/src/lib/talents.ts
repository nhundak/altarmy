/** What a character's Legacy talents and reputation did to a step: the API reports the effects, these name them. */

/** Working Overtime (WoW: Forever's Legacy talent): a better chance of a skill point from every craft. */
export const WORKING_OVERTIME = 1225451

/**
 * What came off a vendor buy: the buyer's Bartering talent and their standing with the vendor's faction, e.g.
 * "Bartering −10%, Orgrimmar reputation −10%"; "" without either.
 */
export function discountNote(discount: number, repDiscount = 0, repFaction = ''): string {
  const parts = []
  if (discount > 0) parts.push(`Bartering −${discount}%`)
  if (repDiscount > 0) parts.push(`${repFaction ? `${repFaction} reputation` : 'Reputation'} −${repDiscount}%`)
  return parts.join(', ')
}

/** A sale's expected extra units from Master Chef, e.g. "+0.3 expected from Master Chef"; "" without any. */
export function bonusNote(bonus: number): string {
  return bonus > 0 ? `+${Number(bonus.toFixed(2))} expected from Master Chef` : ''
}
