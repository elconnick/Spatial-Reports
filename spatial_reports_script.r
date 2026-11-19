############################################################
# Xenium QC Report Generator
#
# Collects run metrics for the PDF report (Xenium_QC_Report.Rmd):
# - Cells detected
# - Total transcripts
# - Median genes per cell
# - Median transcripts per cell
# - % transcripts assigned to cells
#
############################################################

library(dplyr)
library(readr)
library(purrr)

############################################################
# USER SETTINGS
############################################################

# Root directory containing all Xenium region folders
xenium_root <- "/nemo/stp/sequencing/inputs/instruments/xenium/10xdata/20260923__134312__SP26194_230926"

# Output folder
output_dir <- file.path(xenium_root, "QC_Report")

if (!dir.exists(output_dir)) {
  dir.create(output_dir)
}

############################################################
# FIND METRICS FILES
############################################################

metrics_files <- list.files(
  path = xenium_root,
  pattern = "metrics_summary.csv$",
  recursive = TRUE,
  full.names = TRUE
)

if (length(metrics_files) == 0) {
  stop("No metrics_summary.csv files found.")
}

############################################################
# EXTRACT REGION METRICS
############################################################

extract_region_metrics <- function(metrics_file) {
  
  metrics <- read.csv(
    metrics_file,
    stringsAsFactors = FALSE
  )
  
  data.frame(
    
    Region =
      metrics$region_name,
    
    Cells_Detected =
      metrics$num_cells_detected,
    
    Total_Transcripts =
      metrics$total_high_quality_decoded_transcripts,
    
    Median_Genes_Per_Cell =
      metrics$median_genes_per_cell,
    
    Median_Transcripts_Per_Cell =
      metrics$median_transcripts_per_cell,
    
    Percent_Assigned =
      metrics$fraction_transcripts_assigned * 100,
    
    stringsAsFactors = FALSE
    
  )
}

############################################################
# BUILD REGION SUMMARY TABLE
############################################################

summary_df <- metrics_files |>
  lapply(extract_region_metrics) |>
  bind_rows()

############################################################
# OVERALL RUN METRICS
############################################################

overall_summary <- data.frame(
  
  Metric = c(
    "Regions Analysed",
    "Total Cells Detected",
    "Total Transcripts",
    "Median Genes Per Cell",
    "Median Transcripts Per Cell",
    "Mean % Transcripts Assigned"
  ),
  
  Value = c(
    nrow(summary_df),
    
    format(
      sum(summary_df$Cells_Detected),
      big.mark = ","
    ),
    
    format(
      sum(summary_df$Total_Transcripts),
      big.mark = ","
    ),
    
    round(
      median(summary_df$Median_Genes_Per_Cell),
      1
    ),
    
    round(
      median(summary_df$Median_Transcripts_Per_Cell),
      1
    ),
    
    round(
      mean(summary_df$Percent_Assigned),
      1
    )
  )
  
)

############################################################
# OUTLIER DETECTION
############################################################

summary_df <- summary_df %>%
  mutate(
    
    z_cells =
      as.numeric(scale(Cells_Detected)),
    
    z_genes =
      as.numeric(scale(Median_Genes_Per_Cell)),
    
    z_transcripts =
      as.numeric(scale(Median_Transcripts_Per_Cell)),
    
    z_assigned =
      as.numeric(scale(Percent_Assigned))
    
  )

############################################################
# GENERATE INTERPRETATION
############################################################

outlier_text <- c()

for(i in seq_len(nrow(summary_df))) {
  
  issues <- c()
  
  if(abs(summary_df$z_cells[i]) > 2) {
    issues <- c(
      issues,
      paste0(
        "cell detection (",
        summary_df$Cells_Detected[i],
        " cells)"
      )
    )
  }
  
  if(abs(summary_df$z_genes[i]) > 2) {
    issues <- c(
      issues,
      paste0(
        "median genes per cell (",
        summary_df$Median_Genes_Per_Cell[i],
        ")"
      )
    )
  }
  
  if(abs(summary_df$z_transcripts[i]) > 2) {
    issues <- c(
      issues,
      paste0(
        "median transcripts per cell (",
        summary_df$Median_Transcripts_Per_Cell[i],
        ")"
      )
    )
  }
  
  if(abs(summary_df$z_assigned[i]) > 2) {
    issues <- c(
      issues,
      paste0(
        "% transcripts assigned (",
        round(summary_df$Percent_Assigned[i], 1),
        "%)"
      )
    )
  }
  
  if(length(issues) > 0) {
    
    outlier_text <- c(
      outlier_text,
      
      paste(
        "Region",
        summary_df$Region[i],
        "showed unusual performance for:",
        paste(issues, collapse = ", "),
        ". Review in Xenium Explorer is recommended."
      )
      
    )
    
  }
  
}

if(length(outlier_text) == 0) {
  
  outlier_text <- c(
    "No significant regional outliers were identified.",
    "All regions demonstrated consistent data quality."
  )
  
}

############################################################
# SAVE OBJECTS FOR REPORT
############################################################

report_data_file <- file.path(
  output_dir,
  "report_data.RData"
)

save(
  summary_df,
  overall_summary,
  outlier_text,
  file = report_data_file
)

message(
  "Report data written to: ",
  report_data_file,
  "\nRender the PDF with Xenium_QC_Report.Rmd."
)
