# =============================================================================
# tests/test_metrics.R
# -----------------------------------------------------------------------------
# Checks the outputs of R/05_metrics.R. Where possible it recalculates numbers
# from the input files instead of trusting the script's own working.
#
# HOW TO RUN   Rscript R/05_metrics.R  then  Rscript tests/test_metrics.R
# Prints PASS / FAIL per check and exits with an error if any check fails.
# =============================================================================

suppressPackageStartupMessages({ library(readr); library(dplyr) })

summary_df <- read_csv("data/processed/sector_summary.csv", show_col_types = FALSE)
metrics    <- read_csv("data/processed/portfolio_metrics.csv", show_col_types = FALSE)
factors    <- read_csv("data/processed/industry_factors.csv", show_col_types = FALSE,
                       col_types = cols(naics_codes = col_character()))
exposure   <- read_csv("data/processed/bcred_sector_exposure.csv", show_col_types = FALSE)
recon      <- read_csv("data/processed/bcred_reconciliation.csv", show_col_types = FALSE)
crosswalk  <- read_csv("data/reference/sector_naics_crosswalk.csv", col_types = cols(.default = "c"))

failures <- 0
check <- function(name, ok, detail = "") {
  cat(if (isTRUE(ok)) "PASS" else "FAIL", "-", name, if (!isTRUE(ok) && nzchar(detail)) paste0("\n       ", detail) else "", "\n")
  if (!isTRUE(ok)) failures <<- failures + 1
}
tol <- 1e-6

# 1. Percentages of portfolio sum to 100% in every period.
pct <- summary_df |> group_by(period) |> summarise(s = sum(pct_of_portfolio))
check("% of portfolio sums to 100% in every period", all(abs(pct$s - 100) < tol),
      paste(format(pct$period[abs(pct$s - 100) >= tol]), collapse = ", "))

# 2. Contributions to the indicator sum to 100% in every period.
pci <- summary_df |> group_by(period) |> summarise(s = sum(pct_of_indicator, na.rm = TRUE))
check("% of indicator (contributions) sums to 100% in every period", all(abs(pci$s - 100) < tol))

# 3. No industry is unmapped: every industry in the data is in the crosswalk.
missing <- setdiff(unique(exposure$industry), crosswalk$industry_label)
check("Every industry in the data is in the crosswalk (none silently dropped)", length(missing) == 0,
      paste("Missing:", paste(missing, collapse = "; ")))

# 4. Every industry in the exposure data appears in the summary for its period.
pairs_in  <- unique(paste(exposure$period, exposure$industry))
pairs_out <- unique(paste(summary_df$period, summary_df$industry))
check("Every period x industry in the input appears in sector_summary", setequal(pairs_in, pairs_out))

# 5. Industries without a proxy are exactly the six approved in decision #19 - printed, not dropped.
approved_no_proxy <- c("Not assigned to an industry by BCRED", "Consumer", "Industrial Conglomerates",
                       "Energy", "Electric Utilities", "Independent Power and Renewable Electricity Producers")
no_proxy <- factors$industry[!factors$has_proxy]
cat("       No-proxy industries:", paste(no_proxy, collapse = "; "), "\n")
check("No-proxy industries match the approved list (decision #19)", setequal(no_proxy, approved_no_proxy))

# 6. Fair value per period ties to BCRED's reported total investments.
fv <- summary_df |> group_by(adsh) |> summarise(s = sum(fair_value)) |> inner_join(recon, by = "adsh")
check("Total fair value per period equals the filing's reported total",
      nrow(fv) == 16 && all(abs(fv$s - fv$reported_total_fair_value) < 1))

# 7. Recalculate the indicator independently: sum(FV * factor) / sum(FV) over mapped industries.
recalc <- summary_df |> filter(has_proxy) |> group_by(period) |>
  summarise(ind = sum(fair_value * factor_kg_per_usd) / sum(fair_value)) |>
  inner_join(metrics, by = "period")
check("Indicator equals sum(fair value x factor) / sum(mapped fair value)",
      all(abs(recalc$ind - recalc$indicator_kg_per_usd) < tol))

# 8. Spot-check one factor straight from the EPA file: Pharmaceuticals = NAICS 325412.
epa_file <- read_csv("data/raw/epa/manifest.csv", show_col_types = FALSE)
epa_file <- epa_file$saved_as[epa_file$version == "v1.3"]
epa <- read_csv(epa_file, col_types = cols(`2017 NAICS Code` = "c"), show_col_types = FALSE)
pharma_epa <- epa$`Supply Chain Emission Factors with Margins`[epa$`2017 NAICS Code` == "325412"]
check("Pharmaceuticals factor equals EPA v1.3 NAICS 325412 (with margins)",
      abs(factors$factor_kg_per_usd[factors$industry == "Pharmaceuticals"] - pharma_epa) < tol)

# 9. Tiers split the 54 mapped industries into thirds (ties can shift by one).
tiers <- table(factors$tier[factors$has_proxy])
cat("       Tier counts:", paste(names(tiers), tiers, collapse = ", "), "\n")
check("54 mapped industries split roughly into thirds", sum(tiers) == 54 && all(abs(tiers - 18) <= 2))

# 10. Coverage + no-proxy share = 100%.
check("Coverage % + no-proxy % = 100% in every period",
      all(abs(metrics$coverage_pct + metrics$pct_fv_no_proxy - 100) < tol))

# 11. Metric is named and labelled as required.
check("Metric name and proxy label present",
      all(metrics$metric_name == "exposure-weighted sector emissions-intensity indicator") &&
      all(metrics$metric_label == "sector-level proxy, not financed emissions"))

cat("\n", if (failures == 0) "ALL TESTS PASSED" else paste(failures, "TEST(S) FAILED"), "\n")
if (failures > 0) quit(status = 1)
