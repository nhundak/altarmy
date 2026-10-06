import { useState } from 'react'
import { useLocalStorage } from '@mantine/hooks'
import type { z } from 'zod'

/** Parse a stored JSON string with `schema`; anything missing, unparsable or invalid gives `fallback`. */
export function parseStored<T>(schema: z.ZodType<T>, raw: string | undefined, fallback: T): T {
  if (raw === undefined) return fallback
  try {
    const parsed = schema.safeParse(JSON.parse(raw))
    return parsed.success ? parsed.data : fallback
  } catch {
    return fallback
  }
}

/** The raw stored string under `key`, or undefined when it is unset or storage is blocked. */
function readRaw(key: string): string | undefined {
  try {
    return localStorage.getItem(key) ?? undefined
  } catch {
    return undefined
  }
}

/** Whether anything is stored under `key` (false when storage is blocked). */
export const isStored = (key: string): boolean => readRaw(key) !== undefined

/** Store `value` as JSON under `key` (nothing when storage is blocked), for a `useStoredState` mounted later. */
export function writeStored(key: string, value: unknown) {
  try {
    localStorage.setItem(key, JSON.stringify(value))
  } catch {
    // blocked storage: the value is simply not remembered
  }
}

/**
 * `useState` that persists to localStorage under `key`, validated by `schema` on read.
 * `defaultValue` must be referentially stable (a module constant or primitive). While `key` is unset, a valid value
 * under `legacyKey` (where the setting used to be kept) is the default; the legacy key itself is never written.
 */
export function useStoredState<T>(key: string, schema: z.ZodType<T>, defaultValue: T, legacyKey?: string) {
  // Read once, so the default stays the same object for as long as the component lives.
  const [initial] = useState(() =>
    legacyKey === undefined ? defaultValue : parseStored(schema, readRaw(legacyKey), defaultValue),
  )
  return useLocalStorage<T>({
    key,
    defaultValue: initial,
    getInitialValueInEffect: false,
    deserialize: (raw) => parseStored(schema, raw, initial),
  })
}
