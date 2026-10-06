import { useState } from 'react'
import { iconUrl, professionIcon } from '../lib/wow'
import classes from './ProfessionIcon.module.css'

/** A profession's icon as the game shows it, `size` px square (18 by default); an empty square of the same size where
 * there is none, so names beside it line up. */
export function ProfessionIcon({ profession, size = 18 }: { profession: string; size?: number }) {
  const icon = professionIcon(profession)
  const [failed, setFailed] = useState(false)
  const style = { width: size, height: size }
  return icon && !failed ? (
    <img
      className={classes.icon}
      style={style}
      src={iconUrl(icon, size <= 18 ? 'small' : 'medium')}
      alt=""
      onError={() => setFailed(true)}
    />
  ) : (
    <span className={classes.icon} style={style} />
  )
}
