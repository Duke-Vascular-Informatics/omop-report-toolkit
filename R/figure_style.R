# =============================================================================
# R/figure_style.R
#
# Shared greyscale-safe styling for manuscript figures.
#
# WHEN THIS FILE APPLIES
#   Strategus itself produces no manuscript figures. Its outputs are result
#   tables in a results schema, browsed interactively through the OHDSI Shiny
#   viewer. Neither is what a journal receives.
#
#   Manuscript figures come from an OPTIONAL custom step / Word report layered
#   on top of a study's analysis - the pad-amp-ed-desc hybrid pattern. If a
#   study has no such step, it never calls library(omopReportToolkit) and this
#   file costs nothing. If it does, every figure it draws should go through
#   here rather than hand-rolling a new palette.
#
# WHY IT EXISTS
#   Journals commonly print in greyscale, and the default reflex - one hue per
#   series - fails badly there. Hues chosen to look distinct on screen tend to
#   have near-identical LUMINANCE, so desaturating collapses them to a single
#   indistinguishable grey. In the study this was extracted from
#   (pad-amp-nhd-val, #42/#43), a four-curve calibration overlay used navy /
#   red / green / orange; in greyscale all four became one line. The same
#   figure's reference diagonal was `dotted`, which was also the linetype of
#   one model curve, so that curve disappeared into the reference line even
#   BEFORE any greyscale conversion.
#
#   The fix is redundancy, not a better palette. Every multi-series figure
#   draws colour, linetype AND shape from one fixed table (.gs_series_palette)
#   via .gs_scales(): three independent channels, so a figure survives a bad
#   photocopy and not merely a clean PDF desaturation.
#
#   Never assign per-figure hex colours to a new series. Add a slot to
#   .gs_series_palette instead - that is also what keeps figures agreeing with
#   each other. Before this table existed, a study's ROC and calibration
#   figures had drifted onto different palettes and the SAME model appeared
#   orange on one figure and green on the next.
#
# EXPORTS
#   .gs_series_palette            - the fixed grey/linetype/shape encoding table
#   .gs_scales()                  - scale_colour/linetype/shape triple for N series
#   theme_manuscript()            - shared ggplot2 theme, print-legible base size
#   save_figure()                 - writes a ggplot as matched 600dpi TIFF + PDF + PNG
#   .calibration_axis_limits()    - data-driven square limits for calibration plots
#   .calibration_reference_line() - the shared perfect-calibration diagonal
#   .png_aspect()                 - a saved PNG's height/width ratio, for
#                                    officer::body_add_img() sizing
#
# PACKAGE NOTES (read before editing)
#   This file is a workspace-wide shared package, consumed via
#   renv::install("Duke-Vascular-Informatics/omop-report-toolkit@<sha>"). Two
#   consequences that would not apply if this were still a per-study
#   source()d file:
#
#   1. No library() calls here. ggplot2 and patchwork are declared in
#      DESCRIPTION's Imports and referenced via `::` throughout, per normal
#      package hygiene - calling library() inside a package silently changes
#      the caller's search path, which is exactly the kind of surprise a
#      shared dependency must not introduce.
#   2. ragg availability is checked with a FUNCTION (.have_ragg()), not a
#      cached top-level variable. A package's R/ files run once, at BUILD
#      time, not once per library() call - caching
#      `requireNamespace("ragg", ...)` into a top-level object the way a
#      source()d script safely could would freeze whatever was true on the
#      machine that built the package, not the machine that later installs
#      and runs it.
# =============================================================================

# ragg is checked SOFTLY, not with library() or a cached top-level flag (see
# PACKAGE NOTES above).
#
# It is the preferred TIFF device (best text rendering), but it compiles
# against system libraries - libpng, libtiff, freetype, harfbuzz, fribidi.
# Some analytic environments (e.g. a PRCC bundle installer that only does
# `module load R` with no system-package provisioning) may legitimately fail
# to install it. A hard dependency would then abort the entire analysis at
# load time over a figure-device preference, after every other package had
# installed fine.
#
# save_figure() falls back to grDevices::tiff() when this is FALSE. The
# fallback still produces 600 dpi LZW TIFF; only the text rasterisation
# differs.
.have_ragg <- function() {
  ok <- requireNamespace("ragg", quietly = TRUE)
  if (!ok) {
    message("[figures] ragg not available - using grDevices::tiff() for TIFF output. ",
            "Still 600 dpi LZW; text rendering may differ slightly.")
  }
  ok
}


