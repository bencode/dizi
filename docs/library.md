# The published library

The app's pieces are data, published as static files to Aliyun OSS (bucket `upivot-static`, `oss-cn-hangzhou`) and served from `https://g.upivot.cn`. The source is `priv/library/` (not in git); `npm run publish-library` uploads it.

## Layout

```text
upivot-dizi/library/catalog.json               the app's entry point; Cache-Control: public, max-age=300
upivot-dizi/library/scores/<hash>.json         a compiled score (IR); <hash> = first 16 hex digits of its SHA-256;
                                               Cache-Control: public, max-age=31536000, immutable
```

```ts
type Catalog = {
  irVersion: 1 // the IR version of every score listed; an app that cannot read it ignores the catalog
  pieces: {
    id: string
    title: string
    category: 'tones' | 'etude' | 'piece'
    level: 1 | 2 | 3 | 4 // 入门 … 高级
    lesson?: number // the course lesson it comes from
    key: string // as printed: '1=E'
    time: string // as printed: '2/4', or '散板'
    score: string // relative to the catalog: 'scores/3f9a0c…json'
  }[]
}
```

- A changed score gets a new name, so a cached copy is never stale. Old score files stay, so an app holding an older catalog keeps working.
- Scores are uploaded before the catalog, so the catalog never lists a missing file. A score already on OSS is not uploaded again.

## What is published

- A piece is uploaded only when its entry in `priv/library/catalog.json` has `"publish": true`. Without it, the piece stays private: it is bundled in development builds but never uploaded.
- Mark a piece only when it may be distributed publicly: traditional and folk melodies, works whose authors died more than 50 years ago, our own études. Course arrangements and études stay private until permission is given.

## Access

- The bucket is public-read and private-write, and it does not allow anonymous listing. Anyone with a file's URL can read it.
- Unpublished pieces have no file to read. Published scores have unguessable names, but `catalog.json` lists them. This is the phase-1 trade-off; short-lived signed URLs from a server come later.
- Upload keys belong to a RAM sub-account and live only in the repository root's `.env` (gitignored): `OSS_REGION`, `OSS_BUCKET`, `OSS_ACCESS_KEY_ID`, `OSS_ACCESS_KEY_SECRET`, `OSS_UPLOAD_PATH`. The app never holds them.

## Publishing

```sh
npm run publish-library -- --dry-run   # lists the pieces and object keys; touches nothing
npm run publish-library                # uploads, then prints the catalog URL
```

Always do the dry run first and check that the list holds only the pieces meant to be public.
