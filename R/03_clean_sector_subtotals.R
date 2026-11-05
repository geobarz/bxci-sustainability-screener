# =============================================================================
# 03_clean_sector_subtotals.R
# -----------------------------------------------------------------------------
# PURPOSE
#   Build BCRED's fair value by industry sector for every filing, from the
#   industry subtotal rows BCRED tags in its schedule of investments, and check
#   them against BCRED's reported total investments.
#
# RULES APPLIED (see docs-notes/DECISIONS.md)
#   #3  Fair value = SOI column "Initial fair value of Investment".
#   #4  Use industry subtotal rows, not individual holdings.
#   #5  BCRED's own holdings only: drop rows tagged with a JV ("Legal Entity Axis").
#   #6  Keep every investment type, with the type column kept.
#   #7  All 16 filings.
#   #8  Add a "Not assigned to an industry by BCRED" row per filing equal to
#       reported total investments minus the sum of the industry subtotals.
#   #9  Industry names: fix spelling differences only (see clean_industry_label).
#
# INPUTS
#   data/raw/bdc/manifest.csv           list of downloaded ZIPs
#   data/raw/bdc/<zip>/soi.tsv          industry subtotal rows
#   data/raw/bdc/<zip>.zip -> num.tsv   reported total investments (read
#                                       straight from the ZIP, not extracted)
#
# OUTPUTS (data/processed/)
#   bcred_sector_exposure.csv   one row per filing x industry x type x affiliation,
#                               plus one "not assigned" row per filing
#   bcred_reconciliation.csv    per filing: reported total, subtotal sum, gap
#
# HOW TO RUN
#   From the project root:  Rscript R/03_clean_sector_subtotals.R
#   Takes a few minutes (it scans each num.tsv, up to ~1 GB, inside its ZIP).
#
# The script STOPS (rather than guessing) if:
#   - a filing's total investments can't be found, or appears with two values
#   - a subtotal row has no fair value, is malformed, or uses an unexpected tag
#   - the same industry x type x affiliation appears twice in one filing
#   - the subtotals add up to more than the reported total (double counting)
# =============================================================================

source("R/00_helpers.R")   # BCRED_CIK, RAW_BDC_DIR, read_bcred_soi(), read_reported_total()

PROCESSED_DIR <- path("data", "processed")
dir_create(PROCESSED_DIR)

UNASSIGNED_LABEL <- "Not assigned to an industry by BCRED"
ROUNDING_TOLERANCE <- 1e6   # $1m: subtotals are reported in $ thousands

# Columns a BCRED-own subtotal row may use. Anything else -> stop and look.
ALLOWED_DIMENSIONS <- c("Industry Sector Axis", "Investment Type Axis",
                        "Investment, Issuer Affiliation Axis")
ALL_DIMENSIONS_TO_CHECK <- c("Investment, Identifier Axis", "Legal Entity Axis",
                             "Investment, Issuer Name Axis", "Geographical Axis",
                             "Fair Value Hierarchy and NAV Axis",
                             "Financial Instrument Axis", "Derivative Instrument Axis")


# ---- Helper: keep only BCRED-own industry subtotal rows for the filing date --
select_own_subtotals <- function(bcred) {
  rows <- bcred[bcred$ddate == bcred$period & !is.na(bcred$`Industry Sector Axis`), ]

  # Drop rows that belong to a joint venture's own loan book (decision #5).
  if ("Legal Entity Axis" %in% names(rows)) rows <- rows[is.na(rows$`Legal Entity Axis`), ]

  # Any other tag on these rows means a structure we haven't checked.
  for (col in intersect(ALL_DIMENSIONS_TO_CHECK, names(rows))) {
    if (any(!is.na(rows[[col]]))) {
      stop(rows$adsh[1], ": industry subtotal rows also use '", col, "'. Check before continuing.")
    }
  }
  rows
}


# ---- Helper: run the safety checks on one filing's subtotal rows ------------
check_subtotals <- function(rows) {
  id <- rows$adsh[1]
  if (nrow(rows) == 0)                stop(id, ": no industry subtotal rows found.")
  if (any(rows$malformed))            stop(id, ": a subtotal row is malformed in the SEC file.")
  if (any(is.na(rows$fair_value)))    stop(id, ": a subtotal row has no fair value.")

  dup <- rows |> count(industry_raw, investment_type, affiliation) |> filter(n > 1)
  if (nrow(dup) > 0) {
    print(dup)
    stop(id, ": the same industry x type x affiliation appears more than once.")
  }
  invisible(TRUE)
}


# ---- Helper: clean an industry label (spelling only, decision #9) -----------
# Removes tagging artefacts so the same industry has one name in every period:
#   "Electric Utilities Sector [Member]" -> "Electric Utilities"
#   "Paper And Forest Products Sector"   -> "Paper & Forest Products"
# Only a capitalised " And " is changed (an XBRL naming artefact), so official
# names with a lowercase "and" stay as they are. Different industries
# (e.g. "Marine" vs "Marine Transportation") are NOT merged.
clean_industry_label <- function(x) {
  x <- sub(" \\[Member\\]$", "", x)
  x <- sub(" Sector$", "", x)
  gsub(" And ", " & ", x, fixed = TRUE)
}


