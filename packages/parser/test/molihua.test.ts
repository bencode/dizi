import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import { compile } from '../src/index.ts'

describe('spec example', () => {
  it('compiles 茉莉花 without diagnostics', () => {
    const result = compile(readFileSync(new URL('../../../docs/examples/molihua.jianpu', import.meta.url), 'utf8'))

    expect(result.diagnostics).toEqual([])
    expect(result.score?.measures).toHaveLength(27)
  })

  it('reports every error at once and gives no score', () => {
    const result = compile('key: 1=D\ntime: 2/4\ntempo: 60\n\n1 2 3 | 8 | 4@zz 5 |]\n')

    expect(result.score).toBeNull()
    expect(result.diagnostics.map((d) => d.message)).toEqual([
      'measure 1 lasts 3 quarter notes; 2/4 needs 2',
      "unexpected '8'",
      'a measure needs at least one note or rest',
      'unknown technique @zz',
    ])
  })
})
