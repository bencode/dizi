import { describe, expect, it } from 'vitest'
import { compiled, errors } from './helpers.ts'

describe('measures', () => {
  it('reports a measure of the wrong length where its bar line is', () => {
    expect(errors('1 2 | 3 | 4 5 |]')).toEqual(['5:9 measure 2 lasts 1 quarter notes; 2/4 needs 2'])
  })

  it('lets the first (pickup) and the last measure be short', () => {
    expect(errors('5 | 1 2 | 3 |]')).toEqual([])
  })

  it('does not check 散板 and follows a change of time', () => {
    const score = compiled('1 2 3 4 5 | [time 3/4] 1 2 3 | 1 2 3 |]', 'key: 1=D\ntime: free\ntempo: 60')

    expect(score.measures.map((m) => m.time)).toEqual(['free', { beats: 3, unit: 4 }, { beats: 3, unit: 4 }])
  })

  it('needs a final bar line and line breaks only after bar lines', () => {
    expect(errors('1\n2 |]')).toEqual(['5:2 a line must end with a bar line'])
    expect(errors('1 2 | 3 4')).toEqual(['5:9 the score must end with a bar line'])
  })

  it('records where the source breaks its lines', () => {
    expect(compiled('1 2 | 3 4 |\n5 6 | 7 1 |]').layoutHints).toEqual({ lineBreaksAfter: [1] })
  })
})
