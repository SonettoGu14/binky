# Publishing testimonials on binkyfiles.com

Quotes can live in [GitHub Discussions](https://github.com/heyderekj/binky/discussions). Only add entries to the site where the author agreed to be quoted.

## One-time GitHub setup (repo maintainer)

1. **Settings → General → Features** — enable **Discussions** if you want a public place for reviews.
2. Optional: add a **Reviews** (or similar) category and link it from a pinned post.

## Adding a quote to the site

1. Open a discussion you're happy to feature (consent clear).
2. Append an object to [`data/testimonials.json`](data/testimonials.json). See field table in the repo docs.
3. Deploy. The homepage reviews block appears when the JSON array has at least one entry. `[]` keeps it hidden.

Example shape:

```json
[
  {
    "rating": 5,
    "quote": "Downloads finally stopped screaming.",
    "name": "Jordan",
    "githubUser": "jordan",
    "sourceURL": "https://github.com/heyderekj/binky/discussions/1"
  }
]
```
