# =============================================================================
# tests/testthat/test-report-helpers.R
#
# Covers the pure / filesystem-only logic in R/report_helpers.R:
#   .compute_ece()                  — expected calibration error (see REGRESSION below)
#   .append_references_section()    — Vancouver reference formatting into a docx
#   .build_table1()                 — styled flextable structure
#   .strip_heading_autonumbering()  — docx styles.xml rewrite, and its soft failures
#
# Deliberately NOT covered: .save_roc_plot(), .save_dual_roc_plot(), and the
# .save_*_calibration_plot* family. Those are ggplot/patchwork composition that
# ends in save_figure(), i.e. three graphics devices per call. Their non-trivial
# logic (axis limits, palette slots, aspect ratio) is already tested directly in
# test-figure-style.R, which is where the actual decisions live.
# =============================================================================

# -----------------------------------------------------------------------------
# .compute_ece()
#
# REGRESSION GUARD. The comment block in R/report_helpers.R records two bugs
# that shipped undetected because this function is only reachable from a legacy
# entry point no real pipeline calls, and was never tested:
#
#   1. aggregate() with cbind(predicted, observed) and a vector-valued FUN
#      returns each response as its own [n_bins x 2] matrix, not a list — so
#      do.call(rbind, <matrix>) errored.
#   2. Only the "predicted" column was passed on; "observed" was silently
#      dropped, while colnames() assigned five names to a three-column object.
#      mean_obs and n_obs were never computed, so ece_value's formula consumed
#      whatever the column-count mismatch left behind.
#
# The assertions below pin down the shape and the arithmetic so neither can
# regress silently again.
# -----------------------------------------------------------------------------

test_that(".compute_ece() returns both predicted AND observed bin statistics", {
  set.seed(42)
  p <- runif(200)
  y <- rbinom(200, 1, p)

  res <- .compute_ece(y, p, n_bins = 5)

  expect_named(res, c("ece", "bin_data"))

  # Bug 2 above dropped these two columns entirely. Their presence is the
  # single most important thing this test protects.
  expect_true(all(c("bin", "n_pred", "mean_pred", "n_obs", "mean_obs") %in%
                    names(res$bin_data)))

  # Each bin's predicted and observed counts describe the same rows, so the two
  # n columns must agree. They cannot if the response columns get crossed.
  expect_equal(res$bin_data$n_pred, res$bin_data$n_obs)

  # And the bin counts must add back up to the input length.
  expect_equal(sum(res$bin_data$n_pred), length(y))
})


test_that(".compute_ece() returns ~0 for a perfectly calibrated set", {
  # Construct exact calibration: within each bin the observed rate equals the
  # predicted probability. 10 groups of 100, predicted 0.05, 0.15, ... 0.95 —
  # 100 per group so prob * n is a whole number for every group and the
  # agreement is exact rather than rounding-limited.
  probs <- seq(0.05, 0.95, by = 0.10)
  p <- rep(probs, each = 100)
  y <- unlist(lapply(probs, function(prob) {
    n_event <- round(prob * 100)
    c(rep(1L, n_event), rep(0L, 100 - n_event))
  }))

  res <- .compute_ece(y, p, n_bins = 10)

  expect_lt(res$ece, 0.001)
})


test_that(".compute_ece() reports large error for a deliberately miscalibrated set", {
  # Predict high risk for everyone; nobody has the event. ECE should approach
  # the gap between predicted and observed.
  p <- rep(0.90, 100)
  y <- rep(0L, 100)

  res <- .compute_ece(y, p, n_bins = 10)

  expect_gt(res$ece, 0.85)
  expect_lt(res$ece, 1.0)

  # A miscalibrated model must not be reported as well calibrated — guard the
  # direction explicitly, since a crossed-column bug could invert this.
  expect_gt(res$bin_data$mean_pred[1], res$bin_data$mean_obs[1])
})


