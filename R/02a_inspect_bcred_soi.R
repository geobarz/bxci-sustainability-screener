# =============================================================================
# 02a_inspect_bcred_soi.R
# -----------------------------------------------------------------------------
# PURPOSE
#   Look at (do not change or save) BCRED's schedule of investments (SOI) from
#   the BDC Data Set files downloaded by R/01_fetch_sec.R. It prints:
#     1. Which BCRED filings (10-K / 10-Q) and period-end dates are available.
#     2. Which SOI columns BCRED actually fills in, and how often.
#     3. 10 sample holdings from the latest filing.
#
# INPUT   data/raw/bdc/manifest.csv and the soi.tsv files it points to.
# OUTPUT  Printed to the console only. Nothing is written to disk.
#
# HOW TO RUN
#   From the project root:  Rscript R/02a_inspect_bcred_soi.R
#   Takes about a minute (it reads ~16 files of 30-110 MB each).
#
# TWO THINGS TO KNOW ABOUT soi.tsv (see docs-notes/DECISIONS.md)
#   a) Column labels. In these files the columns "Investment Owned, Fair Value"
#      and "Investment Owned, Cost" are empty for every BDC. The values sit in
#      columns the SEC labelled "Initial fair value of Investment" (= XBRL tag
#      InvestmentOwnedAtFairValue) and "Adjusted cost basis" (= XBRL tag
#      InvestmentOwnedAtCost). Checked against num.tsv for the 2026-06-30 10-Q.
#   b) Row types. Rows that name a single investment ("Investment, Identifier
#      Axis") carry no industry. Industry appears only on subtotal rows
#      ("Industry Sector Axis"), which BCRED tags by industry and investment type.
# =============================================================================

suppressPackageStartupMessages({
  library(readr)   # reading the tab-separated files
  library(dplyr)   # filtering and summarising tables
  library(fs)      # file paths
})

BCRED_CIK   <- "1803498"
RAW_BDC_DIR <- path("data", "raw", "bdc")
options(width = 200)

# SOI label as written by the SEC  ->  short name we use, and the XBRL tag behind it.
COLUMN_LABELS <- c(
  "Initial fair value of Investment"            = "fair_value",       # InvestmentOwnedAtFairValue
  "Adjusted cost basis"                         = "cost",             # InvestmentOwnedAtCost
  "Investment Owned, Balance, Principal Amount" = "principal",        # InvestmentOwnedBalancePrincipalAmount
  "Investment Owned, Net Assets, Percentage"    = "pct_net_assets",   # InvestmentOwnedPercentOfNetAssets
  "Investment Interest Rate"                    = "interest_rate",    # InvestmentInterestRate
  "Investment, Basis Spread, Variable Rate"     = "spread",           # InvestmentBasisSpreadVariableRate
  "Investment Maturity Date"                    = "maturity_date",
  "Investment, Identifier Axis"                 = "investment",
  "Industry Sector Axis"                        = "industry",
  "Investment Type Axis"                        = "investment_type",
  "Investment, Issuer Affiliation Axis"         = "affiliation",
  "Legal Entity Axis"                           = "legal_entity"
)


# ---- Helper: read BCRED's rows from one soi.tsv -----------------------------
# Every column is read as text so nothing is silently converted or rounded.
# quote = "" because the SEC files are plain tab-separated with no quoting.
read_bcred_soi <- function(soi_file, zip_name) {
  soi <- suppressWarnings(
    read_tsv(soi_file, col_types = cols(.default = col_character()),
             quote = "", na = "", progress = FALSE)
  )

  # A few lines in some files have more fields than the header (the SEC's own
  # parsing issue). Report any that belong to BCRED so they are not missed.
  bad_rows <- unique(problems(soi)$row)
  bad_bcred <- sum(soi$cik[bad_rows] == BCRED_CIK, na.rm = TRUE)
  if (bad_bcred > 0) warning(zip_name, ": ", bad_bcred, " BCRED rows are malformed")

  soi <- soi[soi$cik == BCRED_CIK, ]
  soi$source_zip <- zip_name   # remember which file each row came from
  soi$malformed_rows_in_file_for_bcred <- bad_bcred
  soi
}


