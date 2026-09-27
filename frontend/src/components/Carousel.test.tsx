import { act, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { MantineProvider } from '@mantine/core'
import { Carousel } from './Carousel'

const slides = [
  { src: '/a.svg', alt: 'First' },
  { src: '/b.svg', alt: 'Second' },
  { src: '/c.svg', alt: 'Third' },
]

const shown = () => screen.getAllByRole('img').map((i) => i.getAttribute('alt'))
const current = () => screen.getAllByRole('button', { name: /^Screenshot \d of 3$/ }).findIndex((b) => b.hasAttribute('aria-current'))

function renderCarousel(offset = 0) {
  return render(
    <MantineProvider env="test">
      <Carousel slides={slides} label="Pictures" interval={1000} offset={offset} />
    </MantineProvider>,
  )
}

describe('Carousel', () => {
  afterEach(() => vi.useRealTimers())

  it('steps through the pictures with the arrows and dots, wrapping around', () => {
    renderCarousel()
    expect(screen.getByRole('group', { name: 'Pictures' })).toHaveAttribute('aria-roledescription', 'carousel')
    expect(shown()).toEqual(['First'])
    expect(current()).toBe(0)
    fireEvent.click(screen.getByRole('button', { name: 'Next screenshot' }))
    expect(shown()).toContain('Second')
    expect(current()).toBe(1)
    fireEvent.click(screen.getByRole('button', { name: 'Previous screenshot' }))
    fireEvent.click(screen.getByRole('button', { name: 'Previous screenshot' }))
    expect(shown()).toContain('Third')
    expect(current()).toBe(2)
    fireEvent.click(screen.getByRole('button', { name: 'Screenshot 1 of 3' }))
    expect(current()).toBe(0)
  })

  it('cycles on its own, pausing while the pointer is over it', () => {
    vi.useFakeTimers()
    renderCarousel()
    act(() => vi.advanceTimersByTime(1000))
    expect(current()).toBe(1)
    fireEvent.mouseEnter(screen.getByRole('group', { name: 'Pictures' }))
    act(() => vi.advanceTimersByTime(3000))
    expect(current()).toBe(1)
    fireEvent.mouseLeave(screen.getByRole('group', { name: 'Pictures' }))
    act(() => vi.advanceTimersByTime(1000))
    expect(current()).toBe(2)
  })

  it('delays its first step by the offset, then keeps the interval', () => {
    vi.useFakeTimers()
    renderCarousel(500)
    act(() => vi.advanceTimersByTime(1000))
    expect(current()).toBe(0)
    act(() => vi.advanceTimersByTime(500))
    expect(current()).toBe(1)
    act(() => vi.advanceTimersByTime(1000))
    expect(current()).toBe(2)
  })

  it('keeps each picture it has shown mounted, so cycling back does not load it again', () => {
    vi.useFakeTimers()
    renderCarousel()
    const first = screen.getByRole('img', { name: 'First' })
    for (let i = 0; i < 3; i++) act(() => vi.advanceTimersByTime(1000))
    expect(current()).toBe(0)
    expect(screen.getByRole('img', { name: 'First' })).toBe(first)
    expect(shown()).toEqual(['First'])
  })

  it('stops cycling once the visitor picks a picture', () => {
    vi.useFakeTimers()
    renderCarousel()
    act(() => vi.advanceTimersByTime(1000))
    expect(current()).toBe(1)
    fireEvent.click(screen.getByRole('button', { name: 'Screenshot 1 of 3' }))
    act(() => vi.advanceTimersByTime(10000))
    expect(current()).toBe(0)
    fireEvent.click(screen.getByRole('button', { name: 'Next screenshot' }))
    act(() => vi.advanceTimersByTime(10000))
    expect(current()).toBe(1)
  })
})
