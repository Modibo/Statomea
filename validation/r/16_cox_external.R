# Validation externe d'un modèle pronostique de Cox : équation développée sur lung (âge, sexe, ph.ecog ; horizon 365 j),
# appliquée SANS réestimation à une cohorte externe simulée (risque de base plus élevé, effets atténués).
source("_common.R")
suppressPackageStartupMessages(library(survival))
lung <- read.csv(file.path(REF_DIR, "cox_lung.csv"))
d <- subset(lung, !is.na(age) & !is.na(sexe) & !is.na(ph.ecog))
d$ev <- as.integer(d$deces == "oui"); d$sexe <- factor(d$sexe, levels = c("F", "H"))
fit <- coxph(Surv(time, ev) ~ age + sexe + ph.ecog, data = d, ties = "efron")
zero <- data.frame(age = 0, sexe = factor("F", levels = c("F", "H")), ph.ecog = 0)
H0dev <- summary(survfit(fit, newdata = zero), times = 365, extend = TRUE)$cumhaz

# Cohorte externe simulée (Weibull), censure administrative à 900 j et censure aléatoire.
set.seed(20261012)
n <- 320
ext <- data.frame(age = round(rnorm(n, 66, 9)), sexe = sample(c("F", "H"), n, TRUE, prob = c(0.4, 0.6)),
                  ph.ecog = sample(0:3, n, TRUE, prob = c(0.25, 0.45, 0.25, 0.05)))
lin <- 0.008 * ext$age + 0.35 * (ext$sexe == "H") + 0.35 * ext$ph.ecog
tev <- (-log(runif(n)) / (0.00045 * exp(lin)))^(1 / 1.15)
cens <- pmin(900, runif(n, 100, 2000))
ext$time <- round(pmax(1, pmin(tev, cens)))
ext$deces <- ifelse(tev <= cens, "oui", "non")
write.csv(ext[, c("time", "deces", "age", "sexe", "ph.ecog")], file.path(REF_DIR, "cox_externe_simule.csv"), row.names = FALSE)

ext$ev <- as.integer(ext$deces == "oui"); ext$sexe <- factor(ext$sexe, levels = c("F", "H"))
lp <- as.vector(model.matrix(~ age + sexe + ph.ecog, ext)[, -1] %*% coef(fit))
risk <- 1 - exp(-H0dev * exp(lp))
km <- summary(survfit(Surv(time, ev) ~ 1, data = ext, conf.type = "log"), times = 365)
sl <- coxph(Surv(time, ev) ~ lp, data = ext)
f0 <- coxph(Surv(time, ev) ~ offset(lp), data = ext)
H0int <- summary(survfit(f0, newdata = data.frame(lp = 0)), times = 365, extend = TRUE)$cumhaz
lps <- coef(sl) * lp
f1 <- coxph(Surv(time, ev) ~ offset(lps), data = data.frame(ext, lps = lps))
H0slope <- summary(survfit(f1, newdata = data.frame(lps = 0)), times = 365, extend = TRUE)$cumhaz
nn <- nrow(ext); o <- order(risk); cal <- list()
for (g in 0:4) {
  sel <- o[(floor(g * nn / 5) + 1):floor((g + 1) * nn / 5)]
  k <- summary(survfit(Surv(time, ev) ~ 1, data = ext[sel, ], conf.type = "log"), times = 365, extend = TRUE)
  cal[[g + 1]] <- c(mean(risk[sel]), 1 - k$surv, 1 - k$upper, 1 - k$lower, length(sel))
}
write_ref(list(
  beta = unname(coef(fit)), H0_dev = H0dev, n = nn, events = sum(ext$ev),
  c = concordance(Surv(time, ev) ~ lp, data = ext, reverse = TRUE)$concordance,
  slope = unname(coef(sl)), slope_se = unname(sqrt(vcov(sl)[1, 1])),
  mean_risk = mean(risk), km_risk = 1 - km$surv, km_lower = 1 - km$upper, km_upper = 1 - km$lower,
  oe = (1 - km$surv) / mean(risk), H0_recal_intercept = H0int, H0_recal_slope = H0slope,
  calibration = do.call(rbind, cal)
), "cox_external")
