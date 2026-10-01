import { useState, type ReactNode } from 'react'
import { HoverCard } from '@mantine/core'
import type { ItemInfo, ItemMap, RankResult } from '../api/client'
import {
  QUALITY_COLORS,
  armorText,
  bindingText,
  damageLine,
  dpsText,
  iconUrl,
  slotLine,
  speedText,
} from '../lib/wow'
import classes from './ItemTooltip.module.css'
import { Money } from './Money'

const qualityColor = (quality: number) => QUALITY_COLORS[quality] ?? QUALITY_COLORS[1]

/** A CDN icon that disappears if it cannot load (offline, or an icon Wowhead does not have). */
function Icon({
  icon,
  size,
  className,
}: {
  icon: string | null
  size: 'small' | 'large'
  className: string
}) {
  const [failed, setFailed] = useState(false)
  if (!icon || failed) return null
  return <img className={className} src={iconUrl(icon, size)} alt="" onError={() => setFailed(true)} />
}

/** The Disenchant spell's icon and name, as a flip's recipe column starts. */
export function DisenchantLabel() {
  return (
    <span className={classes.link}>
      <Icon icon="inv_enchant_disenchant" size="small" className={classes.smallIcon} />
      <span>Disenchant</span>
    </span>
  )
}

/** The item's tooltip lines in in-game order. Stats, armor, damage and the green lines are computed at
 * ingest; a database from before that shows none of them. */
function ItemLines({ item }: { item: ItemInfo }) {
  const binding = bindingText(item.bonding)
  const slot = slotLine(item)
  const damage = damageLine(item)
  const speed = speedText(item)
  const dps = dpsText(item)
  const armor = armorText(item)
  return (
    <>
      <div className={classes.title} style={{ color: qualityColor(item.quality) }}>
        {item.name}
      </div>
      {binding && <div>{binding}</div>}
      {slot && (
        <div className={classes.split}>
          <span>{slot.left}</span>
          {slot.right && <span>{slot.right}</span>}
        </div>
      )}
      {damage ? (
        <div className={classes.split}>
          <span>{damage.left}</span>
          {damage.right && <span>{damage.right}</span>}
        </div>
      ) : (
        speed && <div className={classes.right}>{speed}</div>
      )}
      {dps && <div>{dps}</div>}
      {armor && <div>{armor}</div>}
      {item.stats.map((stat) => (
        <div key={stat}>{stat}</div>
      ))}
      {item.required_level > 1 && <div>Requires Level {item.required_level}</div>}
      {item.required_skill && (
        <div>
          Requires {item.required_skill} ({item.required_skill_rank})
        </div>
      )}
      {item.effects.map((effect, i) => (
        <div key={i} className={classes.green}>
          {effect.trigger}: {effect.text}
        </div>
      ))}
      {item.description && <div className={classes.flavor}>"{item.description}"</div>}
      {item.sell_price > 0 && (
        <div>
          Sell Price: <Money copper={item.sell_price} />
        </div>
      )}
      {item.ah_price != null && (
        <div>
          Auction: <Money copper={item.ah_price} />
        </div>
      )}
      {item.ah_quantity != null && <div>{item.ah_quantity.toLocaleString()} listed</div>}
      {item.ah_levels.length > 1 &&
        item.ah_levels.map((level) => (
          <div key={level.price} style={{ opacity: 0.8 }}>
            {level.quantity.toLocaleString()}
            {level.more ? ' more from ' : ' at '}
            <Money copper={level.price} />
            {level.counted ? '' : ' (just listed: not counted on)'}
          </div>
        ))}
      {item.ah_price != null && item.ah_sell_price != null && item.ah_sell_price < item.ah_price && (
        <div>
          Sells for (going rate): <Money copper={item.ah_sell_price} />
        </div>
      )}
      {item.vendor_price != null && (
        <div>
          Vendor: <Money copper={item.vendor_price} />
        </div>
      )}
    </>
  )
}

/** With `wide`, the box grows to fit lines that cannot wrap instead of stopping at the usual max width. */
function TooltipFrame({ icon, wide = false, children }: { icon: string | null; wide?: boolean; children: ReactNode }) {
  return (
    <div className={classes.frame}>
      <Icon icon={icon} size="large" className={classes.bigIcon} />
      <div className={classes.tooltip} data-wide={wide || undefined}>
        {children}
      </div>
    </div>
  )
}

export function ItemTooltip({ item }: { item: ItemInfo }) {
  return (
    <TooltipFrame icon={item.icon}>
      <ItemLines item={item} />
    </TooltipFrame>
  )
}

