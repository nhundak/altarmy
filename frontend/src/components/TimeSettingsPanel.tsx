import { useState } from 'react'
import { Alert, Button, Group, Loader, NumberInput, Select, SimpleGrid, Stack, Text } from '@mantine/core'
import { useDebouncedCallback } from '@mantine/hooks'
import type { TimeConfig, TimeSettings } from '../api/client'
import { useSetTime, useTime } from '../api/queries'

type Draft = { city: string | null; config: TimeConfig }
type NumberKey = { [K in keyof TimeConfig]: TimeConfig[K] extends number ? K : never }[keyof TimeConfig]

/** The seconds each action takes, as the "Seconds per action" grid lists them. */
const ACTIONS: readonly { key: NumberKey; label: string; step: number; min?: number; whole?: boolean }[] = [
  { key: 'ah_search', label: 'Search the AH (per item)', step: 1 },
  { key: 'ah_buy', label: 'Buy on the AH (per stack)', step: 0.5 },
  { key: 'ah_post', label: 'Post on the AH (per stack)', step: 0.5 },
  { key: 'vendor_buy', label: 'Buy from a vendor (per stack)', step: 0.5 },
  { key: 'vendor_sell', label: 'Sell to a vendor (per stack)', step: 0.5 },
  { key: 'mail_send', label: 'Send a mail', step: 1 },
  { key: 'mail_attach', label: 'Attach a stack', step: 0.5 },
  { key: 'mail_open', label: 'Open a mail', step: 0.5 },
  { key: 'switch_character', label: 'Switch characters', step: 5 },
  { key: 'craft_overhead', label: 'Extra per craft', step: 0.1 },
  { key: 'run_speed', label: 'Run speed (yards per second)', step: 0.5, min: 0.5 },
]

/** The config's settings that differ from the defaults: what is saved. */
function changes(config: TimeConfig, defaults: TimeConfig): Partial<TimeConfig> {
  return Object.fromEntries(
    Object.entries(config).filter(([key, value]) => value !== defaults[key as keyof TimeConfig]),
  ) as Partial<TimeConfig>
}

function cityOptions(settings: TimeSettings) {
  return [
    { value: '', label: 'Whatever is fastest' },
    ...settings.cities.map((c) => ({ value: c.name, label: c.name })),
  ]
}

/** Where plans are timed and how long each action takes; saved on the server a moment after each change. */
export function TimeSettingsPanel() {
  const time = useTime()
  const setTime = useSetTime()
  const [draft, setDraft] = useState<Draft | null>(null)
  const save = useDebouncedCallback((d: Draft, defaults: TimeConfig) => {
    setTime.mutate({ city: d.city, config: changes(d.config, defaults) })
  }, 600)
  if (time.isPending) return <Loader size="sm" />
  if (time.isError) return <Alert color="red">{time.error.message}</Alert>
  const settings = time.data
  const shown: Draft = draft ?? { city: settings.city, config: settings.config }
  const update = (next: Draft) => {
    setDraft(next)
    save(next, settings.defaults)
  }
  const set = (key: NumberKey, value: number | string, min = 0, whole = false) => {
    if (typeof value !== 'number' || value < min) return // an empty or out-of-range field keeps the old value
    update({ ...shown, config: { ...shown.config, [key]: whole ? Math.round(value) : value } })
  }
  return (
    <Stack>
      {settings.cities.length ? (
        <Select
          label="Craft Location"
          description="Some cities have shorter times to run between mailboxes, vendors, etc"
          data={cityOptions(settings)}
          value={shown.city ?? ''}
          onChange={(v) => update({ ...shown, city: v || null })}
          allowDeselect={false}
          maw={420}
        />
      ) : (
        <Text size="sm" c="dimmed">
          No city maps for this game yet: times count casts, clicks and switching characters, not running.
        </Text>
      )}
      <NumberInput
        label="Crafts per session"
        description="Crafting multiple items at once improves average time, because you don't need to run around as much."
        value={shown.config.batch}
        onChange={(v) => set('batch', v, 1, true)}
        min={1}
        step={5}
        allowDecimal={false}
        maw={420}
      />
      <Text size="sm" fw={500}>
        Seconds per action
      </Text>
      <SimpleGrid cols={{ base: 1, xs: 2 }}>
        {ACTIONS.map(({ key, label, step, min = 0, whole = false }) => (
          <NumberInput
            key={key}
            label={label}
            value={shown.config[key]}
            onChange={(v) => set(key, v, min, whole)}
            min={min}
            step={step}
            decimalScale={whole ? 0 : 2}
            allowDecimal={!whole}
          />
        ))}
      </SimpleGrid>
      <Group>
        <Button
          variant="light"
          size="xs"
          onClick={() => update({ city: null, config: settings.defaults })}
          disabled={shown.city === null && Object.keys(changes(shown.config, settings.defaults)).length === 0}
        >
          Reset to defaults
        </Button>
        {setTime.isPending && <Loader size="xs" aria-label="Saving" />}
      </Group>
    </Stack>
  )
}
