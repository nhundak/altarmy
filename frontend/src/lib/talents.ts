/** What a character's Legacy talents did to a step: the API reports the effects, these name them. */

/** A vendor buy's Bartering discount, e.g. "Bartering −10%"; "" without one. */
export function discountNote(discount: number): string {
  return discount > 0 ? `Bartering −${discount}%` : ''
}

/** A sale's expected extra units from Master Chef, e.g. "+0.3 expected from Master Chef"; "" without any. */
export function bonusNote(bonus: number): string {
  return bonus > 0 ? `+${Number(bonus.toFixed(2))} expected from Master Chef` : ''
}
