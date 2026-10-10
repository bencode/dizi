// The score library: catalog.json and the pieces it lists, compiled. Shared by build-library and publish-library.
import { createHash } from 'node:crypto'
import { existsSync, readdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { compile, type Diagnostic, type Score } from '../packages/parser/src/index.ts'

/** A group of the list, in display order: 吐音, 乐曲. Content, so it is data, not app code. */
export type Section = { id: string; title: string; kind: SectionKind }
/** The app tab a section shows in. The tabs are app structure, so the set is closed. */
export type SectionKind = 'practice' | 'repertoire'
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

/** The 词典 (dictionary.json): entries to look up, and the fingering table their charts are drawn from. */
export type Dictionary = {
  categories: { id: string; title: string }[]
  /** One per pitch: `above` is semitones above the tube note; holes from the blow hole down, x / o / h (half). */
  fingerings: { above: number; holes: string; breath: 'gentle' | 'strong' | 'over'; or?: string[] }[]
  entries: {
    id: string
    title: string
    category: string
    aliases: string[]
    text: string
    /** A fingering chart for this tube note: { degree: 5, octave: -1 } is 筒音作5̣. */
    chart?: { degree: number; octave: number }
  }[]
}
const emptyDictionary: Dictionary = { categories: [], fingerings: [], entries: [] }

export type Outcome = {
  sections: Section[]
  dictionary: Dictionary
  built: Built[]
  errors: string[]
  warnings: string[]
}

const isRecord = (value: unknown): value is Record<string, unknown> => typeof value === 'object' && value !== null
const isID = (value: unknown): value is string => typeof value === 'string' && /^[a-z0-9-]+$/.test(value)
const isText = (value: unknown): value is string => typeof value === 'string' && value !== ''
const isKind = (value: unknown): value is SectionKind => value === 'practice' || value === 'repertoire'
const isLevel = (value: unknown): value is Entry['level'] => value === 1 || value === 2
const isCount = (value: unknown): value is number => Number.isInteger(value) && (value as number) >= 1

const idProblem = (at: string): string => `${at}.id: expected lowercase letters, digits, -`

/** One catalog section checked: the section, or what is wrong with it. */
const parseSection = (value: unknown, at: string): Section | string[] => {
  if (!isRecord(value)) return [`${at}: expected an object`]
  const { id, title, kind } = value
  if (isID(id) && isText(title) && isKind(kind)) return { id, title, kind }
  return [
    ...(isID(id) ? [] : [idProblem(at)]),
    ...(isText(title) ? [] : [`${at}.title: expected text`]),
    ...(isKind(kind) ? [] : [`${at}.kind: expected practice or repertoire`]),
  ]
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
  ids.filter((id, index) => ids.indexOf(id) !== index).map((id) => `${what} '${id}' is used twice`)

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
        'section id',
      ),
      ...entries.problems,
      ...duplicates(
        entries.values.map((entry) => entry.id),
        'piece id',
      ),
    ],
  }
}

const isHoles = (value: unknown): value is string => typeof value === 'string' && /^[xoh]{6}$/.test(value)
const isBreath = (value: unknown): value is Dictionary['fingerings'][number]['breath'] =>
  value === 'gentle' || value === 'strong' || value === 'over'
const isTube = (value: unknown): value is { degree: number; octave: number } =>
  isRecord(value) &&
  Number.isInteger(value.degree) &&
  (value.degree as number) >= 1 &&
  (value.degree as number) <= 7 &&
  Number.isInteger(value.octave)
const isTexts = (value: unknown): value is string[] => Array.isArray(value) && value.every(isText)

const parseFingering = (value: unknown, at: string): Dictionary['fingerings'][number] | string[] => {
  if (!isRecord(value)) return [`${at}: expected an object`]
  const { above, holes, breath, or } = value
  const alternatives = or === undefined ? [] : or
  const isAbove = isCount(above) || above === 0
  const isOr = Array.isArray(alternatives) && alternatives.every(isHoles)
  if (isAbove && above <= 36 && isHoles(holes) && isBreath(breath) && isOr) {
    return { above, holes, breath, ...(alternatives.length === 0 ? {} : { or: alternatives }) }
  }
  return [
    ...(isAbove && above <= 36 ? [] : [`${at}.above: expected semitones above the tube, 0–36`]),
    ...(isHoles(holes) && isOr ? [] : [`${at}.holes: expected six of x (closed), o (open), h (half)`]),
    ...(isBreath(breath) ? [] : [`${at}.breath: expected gentle, strong or over`]),
  ]
}

