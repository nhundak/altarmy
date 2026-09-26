import { useEffect, useRef, useState } from 'react'
import { ActionIcon, UnstyledButton } from '@mantine/core'
import { AnimatePresence, motion, useReducedMotion } from 'motion/react'
import classes from './Carousel.module.css'
import { IconChevron } from './icons'

export type Slide = { src: string; alt: string }

/**
 * A few pictures shown one at a time in a frame of the given `aspect` ratio: they cycle on their own every
 * `interval` ms (the first step `offset` ms later, so several carousels on a page can take turns; paused while
 * hovered or focused, and never when the visitor prefers reduced motion), and the arrows and dots step through
 * them, after which the pictures stay put: the visitor is looking at one.
 */
export function Carousel({
  slides,
  label,
  interval = 6000,
  offset = 0,
  aspect = '3 / 2',
}: {
  slides: readonly Slide[]
  label: string
  interval?: number
  offset?: number
  aspect?: string
}) {
  const [index, setIndex] = useState(0)
  const [paused, setPaused] = useState(false)
  const [stopped, setStopped] = useState(false)
  const reduced = useReducedMotion()
  const count = slides.length
  // The offset applies once, to the wait before the first automatic step.
  const pending = useRef(offset)
  const pick = (i: number) => {
    setStopped(true)
    setIndex(i)
  }
  const step = (by: number) => pick((index + by + count) % count)

  useEffect(() => {
    if (paused || stopped || reduced || count < 2) return
    const id = window.setTimeout(() => {
      pending.current = 0
      setIndex((i) => (i + 1) % count)
    }, interval + pending.current)
    return () => window.clearTimeout(id)
  }, [paused, stopped, reduced, count, interval, index])

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
      <div className={classes.frame} style={{ aspectRatio: aspect }}>
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
                onClick={() => pick(i)}
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
