import { Progress } from '@mantine/core'
import classes from './Skill.module.css'

/** A profession's skill against its current cap: a short bar and the numbers ("112/150"); `aligned`: the numbers
 * take the same width whatever they are, so bars in a column line up. */
export function SkillBar({
  rank,
  maxRank,
  label,
  aligned,
}: {
  rank: number
  maxRank: number
  label?: string
  aligned?: boolean
}) {
  return (
    <span className={classes.bar}>
      <Progress
        className={classes.track}
        size="sm"
        value={maxRank ? Math.min(100, (100 * rank) / maxRank) : 0}
        aria-label={label ? `${label} skill` : 'Skill'}
      />
      <span className={aligned ? classes.numbers : undefined}>
        {rank}/{maxRank}
      </span>
    </span>
  )
}
