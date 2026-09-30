import type { FlowNode, RankResult } from '../api/client'

/** A bought reagent; with no `options`, buying it `source` is its only option. */
export const bought = (
  item_id: number,
  name: string,
  quantity: number,
  cost: number,
  source = 'ah',
  options: FlowNode['options'] = [{ key: source, cost, source, via: '', crafter: '', seconds: 0 }],
): FlowNode => ({
  item_id,
  name,
  quantity,
  cost,
  via: '',
  crafts: 0,
  made: 0,
  source,
  crafter: '',
  mail_to: '',
  postage: 0,
  discount: 0,
  seconds: 0,
  options,
  option: source,
  inputs: [],
})

/** Green Robe: 10 linen (AH) + 1 thread (vendor, or 1s 50c on the AH), sold to a vendor for 200 profit
 * (or 175 on the AH). */
export const robeResult: RankResult = {
  recipe_id: 100,
  recipe: 'Green Robe',
  profession: 'Tailoring',
  crafters: ['Tailor Guy'],
  crafter: 'Tailor Guy',
  output_item_id: 3,
  output_name: 'Green Robe',
  output_count: 1,
  cost: 300,
  revenue: 500,
  profit: 200,
  roi: 2 / 3,
  best_exit: 'vendor',
  slow: false,
  days_to_sell: null,
  short: 0,
  postage: 0,
  mail_to: '',
  bonus_output: 0,
  skill_chance: 1,
  skill_ups: 1,
  exits: [
    { kind: 'vendor', value: 500, materials: [], postage: 0, mail_to: '' },
    { kind: 'ah', value: 475, materials: [], postage: 0, mail_to: '' },
  ],
  reagents: [
    { item_id: 1, count: 10 },
    { item_id: 2, count: 1 },
  ],
  steps: [
    { action: 'buy', item_id: 1, name: 'Linen Cloth', quantity: 10, value: -200, via: 'ah', who: '', discount: 0, bonus: 0, seconds: 0, station: '', lead_seconds: 0, paths: ['r.0'] },
    { action: 'buy', item_id: 2, name: 'Coarse Thread', quantity: 1, value: -100, via: 'vendor', who: '', discount: 0, bonus: 0, seconds: 0, station: '', lead_seconds: 0, paths: ['r.1'] },
    { action: 'craft', item_id: 3, name: 'Green Robe', quantity: 1, value: 0, via: 'Green Robe', who: '', discount: 0, bonus: 0, seconds: 0, station: '', lead_seconds: 0, paths: ['r'] },
    { action: 'sell', item_id: 3, name: 'Green Robe', quantity: 1, value: 500, via: 'vendor', who: '', discount: 0, bonus: 0, seconds: 0, station: '', lead_seconds: 0, paths: ['sell'] },
  ],
  tree: {
    item_id: 3,
    name: 'Green Robe',
    quantity: 1,
    cost: 300,
    via: 'Green Robe',
    crafts: 1,
    made: 1,
    source: '',
    crafter: '',
    mail_to: '',
    postage: 0,
    discount: 0,
    seconds: 0,
    options: [],
    option: '',
    inputs: [
      bought(1, 'Linen Cloth', 10, 200),
      bought(2, 'Coarse Thread', 1, 100, 'vendor', [
        { key: 'vendor', cost: 100, source: 'vendor', via: '', crafter: '', seconds: 0 },
        { key: 'ah', cost: 150, source: 'ah', via: '', crafter: '', seconds: 0 },
      ]),
    ],
  },
  sell_options: [
    { kind: 'vendor', profit: 200 },
    { kind: 'ah', profit: 175 },
  ],
  cities: [],
  crafts: 1,
  details: [],
}

/** The robe timed in Orgrimmar (as a session of 10 crafts, though its numbers are one craft's): a 3.5 s craft, a run to the thread seller and back, 1g 23s 45c an hour; quicker
 * in Thunder Bluff. No vendor there sells thread. */
export const timedRobe: RankResult = {
  ...robeResult,
  crafts: 10,
  steps: robeResult.steps.map((s) => (s.action === 'craft' ? { ...s, seconds: 3.5, station: 'anvil' } : s)),
  timing: {
    city: 'Orgrimmar',
    fixed_seconds: 200,
    per_craft_seconds: 2.5,
    total_seconds: 250,
    per_hour: 12345,
    breakdown: { travel: 200, switch: 0, ah: 0, vendor: 0, mail: 0, craft: 50, disenchant: 0 },
    legs: [
      { who: '', from_id: 'ah', from_name: 'Auctioneer', to_id: 'vendor:1', to_name: 'Thread Seller', seconds: 100 },
      { who: '', from_id: 'vendor:1', from_name: 'Thread Seller', to_id: 'ah', to_name: 'Auctioneer', seconds: 100 },
    ],
    unsold: [2],
    missing: [],
    deployed: [],
  },
  cities: [
    { city: 'Orgrimmar', total_seconds: 250, per_hour: 12345, missing: [] },
    { city: 'Thunder Bluff', total_seconds: 60, per_hour: 51234, missing: [] },
  ],
  best_city: 'Thunder Bluff',
}
