# =============================================================================
# 04_fetch_epa_factors.R
# -----------------------------------------------------------------------------
# PURPOSE
#   Download the Supply Chain GHG Emission Factors (kg CO2e per US dollar, by
#   6-digit NAICS industry) to data/raw/epa/, with date-stamped file names and
#   a manifest recording where each file came from.
#
# FILES DOWNLOADED
#   v1.3   EPA release (July 2024), CO2e factors, 2022 USD, purchaser prices.
#          Catalog: https://catalog.data.gov/dataset/supply-chain-greenhouse-gas-emission-factors-v1-3-by-naics-6
#          DOI:     https://doi.org/10.23719/1531143
#   v1.4.0 Same authors, published via Zenodo (Oct 2025), not by EPA.
#          2024 USD, AR6 warming potentials. Downloaded for comparison only.
#          DOI:     https://doi.org/10.5281/zenodo.17202747
#
# HOW TO RUN
#   From the project root:  Rscript R/04_fetch_epa_factors.R
#   Files already downloaded are skipped (set FORCE_DOWNLOAD <- TRUE to redo).
# =============================================================================

library(httr2)
library(fs)

FORCE_DOWNLOAD <- FALSE
TODAY   <- format(Sys.Date(), "%Y-%m-%d")
RAW_DIR <- path("data", "raw", "epa")
dir_create(RAW_DIR)

# A plain, descriptive client name (no personal details needed for these sites).
USER_AGENT <- "bxci-sustainability-screener (R httr2; portfolio research project)"

SOURCES <- data.frame(
  version = c("v1.3", "v1.4.0", "v1.4.0"),
  what    = c("CO2e factors (CSV)", "Factors workbook (XLSX)", "About / methods (PDF)"),
  url     = c(
    "https://pasteur.epa.gov/uploads/10.23719/1531143/SupplyChainGHGEmissionFactors_v1.3.0_NAICS_CO2e_USD2022.csv",
    "https://zenodo.org/api/records/17202747/files/SupplyChainGHGEmissionFactorsv1.4.0.xlsx/content",
    "https://zenodo.org/api/records/17202747/files/About%20the%20Supply%20Chain%20Greenhouse%20Gas%20Emission%20Factors%20v1.4.0.pdf/content"
  ),
  file_stub = c("SupplyChainGHGEmissionFactors_v1.3.0_NAICS_CO2e_USD2022",
                "SupplyChainGHGEmissionFactors_v1.4.0",
                "About_SupplyChainGHGEmissionFactors_v1.4.0"),
  ext = c("csv", "xlsx", "pdf")
)


# ---- Helper: download one file unless we already have a copy -----------------
download_one <- function(url, file_stub, ext) {
  existing <- dir_ls(RAW_DIR, regexp = paste0(file_stub, "_downloaded-.*\\.", ext, "$"))
  if (length(existing) > 0 && !FORCE_DOWNLOAD) {
    message("Already have ", path_file(existing[length(existing)]), " - skipping")
    return(existing[length(existing)])
  }

  dest <- path(RAW_DIR, paste0(file_stub, "_downloaded-", TODAY, ".", ext))
  message("Downloading ", url)
  resp <- request(url) |>
    req_user_agent(USER_AGENT) |>
    req_retry(max_tries = 3) |>
    req_error(is_error = \(r) FALSE) |>
    req_perform(path = dest)

  if (resp_status(resp) != 200) {
    file_delete(dest)
    stop("HTTP ", resp_status(resp), " for ", url,
         "\nDownload it in a browser, save it to ", RAW_DIR, "/, then re-run.", call. = FALSE)
  }
  dest
}


# ---- Download everything and write the manifest ------------------------------
saved <- vapply(seq_len(nrow(SOURCES)), function(i) {
  as.character(download_one(SOURCES$url[i], SOURCES$file_stub[i], SOURCES$ext[i]))
}, character(1))

manifest <- data.frame(
  version  = SOURCES$version,
  what     = SOURCES$what,
  saved_as = saved,
  url      = SOURCES$url,
  bytes    = as.numeric(file_size(saved)),
  md5      = unname(tools::md5sum(saved))
)
write.csv(manifest, path(RAW_DIR, "manifest.csv"), row.names = FALSE)
message("Done. Files listed in ", path(RAW_DIR, "manifest.csv"))