# ---- Helper: tidy one filing's subtotal rows ---------------------------------
tidy_subtotals <- function(rows, zip_name, soi_file) {
  cost_col <- if ("Adjusted cost basis" %in% names(rows)) rows$`Adjusted cost basis` else NA
  tibble(
    period          = as.Date(rows$period),
    form            = rows$form,
    filed           = as.Date(rows$filed),
    adsh            = rows$adsh,
    industry        = clean_industry_label(rows$`Industry Sector Axis`),       # tidy label
    industry_raw    = rows$`Industry Sector Axis`,                            # as filed
    investment_type = sub(" \\[Member\\]$", "", rows$`Investment Type Axis`),
    affiliation     = rows$`Investment, Issuer Affiliation Axis`,
    fair_value      = as.numeric(rows$`Initial fair value of Investment`),
    cost            = as.numeric(cost_col),
    pct_net_assets  = as.numeric(rows$`Investment Owned, Net Assets, Percentage`),
    row_basis       = "industry subtotal (soi.tsv)",
    source_zip      = zip_name,
    source_file     = as.character(soi_file),
    filing_url      = rows$inlineurl
  )
}


# ---- Process every filing ----------------------------------------------------
manifest <- read_csv(path(RAW_BDC_DIR, "manifest.csv"), show_col_types = FALSE)

results <- lapply(seq_len(nrow(manifest)), function(i) {
  zip_file <- manifest$saved_as[i]
  soi_file <- path(path_ext_remove(zip_file), "soi.tsv")
  message("Processing ", manifest$zip[i], " ...")

  bcred <- read_bcred_soi(soi_file)
  own   <- select_own_subtotals(bcred)
  tidy  <- tidy_subtotals(own, manifest$zip[i], soi_file)
  check_subtotals(mutate(tidy, malformed = own$malformed))

  if (length(unique(tidy$adsh)) != 1) stop(manifest$zip[i], ": more than one BCRED filing found.")

  reported <- read_reported_total(zip_file, tidy$adsh[1], tidy$period[1])
  subtotal_sum <- sum(tidy$fair_value)
  gap <- reported - subtotal_sum

  if (gap < -ROUNDING_TOLERANCE) {
    stop(tidy$adsh[1], ": industry subtotals ($", format(subtotal_sum, big.mark = ","),
         ") exceed reported total ($", format(reported, big.mark = ","),
         "). Possible double counting.")
  }

  # The "not assigned" row (decision #8): reported total minus subtotals.
  unassigned <- tidy[1, ] |> mutate(
    industry = UNASSIGNED_LABEL, industry_raw = NA, investment_type = NA,
    affiliation = NA, fair_value = gap, cost = NA, pct_net_assets = NA,
    row_basis = "reported total (num.tsv InvestmentOwnedAtFairValue) minus industry subtotals",
    source_file = paste0(zip_file, " :: num.tsv + ", soi_file)
  )

  recon <- tibble(
    period = tidy$period[1], form = tidy$form[1], filed = tidy$filed[1], adsh = tidy$adsh[1],
    reported_total_fair_value = reported,
    industry_subtotal_sum     = subtotal_sum,
    not_assigned              = gap,
    not_assigned_pct          = round(100 * gap / reported, 2),
    n_subtotal_rows           = nrow(tidy),
    malformed_bcred_rows_elsewhere_in_file = sum(bcred$malformed),
    source_zip = manifest$zip[i]
  )

  list(exposure = bind_rows(tidy, unassigned), recon = recon)
})

exposure       <- bind_rows(lapply(results, `[[`, "exposure")) |> arrange(desc(period), industry)
reconciliation <- bind_rows(lapply(results, `[[`, "recon"))    |> arrange(desc(period))


# ---- Final check: every filing's rows add up to its reported total ----------
check <- exposure |> group_by(adsh) |> summarise(total = sum(fair_value)) |>
  inner_join(reconciliation, by = "adsh")
if (any(abs(check$total - check$reported_total_fair_value) > ROUNDING_TOLERANCE)) {
  stop("Sector rows do not add up to the reported total for at least one filing.")
}


# ---- Save ---------------------------------------------------------------------
write_csv(exposure,       path(PROCESSED_DIR, "bcred_sector_exposure.csv"))
write_csv(reconciliation, path(PROCESSED_DIR, "bcred_reconciliation.csv"))

cat("\nSaved", nrow(exposure), "rows to data/processed/bcred_sector_exposure.csv\n")
cat("Saved", nrow(reconciliation), "rows to data/processed/bcred_reconciliation.csv\n\n")
print(as.data.frame(reconciliation |>
  transmute(period, form,
            reported_bn = round(reported_total_fair_value / 1e9, 2),
            subtotals_bn = round(industry_subtotal_sum / 1e9, 2),
            not_assigned_bn = round(not_assigned / 1e9, 2),
            not_assigned_pct, n_subtotal_rows)), row.names = FALSE)