# ---- Helper: drop columns that are empty for every BCRED row ----------------
drop_empty_columns <- function(df) {
  df[, colSums(!is.na(df)) > 0, drop = FALSE]
}


# ---- Helper: label each row as a holding, a subtotal, or other --------------
add_row_type <- function(df) {
  df$row_type <- case_when(
    !is.na(df$investment) ~ "holding",           # one named investment
    !is.na(df$industry)   ~ "industry_subtotal", # total for an industry (x type)
    TRUE                  ~ "other"              # derivatives, totals, cash, etc.
  )
  df
}


# ---- 1. Load BCRED's rows from every downloaded ZIP -------------------------
manifest <- read_csv(path(RAW_BDC_DIR, "manifest.csv"), show_col_types = FALSE)

bcred <- bind_rows(lapply(seq_len(nrow(manifest)), function(i) {
  soi_file <- path(path_ext_remove(manifest$saved_as[i]), "soi.tsv")
  if (!file_exists(soi_file)) stop("Missing ", soi_file, " - run R/01_fetch_sec.R first.")
  read_bcred_soi(soi_file, manifest$zip[i])
}))
bcred <- drop_empty_columns(bcred)

# Give the key columns short names (only the ones that exist).
present <- intersect(names(COLUMN_LABELS), names(bcred))
bcred <- rename(bcred, !!!setNames(present, COLUMN_LABELS[present]))
bcred <- add_row_type(bcred)

cat("\nTotal BCRED rows across all files:", nrow(bcred), "\n")


# ---- 2. Which filings and period-end dates are available? -------------------
# Each filing reports holdings for its own period end (ddate == period) and,
# for comparison, the previous year end (ddate earlier than period).
filings <- bcred |>
  group_by(form, period, filed, adsh, source_zip) |>
  summarise(
    holdings_this_period   = sum(ddate == period & row_type == "holding"),
    with_fair_value        = sum(ddate == period & row_type == "holding" & !is.na(fair_value)),
    industry_subtotals     = sum(ddate == period & row_type == "industry_subtotal"),
    rows_prior_period      = sum(ddate != period),
    malformed_bcred_rows   = first(malformed_rows_in_file_for_bcred),
    .groups = "drop"
  ) |>
  arrange(desc(period))

cat("\n===== 1. BCRED filings found in the SOI data =====\n")
print(as.data.frame(filings), row.names = FALSE)


# ---- 3. Which columns does BCRED use? ---------------------------------------
# Share of BCRED rows (all filings) where each column has a value.
column_fill <- bcred |>
  select(-source_zip, -malformed_rows_in_file_for_bcred, -row_type) |>
  summarise(across(everything(), \(x) round(100 * mean(!is.na(x)), 1))) |>
  tidyr::pivot_longer(everything(), names_to = "column", values_to = "pct_rows_filled") |>
  arrange(desc(pct_rows_filled))

cat("\n===== 2. SOI columns BCRED fills in (", nrow(column_fill), " columns) =====\n", sep = "")
print(as.data.frame(column_fill), row.names = FALSE)


# ---- 4. Ten sample holdings from the latest filing --------------------------
# A fixed seed makes the "random" sample the same every time you run this.
latest_period <- max(bcred$period)
show_cols <- intersect(c("investment", "investment_type", "industry", "principal", "cost",
                         "fair_value", "pct_net_assets", "interest_rate", "spread",
                         "maturity_date", "ddate", "form", "adsh"), names(bcred))

holdings_latest <- bcred |>
  filter(period == latest_period, ddate == period, row_type == "holding")

set.seed(42)
sample_rows <- holdings_latest[sample(nrow(holdings_latest), min(10, nrow(holdings_latest))), show_cols]

cat("\n===== 3. 10 sample holdings, period end", latest_period, "=====\n")
print(as.data.frame(sample_rows), row.names = FALSE)

# And a few industry subtotal rows, so you can see where industry lives.
cat("\n===== 3b. 5 sample industry subtotal rows, period end", latest_period, "=====\n")
subtotals <- bcred |>
  filter(period == latest_period, ddate == period, row_type == "industry_subtotal")
print(as.data.frame(head(subtotals[, intersect(c("industry", "investment_type", "affiliation",
  "legal_entity", "cost", "fair_value", "pct_net_assets"), names(bcred))], 5)), row.names = FALSE)
