# CLAUDE.md — Project brief for bxci-sustainability-screener

## Project
A portfolio piece for a Sustainability Associate application at Blackstone Credit &
Insurance (BXCI). It is a **static Quarto dashboard**, published via **GitHub Pages
from `/docs`**, that screens the public holdings of **Blackstone Private Credit Fund
(BCRED, SEC CIK 1803498)** for **sector-level sustainability risk**.

## Rules (follow these on every task)
- **Language: R only** (RStudio + Quarto). No Python. No Shiny server, because GitHub
  Pages only serves static files.
- **Data: free public sources only.**
  - SEC BDC Data Sets (schedule of investments).
  - SEC EDGAR APIs. Send a descriptive User-Agent read from the environment variable
    `SEC_USER_AGENT`, set in the user's `.Renviron`, which git ignores. Never hard-code it.
  - EPA supply-chain GHG emission factors.
- **Never invent, estimate, or "fill in" data.** If something is missing, say so and stop.
- **Traceability:** every number on the dashboard must trace back to a script in `R/`
  and a source file in `data/raw/` or `data/reference/`.
- **Labelling:** always label the emissions metric as
  **"sector-level proxy, not financed emissions."**
- **Beginner-friendly:** comment every script, keep functions small, and after each
  task explain in plain English what was done and how the user can verify it.
- **Ask before assuming.** Ask the user before making any assumption that changes the
  analysis. Log every approved assumption, with the reason, in `docs-notes/DECISIONS.md`.

## Data flow
```
data/raw/        raw downloads, never edited, with date-stamped filenames
                 (e.g. bdc_soi_2026-11-05.zip)
   │  R/ scripts (numbered, run in order)
   ▼
data/processed/  cleaned, analysis-ready files
   │
   ▼
dashboard/       Quarto source. Reads ONLY from data/processed/
   │  quarto render
   ▼
docs/            rendered static site served by GitHub Pages
```

## Folder map
| Folder | Purpose |
|---|---|
| `R/` | Numbered scripts, run in order: `01_download_*.R`, `02_clean_*.R`, `03_…` |
| `data/raw/` | Raw source downloads (date-stamped, untouched) |
| `data/processed/` | Cleaned outputs. The only data the dashboard reads |
| `data/reference/` | Static reference tables (e.g. EPA emission factors, sector crosswalks) |
| `dashboard/` | Quarto dashboard source files |
| `docs/` | Rendered site for GitHub Pages (generated; do not hand-edit) |
| `docs-notes/DECISIONS.md` | Log of each assumption/decision and why |
