# Binky 2.0 — paid transition (internal)

Plan for moving from **free official builds + MIT source** on 1.x to **paid official binaries + optional update renewal** on 2.0, without sneaky lock-in. CleanShot’s framing is the model: **pay once, keep the app, updates are a year then optional**.

---

## Decision framing

- **License shape:** One-time purchase **includes one year of updates**. After that, **optional renewal** (~yearly) extends the update window. **Not a subscription** — the last version you’re entitled to keeps working.
- **Open source:** **MIT stays**. Monetize **signed/notarized binaries**, **hassle-free updates**, and **2.0 feature work** — not the right to read the code.

---

## SKU & pricing (draft)

| SKU | Price (USD) | Notes |
| --- | --- | --- |
| **Binky App License (2.0)** | **$10** anchor | First **2–4 weeks** at **$5** launch promo if you want extra conversion. |
| **Update renewal (Binky)** | **$5 / year** (cap **$7** if support load is high) | Renews **update eligibility** only. |
| **Binky + Dinky bundle (2.0)** | **$15** one-time | Both apps, **one year of updates** for each product’s stream. |
| **Bundle renewal** | **$9 / year** | One renewal for both update streams. |

**Checkout copy (short):**

- *You keep the app. Renewal is only if you want another year of updates.*
- *Not a subscription. Optional renewal. No pressure.*

**Avoid:** calling renewal a “subscription.” Say **update pass** or **renew updates**.

---

## What makes 2.0 “worth paying for”

Keep **trust / safety / calm defaults** in the base experience (Review, stable-file gate, history, undo where macOS allows). Charge for **time saved** and **power** that clearly didn’t exist in 1.x:

1. **Routine depth** — templates / packs (client handoff, creative exports, invoices, “calm desktop” variants), shareable presets.
2. **Smarter batches** — multi-step actions, richer dry-run / simulation reports, batch QA summaries.
3. **Visibility** — weekly digest option, routine health (watcher stuck, permission lost), failure alerts.
4. **Optional online convenience** (only if you want it) — e.g. shareable run logs or stats — **never required** for local sorting.

Do **not** gate: Review, duplicate guard honesty, or “what moved” history.

---

## Bundle with Dinky

- **Positioning:** *Calm + compress* — Binky quietens the inbox; Dinky shrinks what lands in sorted buckets.
- **UX:** Separate product pages + obvious **bundle CTA**; allow **buy one → add the other** with prorated or coupon logic at checkout (implementation TBD with reseller).

---

## Loyalty & existing users

| Audience | Policy (draft) |
| --- | --- |
| **Anyone on Binky 1.x before 2.0 ships** | Grandfathered: **keep using 1.x** as today. No retroactive paywall on that line. |
| **Moving to 2.0** | **Loyalty pricing** for early users: e.g. launch **$5** tier or a **100% discount coupon** for existing MAU (define by build + install date or mailing list / GitHub proof — pick one before launch). |
| **Dinky owners** | **Bundle credit** or **%-off Binky 2.0** when purchased within X days of launch. |
| **Open source / build from source** | MIT remains; state clearly that **official builds** are what the license pays for (and update channel). |

Document the exact eligibility rule in checkout FAQ before launch.

---

## Site & product copy checklist

- [ ] Homepage hero / CTA: **1.x free + MIT**; **2.0 paid official builds** (no surprise).
- [ ] FAQ: licensing trio — *How does 2.0 licensing work?* · *Do I have to renew?* · *I use 1.x — do I pay?*
- [ ] Comparison tables: Binky column = **“1.x free · 2.0 from $10”** (or similar).
- [ ] JSON-LD: two `Offer`s (0 + 10) until 2.0 ships, then revisit.

---

## In-app (minimal)

- Settings → **License** section: plain-language model + link to site FAQ anchor.
- Update banner: small **Licensing…** link next to release notes (optional nag; no modal).

---

## Launch runbook

### Phase 1 — Pre-announce (no paywall)

1. Publish FAQ + pricing page (`binkyfiles.com`) — **planned** wording if needed.
2. Add in-app **License** blurb + Help section.
3. Update README / `llms.txt` / compare pages so “free” isn’t technically wrong.
4. Draft email to existing users + GitHub Discussion: **why**, **what changes**, **what doesn’t**.

### Phase 2 — 2.0 launch

1. Turn on checkout + license keys (or Mac App Store + restore purchases — pick stack).
2. Ship **2.0.0** with first-run **license** pane + **grandfather** detection for 1.x users who stay on old builds.
3. Post changelog + migration guide.

### Phase 3 — First 30 days

1. Track: checkout conversion, refund rate, “I thought it was free” support volume.
2. Tune: **$5 vs $10** anchor, renewal copy, bundle take-rate.
3. Feed learnings back into FAQ.

### Success metrics

- Visitor → checkout (Binky-only vs bundle).
- Renewal page visits / activations.
- Support tickets per 100 sales.
- Sentiment in GitHub Discussions after post.

---

## Related repo paths

- Site: [`site/index.html`](../../site/index.html), [`site/compare/`](../../site/compare/)
- App: [`Binky/PreferencesView.swift`](../../Binky/PreferencesView.swift), [`Binky/Views/UpdateBanner.swift`](../../Binky/Views/UpdateBanner.swift), [`Binky/Resources/en.lproj/Help.md`](../../Binky/Resources/en.lproj/Help.md)

---

*Last updated: 2026-05-03 — aligns with product plan; numbers are draft until checkout is live.*
