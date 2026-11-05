# =============================================================================
# 01_fetch_sec.R
# -----------------------------------------------------------------------------
# PURPOSE
#   Download the SEC data needed to see BCRED's schedule of investments (SOI):
#     1. BCRED's filing list from the EDGAR "submissions" API (JSON).
#     2. Every SEC BDC Data Set ZIP that contains a BCRED 10-K or 10-Q.
#   Each ZIP is saved to data/raw/bdc/ and only the tables we need are
#   extracted next to it (soi.tsv = holdings, sub.tsv = filing details).
#
# SOURCES
#   - BDC Data Sets page:  https://www.sec.gov/data-research/bdc-data-sets
#   - BDC readme (tables): https://www.sec.gov/files/bdc_readme.pdf
#   - EDGAR submissions:   https://data.sec.gov/submissions/CIK0001803498.json
#
# BEFORE RUNNING
#   The SEC requires a descriptive User-Agent. Put this line in ~/.Renviron
#   (run usethis::edit_r_environ()), then restart R:
#       SEC_USER_AGENT="Your Name your.email@example.com"
#
# HOW TO RUN
#   From the project root:  Rscript R/01_fetch_sec.R
#   (or open in RStudio and click "Source").
#   Files already downloaded are skipped. To re-download (the SEC sometimes
#   refreshes old ZIPs), set FORCE_DOWNLOAD <- TRUE below.
# =============================================================================

library(httr2)     # web requests
library(jsonlite)  # reading JSON
library(fs)        # file paths and folders

# ---- Settings ---------------------------------------------------------------
BCRED_CIK      <- 1803498
FORMS_WANTED   <- c("10-K", "10-Q", "10-K/A", "10-Q/A")  # filings that contain an SOI
# Files to extract from each ZIP (matched by file name, wherever they sit inside).
# soi.tsv = holdings, sub.tsv = filing details, plus the SEC's own docs.
# Set to NULL to extract everything (about 1.5 GB per recent ZIP once unzipped).
TABLES_WANTED  <- c("soi.tsv", "sub.tsv", "readme.htm", "bdc_metadata.json")
FORCE_DOWNLOAD <- FALSE
TODAY          <- format(Sys.Date(), "%Y-%m-%d")         # used in file names

DATASETS_PAGE  <- "https://www.sec.gov/data-research/bdc-data-sets"
SUBMISSIONS_URL <- sprintf("https://data.sec.gov/submissions/CIK%010d.json", BCRED_CIK)

RAW_BDC_DIR   <- path("data", "raw", "bdc")
RAW_EDGAR_DIR <- path("data", "raw", "edgar")
dir_create(c(RAW_BDC_DIR, RAW_EDGAR_DIR))


# ---- Helper: the User-Agent -------------------------------------------------
# Reads SEC_USER_AGENT from the environment. Stops with a clear message if unset,
# so we never send requests without identifying ourselves.
get_user_agent <- function() {
  ua <- Sys.getenv("SEC_USER_AGENT")
  if (!nzchar(ua)) {
    stop("SEC_USER_AGENT is not set. Add it to ~/.Renviron and restart R.")
  }
  ua
}


# ---- Helper: one polite request to the SEC ----------------------------------
# Builds a request with our User-Agent, stays well under the SEC's limit of
# 10 requests/second, and retries a few times on temporary errors.
sec_request <- function(url) {
  request(url) |>
    req_user_agent(get_user_agent()) |>
    req_throttle(capacity = 5, fill_time_s = 1) |>
    req_retry(max_tries = 3)
}


# ---- Helper: tell the user what to download by hand if the SEC blocks us ----
blocked_message <- function(url, status) {
  stop(
    "The SEC returned HTTP ", status, " for:\n  ", url, "\n",
    "If this keeps happening, download it manually in a browser and save it to ",
    RAW_BDC_DIR, "/ (ZIPs) or ", RAW_EDGAR_DIR, "/ (JSON), then re-run.",
    call. = FALSE
  )
}


# ---- Step 1: BCRED's filing list from EDGAR ---------------------------------
# Saves the raw JSON (date-stamped) and returns a table of 10-K/10-Q filings.
fetch_bcred_filings <- function() {
  json_file <- path(RAW_EDGAR_DIR, sprintf("CIK%010d_submissions_%s.json", BCRED_CIK, TODAY))

  if (!file_exists(json_file) || FORCE_DOWNLOAD) {
    resp <- sec_request(SUBMISSIONS_URL) |>
      req_error(is_error = \(r) FALSE) |>
      req_perform(path = json_file)
    if (resp_status(resp) != 200) blocked_message(SUBMISSIONS_URL, resp_status(resp))
    message("Saved ", json_file)
  }

  sub <- fromJSON(json_file)
  # "recent" holds the latest 1,000 filings. Older ones live in extra files.
  # Stop rather than silently miss filings if that ever applies to BCRED.
  if (length(sub$filings$files) > 0 && NROW(sub$filings$files) > 0) {
    stop("BCRED has older filings in extra JSON files; this script does not read them yet.")
  }

  recent <- as.data.frame(sub$filings$recent)
  filings <- recent[recent$form %in% FORMS_WANTED,
                    c("form", "filingDate", "reportDate", "accessionNumber")]
  filings$filingDate <- as.Date(filings$filingDate)
  filings
}


