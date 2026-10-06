import { describe, expect, it } from 'vitest'
import { characters } from '../test/status'
import { parseProfitPath, professionSlug, profitPath, realmSlug, resolveRun, runPath, type ProfitView } from './profitRoute'

describe('the Profit page paths', () => {
  it('reads each view from its path', () => {
    expect(parseProfitPath('/profit')).toEqual({ kind: 'start' })
    expect(parseProfitPath('/profit/')).toEqual({ kind: 'start' })
    expect(parseProfitPath('/profit/gold')).toEqual({ kind: 'gold' })
    expect(parseProfitPath('/profit/skill')).toEqual({ kind: 'skill' })
    expect(parseProfitPath('/profit/skill/dreamscythe-horde/Frell/first-aid')).toEqual({
      kind: 'run',
      realm: 'dreamscythe-horde',
      character: 'Frell',
      profession: 'first-aid',
    })
  })

  it('means nothing by any other path under it', () => {
    for (const path of ['/profit/nope', '/profit/gold/x', '/profit/skill/r/c', '/profit/skill/r//p', '/profit/skill/r/%E0/p']) {
      expect(parseProfitPath(path)).toBeNull()
    }
  })

  it('writes each view as the path it reads back from', () => {
    const views: ProfitView[] = [
      { kind: 'start' },
      { kind: 'gold' },
      { kind: 'skill' },
      { kind: 'run', realm: 'classic-beta-pve-horde', character: 'Ëlf Guy', profession: 'tailoring' },
    ]
    for (const view of views) expect(parseProfitPath(profitPath(view))).toEqual(view)
  })

  it('names realms and professions as lower-case words joined by dashes', () => {
    expect(realmSlug({ realm: 'Dreamscythe', faction: 'Horde' })).toBe('dreamscythe-horde')
    expect(realmSlug({ realm: "Mograine's Rest", faction: '' })).toBe('mograine-s-rest')
    expect(professionSlug('First Aid')).toBe('first-aid')
    expect(runPath({ realm: 'Classic Beta PvE', faction: 'Horde' }, 'Tailor Guy', 'Tailoring')).toBe(
      '/profit/skill/classic-beta-pve-horde/Tailor%20Guy/tailoring',
    )
  })
})

describe('resolveRun', () => {
  const run = (realm: string, character: string, profession: string) =>
    ({ kind: 'run', realm, character, profession }) as const

  it('finds the group, profession and character a path names, ignoring case', () => {
    const found = resolveRun(run('classic-beta-pve-horde', 'tailor guy', 'Tailoring'), characters.groups)
    expect(found?.group.realm).toBe('Classic Beta PvE')
    expect(found?.choice.name).toBe('Tailoring')
    expect(found?.holder.name).toBe('Tailor Guy')
    expect(found?.professions.map((p) => p.name)).toEqual(['Cooking', 'Tailoring'])
  })

  it('finds nothing for another realm, character or profession', () => {
    expect(resolveRun(run('dreamscythe-horde', 'Tailor Guy', 'tailoring'), characters.groups)).toBeNull()
    expect(resolveRun(run('classic-beta-pve-horde', 'Frell', 'tailoring'), characters.groups)).toBeNull()
    expect(resolveRun(run('classic-beta-pve-horde', 'Tailor Guy', 'alchemy'), characters.groups)).toBeNull()
    // a profession without recipes in this version isn't one to skill up
    expect(resolveRun(run('classic-beta-pve-horde', 'Tailor Guy', 'cooking'), characters.groups, ['Tailoring'])).toBeNull()
  })
})