# -----------------------------------------------------------------------------
# .gs_series_palette
#
# Fixed, ordered greyscale encoding table. Slot order is significant - the
# Nth level of a factor always gets the Nth row, never chosen by name - so
# that e.g. "Iannuzzi (Lookup)" is always solid/filled-circle/black no matter
# which other series are present in a given figure (2-, 3-, and 4-curve
# variants of a calibration overlay all share slots 1-2 for two shared
# curves).
#
# Slots 1-4: up to four primary model/series curves shared by an overlay
#   figure family (e.g. calibration and ROC overlays for the same models).
# Slots 5-6: reserved for non-model reference strategies (e.g. a decision
#   curve's "Treat all" / "Treat none"), which must be visually subordinate
#   (lighter grey, undecorated shapes) to the primary curves.
# Slots 7-8: added 2026-08-30 after a real (non-synthetic) report needed 7
#   series for the first time -- a by-year trend figure's "indication" panel,
#   which on synthetic data never exceeded 3 non-zero categories (several
#   indication categories were zero-count there) but on real data can show
#   all 8 (Claudication/Rest pain/Tissue loss/Trauma/Access complication/
#   Exposure for endovascular procedure/ECMO/Asymptomatic). These callers use
#   the default seq_along() slot assignment (no primary/reference distinction
#   the way an overlay-family caller has), so slots 7-8 don't need to honor
#   the tiered "primary vs. reference" semantics above -- just stay visually
#   distinct from slots 1-6. A 4th grey tier (grey30, between black and
#   grey45) plus two unused shapes accomplish that.
#
# Slots 9-10: added 2026-08-31 after the SAME "indication" panel grew from 8
#   to 9 categories (pad-oler-ssi-prog merged Trauma + Access complication
#   into one, then added Aneurysm/Dissection and Acute limb ischemia -- net
#   +1) and hit this palette's limit again on a real report. All 6 named
#   ggplot2 linetypes (solid/dashed/dotted/dotdash/longdash/twodash) are
#   already used by slots 1-8, so slots 9-10 reuse linetypes already seen
#   elsewhere in the table -- uniqueness comes from the FULL (colour,
#   linetype, shape) combination, not the linetype alone, and every row
#   below is still a combination no other row shares. Two slots added
#   (not just the one needed right now) for headroom against the next
#   report that adds one more category.
#
#   slot  colour   linetype   shape                                   reads as
#   1     black    solid      16 (filled circle)                      primary, filled
#   2     black    longdash   17 (filled triangle)                    primary, filled
#   3     grey45   dotdash    0  (open square)                        secondary, hollow
#   4     grey45   dotted     5  (open diamond)                       secondary, hollow
#   5     grey70   solid      1  (open circle)                        reference, hollow
#   6     grey70   dashed     2  (open triangle)                      reference, hollow
#   7     black    twodash    15 (filled square)                      extra series, filled
#   8     grey30   solid      18 (filled diamond)                     extra series, filled
#   9     grey15   dashed     3  (plus)                                extra series, filled
#   10    black    dotted     4  (x)                                  extra series, filled
# -----------------------------------------------------------------------------
.gs_series_palette <- data.frame(
  colour   = c("black", "black", "grey45", "grey45", "grey70", "grey70", "black", "grey30", "grey15", "black"),
  linetype = c("solid", "longdash", "dotdash", "dotted", "solid", "dashed", "twodash", "solid", "dashed", "dotted"),
  shape    = c(16, 17, 0, 5, 1, 2, 15, 18, 3, 4),
  stringsAsFactors = FALSE
)

# -----------------------------------------------------------------------------
# .gs_scales()
#
# Returns the scale_colour_manual()/scale_linetype_manual()/scale_shape_manual()
# triple for a set of factor levels, sliced from .gs_series_palette in order.
#
# Arguments:
#   levels - character vector of factor levels, in the order they should be
#            assigned palette slots (i.e. the same order used to build the
#            plotting data frame's factor column).
#   slots  - optional integer vector, same length as `levels`, naming which
#            .gs_series_palette row each level takes. Defaults to 1, 2, 3, ...
#
#            Pass this explicitly whenever some series are semantically
#            SUBORDINATE and must land on the reserved reference slots (5-6)
#            regardless of how many primary series precede them. A decision
#            curve is the motivating case: with four models the defaults
#            happen to be right (4 models + 2 references == slots 1-6), but
#            with one model "Treat all" would otherwise inherit slot 2 -
#            black, filled triangle - and render MORE prominently than the
#            model curve it is supposed to sit behind. Callers should write
#            slots = c(seq_along(model_names), 5, 6).
#
# Returns a named list with elements $colour, $linetype, $shape - each a
# ggplot2 scale object, meant to be added to a plot with `+`. Errors if more
# levels are requested than the palette has slots (rather than silently
# recycling colours, which would defeat the whole point of this table).
# -----------------------------------------------------------------------------
.gs_scales <- function(levels, slots = seq_along(levels)) {
  n <- length(levels)
  if (n > nrow(.gs_series_palette)) {
    stop(".gs_scales(): ", n, " series requested but .gs_series_palette only ",
         "defines ", nrow(.gs_series_palette), " greyscale-safe slots. Add a ",
         "row to .gs_series_palette rather than falling back to hue.")
  }
  if (length(slots) != n) {
    stop(".gs_scales(): `slots` must have one entry per level (got ",
         length(slots), " for ", n, " levels).")
  }
  if (any(slots < 1L) || any(slots > nrow(.gs_series_palette))) {
    stop(".gs_scales(): `slots` must index rows 1-", nrow(.gs_series_palette),
         " of .gs_series_palette.")
  }
  spec <- .gs_series_palette[slots, , drop = FALSE]
  list(
    colour   = ggplot2::scale_colour_manual(values = setNames(spec$colour, levels)),
    linetype = ggplot2::scale_linetype_manual(values = setNames(spec$linetype, levels)),
    shape    = ggplot2::scale_shape_manual(values = setNames(spec$shape, levels))
  )
}

