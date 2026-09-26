import { createTheme, type CSSVariablesResolver, type MantineColorsTuple } from '@mantine/core'
import classes from './theme.module.css'

/**
 * The look: warm charcoal (dark, the default) or warm ivory (light) with a single gold accent. Profit stays
 * `teal` and costs `red` (Mantine's, tuned per colour scheme); class and item-quality colours are the game's.
 */

/** Primary colour. Shade 4 is the accent on dark (dark text on it), shade 7 the one on light (white text). */
const gold: MantineColorsTuple = [
  '#FBF3DE',
  '#F5E4B7',
  '#EDD38C',
  '#E4C063',
  '#D9A441',
  '#C48E2A',
  '#A8751B',
  '#9A6A0F',
  '#7A530C',
  '#573B08',
]

/** Dark scheme neutrals: 0 text, 2 dimmed, 4 borders, 5 hover, 6 surfaces (cards, table), 7 the page. */
const dark: MantineColorsTuple = [
  '#EDE6D8',
  '#CFC7B8',
  '#A69E8E',
  '#6E675A',
  '#3A342B',
  '#292420',
  '#1E1B16',
  '#15130F',
  '#0F0E0B',
  '#0A0908',
]

/** Light scheme neutrals: 0 hover and stripes, 4 borders, 5 placeholders, 6 dimmed, 9 text. */
const gray: MantineColorsTuple = [
  '#F6F2EA',
  '#EFE9DD',
  '#E8E1D3',
  '#DFD7C8',
  '#D5CDBE',
  '#A39A8A',
  '#6B6355',
  '#4A4338',
  '#332E26',
  '#1F1B15',
]

export const theme = createTheme({
  primaryColor: 'gold',
  primaryShade: { light: 7, dark: 4 },
  colors: { gold, dark, gray },
  // Dark text on the dark scheme's gold, white on the light scheme's.
  autoContrast: true,
  luminanceThreshold: 0.3,
  fontFamily: "'Source Sans 3', 'Segoe UI', system-ui, sans-serif",
  fontFamilyMonospace: "'IBM Plex Mono', ui-monospace, 'Cascadia Mono', Consolas, monospace",
  headings: { fontFamily: "'Source Sans 3', 'Segoe UI', system-ui, sans-serif", fontWeight: '700' },
  defaultRadius: 'md',
  components: {
    Accordion: { classNames: { item: classes.accordionItem } },
    Table: { defaultProps: { verticalSpacing: 'sm' } },
  },
})

/** The light scheme's page is ivory with warm text; cards and inputs stay white so they lift off it. */
export const cssVariablesResolver: CSSVariablesResolver = (t) => ({
  variables: {},
  light: {
    '--mantine-color-body': t.colors.gray[0],
    '--mantine-color-text': t.colors.gray[9],
  },
  dark: {},
})
