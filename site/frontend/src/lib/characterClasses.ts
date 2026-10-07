import { createContext } from 'react'

/** Character name -> class file (e.g. PALADIN), for colouring names wherever results mention them. */
export const CharacterClasses = createContext<Readonly<Record<string, string>>>({})
