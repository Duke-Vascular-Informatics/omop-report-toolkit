# =============================================================================
# tests/testthat/test-figure-style.R
#
# Covers the pure logic in R/figure_style.R:
#   .gs_series_palette          — the fixed greyscale encoding table's invariants
#   .gs_scales()                — slot assignment and its guard rails
#   .calibration_axis_limits()  — data-driven square limits, clamping, padding
#   .png_aspect()               — PNG header parsing and its NA fallbacks
#
# Deliberately NOT covered: save_figure() and theme_manuscript(). The first
# writes three image files through three graphics devices (one of which,
# ragg::agg_tiff, may legitimately be absent — see .have_ragg()); the second is
# a thin theme_minimal() wrapper. Neither has branching logic worth asserting,
# and both would make the suite depend on device availability rather than on
# this package's behaviour.
# =============================================================================

test_that(".gs_series_palette keeps the invariants the greyscale scheme relies on", {
  # The whole point of this table is redundant encoding across three channels,
  # so a row must never be missing one of them.
  expect_true(all(c("colour", "linetype", "shape") %in% names(.gs_series_palette)))
  expect_equal(nrow(.gs_series_palette), 8L)

  # Slots must be distinguishable in PRINT, not just on screen: no two rows may
  # share both colour and linetype, or they collapse in greyscale — the exact
  # failure this table was created to prevent.
  combos <- paste(.gs_series_palette$colour, .gs_series_palette$linetype)
  expect_equal(anyDuplicated(combos), 0L)

  # Slots 1-2 are the primary curves and must be black; 5-6 are subordinate
  # reference strategies and must be the lightest grey, so they never out-rank
  # a model curve.
  expect_equal(.gs_series_palette$colour[1:2], c("black", "black"))
  expect_equal(.gs_series_palette$colour[5:6], c("grey70", "grey70"))

  # Shapes are passed to scale_shape_manual() and must be valid pch integers.
  expect_type(.gs_series_palette$shape, "double")
  expect_true(all(.gs_series_palette$shape >= 0 & .gs_series_palette$shape <= 25))
})


test_that(".gs_scales() assigns palette slots in order and names them by level", {
  levels <- c("Model A", "Model B", "Model C")
  scales <- .gs_scales(levels)

  expect_named(scales, c("colour", "linetype", "shape"))
  expect_s3_class(scales$colour, "ScaleDiscrete")
  expect_s3_class(scales$linetype, "ScaleDiscrete")
  expect_s3_class(scales$shape, "ScaleDiscrete")

  # Default slots are 1, 2, 3 ... — assert the actual values reach the scale,
  # since silent recycling here is what produced the two-curves-look-identical
  # bug this helper exists to prevent.
  expect_equal(scales$colour$palette.cache, NULL)  # not yet trained
  expect_equal(unname(scales$colour$palette(3)), .gs_series_palette$colour[1:3])
  expect_equal(names(scales$colour$palette(3)), levels)
})


test_that(".gs_scales() honours explicit slots so subordinate series stay subordinate", {
  # The motivating case from the docs: one model curve plus two decision-curve
  # reference strategies. Without explicit slots, "Treat all" would inherit
  # slot 2 (black, filled triangle) and out-rank the model it sits behind.
  levels <- c("Model", "Treat all", "Treat none")
  scales <- .gs_scales(levels, slots = c(1, 5, 6))

  expect_equal(unname(scales$colour$palette(3)),
               .gs_series_palette$colour[c(1, 5, 6)])
  expect_equal(unname(scales$shape$palette(3)),
               .gs_series_palette$shape[c(1, 5, 6)])
})


test_that(".gs_scales() errors rather than silently recycling or mis-indexing", {
  # More series than the table defines (8 slots as of 2026-08-30). Recycling
  # here would defeat the entire purpose of the palette, so this must be a
  # hard error.
  expect_error(
    .gs_scales(paste("Model", 1:9)),
    "greyscale-safe slots",
    fixed = FALSE
  )

  # slots must be one-per-level.
  expect_error(
    .gs_scales(c("A", "B"), slots = c(1)),
    "one entry per level"
  )

  # Out-of-range slot indices, both directions.
  expect_error(.gs_scales(c("A"), slots = c(0)),  "must index rows 1-8")
  expect_error(.gs_scales(c("A"), slots = c(99)), "must index rows 1-8")
})


