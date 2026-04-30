# Publishing testimonials on dinkyfiles.com

Quotes come from [GitHub Discussions](https://github.com/heyderekj/dinky/discussions) (use a **Reviews** category once you create it). Only add entries where the author checked the consent box on the discussion form.

## One-time GitHub setup (repo maintainer)

1. **Settings → General → Features** — enable **Discussions**.
2. **Discussions** (gear next to Categories) → **New category** — e.g. title **Reviews**, format **Open-ended discussion**, description explaining it’s for testimonials. GitHub derives the URL **slug** from the title (often `reviews` for “Reviews”, or `user-reviews` for “User reviews” — it is **not** a field you type separately).
3. **Why “Sorry, we didn’t recognize that category!”?** Links like `discussions/new?category=reviews` only work after that category exists **and** the slug in the URL matches GitHub’s slug exactly. The app and site use plain [`discussions/new`](https://github.com/heyderekj/dinky/discussions/new) so people always get the category picker instead of an error.
4. **Optional deep link:** After the category exists, open it in the sidebar and copy the slug from the address bar (`…/discussions/categories/<slug>`). You can then share `https://github.com/heyderekj/dinky/discussions/new?category=<slug>` in a pinned post or docs if you want one-click pre-selection.
5. Optionally pin a welcome post in the Reviews category with a short intro and link to **New discussion** (same as [`discussions/new`](https://github.com/heyderekj/dinky/discussions/new)).
6. Associate the form in `.github/DISCUSSION_TEMPLATE/review.yml` with the Reviews category in the GitHub UI if prompted (category-specific templates).

## Adding a quote to the site

1. Open a discussion you’re happy to feature (consent checked).
2. Append an object to [`data/testimonials.json`](data/testimonials.json):

| Field | Required | Notes |
|-------|----------|--------|
| `rating` | yes | Integer 1–5 (maps to stars on the page). |
| `quote` | yes | Short testimonial text. |
| `githubUser` | yes | GitHub username — used for the avatar at `https://github.com/<username>.png`. |
| `name` | no | Display name; falls back to `githubUser`. |
| `handle` | no | Shown under the name; if it doesn’t start with `@`, it’s linked as `https://<handle>` unless `handleURL` is set. |
| `handleURL` | no | Overrides the auto link for `handle`. |
| `sourceURL` | no | Link to the discussion; shown as “via GitHub”. |
| `date` | no | For your own records (not rendered today). |

3. Commit and push. Netlify redeploys `site/`; the reviews block appears when the JSON array has at least one entry. An empty array `[]` keeps the section hidden.

Example:

```json
[
  {
    "rating": 5,
    "quote": "Dinky shaved 70% off my hero image without me even thinking about it.",
    "name": "Alex Chen",
    "handle": "alexbuilds.dev",
    "handleURL": "https://alexbuilds.dev",
    "githubUser": "alexc",
    "sourceURL": "https://github.com/heyderekj/dinky/discussions/42",
    "date": "2026-04-18"
  }
]
```