# ---- Step 2: list the ZIPs on the BDC Data Sets page ------------------------
# Returns a table of ZIP file names, their full URL, and the filing-date
# window each one covers. Monthly files look like "2026_08_bdc.zip";
# quarterly files look like "2025q4_bdc.zip".
list_bdc_zips <- function() {
  resp <- sec_request(DATASETS_PAGE) |> req_error(is_error = \(r) FALSE) |> req_perform()
  if (resp_status(resp) != 200) blocked_message(DATASETS_PAGE, resp_status(resp))

  html  <- resp_body_string(resp)
  paths <- unique(regmatches(html, gregexpr("/files/[^\"]*_bdc\\.zip", html))[[1]])
  if (length(paths) == 0) stop("No ZIP links found on ", DATASETS_PAGE)

  zips <- data.frame(file = basename(paths), url = paste0("https://www.sec.gov", paths))
  zips$start <- as.Date(NA)
  zips$end   <- as.Date(NA)

  for (i in seq_len(nrow(zips))) {
    label <- sub("_bdc\\.zip$", "", zips$file[i])
    if (grepl("^\\d{4}_\\d{2}$", label)) {            # monthly
      start <- as.Date(paste0(sub("_", "-", label), "-01"))
      months <- 1
    } else if (grepl("^\\d{4}q[1-4]$", label)) {      # quarterly
      q <- as.integer(substr(label, 6, 6))
      start <- as.Date(sprintf("%s-%02d-01", substr(label, 1, 4), 3 * q - 2))
      months <- 3
    } else {
      stop("Unrecognised ZIP name: ", zips$file[i])
    }
    zips$start[i] <- start
    zips$end[i]   <- seq(start, by = paste(months, "months"), length.out = 2)[2] - 1
  }
  zips
}


# ---- Step 3: match each BCRED filing to the ZIP that covers its filing date --
match_filings_to_zips <- function(filings, zips) {
  filings$zip <- vapply(seq_len(nrow(filings)), function(i) {
    hit <- zips$file[filings$filingDate[i] >= zips$start & filings$filingDate[i] <= zips$end]
    if (length(hit) == 0) NA_character_ else hit[1]
  }, character(1))
  filings
}


# ---- Step 4: download one ZIP and extract the tables we need ----------------
# Saves e.g. data/raw/bdc/2026_08_bdc_downloaded-2026-11-05.zip and extracts
# into data/raw/bdc/2026_08_bdc_downloaded-2026-11-05/.
# Skips the download if any earlier copy of that ZIP already exists.
download_bdc_zip <- function(zip_file, url) {
  label    <- sub("\\.zip$", "", zip_file)
  existing <- dir_ls(RAW_BDC_DIR, regexp = paste0(label, "_downloaded-.*\\.zip$"))

  if (length(existing) > 0 && !FORCE_DOWNLOAD) {
    message("Already have ", path_file(existing[1]), " - skipping download")
    dest <- existing[length(existing)]   # newest copy
  } else {
    dest <- path(RAW_BDC_DIR, paste0(label, "_downloaded-", TODAY, ".zip"))
    message("Downloading ", url)
    resp <- sec_request(url) |> req_error(is_error = \(r) FALSE) |> req_perform(path = dest)
    if (resp_status(resp) != 200) { file_delete(dest); blocked_message(url, resp_status(resp)) }
  }

  out_dir <- path_ext_remove(dest)
  inside  <- unzip(dest, list = TRUE)$Name
  # Files can sit in subfolders (e.g. "datasets/sub.tsv"), so match on the name only.
  wanted  <- if (is.null(TABLES_WANTED)) inside else inside[basename(inside) %in% TABLES_WANTED]
  missing <- setdiff(TABLES_WANTED, basename(inside))
  if (length(missing) > 0) warning(zip_file, " does not contain: ", paste(missing, collapse = ", "))
  # junkpaths = TRUE puts every extracted file directly in out_dir.
  unzip(dest, files = wanted, exdir = out_dir, overwrite = TRUE, junkpaths = TRUE)

  data.frame(zip = zip_file, saved_as = as.character(dest), url = url,
             bytes = as.numeric(file_size(dest)),
             md5 = unname(tools::md5sum(dest)))   # fingerprint to spot changed files
}


# ---- Run everything ----------------------------------------------------------
filings <- fetch_bcred_filings()
zips    <- list_bdc_zips()
filings <- match_filings_to_zips(filings, zips)

# Filings before the first data set (Oct 2022) have no BDC ZIP. Say so clearly.
not_covered <- filings[is.na(filings$zip), ]
if (nrow(not_covered) > 0) {
  message("\n", nrow(not_covered), " BCRED filings are older than the BDC Data Sets (",
          "coverage starts ", format(min(zips$start)), ") and are NOT downloaded:")
  print(not_covered[, c("form", "filingDate", "reportDate")], row.names = FALSE)
}

covered <- filings[!is.na(filings$zip), ]
message("\nBCRED filings covered by the BDC Data Sets:")
print(covered, row.names = FALSE)

# Download each needed ZIP once, and record what we got.
manifest <- do.call(rbind, lapply(unique(covered$zip), function(z) {
  download_bdc_zip(z, zips$url[zips$file == z])
}))

# The manifest is a small CSV that records exactly which source files we used.
manifest_file <- path(RAW_BDC_DIR, "manifest.csv")
write.csv(manifest, manifest_file, row.names = FALSE)
message("\nDone. ", nrow(manifest), " ZIPs listed in ", manifest_file)
