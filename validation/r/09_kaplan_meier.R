# Kaplan-Meier (survfit, IC log) et log-rank (survdiff) — jeux publics lung et veteran.
source("_common.R")
suppressPackageStartupMessages(library(survival))
lung <- read.csv(file.path(REF_DIR, "cox_lung.csv")); vet <- read.csv(file.path(REF_DIR, "cox_veteran.csv"))
km <- function(d, g) {
  f <- survfit(Surv(time, deces == "oui") ~ 1, data = d, conf.type = "log")
  tab <- summary(f)$table
  ev <- f$n.event > 0
  list(time = f$time[ev], surv = f$surv[ev], se = f$std.err[ev], lower = f$lower[ev], upper = f$upper[ev], n_risk = f$n.risk[ev],
       median = unname(tab["median"]), mlo = unname(tab["0.95LCL"]), mhi = unname(tab["0.95UCL"]),
       s365 = summary(f, times = 365, extend = TRUE)$surv)
}
lr <- function(f, d) { s <- survdiff(f, data = d); list(chi2 = s$chisq, obs = unname(s$obs), exp = unname(s$exp)) }
# Médiane sur un palier exactement à 0,5 : 4 sujets, 2 décès.
half <- data.frame(time = c(1, 2, 3, 4), deces = c("oui", "oui", "oui", "non"))
hf <- survfit(Surv(time, deces == "oui") ~ 1, data = half)
write_ref(list(
  lung_all = km(lung), lung_F = km(subset(lung, sexe == "F")), lung_H = km(subset(lung, sexe == "H")),
  lung_lr = lr(Surv(time, deces == "oui") ~ sexe, lung),
  vet_lr = lr(Surv(time, deces == "oui") ~ celltype, vet),
  half_median = unname(summary(hf)$table["median"])), "kaplan_meier")
