# Calibration d'un modèle de risque, références ResourceSelection 0.3.6 et rms 6.7 :
#  - Hosmer-Lemeshow (hoslem.test, g = 10) : groupes = intervalles des quantiles (type 7) uniques du risque prédit,
#    cut(include.lowest = TRUE) ; χ² = Σ (O − E)²/E sur les cases y = 1 et y = 0 ; ddl = G − 2 ;
#  - Spiegelhalter : z = Σ(y − p)(1 − 2p)/√Σ(1 − 2p)²p(1 − p) (val.prob) ;
#  - courbe lissée : lowess(p, y, iter = 0) (val.prob) ; Eavg, E90, Emax = moyenne, 90e centile, maximum de
#    |p − lissé(p)| ; Brier ; intercept et pente de recalibration logistique (val.prob) ; calibration « dans l'ensemble »
#    (glm avec le logit prédit en offset).
# DONNÉES : modèle logistique développé sur cardiometabolique_simule.csv (n = 800), appliqué à lui-même (calibration
# apparente) et à cardiometabolique_externe_simule.csv (validation externe) ; cas complets.
source("_common.R")
suppressPackageStartupMessages({ library(ResourceSelection); library(rms) })
vars <- c("age", "sexe", "imc", "pas", "glycemie", "hdl", "tabac", "evenement_5ans")
dev <- na.omit(read.csv(file.path(REF_DIR, "cardiometabolique_simule.csv"))[vars])
ext <- na.omit(read.csv(file.path(REF_DIR, "cardiometabolique_externe_simule.csv"))[vars])
fit <- glm(evenement_5ans ~ age + sexe + imc + pas + glycemie + hdl + tabac, data = dev, family = binomial)
ref <- function(p, y) {
  hl <- hoslem.test(y, p, g = 10)
  v <- val.prob(p, y, pl = FALSE)
  sm <- lowess(p, y, iter = 0)
  citl <- coef(glm(y ~ offset(qlogis(p)), family = binomial))[[1]]
  list(p = p, y = y, hl = c(unname(hl$statistic), unname(hl$parameter), hl$p.value),
       observed1 = unname(hl$observed[, 2]), expected1 = unname(hl$expected[, 2]),
       brier = unname(v["Brier"]), intercept = unname(v["Intercept"]), slope = unname(v["Slope"]),
       eavg = unname(v["Eavg"]), e90 = unname(v["E90"]), emax = unname(v["Emax"]),
       spiegel = unname(v[c("S:z", "S:p")]), citl = citl, smooth_x = sm$x, smooth_y = sm$y)
}
pd <- unname(fitted(fit)); pe <- unname(predict(fit, ext, type = "response"))
write_ref(list(dev = ref(pd, dev$evenement_5ans), ext = ref(pe, ext$evenement_5ans)), "calibration")
print(hoslem.test(ext$evenement_5ans, pe)); print(round(val.prob(pe, ext$evenement_5ans, pl = FALSE), 4))
