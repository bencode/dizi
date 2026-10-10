import { describe, expect, it } from 'vitest'
import { compiled, errors, events } from './helpers.ts'

describe('note lengths', () => {
  it.each([
    ['5', 4, 0, 480],
    ['5_', 8, 0, 240],
    ['5__', 16, 0, 120],
    ['5.', 4, 1, 720],
    ['5_.', 8, 1, 360],
    ['5 -', 2, 0, 960],
    ['5 - -', 2, 1, 1440],
    ['5 - - -', 1, 0, 1920],
  ])('%s is value %i with %i dots, %i ticks', (written, value, dots, ticks) => {
    const [note] = events(compiled(`${written} |]`, 'key: 1=D\ntime: free\ntempo: 60'))

    expect(note).toMatchObject({ value, dots, duration: ticks })
  })

  it('rejects lengths no single note can write', () => {
    expect(errors('5 - - - - |]', 'key: 1=D\ntime: free\ntempo: 60')).toEqual([
      '5:1 this length cannot be written as one note; use a tie (… | …) instead',
    ])
  })

  it("lengthens rests with 0s, not '-'", () => {
    expect(errors('0 - |]')).toEqual(["5:3 a rest is lengthened with more 0s, not '-'"])
  })
})
