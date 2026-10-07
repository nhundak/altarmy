import { useId } from 'react'
import { Table, Text } from '@mantine/core'
import type { ItemInfo, RankResult } from '../api/client'
import { depthSteps, priceRange, profitAt, scale, valueRange } from '../lib/depth'
import { EXIT_SHORT } from '../lib/exits'
import { formatMoney } from '../lib/money'
import classes from './MarketSection.module.css'
import { Money } from './Money'

/* The Market section's charts, drawn as plain SVG on the theme's colours: the order book as a staircase and the
 * session's profit over the price it is listed at; and the order book as a table. */

type Level = ItemInfo['ah_levels'][number]

/** A dashed line across a chart at a price, named at its right end. */
export interface Rule {
  price: number
  label: string
  tone: 'cost' | 'profit' | 'plain'
}

const W = 640
const H = 190
const LEFT = 66
const RIGHT = 176
const TOP = 14
const BOTTOM = 26
const TONE = { cost: classes.toneCost, profit: classes.toneProfit, plain: classes.tonePlain } as const

/** Labels at the right edge spread apart so none overlaps another (`gap` px between baselines). */
function spread(ys: readonly number[], gap = 13): number[] {
  const order = ys.map((y, i) => ({ y, i })).sort((a, b) => a.y - b.y)
  const out = [...ys]
  let last = -Infinity
  for (const { y, i } of order) {
    const placed = Math.max(y, last + gap)
    out[i] = placed
    last = placed
  }
  return out
}

/**
 * The order book as a staircase: units listed along, price up, cheapest first. What the plan lists (`insert`) is put
 * in as a block where it would sit; what it buys (`taken`) is shaded. Levels plans don't count on are dashed, the
 * level pooling every dearer one hatched; `rules` mark prices across it (break-even, the usual price).
 */
