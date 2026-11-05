# =============================================================================
# 06_dashboard_inputs.R
# -----------------------------------------------------------------------------
# PURPOSE
#   The dashboard may only read data/processed/. This script copies the two
#   things the Methods page needs from elsewhere into data/processed/:
#     data_sources.csv         every source file, its URL and the date pulled
#     crosswalk_for_methods.csv  approved crosswalk + NAICS titles + factors
#
# INPUTS   data/raw/bdc/manifest.csv, data/raw/edgar/*.json,
#          data/raw/epa/manifest.csv, data/reference/sector_naics_crosswalk.csv,
#          data/processed/industry_factors.csv
# HOW TO RUN   Rscript R/06_dashboard_inputs.R   (after R/05_metrics.R)
# =============================================================================

suppressPackageStartupMessages({ library(readr); library(dplyr); library(fs) })

PROCESSED <- path("data", "processed")

# Pull date = the date stamped in each saved file name.
pull_date <- function(paths) sub(".*(\\d{4}-\\d{2}-\\d{2}).*", "\\1", basename(paths))


# ---- 1. Data sources -----------------------------------------------------------
bdc  <- read_csv(path("data", "raw", "bdc", "manifest.csv"), show_col_types = FALSE)
epa  <- read_csv(path("data", "raw", "epa", "manifest.csv"), show_col_types = FALSE)
edgar_file <- dir_ls(path("data", "raw", "edgar"), glob = "*.json")

sources <- bind_rows(
  tibble(source = "SEC BDC Data Sets (schedule of investments, soi.tsv / num.tsv)",
         detail = bdc$zip, url = bdc$url, pulled = pull_date(bdc$saved_as),
         landing_page = "https://www.sec.gov/data-research/bdc-data-sets"),
  tibble(source = "SEC EDGAR submissions API (BCRED filing list)",
         detail = basename(edgar_file),
         url = "https://data.sec.gov/submissions/CIK0001803498.json",
         pulled = pull_date(edgar_file),
         landing_page = "https://www.sec.gov/search-filings/edgar-application-programming-interfaces"),
  tibble(source = paste("EPA Supply Chain GHG Emission Factors", epa$version),
         detail = epa$what, url = epa$url, pulled = pull_date(epa$saved_as),
         landing_page = ifelse(epa$version == "v1.3",
           "https://catalog.data.gov/dataset/supply-chain-greenhouse-gas-emission-factors-v1-3-by-naics-6",
           "https://doi.org/10.5281/zenodo.17202747"))
)
write_csv(sources, path(PROCESSED, "data_sources.csv"))


# ---- 2. Crosswalk with NAICS titles and factors, for the Methods page --------
crosswalk <- read_csv(path("data", "reference", "sector_naics_crosswalk.csv"),
                      col_types = cols(.default = col_character()))
factors   <- read_csv(path(PROCESSED, "industry_factors.csv"), show_col_types = FALSE,
                      col_types = cols(naics_codes = col_character()))
epa_v13   <- read_csv(epa$saved_as[epa$version == "v1.3"],
                      col_types = cols(`2017 NAICS Code` = col_character()), show_col_types = FALSE)

titles <- vapply(crosswalk$naics_codes, function(codes) {
  if (is.na(codes)) return(NA_character_)
  cs <- strsplit(codes, ";", fixed = TRUE)[[1]]
  paste0(cs, " ", epa_v13$`2017 NAICS Title`[match(cs, epa_v13$`2017 NAICS Code`)], collapse = "; ")
}, character(1))

methods_crosswalk <- crosswalk |>
  mutate(naics_with_titles = unname(titles)) |>
  left_join(select(factors, industry, factor_kg_per_usd, tier), by = c("industry_label" = "industry")) |>
  arrange(tier, industry_label)
write_csv(methods_crosswalk, path(PROCESSED, "crosswalk_for_methods.csv"))

cat("Saved", nrow(sources), "source rows and", nrow(methods_crosswalk), "crosswalk rows to data/processed/\n")