# -----------------------------------------------------------------------------
# theme_manuscript()
#
# Shared ggplot2 theme for every manuscript figure. A thin wrapper over
# theme_minimal() at a print-legible base size (9pt, sized for a single
# journal column at final print scale - ggplot2's default sizing is tuned for
# on-screen viewing, not a ~3.3in column width) with the legend pinned to the
# bottom, since every greyscale overlay figure carries a legend (shape +
# linetype key) rather than relying on colour alone to be self-explanatory.
# -----------------------------------------------------------------------------
theme_manuscript <- function(base_size = 9) {
  ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(
      legend.position = "bottom",
      legend.title     = ggplot2::element_blank(),
      legend.text      = ggplot2::element_text(size = base_size - 1),
      plot.title       = ggplot2::element_text(size = base_size + 1, face = "bold"),
      plot.subtitle    = ggplot2::element_text(size = base_size)
    )
}

# -----------------------------------------------------------------------------
# save_figure()
#
# Single save path for every manuscript figure. Journal submission requires
# print-resolution raster (600 dpi TIFF) and/or vector (PDF) figures; 150 dpi
# PNG is only adequate for on-screen review, so this writes all three from one
# ggplot object:
#   <file_stem>.tiff - 600 dpi, LZW-compressed, via ragg::agg_tiff when ragg
#                       is installed, else grDevices::tiff() (see .have_ragg())
#   <file_stem>.pdf  - vector, via the Cairo PDF device (scales losslessly)
#   <file_stem>.png  - 150 dpi, kept for on-screen review and for
#                       officer::body_add_img(), which cannot embed TIFF/PDF
#
# Arguments:
#   plot          - a ggplot object
#   output_folder - directory to write into (created if missing)
#   file_name     - base file name; any extension is ignored/replaced (e.g.
#                   passing "roc_curve.png" and "roc_curve.tiff" both produce
#                   the same three-file set with stem "roc_curve")
#   width, height - figure size in inches
#   dpi           - resolution for the TIFF; PNG is always saved at 150 dpi
#                   since it is a screen/Word-embedding artifact, not a
#                   submission file
#
# Returns the path to the .png file, so callers that embed the returned path
# into a Word report via officer::body_add_img() need no changes - the
# TIFF/PDF are written as a side effect.
# -----------------------------------------------------------------------------
save_figure <- function(plot, output_folder, file_name, width, height, dpi = 600) {
  if (!dir.exists(output_folder)) {
    dir.create(output_folder, recursive = TRUE, showWarnings = FALSE)
  }

  # Strip whatever extension was passed (or none) down to a bare stem.
  file_stem <- sub("\\.[A-Za-z0-9]+$", "", file_name)

  tiff_path <- file.path(output_folder, paste0(file_stem, ".tiff"))
  pdf_path  <- file.path(output_folder, paste0(file_stem, ".pdf"))
  png_path  <- file.path(output_folder, paste0(file_stem, ".png"))

  # Preferred device is ragg::agg_tiff; grDevices::tiff() is the fallback when
  # ragg could not be installed. Both write 600 dpi LZW. grDevices::tiff()
  # takes its size in the units given and needs an explicit res=, and "cairo"
  # typing for decent antialiased text where it is compiled in.
  if (.have_ragg()) {
    ggplot2::ggsave(tiff_path, plot, width = width, height = height, units = "in",
                    dpi = dpi, device = ragg::agg_tiff, compression = "lzw")
  } else {
    tiff_type <- if (isTRUE(capabilities("cairo"))) "cairo" else "windows"
    ggplot2::ggsave(tiff_path, plot, width = width, height = height, units = "in",
                    dpi = dpi, device = grDevices::tiff,
                    compression = "lzw", res = dpi, type = tiff_type)
  }
  ggplot2::ggsave(pdf_path, plot, width = width, height = height, units = "in",
                  device = grDevices::cairo_pdf)
  ggplot2::ggsave(png_path, plot, width = width, height = height, units = "in",
                  dpi = 150)

  png_path
}


