import { Loader, NumberInput } from '@mantine/core'
import { useEditTime, useTime } from '../api/queries'

/**
 * Crafts per session: one of the search's options, and the only one of the server's time settings the UI edits (the
 * city and the seconds per action are saved back as they were).
 */
export function CraftsPerSession() {
  const time = useTime()
  const { edit } = useEditTime()
  if (!time.data) return time.isError ? null : <Loader size="sm" />
  const settings = time.data
  return (
    <NumberInput
      label="Crafts per session"
      description="More crafts at once need more gold up front and bag space."
      value={settings.config.batch}
      onChange={(v) => {
        if (typeof v === 'number' && v >= 1)
          edit({ city: settings.city, config: { ...settings.config, batch: Math.round(v) } })
      }}
      min={1}
      step={5}
      allowDecimal={false}
    />
  )
}