export function DepthChart({
  name,
  levels,
  insert,
  taken,
  rules = [],
}: {
  name: string
  levels: readonly Level[]
  insert?: { price: number; units: number; label: string } | undefined
  taken?: readonly number[] | undefined
  rules?: readonly Rule[]
}) {
  const hatch = useId()
  const { steps, total } = depthSteps(levels, { insert, taken })
  if (!steps.length) return null
  const { lo, hi } = priceRange([...steps.map((s) => s.price), ...rules.map((r) => r.price)])
  const x = scale(0, Math.max(1, total), LEFT, W - RIGHT)
  const y = scale(lo, hi, H - BOTTOM, TOP)
  const base = H - BOTTOM
  const bought = steps.reduce((sum, s) => sum + s.taken, 0)
  const lastTaken = [...steps].reverse().find((s) => s.taken > 0)
  // the labels at the right end: the rules, what the plan lists or where its buying ends, and the pooled level
  const notes: { y: number; text: string; className: string }[] = [
    ...rules.map((r) => ({ y: y(r.price), text: `${r.label} ${formatMoney(r.price)}`, className: TONE[r.tone] })),
  ]
  const you = steps.find((s) => s.kind === 'you')
  if (you && insert) notes.push({ y: y(you.price), text: `${insert.label} ${formatMoney(you.price)}`, className: classes.toneYou })
  if (lastTaken)
    notes.push({ y: y(lastTaken.price), text: `your ${bought} end at ${formatMoney(lastTaken.price)}`, className: classes.toneYou })
  const tail = steps.find((s) => s.kind === 'tail')
  if (tail) notes.push({ y: y(tail.price), text: `${tail.x1 - tail.x0}+ from ${formatMoney(tail.price)}`, className: classes.tonePlain })
  const placed = spread(notes.map((n) => n.y + 4))
  const ticks = [...new Set([steps[0]!.price, steps[steps.length - 1]!.price])]
  const xTicks = [...new Set([0, ...(you ? [you.x0] : []), ...(bought ? [bought] : []), total])]
  const sellers = steps.filter((s) => s.kind !== 'you').reduce((n, s) => n + s.listings, 0)
  return (
    <svg
      className={classes.chart}
      viewBox={`0 0 ${W} ${H}`}
      role="img"
      aria-label={`Price levels listed for ${name}, cheapest first`}
    >
      <defs>
        <pattern id={hatch} width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
          <line x1="0" y1="0" x2="0" y2="6" className={classes.hatch} />
        </pattern>
      </defs>
      {ticks.map((p) => (
        <g key={p}>
          <line x1={LEFT} x2={W - RIGHT} y1={y(p)} y2={y(p)} className={classes.grid} />
          <text x={LEFT - 6} y={y(p) + 4} textAnchor="end" className={classes.axis}>
            {formatMoney(p)}
          </text>
        </g>
      ))}
      {steps.map((s, i) => {
        const x0 = x(s.x0)
        const x1 = x(s.x1)
        const sy = y(s.price)
        const next = steps[i + 1]
        return (
          <g key={i}>
            {s.taken > 0 && (
              <rect x={x0} y={sy} width={x(s.x0 + s.taken) - x0} height={base - sy} className={classes.taken} />
            )}
            {s.kind === 'tail' && <rect x={x0} y={sy} width={x1 - x0} height={base - sy} fill={`url(#${hatch})`} />}
            {s.kind === 'you' ? (
              <>
                <rect x={x0} y={sy - 7} width={Math.max(2, x1 - x0)} height={14} rx={3} className={classes.you} />
                {x1 - x0 > 46 && (
                  <text x={(x0 + x1) / 2} y={sy + 4} textAnchor="middle" className={classes.youText}>
                    YOU {s.x1 - s.x0}
                  </text>
                )}
              </>
            ) : (
              <line
                x1={x0}
                x2={x1}
                y1={sy}
                y2={sy}
                className={s.kind === 'uncounted' ? classes.uncounted : classes.step}
              />
            )}
            {next && s.kind !== 'you' && next.kind !== 'you' && (
              <line x1={x1} x2={x1} y1={sy} y2={y(next.price)} className={classes.riser} />
            )}
          </g>
        )
      })}
      {rules.map((r) => (
        <line key={r.label} x1={LEFT} x2={W - RIGHT} y1={y(r.price)} y2={y(r.price)} className={`${classes.rule} ${TONE[r.tone]}`} />
      ))}
      {notes.map((n, i) => (
        <text key={i} x={W - RIGHT + 8} y={placed[i]} className={`${classes.note} ${n.className}`}>
          {n.text}
        </text>
      ))}
      <line x1={LEFT} x2={W - RIGHT} y1={base} y2={base} className={classes.grid} />
      {xTicks.map((v) => (
        <text key={v} x={x(v)} y={H - 8} textAnchor="middle" className={classes.axis}>
          {v}
        </text>
      ))}
      <text x={W - RIGHT + 8} y={H - 8} className={classes.axis}>
        {sellers === 1 ? 'units listed · one seller' : 'units listed'}
      </text>
    </svg>
  )
}

/**
 * What the session makes if it is listed at each price: the auction house's line rising with the price, every other
 * way to sell flat, so the price under which another way pays more is where the lines cross. Markers show break-even,
 * the plan's own price and the usual one.
 */
