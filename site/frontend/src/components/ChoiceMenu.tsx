/** The menu that changes a recipe's plan: another source for a reagent, or another way to sell. The flow chart
 * and the step list both show it; `planChoices` lists what it offers. */
import { useContext, type ReactNode } from 'react'
import { ActionIcon, Menu, Text } from '@mantine/core'
import { ChooseContext } from '../lib/choices'
import { IconSwap } from './icons'
import classes from './ChoiceMenu.module.css'

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
