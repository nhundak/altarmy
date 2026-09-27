import { Stack, Text, Title } from '@mantine/core'
import { motion } from 'motion/react'
import classes from './Hero.module.css'

/** The Profit page's welcome banner, shown until the visitor has picked how to start. */
export function Hero() {
  return (
    <section className={classes.hero} aria-label="Welcome">
      {/* Its own layout, so the text isn't stretched while the main page's card resizes into the banner. */}
      <Stack gap="xs" renderRoot={(props) => <motion.div layout="position" {...props} />}>
        <Text className={classes.eyebrow}>Crafting profits for WoW: Forever</Text>
        <Title order={1} className={classes.title}>
          Put your army to work
        </Title>
        <Text className={classes.lead} pt={4}>
          Alt Army Profit steps through all of your characters and finds the recipe chains with the greatest
          opportunity for profit. It will tell you where to source your materials, what to craft, and how best to
          sell the results.
        </Text>
      </Stack>
    </section>
  )
}
