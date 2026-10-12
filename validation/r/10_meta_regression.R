# Méta-régression : références metafor::rma(mods = ) sur les essais du BCG.
source("_common.R")
suppressPackageStartupMessages(library(metafor))
ctl <- list(threshold = 1e-12, maxiter = 1000)
b <- dat.bcg
b$alloc2 <- ifelse(b$alloc == "random", "aleatoire", "non aleatoire")
es <- escalc(measure = "RR", ai = tpos, bi = tneg, ci = cpos, di = cneg, data = b)
one <- function(mods, method, test = "z") {
  m <- rma(yi, vi, mods = mods, data = es, method = method, test = test, control = ctl)
  list(b = as.numeric(m$beta), se = m$se, lower = m$ci.lb, upper = m$ci.ub, p = m$pval, tau2 = m$tau2, QE = m$QE, QEp = m$QEp,
       QM = m$QM, QMp = m$QMp, I2 = m$I2 / 100, H2 = m$H2, R2 = if (is.null(m$R2)) NA else m$R2 / 100)
}
write_ref(list(
  ablat_reml = one(~ ablat, "REML"), ablat_dl = one(~ ablat, "DL"), ablat_fe = one(~ ablat, "FE"),
  ablat_knha = one(~ ablat, "REML", "knha"),
  ablat_alloc = one(~ ablat + alloc2, "REML"), year_reml = one(~ year, "REML")), "meta_regression")
