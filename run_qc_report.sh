#!/usr/bin/env bash
############################################################
# Xenium QC Report wrapper
#
# 1. Activates the renv environment
# 2. Checks R, the R packages and Quarto are available
# 3. Runs spatial_reports_script.r to collect run metrics
# 4. Renders Xenium_QC_Report.qmd to PDF with Quarto (Typst)
#
# Usage:
#   ./run_qc_report.sh /path/to/xenium/run_folder
#
# Settings (environment variables, all optional):
#   RENV_PROJECT   renv project folder containing renv/activate.R
#                  (default: the folder this script is in)
#   QUARTO_MODULE  environment module to load if quarto is not
#                  on PATH, e.g. "Quarto/1.6.40"
############################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RENV_PROJECT="${RENV_PROJECT:-$SCRIPT_DIR}"
QUARTO_MODULE="${QUARTO_MODULE:-}"

R_SCRIPT="$SCRIPT_DIR/spatial_reports_script.r"
QMD_TEMPLATE="$SCRIPT_DIR/Xenium_QC_Report.qmd"
REPORT_NAME="Xenium_Run_QC_Report.pdf"

# Quarto 1.4 is the first release with Typst PDF output
MIN_QUARTO_VERSION="1.4.0"

# R packages used by the script and the report
R_PACKAGES="dplyr readr purrr knitr rmarkdown"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

step() {
  echo
  echo "==> $*"
}

############################################################
# ARGUMENTS
############################################################

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 /path/to/xenium/run_folder" >&2
  exit 1
fi

[ -d "$1" ] || die "Xenium run folder not found: $1"
XENIUM_ROOT="$(cd "$1" && pwd)"
OUTPUT_DIR="$XENIUM_ROOT/QC_Report"
REPORT_DATA="$OUTPUT_DIR/report_data.RData"

[ -f "$R_SCRIPT" ] || die "Missing $R_SCRIPT"
[ -f "$QMD_TEMPLATE" ] || die "Missing $QMD_TEMPLATE"

############################################################
# CHECK TOOLS
############################################################

step "Checking R and Quarto"

command -v Rscript > /dev/null 2>&1 ||
  die "Rscript not found on PATH. Start the R environment (container or module) first."
echo "Rscript: $(command -v Rscript)"

if ! command -v quarto > /dev/null 2>&1 && [ -n "$QUARTO_MODULE" ]; then
  if type module > /dev/null 2>&1; then
    echo "Loading module $QUARTO_MODULE"
    module load "$QUARTO_MODULE"
  else
    echo "QUARTO_MODULE is set but the 'module' command is not available." >&2
  fi
fi

command -v quarto > /dev/null 2>&1 ||
  die "quarto not found on PATH. Install Quarto >= $MIN_QUARTO_VERSION, or set QUARTO_MODULE to a module that provides it."

QUARTO_VERSION="$(quarto --version | tr -d '[:space:]')"
OLDEST="$(printf '%s\n%s\n' "$MIN_QUARTO_VERSION" "$QUARTO_VERSION" | sort -t. -k1,1n -k2,2n -k3,3n | head -n 1)"
[ "$OLDEST" = "$MIN_QUARTO_VERSION" ] ||
  die "Quarto $QUARTO_VERSION is too old; Typst PDF output needs $MIN_QUARTO_VERSION or later."
echo "Quarto: $(command -v quarto) (version $QUARTO_VERSION)"

############################################################
# ACTIVATE RENV AND CHECK R PACKAGES
############################################################

step "Activating renv project: $RENV_PROJECT"

[ -f "$RENV_PROJECT/renv/activate.R" ] ||
  die "No renv/activate.R in $RENV_PROJECT. Set RENV_PROJECT to your renv project folder."

# Activates renv the same way the project's .Rprofile would, checks
# every package, and prints the resulting library paths so the
# script and Quarto's R session use the same libraries.
R_LIBS_RENV="$(
  cd "$RENV_PROJECT" &&
  R_PACKAGES="$R_PACKAGES" Rscript --no-init-file -e '
    source("renv/activate.R")
    pkgs <- strsplit(Sys.getenv("R_PACKAGES"), " ")[[1]]
    missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
    if (length(missing) > 0) {
      message("Missing R packages in this renv environment: ",
              paste(missing, collapse = ", "))
      message("Install them with: renv::install(c(",
              paste0("\"", missing, "\"", collapse = ", "), "))")
      quit(status = 1)
    }
    message("R ", getRversion(), ", all packages found: ",
            paste(pkgs, collapse = ", "))
    cat("R_LIBS_RENV=", paste(.libPaths(), collapse = ":"), "\n", sep = "")
  ' | sed -n 's/^R_LIBS_RENV=//p'
)" || die "renv environment check failed (see messages above)."

[ -n "$R_LIBS_RENV" ] || die "Could not read library paths from the renv environment."
export R_LIBS="$R_LIBS_RENV"
echo "Library paths: $R_LIBS"

############################################################
# COLLECT METRICS
############################################################

step "Collecting metrics from $XENIUM_ROOT"

Rscript --no-init-file "$R_SCRIPT" "$XENIUM_ROOT"

[ -f "$REPORT_DATA" ] || die "Script finished but $REPORT_DATA was not written."

############################################################
# RENDER REPORT
############################################################

step "Rendering report with Quarto"

# Render in a temporary folder so Quarto's intermediate files
# never land in the code folder or the run folder.
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

cp "$QMD_TEMPLATE" "$WORK_DIR/Xenium_QC_Report.qmd"

# Parameters go through a YAML file so paths and run names are
# always read as quoted strings.
cat > "$WORK_DIR/params.yml" <<EOF
data_file: "$REPORT_DATA"
run_name: "$(basename "$XENIUM_ROOT")"
EOF

(
  cd "$WORK_DIR" &&
  quarto render Xenium_QC_Report.qmd \
    --to typst \
    --execute-params params.yml \
    --output "$REPORT_NAME"
)

[ -f "$WORK_DIR/$REPORT_NAME" ] || die "Quarto did not produce $REPORT_NAME."
mv "$WORK_DIR/$REPORT_NAME" "$OUTPUT_DIR/$REPORT_NAME"

step "Report written to: $OUTPUT_DIR/$REPORT_NAME"
