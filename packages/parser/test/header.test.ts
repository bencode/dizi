import { describe, expect, it } from 'vitest'
import { compile } from '../src/index.ts'

describe('header', () => {
  it('reads key, time, tempo, and optional fields', () => {
    const result = compile('title: 茉莉花\nkey: 1=bB\ntime: 6/8\ntempo: 4.=60\nfingering: 2,\n\n1_ 2_ 3_ 4_ 5_ 6_ |]\n')

    expect(result.score?.meta).toEqual({ title: '茉莉花' })
    expect(result.score?.header).toEqual({
      key: { tonic: 'B', accidental: 'flat' },
      fingering: { degree: 2, octave: -1 },
    })
    expect(result.score?.measures[0]?.time).toEqual({ beats: 6, unit: 8 })
    expect(result.score?.marks[0]).toEqual({ kind: 'tempo', at: 0, beat: 720, bpm: 60 })
  })

  it('reports missing and invalid fields, and warns about unknown ones', () => {
    const result = compile('key: 1=H\ntime: 2/4\ncolor: red\n\n1 2 |]\n')

    expect(result.score).toBeNull()
    expect(result.diagnostics.map((d) => `${d.severity} ${d.message}`)).toEqual([
      "error missing field 'tempo'",
      "error invalid key '1=H'; expected 1=<letter>, such as 1=D or 1=bB",
      "warning unknown field 'color' is ignored",
    ])
  })
})
