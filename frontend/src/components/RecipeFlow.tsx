import { useMemo } from 'react'
import { useComputedColorScheme } from '@mantine/core'
import { Controls, Handle, Position, ReactFlow, type NodeProps, type NodeTypes } from '@xyflow/react'
import type { ItemMap, RankResult } from '../api/client'
import { SELL_PATH } from '../lib/choices'
import { buildFlow, type ItemFlowNode, type MailFlowNode, type SellFlowNode } from '../lib/flow'
import { bonusNote, discountNote } from '../lib/talents'
import { CharacterName } from './CharacterName'
import {
  BUY_FROM,
  ChoiceMenu,
  ChooseContext,
  Earned,
  SELL_TEXT,
  sellChoices,
  sourceChoices,
  type PlanEditing,
} from './ChoiceMenu'
import { DisenchantHover, ItemLink } from './ItemTooltip'
import { Money } from './Money'
import classes from './RecipeFlow.module.css'

const MAX_HEIGHT = 480
const PADDING = 32

function ItemNode({ data, items }: NodeProps<ItemFlowNode> & { items: ItemMap }) {
  const {
    itemId,
    name,
    quantity,
    cost,
    via,
    crafts,
    made,
    source,
    discount,
    crafter,
    isLeaf,
    path,
    options,
    option,
    holder,
  } = data
  const spare = made - quantity
  return (
    <div className={classes.node}>
      {!isLeaf && <Handle type="target" position={Position.Left} className={classes.handle} />}
      <div className={classes.title}>
        <span className={classes.quantity}>{quantity}x</span>
        <span className={`nodrag nopan ${classes.name}`}>
          <ItemLink item={items[itemId]} name={name} truncate />
        </span>
        <ChoiceMenu
          label={`Change source of ${name}`}
          paths={[path]}
          choices={sourceChoices(options, option, holder)}
        />
      </div>
      <div className={classes.detail}>
        {via ? (
          `Craft ${crafts}x ${via}${spare > 0 ? ` (${spare} spare)` : ''}`
        ) : (
          <>
            Buy {BUY_FROM[source] ?? source} · <Money copper={cost} cost />
            {discount > 0 && ` · ${discountNote(discount)}`}
          </>
        )}
      </div>
      {crafter && (
        <div className={classes.detail}>
          <CharacterName name={crafter} />
        </div>
      )}
      <Handle type="source" position={Position.Right} className={classes.handle} />
    </div>
  )
}

function MailNode({ data: { to, postage, quantity } }: NodeProps<MailFlowNode>) {
  return (
    <div className={classes.node}>
      <Handle type="target" position={Position.Left} className={classes.handle} />
      <div className={classes.title}>
        <span>
          Mail {quantity}x to <CharacterName name={to} />
        </span>
      </div>
      <div className={classes.detail}>Postage · <Money copper={postage} cost /></div>
      <Handle type="source" position={Position.Right} className={classes.handle} />
    </div>
  )
}

function SellNode({
  data: { exit, revenue, profit, bonus, seller, options },
  result,
  items,
}: NodeProps<SellFlowNode> & { result: RankResult; items: ItemMap }) {
  const text = SELL_TEXT[exit] ?? `Sell via ${exit}`
  return (
    <div className={`${classes.node} ${classes.sell}`}>
      <Handle type="target" position={Position.Left} className={classes.handle} />
      <div className={classes.title}>
        {exit === 'disenchant' ? (
          <span className="nodrag nopan">
            <DisenchantHover result={result} items={items}>
              {text}
            </DisenchantHover>
          </span>
        ) : (
          <span>{text}</span>
        )}
        <ChoiceMenu label="Change how it is sold" paths={[SELL_PATH]} choices={sellChoices(options, exit)} />
      </div>
      <div className={classes.detail}>
        Gross <Earned copper={revenue} /> · Net <Earned copper={profit} />
      </div>
      {bonus > 0 && <div className={classes.detail}>{bonusNote(bonus)}</div>}
      {exit === 'disenchant' && seller && (
        <div className={classes.detail}>
          <CharacterName name={seller} />
        </div>
      )}
    </div>
  )
}

/** A recipe's reagent tree as a left-to-right flow chart: bought reagents, crafts, mailing, then the sale. With
 * `editing`, nodes with alternatives get a menu of them (Reset and progress are the caller's to show). */
export function RecipeFlow({ result, items, editing }: { result: RankResult; items: ItemMap; editing?: PlanEditing }) {
  const colorScheme = useComputedColorScheme('light')
  const flow = useMemo(() => buildFlow(result), [result])
  const nodeTypes = useMemo<NodeTypes>(
    () => ({
      item: (props: NodeProps<ItemFlowNode>) => <ItemNode {...props} items={items} />,
      mail: MailNode,
      sell: (props: NodeProps<SellFlowNode>) => <SellNode {...props} result={result} items={items} />,
    }),
    [result, items],
  )
  return (
    <ChooseContext.Provider value={editing?.onChoose}>
      <div style={{ height: Math.min(flow.height + PADDING * 2, MAX_HEIGHT) }}>
        <ReactFlow
          nodes={flow.nodes}
          edges={flow.edges}
          nodeTypes={nodeTypes}
          colorMode={colorScheme}
          style={{ background: 'transparent' }}
          fitView
          fitViewOptions={{ padding: `${PADDING}px`, maxZoom: 1 }}
          minZoom={0.3}
          nodesDraggable={false}
          nodesConnectable={false}
          elementsSelectable={false}
          zoomOnScroll={false}
          preventScrolling={false}
          proOptions={{ hideAttribution: true }}
        >
          <Controls showInteractive={false} />
        </ReactFlow>
      </div>
    </ChooseContext.Provider>
  )
}
