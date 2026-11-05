# =============================================================================
# 05_metrics.R
# -----------------------------------------------------------------------------
# PURPOSE
#   Apply the approved sector -> NAICS crosswalk to BCRED's sector exposure and
#   calculate the "exposure-weighted sector emissions-intensity indicator".
#
#   THIS IS A SECTOR-LEVEL PROXY, NOT FINANCED EMISSIONS. It multiplies how
#   much BCRED has in each sector by the average supply-chain emissions per
#   dollar of that sector's output (EPA). It says nothing about the actual
#   emissions of BCRED's borrowers.
#
# THE CALCULATION IN ONE SENTENCE
#   For each period, every mapped industry's emission factor is weighted by
#   its share of BCRED's fair value in mapped industries, and the weighted
#   factors are added up.
#     weight_i       = fair_value_i / sum(fair_value of mapped industries)
#     contribution_i = weight_i * factor_i
#     indicator      = sum(contribution_i)
#
# RULES APPLIED (see docs-notes/DECISIONS.md)
#   #17 EPA v1.3 "Supply Chain Emission Factors with Margins" column.
#   #18 Industry factor = simple average of its crosswalk NAICS codes.
#   #19 Six industries have no proxy: kept and printed, never dropped.
#   #21 Weights use covered (mapped) fair value only; coverage reported.
#   #22 Tiers = tertiles of the factor across the 54 mapped industries.
#   #23 All 16 periods.   #24 No holdings-count column.
#
# UNITS
#   factor and indicator: kg CO2e per 2022 US dollar (purchaser price).
#   Also shown as t CO2e per $ million (x 1,000). Fair value: US dollars.
#
# INPUTS   data/processed/bcred_sector_exposure.csv
#          data/reference/sector_naics_crosswalk.csv
#          data/raw/epa/manifest.csv -> EPA v1.3 CSV
# OUTPUTS  data/processed/industry_factors.csv   factor + tier per industry
#          data/processed/sector_summary.csv     period x industry
#          data/processed/portfolio_metrics.csv  one row per period
#
# HOW TO RUN   Rscript R/05_metrics.R      then test:  Rscript tests/test_metrics.R
# =============================================================================

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(fs)
})

METRIC_NAME  <- "exposure-weighted sector emissions-intensity indicator"
METRIC_LABEL <- "sector-level proxy, not financed emissions"
FACTOR_COL   <- "Supply Chain Emission Factors with Margins"   # decision #17
PROCESSED    <- path("data", "processed")


# ---- Helper: load the EPA v1.3 factors named in the EPA manifest ------------
load_epa_v13 <- function() {
  manifest <- read_csv(path("data", "raw", "epa", "manifest.csv"), show_col_types = FALSE)
  file <- manifest$saved_as[manifest$version == "v1.3"]
  if (length(file) != 1) stop("Expected one EPA v1.3 file in the manifest.")
  epa <- read_csv(file, col_types = cols(`2017 NAICS Code` = col_character()), show_col_types = FALSE)
  if (!all(epa$Unit == "kg CO2e/2022 USD, purchaser price")) stop("Unexpected unit in EPA file.")
  if (anyDuplicated(epa$`2017 NAICS Code`)) stop("Duplicate NAICS codes in EPA file.")
  tibble(naics = epa$`2017 NAICS Code`, factor = epa[[FACTOR_COL]], source_file = file)
}


# ---- Helper: one factor per industry = simple average of its NAICS codes ----
industry_factors <- function(crosswalk, epa) {
  rows <- lapply(seq_len(nrow(crosswalk)), function(i) {
    codes <- if (is.na(crosswalk$naics_codes[i])) character() else
      strsplit(crosswalk$naics_codes[i], ";", fixed = TRUE)[[1]]
    missing <- setdiff(codes, epa$naics)
    if (length(missing) > 0) {
      stop(crosswalk$industry_label[i], ": NAICS codes not in EPA v1.3: ", paste(missing, collapse = ", "))
    }
    tibble(
      industry        = crosswalk$industry_label[i],
      naics_codes     = crosswalk$naics_codes[i],
      n_codes         = length(codes),
      has_proxy       = length(codes) > 0,
      factor_kg_per_usd = if (length(codes) > 0) mean(epa$factor[match(codes, epa$naics)]) else NA_real_,
      confidence      = crosswalk$confidence[i],
      aggregation     = crosswalk$aggregation[i]
    )
  })
  bind_rows(rows)
}


# ---- Helper: High / Medium / Low by tertile of the factor (decision #22) -----
add_tiers <- function(factors) {
  mapped <- factors$factor_kg_per_usd[factors$has_proxy]
  cuts   <- quantile(mapped, probs = c(1/3, 2/3), names = FALSE)
  factors |> mutate(
    tier = case_when(
      !has_proxy                       ~ "No emissions proxy",
      factor_kg_per_usd <= cuts[1]     ~ "Low",
      factor_kg_per_usd <= cuts[2]     ~ "Medium",
      TRUE                             ~ "High"
    ),
    tier_cut_low_medium  = cuts[1],
    tier_cut_medium_high = cuts[2]
  )
}


