import { describe, expect, it } from 'vitest'
import { compiled, errors, events } from './helpers.ts'

const free = 'key: 1=D\ntime: free\ntempo: 60'

describe('graces, slurs, breaths, sections, beams', () => {
  it('attaches graces to the note they touch', () => {
    const [first, second] = events(compiled("{6}5 3{2'} |]", free))

    expect(first).toMatchObject({ graces: [{ position: 'before', pitches: [{ degree: 6 }] }] })
    expect(second).toMatchObject({ graces: [{ position: 'after', pitches: [{ degree: 2, octave: 1 }] }] })
    expect(errors('5 {6} 3 |]', free)).toEqual(['5:3 grace notes must touch exactly one note'])
  })

  it('pairs slurs, and makes two equal notes a tie', () => {
    expect(compiled('(1 2 3) (5 | 5) |]', free).spans).toEqual([
      { type: 'slur', from: 'n1', to: 'n3' },
      { type: 'tie', from: 'n4', to: 'n5' },
    ])
    expect(errors('(1 (2 3) |]', free)).toEqual(['5:4 slurs cannot be nested'])
    expect(errors('1 2) |]', free)).toEqual(["5:4 ')' closes no slur"])
    expect(errors('(1 2 |]', free)).toEqual(["5:1 a slur '(' is never closed"])
  })

  it('marks breaths, sections, and changes of tempo where they fall', () => {
    const marks = compiled('[section 引子] 1 v 2 | [tempo 4.=90] 3 V 4 |]').marks

    expect(marks).toEqual([
      { kind: 'tempo', at: 0, beat: 480, bpm: 60 },
      { kind: 'section', at: 0, label: '引子' },
      { kind: 'breath', at: 480, style: 'normal' },
      { kind: 'tempo', at: 960, beat: 720, bpm: 90 },
      { kind: 'breath', at: 1440, style: 'circular' },
    ])
  })

  it('beams short notes within a beat, at each level', () => {
    const measure = (body: string, header?: string) => compiled(body, header).parts[0]?.measures[0]?.beams

    expect(measure('3 3_ 5_ |]')).toEqual([{ level: 1, from: 'n2', to: 'n3' }])
    expect(measure('1__ 2__ 3_ 4_ 5_ |]')).toEqual([
      { level: 1, from: 'n1', to: 'n3' },
      { level: 1, from: 'n4', to: 'n5' },
      { level: 2, from: 'n1', to: 'n2' },
    ])
    expect(measure('1_ 2_ 3_ 4_ 5_ 6_ |]', 'key: 1=D\ntime: 6/8\ntempo: 60')).toEqual([
      { level: 1, from: 'n1', to: 'n3' },
      { level: 1, from: 'n4', to: 'n6' },
    ])
  })
})
