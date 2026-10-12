# Métaanalyse diagnostique bivariée : références mada::reitsma (REML, via mvmeta).
source("_common.R")
suppressPackageStartupMessages(library(mada))
one <- function(d, name) {
  write.csv(d[, c("TP", "FN", "FP", "TN")], file.path(REF_DIR, paste0("diagmeta_", name, ".csv")), row.names = FALSE)
  f <- reitsma(d, control = list(reltol = 1e-14, maxit = 5000))
  s <- summary(f)
  list(coef = as.numeric(f$coefficients), vcov = unname(f$vcov), Psi = unname(f$Psi), logLik = as.numeric(f$logLik),
       auc = as.numeric(s$AUC$AUC), sens_ci = as.numeric(s$coefficients[3, c(5, 6)]), fpr_ci = as.numeric(s$coefficients[4, c(5, 6)]))
}
data(AuditC); data(Dementia)
write_ref(list(auditc = one(AuditC, "auditc"), dementia = one(Dementia, "dementia"), mada = as.character(packageVersion("mada"))), "meta_diagnostic")
