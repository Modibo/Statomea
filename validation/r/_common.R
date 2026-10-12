# Utilitaires communs aux scripts de référence. Exécuter depuis validation/r/ :
#   Rscript 00_distributions.R
suppressPackageStartupMessages(library(jsonlite))
REF_DIR <- normalizePath(file.path("..", "..", "packages", "statomea_core", "test", "reference"), mustWork = FALSE)
dir.create(REF_DIR, showWarnings = FALSE, recursive = TRUE)
write_ref <- function(obj, name) {
  obj$`_meta` <- list(R = R.version.string, generated = format(Sys.Date()),
                      packages = lapply(c("metafor","logistf","pROC","sandwich","car"), function(p)
                        if (requireNamespace(p, quietly = TRUE)) paste(p, packageVersion(p)) else paste(p, "absent")))
  writeLines(toJSON(obj, digits = NA, auto_unbox = TRUE, null = "null", na = "null", pretty = TRUE),
             file.path(REF_DIR, paste0(name, ".json")))
  cat("écrit :", name, "\n")
}
