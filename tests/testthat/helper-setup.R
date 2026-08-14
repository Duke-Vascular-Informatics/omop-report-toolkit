# =============================================================================
# tests/testthat/helper-setup.R
#
# Makes the suite runnable in BOTH modes:
#
#   1. Installed-package mode (`R CMD check`, CI) — omopReportToolkit is already
#      on the search path via tests/testthat.R, so this file does nothing.
#   2. Source mode (dev container, no install) — source()s R/*.R directly, for
#      the fast edit-test loop:
#          Rscript -e 'testthat::test_dir("tests/testthat")'
#
# WHY SOURCE MODE NEEDS TO ATTACH PACKAGES ITSELF
#   R/report_helpers.R deliberately calls some functions BARE (unqualified) —
#   body_add_par(), fp_border(), flextable(), set_header_labels(), quantile(),
#   read.csv() — and relies on the hand-written NAMESPACE's importFrom() lines
#   to resolve them. NAMESPACE is only consulted when the package is properly
#   loaded. source()ing the files skips it entirely, so those bare calls would
#   fail with "could not find function" even though the package itself is fine.
#
#   So in source mode we attach officer and flextable to stand in for the
#   importFrom() lines. If you add a new bare call to another package in R/*.R,
#   add it to NAMESPACE *and* here, or source mode will diverge from installed
#   mode and the suite will pass in CI while failing locally (or vice versa).
# =============================================================================

if (!requireNamespace("omopReportToolkit", quietly = TRUE)) {

  # Stand in for NAMESPACE's importFrom() entries — see comment above.
  suppressPackageStartupMessages({
    library(officer)
    library(flextable)
  })

  pkg_root <- normalizePath(file.path(testthat::test_path(), "..", ".."),
                            mustWork = TRUE)
  r_files <- list.files(file.path(pkg_root, "R"), pattern = "\\.R$",
                        full.names = TRUE)

  if (length(r_files) == 0L) {
    stop("helper-setup.R: no R/*.R files found under ", pkg_root)
  }

  # Source into the global environment so the dot-prefixed helpers are visible
  # to the tests exactly as they would be after library(omopReportToolkit).
  for (f in r_files) sys.source(f, envir = globalenv())
}


# -----------------------------------------------------------------------------
# .test_write_png()
#
# Writes a real PNG of known pixel dimensions to a temp path, for the
# .png_aspect() tests. Uses grDevices::png() rather than a checked-in fixture
# so the expected aspect ratio is derived from the call, not from a binary blob
# nobody can inspect in a diff.
#
# Returns the file path.
# -----------------------------------------------------------------------------
.test_write_png <- function(width_px, height_px) {
  path <- tempfile(fileext = ".png")
  grDevices::png(filename = path, width = width_px, height = height_px)
  graphics::plot.new()
  grDevices::dev.off()
  path
}


# -----------------------------------------------------------------------------
# .read_styles_xml()
#
# Extracts word/styles.xml from a .docx and returns it as one string, so a test
# can assert on what .strip_heading_autonumbering() did or did not remove.
#
# Returns "" when the archive has no styles.xml, so callers can assert absence
# without handling an error.
# -----------------------------------------------------------------------------
.read_styles_xml <- function(docx_path) {
  work <- tempfile("docx_read_")
  dir.create(work, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(work, recursive = TRUE, force = TRUE), add = TRUE)

  utils::unzip(docx_path, exdir = work)
  styles <- file.path(work, "word", "styles.xml")
  if (!file.exists(styles)) return("")

  paste(readLines(styles, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}
