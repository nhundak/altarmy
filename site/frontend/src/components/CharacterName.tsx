import { useContext } from 'react'
import { CharacterClasses } from '../lib/characterClasses'
import classes from './CharacterName.module.css'

/** A character's name in their class colour; `classFile` overrides the `CharacterClasses` lookup. */
export function CharacterName({ name, classFile }: { name: string; classFile?: string }) {
  const known = useContext(CharacterClasses)
  return (
    <span className={classes.name} data-class={classFile ?? known[name]}>
      {name}
    </span>
  )
}