test_that(".gs_scales() supports 7-8 series (added 2026-08-30)", {
  # Regression test for the real (non-synthetic) report that first needed 7
  # series -- a by-year trend figure's "indication" panel, which on synthetic
  # data never exceeded 3 non-zero categories. Must not error, and the two
  # new slots must stay visually distinct from every other row (no duplicate
  # colour+linetype combo -- the general invariant test above already covers
  # this for all 8 rows, but assert it explicitly here too since that's the
  # exact failure mode this addition risked reintroducing).
  levels <- paste("Series", 1:8)
  scales <- .gs_scales(levels)
  expect_equal(unname(scales$colour$palette(8)), .gs_series_palette$colour)
  expect_equal(unname(scales$shape$palette(8)),  .gs_series_palette$shape)

  combos <- paste(.gs_series_palette$colour[7:8], .gs_series_palette$linetype[7:8])
  expect_false(any(combos %in% paste(.gs_series_palette$colour[1:6], .gs_series_palette$linetype[1:6])))
})


test_that(".calibration_axis_limits() zooms to the data but stays square and in [0, 1]", {
  res <- .calibration_axis_limits(c(0.20, 0.60))

  expect_named(res, c("limits", "breaks", "pad"))
  expect_length(res$limits, 2L)

  # Padding is 8% of the data range by default.
  expect_equal(res$pad, 0.08 * 0.40)
  expect_equal(res$limits, c(0.20 - 0.032, 0.60 + 0.032))

  # Breaks must fall inside the limits, or ggplot draws axis labels outside the
  # panel.
  expect_true(all(res$breaks >= res$limits[1] & res$breaks <= res$limits[2]))
})


test_that(".calibration_axis_limits() clamps to [0, 1] because these are probabilities", {
  # Data touching both ends must not produce limits outside [0, 1].
  res <- .calibration_axis_limits(c(0, 1))
  expect_gte(res$limits[1], 0)
  expect_lte(res$limits[2], 1)
  expect_equal(res$limits, c(0, 1))
})


test_that(".calibration_axis_limits() enforces a minimum pad on degenerate ranges", {
  # All-identical values give diff() == 0. Without the floor of 0.02 the limits
  # would collapse to a zero-width range and the panel would be unplottable.
  res <- .calibration_axis_limits(c(0.5, 0.5, 0.5))
  expect_equal(res$pad, 0.02)
  expect_equal(res$limits, c(0.48, 0.52))
  expect_true(diff(res$limits) > 0)
})


test_that(".calibration_axis_limits() ignores NA rather than propagating it", {
  res <- .calibration_axis_limits(c(0.2, NA, 0.6))
  expect_false(any(is.na(res$limits)))
  expect_equal(res$limits, .calibration_axis_limits(c(0.2, 0.6))$limits)
})


test_that(".calibration_reference_line() is solid grey, never dotted or dashed", {
  ref <- .calibration_reference_line()

  # A dotted reference line would be visually identical to a slot-4 model
  # curve, which is the documented reason this is pinned to solid.
  expect_equal(ref$aes_params$linetype, "solid")
  expect_equal(ref$aes_params$colour, "grey80")
  expect_lt(ref$aes_params$linewidth, 0.5)
})


test_that(".png_aspect() reads height/width from a real PNG header", {
  path <- .test_write_png(width_px = 800, height_px = 400)
  on.exit(unlink(path), add = TRUE)

  expect_equal(.png_aspect(path), 0.5, tolerance = 1e-9)

  tall <- .test_write_png(width_px = 300, height_px = 900)
  on.exit(unlink(tall), add = TRUE)
  expect_equal(.png_aspect(tall), 3, tolerance = 1e-9)
})


test_that(".png_aspect() returns NA_real_ instead of erroring on bad input", {
  # The documented contract: callers pass the return value of a plotting helper,
  # which is NULL when the figure could not be built. file.exists(NULL) is
  # logical(0) and would make an `if` error out, so NULL must be screened.
  expect_identical(.png_aspect(NULL), NA_real_)
  expect_identical(.png_aspect(NA_character_), NA_real_)
  expect_identical(.png_aspect(""), NA_real_)
  expect_identical(.png_aspect(c("a.png", "b.png")), NA_real_)
  expect_identical(.png_aspect(file.path(tempdir(), "does-not-exist.png")), NA_real_)

  # A file that exists but is not a PNG must fail soft, not abort a report.
  not_png <- tempfile(fileext = ".png")
  writeLines("this is not a PNG", not_png)
  on.exit(unlink(not_png), add = TRUE)
  expect_identical(.png_aspect(not_png), NA_real_)
})
