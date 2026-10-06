import { describe, expect, it } from 'vitest'
import { hammer, helm, makeItem, robe } from '../test/items'
import {
  armorText,
  bindingText,
  classWord,
  damageLine,
  dpsText,
  iconUrl,
  slotLine,
  speedText,
  splitMoney,
  zoneMapUrl,
} from './wow'

describe('wow helpers', () => {
  it('splits copper into coins from the largest non-zero one down', () => {
    expect(splitMoney(21605)).toEqual([
      { unit: 'gold', amount: 2 },
      { unit: 'silver', amount: 16 },
      { unit: 'copper', amount: 5 },
    ])
    expect(splitMoney(10004)).toEqual([
      { unit: 'gold', amount: 1 },
      { unit: 'silver', amount: 0 },
      { unit: 'copper', amount: 4 },
    ])
    expect(splitMoney(500)).toEqual([
      { unit: 'silver', amount: 5 },
      { unit: 'copper', amount: 0 },
    ])
    expect(splitMoney(30)).toEqual([{ unit: 'copper', amount: 30 }])
    expect(splitMoney(0)).toEqual([{ unit: 'copper', amount: 0 }])
  })

  it('leaves out copper from 100 gold and silver from 10000 gold', () => {
    expect(splitMoney(999999)).toEqual([
      { unit: 'gold', amount: 99 },
      { unit: 'silver', amount: 99 },
      { unit: 'copper', amount: 99 },
    ])
    expect(splitMoney(1234567)).toEqual([
      { unit: 'gold', amount: 123 },
      { unit: 'silver', amount: 45 },
    ])
    expect(splitMoney(1000099)).toEqual([
      { unit: 'gold', amount: 100 },
      { unit: 'silver', amount: 0 },
    ])
    expect(splitMoney(123456789)).toEqual([{ unit: 'gold', amount: 12345 }])
  })

  it('builds icon urls', () => {
    expect(iconUrl('inv_fabric_linen_01', 'large')).toBe(
      'https://wow.zamimg.com/images/wow/icons/large/inv_fabric_linen_01.jpg',
    )
  })

  it('names a zone map by its area id among the served maps', () => {
    expect(zoneMapUrl(1637)).toBe('/maps/1637.jpg')
  })

  it('names bindings', () => {
    expect(bindingText(2)).toBe('Binds when equipped')
    expect(bindingText(0)).toBeUndefined()
  })

  it('builds the slot line', () => {
    expect(slotLine(robe)).toEqual({ left: 'Chest', right: 'Cloth' })
    expect(slotLine({ ...robe, inventory_type: 16 })).toEqual({
      left: 'Back',
      right: undefined,
    })
    expect(slotLine({ ...robe, subclass_name: 'Miscellaneous', inventory_type: 11 })).toEqual({
      left: 'Finger',
      right: undefined,
    })
    const bag = makeItem({
      id: 9,
      name: 'Bag',
      class_id: 1,
      subclass_name: 'Herb Bag',
      container_slots: 12,
    })
    expect(slotLine(bag)).toEqual({ left: '12 Slot Herb Bag' })
    expect(slotLine(makeItem({ id: 1, name: 'Linen Cloth' }))).toBeUndefined()
  })

  it('shows weapon speed', () => {
    const sword = makeItem({
      id: 5,
      name: 'Sword',
      class_id: 2,
      item_delay: 2500,
      inventory_type: 13,
    })
    expect(speedText(sword)).toBe('Speed 2.50')
    expect(speedText(robe)).toBeUndefined()
  })

  it('shows weapon damage and dps once ingested, and armor', () => {
    expect(damageLine(hammer)).toEqual({
      left: '46 - 86 Damage',
      right: 'Speed 2.80',
    })
    expect(dpsText(hammer)).toBe('(23.6 damage per second)')
    expect(damageLine({ ...hammer, dmg_min: 0, dmg_max: 0, dps: 0 })).toBeUndefined()
    expect(dpsText(robe)).toBeUndefined()
    expect(armorText(helm)).toBe('565 Armor')
    expect(armorText(hammer)).toBeUndefined()
  })
})

describe('classWord', () => {
  it('words a class file as said in a sentence', () => {
    expect(classWord('MAGE')).toBe('mage')
    expect(classWord('DEATHKNIGHT')).toBe('death knight')
    expect(classWord('DEMONHUNTER')).toBe('demon hunter')
  })
})
