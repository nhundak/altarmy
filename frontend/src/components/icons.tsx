import type { ReactNode } from 'react'

/** The few line icons the site uses (24px grid, currentColor), so no icon package is needed. */

type IconProps = { size?: number }

function Svg({ size = 24, children }: IconProps & { children: ReactNode }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.8}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {children}
    </svg>
  )
}

/** A clipboard: paste the addon's export. */
export function IconPaste(props: IconProps) {
  return (
    <Svg {...props}>
      <rect x="6" y="4" width="12" height="17" rx="2" />
      <path d="M9 4.5V3.5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v1" />
      <path d="M9 11h6M9 15h4" />
    </Svg>
  )
}

/** A person with a plus: add a character. */
export function IconUserPlus(props: IconProps) {
  return (
    <Svg {...props}>
      <circle cx="10" cy="8" r="3.5" />
      <path d="M3.5 20a6.5 6.5 0 0 1 13 0" />
      <path d="M19 8v6M16 11h6" />
    </Svg>
  )
}

/** A compass: look around. */
export function IconCompass(props: IconProps) {
  return (
    <Svg {...props}>
      <circle cx="12" cy="12" r="9" />
      <path d="m15.5 8.5-2 5-5 2 2-5z" />
    </Svg>
  )
}

/** A sun: switch to the light scheme. */
export function IconSun(props: IconProps) {
  return (
    <Svg {...props}>
      <circle cx="12" cy="12" r="4" />
      <path d="M12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2M5.3 5.3l1.4 1.4M17.3 17.3l1.4 1.4M5.3 18.7l1.4-1.4M17.3 6.7l1.4-1.4" />
    </Svg>
  )
}

/** A crescent moon: switch to the dark scheme. */
export function IconMoon(props: IconProps) {
  return (
    <Svg {...props}>
      <path d="M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z" />
    </Svg>
  )
}

/** Two opposed arrows: swap for an alternative. */
export function IconSwap(props: IconProps) {
  return (
    <Svg {...props}>
      <path d="M4 8h15m-4-4 4 4-4 4M20 16H5m4-4-4 4 4 4" />
    </Svg>
  )
}

/** A downward chevron: open a section. */
export function IconChevron(props: IconProps) {
  return (
    <Svg {...props}>
      <path d="m6 9 6 6 6-6" />
    </Svg>
  )
}

/** A triangle with an exclamation mark: something needs attention. */
export function IconWarning(props: IconProps) {
  return (
    <Svg {...props}>
      <path d="M10.3 3.9 2.6 17.2a2 2 0 0 0 1.7 3h15.4a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z" />
      <path d="M12 9v4M12 17h.01" />
    </Svg>
  )
}
