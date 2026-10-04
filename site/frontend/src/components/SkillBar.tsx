import { Progress } from '@mantine/core'
import classes from './Skill.module.css'

/** A profession's skill against its current cap: a short bar and the numbers ("112/150"). */
export function SkillBar({ rank, maxRank, label }: { rank: number; maxRank: number; label?: string }) {
  return (
    <span className={classes.bar}>
      <Progress
        className={classes.track}
        size="sm"
        value={maxRank ? Math.min(100, (100 * rank) / maxRank) : 0}
        aria-label={label ? `${label} skill` : 'Skill'}
      />
      <span>
        {rank}/{maxRank}
      </span>
    </span>
  )
}
