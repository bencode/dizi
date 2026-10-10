export type Position = { line: number; column: number }

export type Diagnostic = {
  severity: 'error' | 'warning'
  position: Position
  /** English, written to be handed back to a model as well as read by a person. */
  message: string
}

export const error = (position: Position, message: string): Diagnostic => ({ severity: 'error', position, message })

export const warning = (position: Position, message: string): Diagnostic => ({ severity: 'warning', position, message })

export const hasErrors = (diagnostics: readonly Diagnostic[]): boolean =>
  diagnostics.some((diagnostic) => diagnostic.severity === 'error')

export const byPosition = (a: Diagnostic, b: Diagnostic): number =>
  a.position.line - b.position.line || a.position.column - b.position.column
