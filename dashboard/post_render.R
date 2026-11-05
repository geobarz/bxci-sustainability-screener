# Runs automatically after `quarto render` (see _quarto.yml).
# GitHub Pages runs Jekyll by default; an empty .nojekyll file turns it off so
# every rendered file (including folders like index_files/) is served as-is.
file.create(file.path("..", "docs", ".nojekyll"))
