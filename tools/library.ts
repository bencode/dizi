// The score library: catalog.json and the pieces it lists, compiled. Shared by build-library and publish-library.
import { createHash } from 'node:crypto'
import { readdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { compile, type Diagnostic, type Score } from '../packages/parser/src/index.ts'

/** A group of the list, in display order: 吐音, 乐曲. Content, so it is data, not app code. */
export type Section = { id: string; title: string }
export type Entry = {
  id: string
  title: string
  /** The id of the section it is listed in. */
  section: string
  /** 1 入门 (course part a), 2 进阶 (part b). */
  level: 1 | 2
  lesson?: number
  /** Pieces sharing a series fold into one card in the app: '双吐练习'. */
  series?: string
  /** Uploaded to OSS by `npm run publish-library`; pieces without it stay private. */
  publish?: true
}
export type Built = { entry: Entry; score: Score }
export type Outcome = {
  sections: Section[]
  built: Built[]
  errors: string[]
  warnings: string[]
}

const isRecord = (value: unknown): value is Record<string, unknown> => typeof value === 'object' && value !== null
const isID = (value: unknown): value is string => typeof value === 'string' && /^[a-z0-9-]+$/.test(value)
const isText = (value: unknown): value is string => typeof value === 'string' && value !== ''
const isLevel = (value: unknown): value is Entry['level'] => value === 1 || value === 2
const isCount = (value: unknown): value is number => Number.isInteger(value) && (value as number) >= 1

const idProblem = (at: string): string => `${at}.id: expected lowercase letters, digits, -`

/** One catalog section checked: the section, or what is wrong with it. */
const parseSection = (value: unknown, at: string): Section | string[] => {
  if (!isRecord(value)) return [`${at}: expected an object`]
  const { id, title } = value
  if (isID(id) && isText(title)) return { id, title }
  return [...(isID(id) ? [] : [idProblem(at)]), ...(isText(title) ? [] : [`${at}.title: expected text`])]
}

/** One catalog piece checked field by field against the catalog's sections: the entry, or what is wrong with it. */
const parseEntry = (value: unknown, at: string, sections: Set<string>): Entry | string[] => {
  if (!isRecord(value)) return [`${at}: expected an object`]
  const { id, title, section, level, lesson, series, publish } = value
  const isSection = (candidate: unknown): candidate is string => isID(candidate) && sections.has(candidate)
  const problems = [
    ...(isID(id) ? [] : [idProblem(at)]),
    ...(isText(title) ? [] : [`${at}.title: expected text`]),
    ...(isSection(section) ? [] : [`${at}.section: ${JSON.stringify(section)} is not a section`]),
    ...(isLevel(level) ? [] : [`${at}.level: expected 1 (入门) or 2 (进阶)`]),
    ...(lesson === undefined || isCount(lesson) ? [] : [`${at}.lesson: expected a lesson number`]),
    ...(series === undefined || (typeof series === 'string' && series !== '') ? [] : [`${at}.series: expected text`]),
    ...(publish === undefined || publish === true ? [] : [`${at}.publish: expected true, or leave it out`]),
  ]
  if (problems.length > 0 || !isID(id) || !isText(title) || !isSection(section) || !isLevel(level)) return problems
  return {
    id,
    title,
    section,
    level,
    ...(isCount(lesson) ? { lesson } : {}),
    ...(typeof series === 'string' && series !== '' ? { series } : {}),
    ...(publish === true ? { publish } : {}),
  }
}

const duplicates = (ids: string[], what: string): string[] =>
  ids.filter((id, index) => ids.indexOf(id) !== index).map((id) => `${what} id '${id}' is used twice`)

/** The values parsed, and the problems of the ones that did not parse. */
const split = <T>(results: (T | string[])[]): { values: T[]; problems: string[] } => ({
  values: results.filter((result): result is T => !Array.isArray(result)),
  problems: results.flatMap((result) => (Array.isArray(result) ? result : [])),
})

/** catalog.json parsed into sections and entries, with every problem found. */
const parseCatalog = (json: unknown): { sections: Section[]; entries: Entry[]; problems: string[] } => {
  const listed = isRecord(json) ? json.sections : undefined
  const pieces = isRecord(json) ? json.pieces : undefined
  if (!Array.isArray(listed) || !Array.isArray(pieces)) {
    return {
      sections: [],
      entries: [],
      problems: ['sections, pieces: expected two lists'],
    }
  }
  const sections = split(listed.map((section, index) => parseSection(section, `sections[${String(index)}]`)))
  const known = new Set(sections.values.map((section) => section.id))
  const entries = split(pieces.map((piece, index) => parseEntry(piece, `pieces[${String(index)}]`, known)))
  return {
    sections: sections.values,
    entries: entries.values,
    problems: [
      ...sections.problems,
      ...duplicates(
        sections.values.map((section) => section.id),
        'section',
      ),
      ...entries.problems,
      ...duplicates(
        entries.values.map((entry) => entry.id),
        'piece',
      ),
    ],
  }
}

const located = (file: string, diagnostic: Diagnostic): string =>
  `${file}:${String(diagnostic.position.line)}:${String(diagnostic.position.column)}: ${diagnostic.message}`

/** Every piece of a library directory compiled, with the catalog's problems and the compiler's diagnostics. */
export const fromLibrary = (directory: string): Outcome => {
  const catalogFile = join(directory, 'catalog.json')
  const { sections, entries, problems } = parseCatalog(JSON.parse(readFileSync(catalogFile, 'utf8')))
  const results = entries.map((entry) => {
    const file = join(directory, `${entry.id}.jianpu`)
    return { entry, file, result: compile(readFileSync(file, 'utf8')) }
  })
  const diagnostics = (severity: Diagnostic['severity']) =>
    results.flatMap(({ file, result }) =>
      result.diagnostics.filter((diagnostic) => diagnostic.severity === severity).map((d) => located(file, d)),
    )
  return {
    sections,
    built: results.flatMap(({ entry, result }) => (result.score === null ? [] : [{ entry, score: result.score }])),
    errors: [...problems.map((problem) => `${catalogFile}: ${problem}`), ...diagnostics('error')],
    warnings: diagnostics('warning'),
  }
}

/** Without a library (a fresh clone), the compiled examples stand in so the app always has pieces. */
export const fromExamples = (root: string): Outcome => {
  const examples = join(root, 'docs/examples')
  const built = readdirSync(examples)
    .filter((name) => name.endsWith('.ir.json'))
    .map((name): Built => {
      const score = JSON.parse(readFileSync(join(examples, name), 'utf8')) as Score
      const id = name.replace('.ir.json', '')
      return {
        entry: {
          id,
          title: score.meta.title ?? id,
          section: 'pieces',
          level: 1,
        },
        score,
      }
    })
  return {
    sections: [{ id: 'pieces', title: '乐曲' }],
    built,
    errors: [],
    warnings: [],
  }
}

const keyText = (score: Score): string => {
  const { tonic, accidental } = score.header.key
  return `1=${accidental === 'flat' ? '♭' : accidental === 'sharp' ? '♯' : ''}${tonic}`
}

const timeText = (score: Score): string => {
  const time = score.measures[0]?.time
  return time === undefined || time === 'free' ? '散板' : `${String(time.beats)}/${String(time.unit)}`
}

const json = (value: unknown): string => `${JSON.stringify(value)}\n`
const hashName = (body: string): string => createHash('sha256').update(body).digest('hex').slice(0, 16)

/**
 * The library as files (docs/library.md): each score named by its content hash, and the catalog that lists them
 * with the sections that have pieces. The app's bundled snapshot and the published library share this layout.
 */
export const listing = (
  sections: Section[],
  built: Built[],
  updated: number,
): { scores: { path: string; body: string }[]; catalog: string } => {
  const scores = built.map(({ score }) => {
    const body = json(score)
    return { path: `scores/${hashName(body)}.json`, body }
  })
  const pieces = built.map(({ entry, score }, index) => ({
    id: entry.id,
    title: entry.title,
    section: entry.section,
    level: entry.level,
    ...(entry.lesson === undefined ? {} : { lesson: entry.lesson }),
    ...(entry.series === undefined ? {} : { series: entry.series }),
    key: keyText(score),
    time: timeText(score),
    score: scores[index]?.path ?? '',
  }))
  const used = sections.filter((section) => built.some(({ entry }) => entry.section === section.id))
  return {
    scores,
    catalog: json({ irVersion: 1, updated, sections: used, pieces }),
  }
}