export function ProfitChart({
  result: r,
  sellPrice,
  cut,
  marks,
}: {
  result: RankResult
  sellPrice: number
  cut: number
  marks: readonly Rule[]
}) {
  const others = r.sell_options.filter((o) => o.kind !== 'ah' && o.kind !== 'keep')
  const prices = [sellPrice, ...marks.map((m) => m.price)]
  const p0 = Math.floor(Math.min(...prices) * 0.8)
  const p1 = Math.ceil(Math.max(...prices) * 1.2)
  const at = (p: number) => profitAt(r, sellPrice, cut, p) ?? 0
  const { lo, hi } = valueRange([at(p0), at(p1), 0, ...others.map((o) => o.profit)])
  const x = scale(p0, p1, LEFT, W - RIGHT)
  const y = scale(lo, hi, H - BOTTOM, TOP)
  const notes = [
    { y: y(at(p1)), text: 'auction house', className: classes.toneProfit },
    ...others.map((o) => ({ y: y(o.profit), text: `${EXIT_SHORT[o.kind] ?? o.kind} ${formatMoney(o.profit)}`, className: classes.tonePlain })),
  ]
  const placed = spread(notes.map((n) => n.y + 4))
  return (
    <svg className={classes.chart} viewBox={`0 0 ${W} ${H}`} role="img" aria-label="Session profit at each listing price">
      <line x1={LEFT} x2={W - RIGHT} y1={y(0)} y2={y(0)} className={classes.grid} />
      <text x={LEFT - 6} y={y(0) + 4} textAnchor="end" className={classes.axis}>
        0
      </text>
      {others.map((o) => (
        <line key={o.kind} x1={LEFT} x2={W - RIGHT} y1={y(o.profit)} y2={y(o.profit)} className={`${classes.rule} ${classes.tonePlain}`} />
      ))}
      <line x1={x(p0)} x2={x(p1)} y1={y(at(p0))} y2={y(at(p1))} className={classes.profitLine} />
      {marks.map((m, i) => (
        <g key={m.label}>
          <line x1={x(m.price)} x2={x(m.price)} y1={TOP} y2={H - BOTTOM} className={`${classes.rule} ${TONE[m.tone]}`} />
          <text x={x(m.price) + 4} y={TOP + 10 + i * 13} className={`${classes.note} ${TONE[m.tone]}`}>
            {m.label}
          </text>
        </g>
      ))}
      <circle cx={x(sellPrice)} cy={y(at(sellPrice))} r={4.5} className={classes.you} />
      <text x={x(sellPrice) + 8} y={y(at(sellPrice)) + 16} className={`${classes.note} ${classes.toneYou}`}>
        {formatMoney(at(sellPrice))}
      </text>
      {notes.map((n, i) => (
        <text key={i} x={W - RIGHT + 8} y={placed[i]} className={`${classes.note} ${n.className}`}>
          {n.text}
        </text>
      ))}
      <line x1={LEFT} x2={W - RIGHT} y1={H - BOTTOM} y2={H - BOTTOM} className={classes.grid} />
      {[p0, Math.round((p0 + p1) / 2), p1].map((p) => (
        <text key={p} x={x(p)} y={H - 8} textAnchor="middle" className={classes.axis}>
          {formatMoney(p)}
        </text>
      ))}
      <text x={W - RIGHT + 8} y={H - 8} className={classes.axis}>
        your price
      </text>
    </svg>
  )
}

/** Every price level listed, cheapest first: units, listings and how long it has been up (levels plans don't count on
 * dimmed); with `taken`, the units the plan buys of each ("~" when other branches share the walk). */
export function LadderTable({
  levels,
  taken,
  shared = false,
}: {
  levels: readonly Level[]
  taken?: readonly number[] | undefined
  shared?: boolean
}) {
  return (
    <div className={classes.tableWrap}>
      <Table className={classes.ladder} verticalSpacing={2} horizontalSpacing="xs" withRowBorders={false}>
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Price</Table.Th>
            <Table.Th>Units</Table.Th>
            <Table.Th>Listings</Table.Th>
            <Table.Th>Listed for</Table.Th>
            {taken && <Table.Th>You buy</Table.Th>}
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {levels.map((l, i) => (
            <Table.Tr key={`${l.price}-${i}`} data-uncounted={!l.counted || undefined} data-taken={(taken?.[i] ?? 0) > 0 || undefined}>
              <Table.Td>
                <Money copper={l.price} />
                {l.more && ' and up'}
              </Table.Td>
              <Table.Td>
                {l.quantity.toLocaleString()}
                {l.more && '+'}
              </Table.Td>
              <Table.Td>{l.listings}</Table.Td>
              <Table.Td>
                {l.age === 0 ? 'just listed' : `${l.age + 1} scans`}
                {!l.counted && ' · not counted on'}
              </Table.Td>
              {taken && <Table.Td>{taken[i] ? `${shared ? '~' : ''}${taken[i]}` : ''}</Table.Td>}
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
      {levels.some((l) => !l.counted) && (
        <Text size="xs" c="dimmed">
          Levels first seen in the newest scan far under the usual price aren&apos;t counted on: they may be gone before you
          get there.
        </Text>
      )}
    </div>
  )
}