/** Like a recipe item in game: recipe name, profession and reagents, then the crafted item's tooltip. */
export function RecipeTooltip({
  name,
  profession,
  reagents,
  output,
  items,
}: {
  name: string
  profession: string
  reagents: RankResult['reagents']
  output: ItemInfo | undefined
  items: ItemMap
}) {
  const reagentList = reagents
    .map(({ item_id, count }) => {
      const reagent = items[item_id]?.name ?? `Item ${item_id}`
      return count > 1 ? `${reagent} (${count})` : reagent
    })
    .join(', ')
  return (
    <TooltipFrame icon={output?.icon ?? null}>
      <div className={classes.title}>{name}</div>
      <div>{profession}</div>
      <div className={classes.reagents}>Reagents: {reagentList}</div>
      {output && (
        <div className={classes.section}>
          <ItemLines item={output} />
        </div>
      )}
    </TooltipFrame>
  )
}

type Material = RankResult['exits'][number]['materials'][number]

const countRange = ({ min_count, max_count }: Material) =>
  min_count === max_count ? `×${min_count}` : `×${min_count}-${max_count}`

/** What disenchanting one `name` yields: each material's count, chance and expected AH value, then the total. */
export function DisenchantTooltip({
  name,
  materials,
  value,
  items,
}: {
  name: string
  materials: Material[]
  value: number
  items: ItemMap
}) {
  return (
    <TooltipFrame icon={null} wide>
      <div className={classes.title}>Disenchanting {name}</div>
      <div className={classes.materials}>
        {materials.map((m) => {
          const item = items[m.item_id]
          return (
            <div key={m.item_id} className={classes.materialRow}>
              <span className={classes.material}>
                <Icon icon={item?.icon ?? null} size="small" className={classes.smallIcon} />
                <span style={{ color: qualityColor(item?.quality ?? 1) }}>{m.name}</span>
              </span>
              <span>
                {countRange(m)} ({Math.round(m.chance * 100)}%)
              </span>
              <span className={classes.right}>
                {m.value == null ? <span className={classes.dim}>no price</span> : <Money copper={m.value} />}
              </span>
            </div>
          )
        })}
        <div className={`${classes.materialRow} ${classes.total}`}>
          <span>Expected total after AH cut</span>
          <span />
          <span className={classes.right}>
            <Money copper={value} />
          </span>
        </div>
      </div>
    </TooltipFrame>
  )
}

/** Hover `children` for the disenchant breakdown of `result`'s output; plain children if it has none. */
export function DisenchantHover({
  result,
  items,
  children,
}: {
  result: RankResult
  items: ItemMap
  children: ReactNode
}) {
  const exit = result.exits.find((e) => e.kind === 'disenchant')
  if (!exit) return <>{children}</>
  return (
    <Hover
      tooltip={
        <DisenchantTooltip
          name={result.output_name}
          materials={exit.materials}
          value={exit.value}
          items={items}
        />
      }
    >
      {children}
    </Hover>
  )
}

/** Hover `children` to show `tooltip` beside it. */
export function Hover({
  tooltip,
  children,
  truncate = false,
}: {
  tooltip: ReactNode
  children: ReactNode
  truncate?: boolean
}) {
  return (
    <HoverCard
      openDelay={0}
      closeDelay={0}
      transitionProps={{ duration: 0 }}
      position="right-start"
      offset={8}
      withinPortal
    >
      <HoverCard.Target>
        <span className={classes.target} data-truncate={truncate || undefined}>
          {children}
        </span>
      </HoverCard.Target>
      <HoverCard.Dropdown className={classes.dropdown}>{tooltip}</HoverCard.Dropdown>
    </HoverCard>
  )
}

/** An item name in its quality colour with a small icon; hover for the tooltip. `name` is the fallback
 * when the item has no details (e.g. a database from before tooltips were ingested). With `truncate`, a
 * name too long for its (flex) container ends in an ellipsis instead of overflowing. `tooltip` replaces the
 * item's own tooltip (e.g. a recipe's). */
export function ItemLink({
  item,
  name,
  truncate = false,
  tooltip,
}: {
  item: ItemInfo | undefined
  name?: string
  truncate?: boolean
  tooltip?: ReactNode
}) {
  if (!item) {
    const plain = truncate ? <span className={classes.plainName}>{name}</span> : <>{name}</>
    return tooltip ? <Hover tooltip={tooltip}>{plain}</Hover> : plain
  }
  return (
    <Hover tooltip={tooltip ?? <ItemTooltip item={item} />} truncate={truncate}>
      <span className={classes.link} data-quality={item.quality} data-truncate={truncate || undefined}>
        <Icon icon={item.icon} size="small" className={classes.smallIcon} />
        <span className={classes.name}>{item.name}</span>
      </span>
    </Hover>
  )
}
