import { describe, expect, it } from 'vitest'
import { compiled, errors, events } from './helpers.ts'

describe('triplets', () => {
  it('plays three eighths in one beat and marks them as a tuplet', () => {
    const score = compiled('<1_ 1_ 1_> 1 |]')

    expect(events(score).map((event) => event.duration)).toEqual([160, 160, 160, 480])
    expect(score.spans).toEqual([{ type: 'tuplet', actual: 3, normal: 2, from: 'n1', to: 'n3' }])
  })

  it('fills a bar with three quarter-note triplets', () => {
    expect(errors('<1 2 3> |]')).toEqual([])
  })

  it('keeps slurs working inside a triplet', () => {
    expect(compiled('<(1_ 2_ 3_)> 5 |]').spans.map((span) => span.type)).toEqual(['slur', 'tuplet'])
  })

  it('reports nested, unclosed, and stray triplets', () => {
    expect(errors('<1_ <2_ 3_> 5 |]')).toContain('5:5 tuplets cannot be nested')
    expect(errors('<1_ 2_ 3_ 5 |]')).toContain('5:1 a tuplet must close within its measure')
    expect(errors('1 2> |]')).toContain("5:4 '>' closes no tuplet")
  })
})
