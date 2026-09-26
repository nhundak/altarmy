import { Stack, Text, Title } from '@mantine/core'
import { useStatus } from '../api/queries'
import { realmLabel } from '../lib/realms'
import classes from './Hero.module.css'

/** The Profit page's welcome banner, shown until the visitor has picked how to start. */
export function Hero() {
  const status = useStatus().data
  return (
    <section className={classes.hero} aria-label="Welcome">
      <Stack gap="xs">
        <Text className={classes.eyebrow}>Crafting profits for WoW: Forever</Text>
        <Title order={1} className={classes.title}>
          Put your army to work
        </Title>
        <Stack gap="md" pt={4}>
          <Text className={classes.lead}>
            Alt Army Profit steps through all of your characters and finds the recipe chains with the greatest
            opportunity for profit. It will tell you where to source your materials, what to craft, and how best to
            sell the results.
          </Text>
          {status && status.recipes > 0 && (
            <div className={classes.stats}>
              <span>
                <b>{status.recipes.toLocaleString()}</b> recipes
              </span>
              <span>
                <b>{status.items.toLocaleString()}</b> items
              </span>
              {status.selection && status.prices > 0 && (
                <span>
                  <b>{status.prices.toLocaleString()}</b> auction prices on {realmLabel(status.selection)}
                </span>
              )}
            </div>
          )}
        </Stack>
      </Stack>
    </section>
  )
}
