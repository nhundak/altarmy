/** What the plan's menus offer (`ChoiceMenu`): another source for a reagent, or another way to sell. */
import type { ReactNode } from 'react'
import type { FlowNode, RankResult } from '../api/client'
import { CharacterName } from './CharacterName'
import type { Choice } from './ChoiceMenu'
import { Earned, Money } from './Money'

export const BUY_FROM: Readonly<Record<string, string>> = { ah: 'on the AH', vendor: 'from a vendor' }

export const SELL_TEXT: Readonly<Record<string, string>> = {
  ah: 'Sell on the AH',
  vendor: 'Sell to a vendor',
  disenchant: 'Disenchant and auction',
  // skilling up: worth nothing, the skill point was the point; only ever offered when nothing else is
  keep: 'Dead loss (no vendor buys it)',
}

/** A source option as a menu line: crafts name the crafter, and say so when they mail it to `holder`. */
function optionLabel({ source, via, crafter, convert }: FlowNode['options'][number], holder: string): ReactNode {
  if (!via) return `Buy ${BUY_FROM[source] ?? source}`
  return (
    <>
      {convert ? 'Convert' : `Craft (${via})`}
      {crafter && (
        <>
          {' '}
          by <CharacterName name={crafter} />
          {crafter !== holder && holder ? ', mailed' : ''}
        </>
      )}
    </>
  )
}

/** The ways to get a reagent, with what each costs; `option` is the key of the one taken. */
export const sourceChoices = (options: FlowNode['options'], option: string, holder: string): Choice[] =>
  options.map((o) => ({
    key: o.key,
    label: optionLabel(o, holder),
    amount: <Money copper={o.cost} cost />,
    current: o.key === option,
  }))

/** The ways to sell the craft, with the profit each makes; `exit` is the one taken. Keeping it is left out
 * unless it is the only way. */
export const sellChoices = (options: RankResult['sell_options'], exit: string): Choice[] =>
  (options.some((o) => o.kind !== 'keep') ? options.filter((o) => o.kind !== 'keep') : options).map((o) => ({
    key: o.kind,
    label: SELL_TEXT[o.kind] ?? `Sell via ${o.kind}`,
    amount: (
      <>
        profit <Earned copper={o.profit} minus />
      </>
    ),
    current: o.kind === exit,
  }))