test_that(".compute_ece() falls back to a single bin when quantiles collapse", {
  # All identical predictions make every quantile break identical, so
  # length(unique(breaks)) < 3 and the function must fall back to c(0, 1)
  # rather than handing cut() a degenerate breaks vector.
  p <- rep(0.4, 50)
  y <- rbinom(50, 1, 0.4)

  res <- .compute_ece(y, p, n_bins = 10)

  expect_equal(nrow(res$bin_data), 1L)
  expect_equal(res$bin_data$n_pred, 50L)
  expect_false(is.na(res$ece))
})


test_that(".compute_ece() clamps probabilities away from 0 and 1", {
  # REGRESSION (found by this test, fixed 2026-08-14): a bimodal prediction set
  # clamped to [0.0001, 0.9999] yields quantile breaks
  # c(0.0001, 0.0001, 0.5, 0.9999, 0.9999) — five values, three unique. The old
  # `length(unique(breaks)) < 3` guard did not fire and did not de-duplicate, so
  # cut() aborted with "'breaks' are not unique" and took the whole report with
  # it. Predictions concentrated near 0 and 1 are entirely realistic for a
  # confident model or a small cohort, so this was reachable in normal use.
  p <- c(rep(0, 25), rep(1, 25))
  y <- c(rep(0L, 25), rep(1L, 25))

  expect_no_error(res <- .compute_ece(y, p, n_bins = 4))

  expect_false(is.na(res$ece))
  expect_false(is.infinite(res$ece))
  expect_lt(res$ece, 0.01)  # this set is essentially perfectly calibrated

  # Fewer bins than requested is the correct outcome for a concentrated
  # distribution — assert it collapsed rather than silently recycling a break.
  expect_lt(nrow(res$bin_data), 4L)
})


# -----------------------------------------------------------------------------
# .append_references_section()
# -----------------------------------------------------------------------------

test_that(".append_references_section() returns the doc untouched for no citations", {
  doc <- officer::read_docx()

  # Both the NULL and the zero-length cases must short-circuit, so a report with
  # no bibliography does not gain an empty "References" heading.
  n_before <- nrow(officer::docx_summary(doc))
  expect_equal(nrow(officer::docx_summary(.append_references_section(doc, NULL))),
               n_before)
  expect_equal(nrow(officer::docx_summary(.append_references_section(doc, list()))),
               n_before)
})


test_that(".append_references_section() writes numbered Vancouver-format references", {
  citations <- list(
    list(authors = "Anderson DJ, Podgorny K", title = "Strategies to prevent SSI",
         journal = "Infect Control Hosp Epidemiol", year = "2014",
         volume = "35", issue = "6", pages = "605-27", doi = "10.1086/676022"),
    list(authors = "Iannuzzi JC", title = "Risk score for discharge",
         journal = "J Vasc Surg", year = "2013",
         volume = "58", issue = "5", pages = "1281-6", doi = "10.1016/j.jvs.2013.05.011")
  )

  doc <- .append_references_section(officer::read_docx(), citations)
  text <- officer::docx_summary(doc)$text

  expect_true(any(text == "References"))

  # Numbering is positional (1., 2., ...) and must track list order.
  expect_true(any(grepl("^1\\. Anderson DJ", text)))
  expect_true(any(grepl("^2\\. Iannuzzi JC", text)))

  # Spot-check the full Vancouver assembly, including the doi: prefix.
  expect_true(any(grepl(
    "1\\. Anderson DJ, Podgorny K\\. Strategies to prevent SSI\\. .*2014;35\\(6\\):605-27\\. doi:10\\.1086/676022",
    text)))
})


# -----------------------------------------------------------------------------
# .build_table1()
# -----------------------------------------------------------------------------

