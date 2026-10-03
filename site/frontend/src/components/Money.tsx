import { Fragment } from 'react'
import { splitMoney } from '../lib/wow'
import classes from './Money.module.css'

/** Silver and copper after a larger coin padded to two characters with a non-breaking space, so coins line up
 * in a column; the leading coin is never padded. */
const pad = (amount: number, leading: boolean) => (!leading && amount < 10 ? `\u00a0${amount}` : String(amount))

/** Integer copper as in-game coins (amounts with gold, silver and copper icons). `signed` adds a `+` to gains;
 * a `cost` (money spent, positive) shows in red with no sign; `padded` lines amounts up in a table column. */
export function Money({
  copper,
  signed = false,
  cost = false,
  padded = false,
}: {
  copper: number
  signed?: boolean
  cost?: boolean
  padded?: boolean
}) {
  const sign = cost ? '' : copper < 0 ? '-' : signed && copper > 0 ? '+' : ''
  return (
    <span className={classes.coins} data-cost={cost || undefined}>
      {sign}
      {splitMoney(Math.abs(copper)).map(({ unit, amount }, i) => (
        <Fragment key={unit}>
          {i > 0 && ' '}
          <span className={classes.coin} data-unit={unit} title={unit}>
            {padded ? pad(amount, i === 0) : amount}
          </span>
        </Fragment>
      ))}
    </span>
  )
}