# ---- 1. Load inputs ------------------------------------------------------------
exposure  <- read_csv(path(PROCESSED, "bcred_sector_exposure.csv"), show_col_types = FALSE)
crosswalk <- read_csv(path("data", "reference", "sector_naics_crosswalk.csv"),
                      col_types = cols(.default = col_character()))
epa <- load_epa_v13()

# Every industry in the data must be in the crosswalk. Print and stop otherwise.
not_in_crosswalk <- setdiff(unique(exposure$industry), crosswalk$industry_label)
if (length(not_in_crosswalk) > 0) {
  cat("Industries missing from the crosswalk:\n"); print(not_in_crosswalk)
  stop("Add these to data/reference/sector_naics_crosswalk.csv before continuing.")
}

factors <- add_tiers(industry_factors(crosswalk, epa))
factors$factor_t_per_usd_m <- factors$factor_kg_per_usd * 1000


# ---- 2. Sector summary: one row per period x industry -------------------------
sector_summary <- exposure |>
  group_by(period, form, adsh, industry) |>
  summarise(fair_value = sum(fair_value), .groups = "drop") |>
  left_join(select(factors, industry, has_proxy, factor_kg_per_usd, factor_t_per_usd_m,
                    tier, confidence), by = "industry") |>
  group_by(period) |>
  mutate(
    pct_of_portfolio   = 100 * fair_value / sum(fair_value),
    weight_in_covered  = ifelse(has_proxy, fair_value / sum(fair_value[has_proxy]), NA_real_),
    contribution_kg_per_usd = weight_in_covered * factor_kg_per_usd,
    pct_of_indicator   = 100 * contribution_kg_per_usd / sum(contribution_kg_per_usd, na.rm = TRUE)
  ) |>
  ungroup() |>
  mutate(metric_label = METRIC_LABEL) |>
  arrange(desc(period), desc(fair_value))


# ---- 3. Portfolio metrics: one row per period ---------------------------------
portfolio_metrics <- sector_summary |>
  group_by(period, form, adsh) |>
  summarise(
    total_fair_value      = sum(fair_value),
    covered_fair_value    = sum(fair_value[has_proxy]),
    coverage_pct          = 100 * covered_fair_value / total_fair_value,
    indicator_kg_per_usd  = sum(contribution_kg_per_usd, na.rm = TRUE),
    pct_fv_high_tier      = 100 * sum(fair_value[tier == "High"]) / total_fair_value,
    pct_fv_no_proxy       = 100 * sum(fair_value[!has_proxy]) / total_fair_value,
    n_industries          = n(),
    n_industries_no_proxy = sum(!has_proxy),
    .groups = "drop"
  ) |>
  mutate(indicator_t_per_usd_m = indicator_kg_per_usd * 1000,
         metric_name = METRIC_NAME, metric_label = METRIC_LABEL,
         factor_source = "EPA Supply Chain GHG Emission Factors v1.3, with margins, kg CO2e per 2022 USD") |>
  arrange(desc(period))


# ---- 4. Print the no-proxy industries (never silently dropped) ---------------
latest <- max(sector_summary$period)
cat("Industries with NO emissions proxy in", format(latest), "(kept in totals, excluded from the indicator):\n")
print(as.data.frame(sector_summary |> filter(period == latest, !has_proxy) |>
  transmute(industry, fair_value_bn = round(fair_value / 1e9, 2), pct_of_portfolio = round(pct_of_portfolio, 2))),
  row.names = FALSE)


# ---- 5. Save -------------------------------------------------------------------
write_csv(factors,           path(PROCESSED, "industry_factors.csv"))
write_csv(sector_summary,    path(PROCESSED, "sector_summary.csv"))
write_csv(portfolio_metrics, path(PROCESSED, "portfolio_metrics.csv"))

m <- portfolio_metrics[portfolio_metrics$period == latest, ]
cat(sprintf("\n%s (%s), %s:\n", METRIC_NAME, METRIC_LABEL, format(latest)))
cat(sprintf("  %.3f kg CO2e per 2022 USD  (= %.0f t CO2e per $m)\n", m$indicator_kg_per_usd, m$indicator_t_per_usd_m))
cat(sprintf("  Coverage: %.1f%% of fair value has a factor\n", m$coverage_pct))
cat(sprintf("  High-tier share: %.1f%% of fair value\n", m$pct_fv_high_tier))
cat(sprintf("  Tier cut-offs: Low <= %.3f < Medium <= %.3f < High (kg CO2e/$)\n",
            factors$tier_cut_low_medium[1], factors$tier_cut_medium_high[1]))
cat("\nSaved industry_factors.csv, sector_summary.csv, portfolio_metrics.csv to data/processed/\n")
