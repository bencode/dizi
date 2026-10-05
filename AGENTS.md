# Agent guide

The app is developed by agents; the owner reviews behavior, not Swift code. Checks are the safety net.

## Done means checked

Run `scripts/check.sh` after every change. Work is done only when it prints `All checks passed.` It runs, in order:

| Step | Tool | Fails on |
| --- | --- | --- |
| Format | `swift-format` (bundled with Xcode), config `.swift-format` | any formatting difference; fix with `xcrun swift-format format --in-place <files>` |
| Lint | SwiftLint, config `.swiftlint.yml` | errors; warnings (e.g. a function over 40 lines, a file over 200) call for a second look, not a mechanical split |
| ScoreKit tests | `swift test --package-path Packages/ScoreKit` on the Mac | failing unit tests |
| Project | XcodeGen | `App/Dizi.xcodeproj` out of date with `App/project.yml` |
| Build and test | `xcodebuild test` on the iOS simulator (`SIMULATOR`, default `iPhone 17e`) | compiler warnings (treated as errors), failing unit or UI tests |

## Code style: functional

Write code the Elixir / Clojure way: **data in, transformations, data out**.

- **Immutable values**: `struct` and `enum` with `let`; build new values instead of mutating.
- **Results by return value, not side effects**: a function computes and returns; it does not change state it was not given.
- **Pure core, thin effectful edge**: layout, decoding, and timing are pure functions (testable); only the edges paint, play audio, read files, or log. Example: layout items map to `Ink` values purely; the `Canvas` only paints them.
- **Collections through `map`, `filter`, `flatMap`, `reduce`**, not `for` loops with `var` accumulators. Never mutate outside state inside a `map`.
- **`switch` is pattern matching**: use it as an expression returning a value, and keep it exhaustive (no `default` on our own enums) so a new case breaks the build where it must be handled. A `switch` statement only at the edge, where each branch is an effect.
- `for` loops only for effects at the edge (painting, I/O).

## Project facts

- `App/project.yml` defines the Xcode project; never edit `App/Dizi.xcodeproj` by hand. Run `xcodegen generate` in `App/` after changing the spec, and commit both.
- `Packages/ScoreKit` holds the logic that needs no UI: the [score IR](docs/score-ir.md) model and the score layout. Test it with Swift Testing on the Mac; it is fast and needs no simulator. The app draws what ScoreKit computes.
- iOS 26, iPhone only, portrait, Swift 6 with strict concurrency.
- UI text lives in `App/Dizi/Localizable.xcstrings`, Chinese first. Code, comments, and commits are English; dizi terms are pinyin in code, with the Chinese term in a comment.
- Tests: Swift Testing for logic; XCUITest (`App/DiziUITests`) for screen-to-screen flows. Write only tests that catch a real regression.

## Tools to install

```sh
brew install xcodegen swiftlint
```
