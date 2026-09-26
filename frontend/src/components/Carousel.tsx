import { useEffect, useRef, useState } from 'react'
import { ActionIcon, UnstyledButton } from '@mantine/core'
import { AnimatePresence, motion, useReducedMotion } from 'motion/react'
import classes from './Carousel.module.css'
import { IconChevron } from './icons'

export type Slide = { src: string; alt: string }

/**
 * A few pictures shown one at a time: they cycle on their own every `interval` ms (the first step `offset` ms
 * later, so several carousels on a page can take turns; paused while hovered or focused, and never when the
 * visitor prefers reduced motion), and the arrows and dots step through them.
 */
export function Carousel({
  slides,
  label,
  interval = 6000,
  offset = 0,
}: {
  slides: readonly Slide[]
  label: string
  interval?: number
  offset?: number
}) {
  const [index, setIndex] = useState(0)
  const [paused, setPaused] = useState(false)
  const reduced = useReducedMotion()
  const count = slides.length
  // The offset applies once, to the wait before the first step of any kind.
  const pending = useRef(offset)
  const show = (i: number) => {
    pending.current = 0
    setIndex(i)
  }
  const step = (by: number) => show((index + by + count) % count)

  // `index` is a dependency so a manual step starts a fresh wait.
  useEffect(() => {
    if (paused || reduced || count < 2) return
    const id = window.setTimeout(() => show((index + 1) % count), interval + pending.current)
    return () => window.clearTimeout(id)
  }, [paused, reduced, count, interval, index])

  const slide = slides[index]
  if (!slide) return null
  return (
    <div
      className={classes.carousel}
      role="group"
      aria-roledescription="carousel"
      aria-label={label}
      onMouseEnter={() => setPaused(true)}
      onMouseLeave={() => setPaused(false)}
      onFocus={() => setPaused(true)}
      onBlur={() => setPaused(false)}
    >
      <div className={classes.frame}>
        <AnimatePresence initial={false}>
          <motion.img
            key={slide.src}
            src={slide.src}
            alt={slide.alt}
            className={classes.image}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.5 }}
          />
        </AnimatePresence>
      </div>
      {count > 1 && (
        <div className={classes.controls}>
          <ActionIcon variant="subtle" color="gray" size="sm" aria-label="Previous screenshot" onClick={() => step(-1)}>
            <span className={classes.left}>
              <IconChevron size={18} />
            </span>
          </ActionIcon>
          <div className={classes.dots}>
            {slides.map((s, i) => (
              <UnstyledButton
                key={s.src}
                className={classes.dot}
                aria-label={`Screenshot ${i + 1} of ${count}`}
                aria-current={i === index || undefined}
                onClick={() => show(i)}
              />
            ))}
          </div>
          <ActionIcon variant="subtle" color="gray" size="sm" aria-label="Next screenshot" onClick={() => step(1)}>
            <span className={classes.right}>
              <IconChevron size={18} />
            </span>
          </ActionIcon>
        </div>
      )}
    </div>
  )
}
