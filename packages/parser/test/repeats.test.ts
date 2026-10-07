import { describe, expect, it } from 'vitest'
import { compiled, errors } from './helpers.ts'

describe('repeats and endings', () => {
  it('plays a repeated passage twice', () => {
    const score = compiled('1 2 |: 3 4 | 5 6 :| 7 1 |]')

    expect(score.playOrder).toEqual([0, 1, 2, 1, 2, 3])
    expect(score.measures[1]).toMatchObject({ repeatStart: true })
    expect(score.measures[2]).toMatchObject({ repeatEnd: true })
  })

  it('repeats from the beginning when no repeat is opened', () => {
    expect(compiled('1 2 | 3 4 :| 5 6 |]').playOrder).toEqual([0, 1, 0, 1, 2])
  })

  it('plays the first ending, goes back, then the second', () => {
    // 八月桂花's shape: |: A | B | [1.] C :| [2.] D ||
    const score = compiled('|: 1 2 | 3 4 | [1.] 5 - :| [2.] 1 - ||')

    expect(score.playOrder).toEqual([0, 1, 2, 0, 1, 3])
    expect(score.measures.map((measure) => measure.volta)).toEqual([undefined, undefined, [1], [2]])
  })

  it('carries an ending over several measures and supports a third ending', () => {
    const score = compiled('|: 1 2 | [1.2.] 3 4 | 5 6 :| [3.] 7 1 |]')

    expect(score.measures.map((measure) => measure.volta)).toEqual([undefined, [1, 2], [1, 2], [3]])
    expect(score.playOrder).toEqual([0, 1, 2, 0, 1, 2, 0, 3])
  })

  it('reports measures that no pass plays', () => {
    // An ending outside a repeat: the second pass never comes.
    expect(errors('1 2 | [2.] 3 4 | 5 6 |]')).toEqual([
      '5:16 measure 2 is never played; check its ending [n.] and the repeat signs',
      '5:22 measure 3 is never played; check its ending [n.] and the repeat signs',
    ])
  })

  it('rejects a malformed ending', () => {
    expect(errors('[1.] 1 [2.] 2 |]')).toEqual(['5:8 [2. …] must start a measure'])
  })
})
