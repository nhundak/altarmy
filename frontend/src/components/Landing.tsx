import { Stack, Text, Title } from '@mantine/core'
import { motion } from 'motion/react'
import { linkProps, type Route } from '../lib/router'
import { Carousel, type Slide } from './Carousel'
import classes from './Landing.module.css'

const EASE = [0.25, 0.8, 0.25, 1] as const

type Showcase = {
  key: string
  to: Route
  eyebrow: string
  title: string
  copy: string
  /** A short line under the copy. */
  note?: string
  cue: string
  slides: readonly Slide[]
  /** The screenshots' shape, as a CSS aspect ratio (the carousel's default is 3:2). */
  aspect?: string
  /** Pictures on the left, copy on the right (on wide screens; phones always read the copy first). */
  reverse?: boolean
}

const SHOWCASES: readonly Showcase[] = [
  {
    key: 'addon',
    to: '/addon',
    eyebrow: 'The addon',
    title: 'Alt Army',
    copy:
      'Alt Army remembers every one of your characters: their items, professions, levels, etc. You can then ' +
      "quickly view a summary of their current state, or search for that item or recipe you're interested in.",
    note: 'Versions supported: Forever, and Burning Crusade',
    cue: 'Get the Addon',
    // The addon's CurseForge screenshots (https://www.curseforge.com/wow/addons/alt-army).
    slides: [
      { src: '/landing/addon-summary.png', alt: 'Alt Army: a summary of every character' },
      { src: '/landing/addon-search.png', alt: 'Alt Army: searching every character for an item' },
      { src: '/landing/addon-gear.png', alt: "Alt Army: a character's gear" },
      { src: '/landing/addon-graphs.png', alt: 'Alt Army: graphs of time played per level, character by character' },
      { src: '/landing/addon-guild.png', alt: 'Alt Army: your guilds' },
      { src: '/landing/addon-cooldowns.png', alt: 'Alt Army: profession cooldowns' },
      { src: '/landing/addon-reputation.png', alt: 'Alt Army: reputations' },
    ],
  },
  {
    key: 'profit',
    to: '/profit',
    eyebrow: 'Crafting profits for WoW: Forever',
    title: 'Put your army to work',
    copy:
      'Combine your character details with the latest auctionhouse prices and find the best recipes for you to ' +
      "make a profit. We'll show you where to source your materials, what to craft, and how best to sell the " +
      'results.',
    cue: 'Find profitable crafts',
    slides: [
      { src: '/landing/profit-search.png', alt: 'Profit: recipes ranked by profit, profit per hour and return' },
      { src: '/landing/profit-flow.png', alt: 'Profit: the flow chart of what to buy and craft for Hard Gold Bracers' },
      { src: '/landing/profit-steps.png', alt: 'Profit: the step-by-step plan, with the run to each spot on the city map' },
    ],
    aspect: '16 / 9',
    reverse: true,
  },
]

/**
 * One full-width card: copy on one side, screenshots on the other. Its title is the link, stretched over the whole
 * card (so clicking anywhere goes to the page), with the carousel's buttons above it.
 */
function ShowcaseCard({ spec, index }: { spec: Showcase; index: number }) {
  const titleId = `showcase-${spec.key}-title`
  return (
    <motion.article
      className={classes.card}
      data-reverse={spec.reverse || undefined}
      aria-labelledby={titleId}
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.35, delay: 0.08 * index, ease: EASE }}
    >
      <div className={classes.copy}>
        <Text className={classes.eyebrow}>{spec.eyebrow}</Text>
        <Title order={2} id={titleId} className={classes.title}>
          <a className={classes.link} {...linkProps(spec.to)}>
            {spec.title}
          </a>
        </Title>
        <Text className={classes.lead}>{spec.copy}</Text>
        {spec.note && <Text className={classes.note}>{spec.note}</Text>}
        <span className={classes.cue}>
          {spec.cue}
          <span className={classes.arrow} aria-hidden="true">
            →
          </span>
        </span>
      </div>
      <div className={classes.shots}>
        {/* The cards take turns: the second one's first step comes half an interval after the first one's. */}
        <Carousel slides={spec.slides} label={`${spec.title} screenshots`} offset={index * 3000} aspect={spec.aspect} />
      </div>
    </motion.article>
  )
}

/** The main page: what the addon and the Profit page are, each a card leading to its page. */
export function Landing() {
  return (
    <Stack gap="lg">
      {SHOWCASES.map((spec, i) => (
        <ShowcaseCard key={spec.key} spec={spec} index={i} />
      ))}
    </Stack>
  )
}
