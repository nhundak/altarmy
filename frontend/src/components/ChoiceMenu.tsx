/** The menus that change a recipe's plan: another source for a reagent, or another way to sell. The flow chart
 * and the step list both show them. */
import { createContext, useContext, type ReactNode } from 'react'
import { ActionIcon, Menu, Text } from '@mantine/core'
import type { FlowNode, RankResult } from '../api/client'
import { CharacterName } from './CharacterName'
import { IconSwap } from './icons'
import { Money } from './Money'
import classes from './ChoiceMenu.module.css'

export const BUY_FROM: Readonly<Record<string, string>> = { ah: 'on the AH', vendor: 'from a vendor' }

export const SELL_TEXT: Readonly<Record<string, string>> = {
  ah: 'Sell on the AH',
  vendor: 'Sell to a vendor',
  disenchant: 'Disenchant, sell the materials',
}

/** Money made: green, or red with a minus sign when it is a loss. */
export const Earned = ({ copper }: { copper: number }) => (
  <Text span inherit c={copper < 0 ? 'red' : 'teal'}>
    <Money copper={copper} />
  </Text>
)

/** Makes a recipe's plan editable: places with alternatives get a menu of them. */
export type PlanEditing = {
  /** Picks option `key` at every tree path in `paths` (several when one step stands for several nodes). */
  onChoose: (paths: readonly string[], key: string) => void
  /** The user changed something: offer Reset. */
  modified: boolean
  onReset: () => void
  /** The changed plan is being re-costed. */
  pending: boolean
  error: string | null
}

/** Picks another source (or exit) at tree paths; absent when the plan is read-only. */
export const ChooseContext = createContext<PlanEditing['onChoose'] | undefined>(undefined)

export type Choice = { key: string; label: ReactNode; amount: ReactNode; current: boolean }

/** A button listing a place's alternatives, best first; nothing when read-only or there is no alternative. */
export function ChoiceMenu({ label, paths, choices }: { label: string; paths: readonly string[]; choices: Choice[] }) {
  const onChoose = useContext(ChooseContext)
  if (!onChoose || choices.length < 2) return null
  return (
    <Menu position="bottom-end" shadow="md" withinPortal>
      <Menu.Target>
        <ActionIcon className={`nodrag nopan ${classes.menu}`} variant="subtle" size="xs" aria-label={label}>
          <IconSwap size={14} />
        </ActionIcon>
      </Menu.Target>
      {/* Portalled in the browser, but inline in tests: either way, clicks in it must not pan the chart. */}
      <Menu.Dropdown className="nodrag nopan">
        {choices.map((c) => (
          <Menu.Item
            key={c.key}
            leftSection={<span className={classes.check}>{c.current ? '✓' : ''}</span>}
            rightSection={
              <Text span size="xs" c="dimmed" ff="monospace">
                {c.amount}
              </Text>
            }
            fw={c.current ? 600 : undefined}
            onClick={() => !c.current && onChoose(paths, c.key)}
          >
            {c.label}
          </Menu.Item>
        ))}
      </Menu.Dropdown>
    </Menu>
  )
}

/** A source option as a menu line: crafts name the crafter, and say so when they mail it to `holder`. */
function optionLabel({ source, via, crafter, convert }: FlowNode['options'][number], holder: string): ReactNode {
  if (!via) return `Buy ${BUY_FROM[source] ?? source}`
  return (
    <>
      {convert ? 'Convert' : `Craft (${via})`}
      {crafter && (
        <>
          {' '}
          by <CharacterName name={crafter} />
          {crafter !== holder && holder ? ', mailed' : ''}
        </>
      )}
    </>
  )
}

/** The ways to get a reagent, with what each costs; `option` is the key of the one taken. */
export const sourceChoices = (options: FlowNode['options'], option: string, holder: string): Choice[] =>
  options.map((o) => ({
    key: o.key,
    label: optionLabel(o, holder),
    amount: <Money copper={o.cost} cost />,
    current: o.key === option,
  }))

/** The ways to sell the craft, with the profit each makes; `exit` is the one taken. */
export const sellChoices = (options: RankResult['sell_options'], exit: string): Choice[] =>
  options.map((o) => ({
    key: o.kind,
    label: SELL_TEXT[o.kind] ?? `Sell via ${o.kind}`,
    amount: (
      <>
        profit <Earned copper={o.profit} />
      </>
    ),
    current: o.kind === exit,
  }))
