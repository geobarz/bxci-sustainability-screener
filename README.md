# bxci-sustainability-screener

A static Quarto dashboard that screens the public holdings of **Blackstone Private
Credit Fund (BCRED, SEC CIK 1803498)** for **sector-level sustainability risk**.
Built in R as a portfolio piece. Published via GitHub Pages from `/docs`.

> **Note on emissions:** the emissions figures are a **sector-level proxy, not
> financed emissions**. They apply sector average emission factors to reported
> holdings. They are not company-reported or attributed emissions.

## Data sources (free and public)
- [SEC BDC Data Sets](https://www.sec.gov/data-research/sec-markets-data/bdc-data-sets): schedule of investments
- [SEC EDGAR APIs](https://www.sec.gov/search-filings/edgar-application-programming-interfaces)
- [EPA Supply Chain GHG Emission Factors](https://www.epa.gov/climateleadership/ghg-emission-factors-hub)

## Folder map
| Folder | Purpose |
|---|---|
| `R/` | Numbered scripts, run in order |
| `data/raw/` | Raw downloads (date-stamped) |
| `data/processed/` | Cleaned data. The dashboard reads only from here |
| `data/reference/` | Reference tables (emission factors, crosswalks) |
| `dashboard/` | Quarto dashboard source |
| `docs/` | Rendered site (GitHub Pages) |
| `docs-notes/DECISIONS.md` | Log of assumptions and why |

## Setup
The SEC asks automated clients to identify themselves. Add this line to your
`.Renviron` file (in RStudio, run `usethis::edit_r_environ()`), then restart R:

```
SEC_USER_AGENT="Your Name your.email@example.com"
```

`.Renviron` is git-ignored, so your details are never committed.

## How to reproduce
_TBD. Steps will be added as scripts are written._

1. Download raw data: _TBD_
2. Clean data: _TBD_
3. Render dashboard: _TBD_
