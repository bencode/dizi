# Dizi

An iPhone app for practicing the dizi (Chinese bamboo flute) along a score: open a score, set the tempo, and play with a metronome while the screen shows, live, whether each note is high or low.

See [the product](docs/product.md).

## Development

Requires Node 24 (`npm install` at the root), Xcode 27, [XcodeGen](https://github.com/yonaskolb/XcodeGen), and [SwiftLint](https://github.com/realm/SwiftLint):

```sh
brew install xcodegen swiftlint
```

```sh
npm run library     # compile the scores the app bundles (a fresh clone uses docs/examples)
cd apps/ios
xcodegen generate   # after changing project.yml
open Dizi.xcodeproj
```

`apps/ios/project.yml` defines the project; the generated `Dizi.xcodeproj` is committed so it opens without XcodeGen.

Before committing, run every check (format, lint, project sync, build, tests):

```sh
scripts/check.sh
```

See [AGENTS.md](AGENTS.md) for what each check enforces.

## Credits

The demo melody plays the [Salamander Grand Piano V3](https://github.com/sfzinstruments/SalamanderGrandPiano) by Alexander Holm, licensed under [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/); the samples are trimmed, mixed to mono and levelled (see `apps/ios/Dizi/Samples/piano/README.md`).
