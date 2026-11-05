# Runs automatically before `quarto render` (see _quarto.yml).
# Removes the previous render's pages and support files from ../docs so old,
# unused files never pile up. Only these generated outputs are touched.
old <- file.path("..", "docs", c("index.html", "methods.html", "index_files", "methods_files"))
unlink(old[file.exists(old)], recursive = TRUE)
