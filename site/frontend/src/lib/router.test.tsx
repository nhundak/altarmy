import { act, fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { linkProps, navigate, previousRoute, routeOf, usePath, useRoute } from './router'

function Where() {
  const route = useRoute()
  return (
    <>
      <p>at {route}</p>
      <a {...linkProps('/manage')}>Manage</a>
    </>
  )
}

describe('router', () => {
  it('maps paths to pages, unknown ones to the main page', () => {
    expect(routeOf('/addon')).toBe('/addon')
    expect(routeOf('/profit')).toBe('/profit')
    expect(routeOf('/manage/')).toBe('/manage')
    expect(routeOf('/nope')).toBe('/')
    expect(routeOf('/')).toBe('/')
  })

  it('counts a path under a page as that page', () => {
    expect(routeOf('/profit/gold')).toBe('/profit')
    expect(routeOf('/profit/skill/r/Amy/tailoring/')).toBe('/profit')
    expect(routeOf('/profiteer')).toBe('/')
  })

  it('gives the whole path, following navigate and the back button', () => {
    function Path() {
      return <p>path {usePath()}</p>
    }
    act(() => navigate('/profit'))
    render(<Path />)
    expect(screen.getByText('path /profit')).toBeInTheDocument()
    act(() => navigate('/profit/gold'))
    expect(screen.getByText('path /profit/gold')).toBeInTheDocument()
    act(() => {
      window.history.back()
    })
    return vi.waitFor(() => expect(screen.getByText('path /profit')).toBeInTheDocument())
  })

  it('replaces the current entry when asked, so the back button skips it', () => {
    act(() => navigate('/addon'))
    const length = window.history.length
    act(() => navigate('/profit/skill', { replace: true }))
    expect(window.location.pathname).toBe('/profit/skill')
    expect(window.history.length).toBe(length)
  })

  it('starts at the current path and follows links, navigate and the back button', () => {
    window.history.pushState(null, '', '/addon')
    render(<Where />)
    expect(screen.getByText('at /addon')).toBeInTheDocument()

    fireEvent.click(screen.getByRole('link', { name: 'Manage' }))
    expect(screen.getByText('at /manage')).toBeInTheDocument()
    expect(window.location.pathname).toBe('/manage')

    act(() => navigate('/'))
    expect(screen.getByText('at /')).toBeInTheDocument()

    act(() => {
      window.history.pushState(null, '', '/profit')
      window.dispatchEvent(new PopStateEvent('popstate'))
    })
    expect(screen.getByText('at /profit')).toBeInTheDocument()
  })

  it('leaves modified clicks to the browser', () => {
    render(<Where />)
    const link = screen.getByRole('link', { name: 'Manage' })
    expect(link).toHaveAttribute('href', '/manage')
    fireEvent.click(link, { ctrlKey: true })
    expect(screen.getByText('at /')).toBeInTheDocument()
  })

  it('remembers the page shown before the current one, through links and the back button', () => {
    act(() => navigate('/'))
    act(() => navigate('/addon'))
    expect(previousRoute()).toBe('/')
    act(() => navigate('/addon'))
    expect(previousRoute()).toBe('/') // staying put is no move
    act(() => {
      window.history.pushState(null, '', '/profit')
      window.dispatchEvent(new PopStateEvent('popstate'))
    })
    expect(previousRoute()).toBe('/addon')
  })
})
