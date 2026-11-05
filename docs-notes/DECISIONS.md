# Decisions log

Record every assumption or decision that could affect the analysis or how the site is
published. Add new entries at the bottom and don't delete old ones. If a decision
changes later, add a new entry that supersedes the old one.

| # | Date | Decision | Why | Effect on analysis | Approved by |
|---|---|---|---|---|---|
| 1 | 2026-11-05 | Removed the `docs/` line from `.gitignore` (a leftover from the R template's pkgdown section). | GitHub Pages publishes from `/docs`. With `docs/` ignored, the rendered site would never be committed. | None. Publishing setup only. | User (approved scaffold plan) |
| 2 | 2026-11-05 | Raw BDC ZIPs (and the files extracted from them) are kept on disk but not committed to git. `data/raw/bdc/manifest.csv` (URL, saved file, size, MD5) is committed. Only `soi.tsv`, `sub.tsv`, `readme.htm` and `bdc_metadata.json` are extracted. | The 16 ZIPs total ~480 MB and one unzipped file is >1 GB. GitHub rejects files over 100 MB. The manifest keeps every source file traceable, and `R/01_fetch_sec.R` re-downloads them. | None on numbers. | Claude. Repo setup; tell the user. |
| 3 | 2026-11-05 | Read SOI column "Initial fair value of Investment" as fair value and "Adjusted cost basis" as cost. | In `soi.tsv` the columns labelled "Investment Owned, Fair Value" and "Investment Owned, Cost" are empty for all 169 BDCs in the 2026_08 file. Checked in `num.tsv` (2026_08 ZIP, BCRED 10-Q 0001803498-26-000048): Flash Charm, Inc. \| Verdelite JV LP has InvestmentOwnedAtFairValue = 2,965,000 and InvestmentOwnedAtCost = 3,793,000, matching those two SOI columns. | Determines which column is "fair value" everywhere. | Verified fact. Shown to the user. |
