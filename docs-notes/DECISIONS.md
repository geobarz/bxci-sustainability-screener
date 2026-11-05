# Decisions log

Record every assumption or decision that could affect the analysis or how the site is
published. Add new entries at the bottom and don't delete old ones. If a decision
changes later, add a new entry that supersedes the old one.

| # | Date | Decision | Why | Effect on analysis | Approved by |
|---|---|---|---|---|---|
| 1 | 2026-11-05 | Removed the `docs/` line from `.gitignore` (a leftover from the R template's pkgdown section). | GitHub Pages publishes from `/docs`. With `docs/` ignored, the rendered site would never be committed. | None. Publishing setup only. | User (approved scaffold plan) |