const parseDictionaryEntry = (
  value: unknown,
  at: string,
  categories: Set<string>,
): Dictionary['entries'][number] | string[] => {
  if (!isRecord(value)) return [`${at}: expected an object`]
  const { id, title, category, aliases, text, chart } = value
  const isCategory = (candidate: unknown): candidate is string => isID(candidate) && categories.has(candidate)
  if (isID(id) && isText(title) && isCategory(category) && isTexts(aliases) && isText(text)) {
    if (chart === undefined) return { id, title, category, aliases, text }
    if (isTube(chart))
      return { id, title, category, aliases, text, chart: { degree: chart.degree, octave: chart.octave } }
  }
  return [
    ...(isID(id) ? [] : [idProblem(at)]),
    ...(isText(title) ? [] : [`${at}.title: expected text`]),
    ...(isCategory(category) ? [] : [`${at}.category: ${JSON.stringify(category)} is not a category`]),
    ...(isTexts(aliases) ? [] : [`${at}.aliases: expected a list of texts`]),
    ...(isText(text) ? [] : [`${at}.text: expected text`]),
    ...(chart === undefined || isTube(chart) ? [] : [`${at}.chart: expected { degree: 1–7, octave }`]),
  ]
}

/** dictionary.json parsed, with every problem found. */
const parseDictionary = (json: unknown): { dictionary: Dictionary; problems: string[] } => {
  const { categories: listed, fingerings: table, entries: listedEntries } = isRecord(json) ? json : {}
  if (!Array.isArray(listed) || !Array.isArray(table) || !Array.isArray(listedEntries)) {
    return { dictionary: emptyDictionary, problems: ['categories, fingerings, entries: expected three lists'] }
  }
  const categories = split(
    listed.map((category, index) => {
      const at = `categories[${String(index)}]`
      if (isRecord(category) && isID(category.id) && isText(category.title)) {
        return { id: category.id, title: category.title }
      }
      return [`${at}: expected { id, title }`]
    }),
  )
  const known = new Set(categories.values.map((category) => category.id))
  const fingerings = split(table.map((row, index) => parseFingering(row, `fingerings[${String(index)}]`)))
  const entries = split(
    listedEntries.map((entry, index) => parseDictionaryEntry(entry, `entries[${String(index)}]`, known)),
  )
  return {
    dictionary: { categories: categories.values, fingerings: fingerings.values, entries: entries.values },
    problems: [
      ...categories.problems,
      ...duplicates(
        categories.values.map((category) => category.id),
        'category id',
      ),
      ...fingerings.problems,
      ...duplicates(
        fingerings.values.map((row) => String(row.above)),
        'fingering above',
      ),
      ...entries.problems,
      ...duplicates(
        entries.values.map((entry) => entry.id),
        'entry id',
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
  const dictionaryFile = join(directory, 'dictionary.json')
  const { dictionary, problems: dictionaryProblems } = existsSync(dictionaryFile)
    ? parseDictionary(JSON.parse(readFileSync(dictionaryFile, 'utf8')))
    : { dictionary: emptyDictionary, problems: [] }
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
    dictionary,
    built: results.flatMap(({ entry, result }) => (result.score === null ? [] : [{ entry, score: result.score }])),
    errors: [
      ...problems.map((problem) => `${catalogFile}: ${problem}`),
      ...dictionaryProblems.map((problem) => `${dictionaryFile}: ${problem}`),
      ...diagnostics('error'),
    ],
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
    sections: [{ id: 'pieces', title: '乐曲', kind: 'repertoire' }],
    dictionary: emptyDictionary,
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
 * with the sections that have pieces, and the dictionary. The app's bundled snapshot and the published library
 * share this layout.
 */
export const listing = (
  { sections, dictionary }: { sections: Section[]; dictionary: Dictionary },
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
    catalog: json({ irVersion: 1, updated, sections: used, pieces, dictionary }),
  }
}
