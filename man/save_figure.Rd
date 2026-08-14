% Hand-written, not roxygen2-generated - see NAMESPACE's header comment for
% why (no roxygen2/devtools in the authoring dev container). If you change
% save_figure()'s signature in R/figure_style.R, update this file to match
% by hand.
\name{save_figure}
\alias{save_figure}
\title{Save a manuscript figure as matched TIFF, PDF, and PNG}
\usage{
save_figure(plot, output_folder, file_name, width, height, dpi = 600)
}
\arguments{
\item{plot}{A ggplot object.}

\item{output_folder}{Directory to write into; created if missing.}

\item{file_name}{Base file name. Any extension is ignored and replaced -
passing \code{"roc_curve.png"} and \code{"roc_curve.tiff"} both produce the
same three-file set with stem \code{"roc_curve"}.}

\item{width, height}{Figure size in inches.}

\item{dpi}{Resolution for the TIFF. The PNG is always written at 150 dpi,
since it is a screen/Word-embedding artifact, not a submission file.}
}
\value{
The path to the written \code{.png} file, returned visibly so callers that
embed it into a Word report via \code{officer::body_add_img()} need no
further changes. The \code{.tiff}/\code{.pdf} files are written as a side
effect at the same stem.
}
\description{
Single save path for every manuscript figure in this package. Journal
submission requires print-resolution raster (600 dpi TIFF) and/or vector
(PDF) figures; a 150 dpi PNG is kept for on-screen review and for
\code{officer::body_add_img()}, which cannot embed TIFF or PDF directly.
Prefers \code{ragg::agg_tiff} for the TIFF device when the \code{ragg}
package is installed, and falls back to \code{grDevices::tiff()} otherwise
(see \code{.have_ragg()} in \code{R/figure_style.R}) - both write 600 dpi
LZW-compressed TIFF; only text rasterisation differs.
}
