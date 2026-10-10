import { describe, expect, it } from 'vitest'
import { compiled, errors, events } from './helpers.ts'

const free = 'key: 1=D\ntime: free\ntempo: 60'

describe('techniques', () => {
  it.each([
    ['@t', { type: 't' }],
    ['@qiang', { type: 'qiang' }],
    ['@die', { type: 'die' }],
    ['@bo', { type: 'bo', direction: 'up' }],
    ['@xiabo', { type: 'bo', direction: 'down' }],
    ['@tr', { type: 'tr' }],
    ['@shanghua', { type: 'slide', direction: 'up' }],
  ])('%s', (written, technique) => {
    expect(events(compiled(`5${written} |]`, free))[0]).toMatchObject({ techniques: [technique] })
  })

  it('turns arguments into pitches', () => {
    const [note] = events(compiled("3@tr(4)@duo(1')@xiahua(5,) |]", free))

    expect(note).toMatchObject({
      techniques: [
        { type: 'tr', to: { degree: 4, octave: 0, semitones: 5 } },
        { type: 'duo', from: { degree: 1, octave: 1, semitones: 12 } },
        { type: 'slide', direction: 'down', from: { degree: 5, octave: -1, semitones: -5 } },
      ],
    })
  })

  it('rejects unknown, uppercase, and misplaced techniques', () => {
    expect(errors('5@T 5@zhong 5@duo 0@tr |]', free)).toEqual([
      '5:2 unknown technique @T',
      '5:6 unknown technique @zhong',
      '5:14 @duo needs a note, such as @duo(5)',
      '5:20 a rest takes only @yanchang, not @tr',
    ])
  })
})
