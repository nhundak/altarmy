import { useCharacters } from '../api/queries'
import type { CharacterGroup } from '../api/client'
import { BARTERING, BARTERING_PERCENT, BARTERING_RANKS } from '../lib/talents'
import { CharacterName } from './CharacterName'
import { TooltipFrame } from './ItemTooltip'
import classes from './ItemTooltip.module.css'

type Character = CharacterGroup['characters'][number]

/** The character `who` among the uploaded ones: on the selected realm and faction first, else anywhere. */
function useCharacter(who: string): Character | undefined {
  const data = useCharacters().data
  if (!data || !who) return undefined
  const { groups, selection } = data
  const selected = groups.find((g) => g.realm === selection?.realm && g.faction === selection.faction)
  const find = (g: CharacterGroup) => g.characters.find((c) => c.name === who)
  return (selected && find(selected)) ?? groups.map(find).find(Boolean)
}

/**
 * What takes money off `who`'s vendor buys: the factions whose vendors their standing makes cheaper (only when there
 * is one) and their ranks of Bartering. Until their character is known, what the step itself says came off.
 */
export function DiscountTooltip({
  who,
  discount,
  repDiscount,
  repFaction,
}: {
  who: string
  discount: number
  repDiscount: number
  repFaction: string
}) {
  const character = useCharacter(who)
  const reputations = character
    ? character.vendor_discounts
    : repDiscount > 0
      ? [{ faction: repFaction || 'This vendor', percent: repDiscount }]
      : []
  const bartering = character?.talents.find((t) => t.spell_id === BARTERING)
  const ranks = character ? (bartering?.rank ?? 0) : Math.round(discount / BARTERING_PERCENT)
  const maxRanks = bartering?.max_rank ?? BARTERING_RANKS
  return (
    <TooltipFrame icon={null}>
      <div className={classes.title}>
        {who ? (
          <>
            <CharacterName name={who} classFile={character?.class_file || undefined} />
            &apos;s vendor discounts
          </>
        ) : (
          'Vendor discounts'
        )}
      </div>
      {reputations.length > 0 && (
        <div className={classes.section}>
          <div>Reputation</div>
          {reputations.map((r) => (
            <div key={r.faction} className={classes.split}>
              <span>{r.faction} vendors</span>
              <span>−{r.percent}%</span>
            </div>
          ))}
        </div>
      )}
      <div className={`${classes.section} ${classes.split}`}>
        <span>
          Bartering {ranks}/{maxRanks}
        </span>
        <span className={ranks ? undefined : classes.dim}>{ranks ? `−${ranks * BARTERING_PERCENT}%` : 'none'}</span>
      </div>
    </TooltipFrame>
  )
}
