# Modèle pronostique de Cox : risque de base (survfit.coxph), risque prédit à un horizon, concordance,
# pente de calibration et optimisme par bootstrap (Harrell), indices de rééchantillonnage rejoués à l'identique.
source("_common.R")
suppressPackageStartupMessages(library(survival))
lung <- read.csv(file.path(REF_DIR, "cox_lung.csv"))
d <- subset(lung, !is.na(age) & !is.na(sexe) & !is.na(ph.ecog))
d$ev <- as.integer(d$deces == "oui")
d$sexe <- factor(d$sexe, levels = c("F", "H"))
f <- Surv(time, ev) ~ age + sexe + ph.ecog
fit <- coxph(f, data = d, ties = "efron")
fitB <- coxph(f, data = d, ties = "breslow")
zero <- data.frame(age = 0, sexe = factor("F", levels = c("F", "H")), ph.ecog = 0)
H0 <- function(m, t, ctype = NULL) {
  s <- if (is.null(ctype)) survfit(m, newdata = zero) else survfit(m, newdata = zero, ctype = ctype)
  summary(s, times = t, extend = TRUE)$cumhaz
}
horizons <- c(180, 365, 730)
risk365 <- 1 - summary(survfit(fit, newdata = d), times = 365, extend = TRUE)$surv[1, ]
cstat <- function(time, ev, lp) concordance(Surv(time, ev) ~ lp, reverse = TRUE)$concordance
slope <- function(time, ev, lp) unname(coef(coxph(Surv(time, ev) ~ lp)))

# Bootstrap : indices tirés par R (base 0 dans le JSON), rejoués par le moteur.
set.seed(20261011)
B <- 60; n <- nrow(d)
idx <- t(replicate(B, sample.int(n, n, replace = TRUE)))
lpOf <- function(m, nd) as.vector(model.matrix(~ age + sexe + ph.ecog, nd)[, -1] %*% coef(m))
lpApp <- lpOf(fit, d)
optC <- optS <- numeric(B)
for (b in 1:B) {
  db <- d[idx[b, ], ]
  fb <- coxph(f, data = db, ties = "efron")
  optC[b] <- cstat(db$time, db$ev, lpOf(fb, db)) - cstat(d$time, d$ev, lpOf(fb, d))
  optS[b] <- 1 - slope(d$time, d$ev, lpOf(fb, d))
}
# Calibration à 365 jours, quintiles de risque prédit (même découpage que le moteur).
o <- order(risk365); cal <- list()
for (g in 0:4) {
  sel <- o[(floor(g * n / 5) + 1):floor((g + 1) * n / 5)]
  km <- summary(survfit(Surv(time, ev) ~ 1, data = d[sel, ], conf.type = "log"), times = 365, extend = TRUE)
  cal[[g + 1]] <- c(predicted = mean(risk365[sel]), observed = 1 - km$surv, lower = 1 - km$upper, upper = 1 - km$lower, n = length(sel))
}
write_ref(list(
  n = n, events = sum(d$ev), beta = unname(coef(fit)), beta_breslow = unname(coef(fitB)),
  horizons = horizons,
  H0_efron = H0(fit, horizons), H0_efron_breslowtype = H0(fit, horizons, ctype = 1), H0_breslow = H0(fitB, horizons),
  risk365_head = head(unname(risk365), 20), mean_risk365 = mean(risk365),
  km365_all = 1 - summary(survfit(Surv(time, ev) ~ 1, data = d), times = 365)$surv,
  c_app = cstat(d$time, d$ev, lpApp), c_coxph = unname(concordance(fit)$concordance),
  indices = idx - 1, opt_c = mean(optC), opt_slope = mean(optS),
  c_corrected = cstat(d$time, d$ev, lpApp) - mean(optC), slope_corrected = 1 - mean(optS),
  calibration = do.call(rbind, cal)
), "cox_prediction")
