# Agent guide

The app is developed by agents; the owner reviews behavior, not Swift code. Checks are the safety net.

## Done means checked

Run `scripts/check.sh` after every change. Work is done only when it prints `All checks passed.` It runs, in order:

| Step | Tool | Fails on |
| --- | --- | --- |
| Format | `swift-format` (bundled with Xcode), config `.swift-format` | any formatting difference; fix with `xcrun swift-format format --in-place <files>` |
| Lint | SwiftLint, config `.swiftlint.yml` | errors; warnings (e.g. a function over 40 lines, a file over 200) call for a second look, not a mechanical split |
| Library | `npm run library`: compiles `priv/library` (or, without it, `docs/examples`) into `apps/ios/Dizi/Library/` | a catalog problem or a score with errors |
| Project | XcodeGen | `apps/ios/Dizi.xcodeproj` out of date with `apps/ios/project.yml` |
| Parser and tools | `npm run --workspace packages/parser check`: TypeScript strict, ESLint (strict type-checked), Prettier, Vitest; `npm run check:tools`: the same for `tools/*.ts` | type errors, lint or format issues, failing tests |
| Score examples | the parser recompiles `docs/examples/molihua.jianpu` | `docs/examples/molihua.ir.json` differs from the compiled output |
| ScoreKit tests | `swift test --package-path packages/scorekit` on the Mac | failing unit tests |
| Build and test | `xcodebuild test` on the iOS simulator (`SIMULATOR`, default `iPhone 17e`) | compiler warnings (treated as errors), failing unit or UI tests |

## Code style: functional

Programs are data flowing through transformations; effects stay at the edge. Sources and examples: the study note behind these rules (kept privately) cites Hickey, Normand, Bernhardt, Minsky, Wlaschin, Armstrong, Carmack, and Apple's Swift guidance.

1. **Data, calculations, actions.** Sort code into data (inert values), calculations (pure: same input, same output), and actions (depend on when or how often they run: drawing, audio, files, time, logging). Move logic out of actions into calculations.
2. **Functional core, imperative shell.** `packages/scorekit` is the core and has no effects; the app is a thin shell that reads, paints, and plays the values the core returns. Pass plain values across boundaries.
3. **Values, not places.** `struct` and `enum` with `let`; a change produces a new value. State that changes over time (playhead, settings) has one source of truth and is replaced, not edited in place; everything shown is derived from it. A SwiftUI `body` is a pure function of state.
4. **Purity is judged from outside.** A local `var`, `inout`, or `reduce(into:)` inside a function is fine when no caller can observe it. Never change state you were not given, and never cause effects inside `map`/`filter`/`reduce`.
5. **Pipelines of small transformations.** Prefer `map`, `filter`, `flatMap`, `reduce`; use a plain loop when it is clearer (early exit, several accumulators, sequential `await`, effects at the edge).
6. **Make illegal states unrepresentable.** Use enums with associated values instead of flags, sentinel values, or loose optionals. Decode input into types that only admit valid values ("parse, don't validate").
7. **`switch` is pattern matching.** Use `switch`/`if` as expressions; keep `switch` over our own enums exhaustive with no `default`, so a new case fails the build where it must be handled.
8. **Two kinds of failure.** Expected failures (a downloaded score that does not decode) are values the UI shows: `throws` by default, `Result` only to store an outcome. Programmer errors are not defended against at every step; let them fail fast.
9. **Name by side effect.** Pure functions read as nouns or past participles (`sorted()`, `underlines(…)`); functions with effects read as verbs (`sort()`, `render(…)`).
10. **Pragmatic.** Almost pure beats pure at any cost; mind the cost of copying large values.

## Project facts

- Layout: `apps/` holds runnable products (`apps/ios`; later server, web, android); `packages/` holds shared libraries in any language (`packages/scorekit` Swift, `packages/parser` TypeScript); `tools/` build and one-off scripts; `docs/examples/` the spec's example score and its IR. TypeScript packages are npm workspaces listed explicitly in the root `package.json`.
- `packages/parser` compiles score text ([format](docs/score-format.md)) into the [IR](docs/score-ir.md); Node 24 runs its `.ts` files directly, no build step. `node packages/parser/src/cli.ts <file>` prints the IR or the diagnostics.

- `apps/ios/project.yml` defines the Xcode project; never edit `apps/ios/Dizi.xcodeproj` by hand. Run `xcodegen generate` in `apps/ios/` after changing the spec, and commit both.
- `packages/scorekit` holds the logic that needs no UI: the [score IR](docs/score-ir.md) model and the score layout. Test it with Swift Testing on the Mac; it is fast and needs no simulator. The app draws what ScoreKit computes.
- iOS 26, iPhone only, portrait, Swift 6 with strict concurrency.
- UI text lives in `apps/ios/Dizi/Localizable.xcstrings`, Chinese first. Code, comments, and commits are English; dizi terms are pinyin in code, with the Chinese term in a comment.
- Tests: Swift Testing for logic; XCUITest (`apps/ios/DiziUITests`) for screen-to-screen flows. Write only tests that catch a real regression.

## Scores are data

- The score library is data, not code: it lives in `priv/library/` (`catalog.json` + `<id>.jianpu`; not in git, partly copyrighted) and will be published to OSS. The repository keeps only test and spec fixtures (`docs/examples/`).
- `npm run library` compiles it into `apps/ios/Dizi/Library/` (gitignored), which the app bundles; run it after cloning and after editing scores.

## Assets

- `apps/ios/Dizi/Samples/dizi-c/`: the demo voice, generated by `tools/prepare-samples.py` (Python 3 + numpy) from a CC0 Freesound pack; see its README. Regenerate rather than edit by hand.

## Tools to install

```sh
brew install xcodegen swiftlint
npm install   # at the repository root: the parser's dependencies (Node 24)
```