test_that(".build_table1() produces a flextable with one body row per input row", {
  df <- data.frame(
    variable    = c("Age >= 65", "Diabetes"),
    points      = c(2L, 1L),
    lookback    = c("index", "365d"),
    omop_domain = c("Person", "Condition"),
    derivation  = c("year_of_birth", "condition_occurrence descendants"),
    stringsAsFactors = FALSE
  )

  ft <- .build_table1(df)

  expect_s3_class(ft, "flextable")
  expect_equal(nrow(ft$body$dataset), 2L)

  # Assert the header labels via the RENDERED document rather than flextable's
  # internal chunkset. set_header_labels() does not touch $header$dataset (which
  # keeps the raw column keys), and the internal representation is not part of
  # flextable's public API — reading it would make this test fragile against
  # flextable upgrades. Rendering checks the contract that actually matters:
  # what lands in the manuscript.
  docx_path <- tempfile(fileext = ".docx")
  on.exit(unlink(docx_path), add = TRUE)
  doc <- flextable::body_add_flextable(officer::read_docx(), ft)
  print(doc, target = docx_path)

  rendered <- officer::docx_summary(officer::read_docx(docx_path))$text
  for (label in c("Variable", "Points", "Lookback Window",
                  "OMOP Domain", "OMOP Derivation Method")) {
    expect_true(any(rendered == label), info = paste("missing header:", label))
  }

  # And the body values must survive rendering too.
  expect_true(any(rendered == "Age >= 65"))
  expect_true(any(rendered == "Diabetes"))
})


# -----------------------------------------------------------------------------
# .strip_heading_autonumbering()
# -----------------------------------------------------------------------------

test_that(".strip_heading_autonumbering() removes numPr from heading styles", {
  # officer's default template is the French locale one, so its heading styles
  # are Titre1/Titre2/Titre3 — one of the two naming schemes the function
  # handles.
  path <- tempfile(fileext = ".docx")
  on.exit(unlink(path), add = TRUE)
  doc <- officer::read_docx()
  doc <- officer::body_add_par(doc, "A heading", style = "heading 1")
  print(doc, target = path)

  # Inject auto-numbering into a heading style so there is something to strip,
  # mimicking a corporate template.
  work <- tempfile("docx_inject_"); dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  utils::unzip(path, exdir = work)
  styles <- file.path(work, "word", "styles.xml")
  xml <- paste(readLines(styles, warn = FALSE), collapse = "\n")
  skip_if_not(grepl('w:styleId="Titre1"', xml), "template has no Titre1 style")

  xml <- sub('(<w:style[^>]*w:styleId="Titre1"[^>]*>)',
             '\\1<w:pPr><w:numPr><w:ilvl w:val="0"/></w:numPr></w:pPr>',
             xml, perl = TRUE)
  writeLines(xml, styles, useBytes = TRUE)
  old <- setwd(work)
  utils::zip("rebuilt.docx", list.files(".", recursive = TRUE, all.files = TRUE,
                                        no.. = TRUE), flags = "-q -X")
  setwd(old)
  file.copy(file.path(work, "rebuilt.docx"), path, overwrite = TRUE)

  # Precondition: the numbering really is present before we strip it.
  expect_true(grepl("<w:numPr>", .read_styles_xml(path), fixed = TRUE))

  suppressMessages(.strip_heading_autonumbering(path))

  expect_false(grepl("<w:numPr>", .read_styles_xml(path), fixed = TRUE))

  # The archive must still be a readable docx afterwards — a rezip that loses
  # the relative paths would corrupt it while still "succeeding".
  expect_s3_class(officer::read_docx(path), "rdocx")
})


test_that(".strip_heading_autonumbering() fails soft rather than aborting a report", {
  # Missing file: returns its argument invisibly, no error.
  missing <- file.path(tempdir(), "no-such-file.docx")
  expect_silent(res <- .strip_heading_autonumbering(missing))
  expect_identical(res, missing)

  # A file that exists but is not a valid docx: the documented contract is a
  # non-fatal message, because a report must not die over heading cosmetics.
  # utils::unzip() also emits its own "error 1 in extracting from zip file"
  # warning on the way through, which is expected here and not the thing under
  # test — suppress it so the assertion is about our message, not unzip's.
  bogus <- tempfile(fileext = ".docx")
  writeLines("not a docx", bogus)
  on.exit(unlink(bogus), add = TRUE)
  suppressWarnings(
    expect_message(.strip_heading_autonumbering(bogus),
                   "Could not strip heading auto-numbering")
  )
})