# -----------------------------------------------------------------------------
# .calibration_axis_limits()
#
# Shared data-driven square axis limits for a calibration plot.
#
# WHY: a calibration panel hardcoded to limits = c(0, 1) on both axes wastes
# most of the panel whenever a cohort's curves live in a narrower range (e.g.
# x [0.09, 0.75] / y [0, 0.50]), cramming every curve into one corner. Zooming
# to the data is the single biggest legibility win here, independent of the
# greyscale requirement - and it matters MORE in greyscale, because curves
# that overlap in a cramped corner are exactly the ones grey levels alone
# cannot separate.
#
# The panel stays square (same limits on both axes) so the 45-degree
# perfect-calibration diagonal remains a true 45 degrees and the plot is not
# visually misleading.
#
# Arguments:
#   values - numeric vector of every value that must be visible (typically
#            c(predicted, observed) across all curves)
#   pad_frac - fractional padding beyond the data range (default 8%)
#
# Returns a list with $limits (length-2 numeric, clamped to [0, 1] since risk
# and observed rate are probabilities) and $breaks (pretty breaks inside them).
# -----------------------------------------------------------------------------
.calibration_axis_limits <- function(values, pad_frac = 0.08) {
  data_range <- range(values, na.rm = TRUE)
  pad        <- max(diff(data_range) * pad_frac, 0.02)
  limits     <- c(max(0, data_range[1] - pad), min(1, data_range[2] + pad))
  breaks     <- pretty(limits, n = 5)
  breaks     <- breaks[breaks >= limits[1] & breaks <= limits[2]]
  list(limits = limits, breaks = breaks, pad = pad)
}

# -----------------------------------------------------------------------------
# .calibration_reference_line()
#
# The perfect-calibration diagonal, as one shared geom so every calibration
# figure uses an identical reference line.
#
# Thin, light grey, SOLID. Deliberately not "dotted" or "dashed": in a 4-curve
# overlay those linetypes are typically taken by model slots 3 and 4, and a
# dotted reference line would be visually identical to a dotted model curve.
# Weight (0.4) and grey80 keep it subordinate to slot 1, which is also solid
# but black and heavier.
# -----------------------------------------------------------------------------
.calibration_reference_line <- function() {
  ggplot2::geom_abline(intercept = 0, slope = 1,
                       linetype = "solid", colour = "grey80", linewidth = 0.4)
}

# -----------------------------------------------------------------------------
# .png_aspect()
#
# Returns a PNG's height/width ratio, read straight from the file header.
#
# WHY: figures are embedded into a Word report with
# officer::body_add_img(width, height). Those two numbers must match the
# aspect ratio the figure was actually saved at, or the image is stretched.
# Hardcoding the ratio at the embed site duplicates a number that lives in the
# plotting code, and silently goes wrong the moment a figure's dimensions
# become dynamic - e.g. a dual-calibration plot that sizes itself from the
# number of curves. Reading the real file cannot drift.
#
# Parses the IHDR chunk (PNG spec: 8-byte signature, 4-byte length, 4-byte
# "IHDR", then width and height as big-endian uint32) rather than taking a
# dependency on the `png` package for two integers.
#
# Returns height/width, or NA_real_ if the file is missing or not a PNG, so
# callers can fall back rather than abort a report over a figure size.
# -----------------------------------------------------------------------------
.png_aspect <- function(path) {
  # Callers pass the return value of a plotting helper, which is NULL when the
  # figure could not be built - file.exists(NULL) is logical(0) and would make
  # the `if` error out, so screen that before touching the filesystem.
  if (is.null(path) || length(path) != 1L || is.na(path) ||
      !nzchar(path) || !file.exists(path)) {
    return(NA_real_)
  }
  tryCatch({
    con <- file(path, "rb"); on.exit(close(con), add = TRUE)
    sig <- readBin(con, "raw", 8L)
    if (!identical(as.integer(sig[2:4]), c(80L, 78L, 71L))) return(NA_real_)  # "PNG"
    readBin(con, "raw", 8L)                                    # length + "IHDR"
    dims <- readBin(con, "integer", n = 2L, size = 4L, endian = "big")
    if (length(dims) < 2L || any(dims <= 0L)) return(NA_real_)
    dims[2] / dims[1]                                          # height / width
  }, error = function(e) NA_real_)
}
