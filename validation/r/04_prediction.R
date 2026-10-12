# Démonstration 3 et références du module de prédiction.
# DONNÉES SIMULÉES à but pédagogique : aucune donnée de patient réel.
source("_common.R")
suppressPackageStartupMessages({library(pROC); library(pmsampsize)})
set.seed(20261010)
n <- 800
age <- round(runif(n, 30, 70))
sexe <- sample(c("F", "H"), n, TRUE)
imc <- round(rnorm(n, 27, 4.5), 1)
tour_taille <- round(0.9 * imc * 3.2 + ifelse(sexe == "H", 8, 0) + rnorm(n, 0, 6))
pas <- round(105 + 0.6 * age + 0.7 * (imc - 27) + rnorm(n, 0, 13))
glycemie <- round(rlnorm(n, log(5.2) + 0.012 * (imc - 27), 0.12), 2)   # mmol/L
hdl <- round(rnorm(n, ifelse(sexe == "F", 1.45, 1.2) - 0.02 * (imc - 27), 0.3), 2)
tabac <- sample(c("non", "oui"), n, TRUE, prob = c(.75, .25))
atcd_familial <- sample(c("non", "oui"), n, TRUE, prob = c(.7, .3))
lp <- -13.7 + 0.045 * age + 0.07 * tour_taille + 0.018 * pas + 0.55 * glycemie - 0.9 * hdl + 0.35 * (tabac == "oui") + 0.4 * (atcd_familial == "oui")
evenement <- rbinom(n, 1, plogis(lp))
glycemie[sample(n, 14)] <- NA; hdl[sample(n, 9)] <- NA
d <- data.frame(id = 1:n, age, sexe, imc, tour_taille, pas, glycemie, hdl, tabac, atcd_familial, evenement_5ans = evenement)
write.csv(d, file.path("..", "..", "demos", "cardiometabolique_simule.csv"), row.names = FALSE, na = "")
file.copy(file.path("..", "..", "demos", "cardiometabolique_simule.csv"), file.path(REF_DIR, "cardiometabolique_simule.csv"), overwrite = TRUE)
cc <- d[complete.cases(d), ]
cc$sexe <- relevel(factor(cc$sexe), "F"); cc$tabac <- relevel(factor(cc$tabac), "non"); cc$atcd_familial <- relevel(factor(cc$atcd_familial), "non")
ctl <- glm.control(epsilon = 1e-14, maxit = 100)
fnew <- evenement_5ans ~ age + sexe + tour_taille + pas + glycemie + hdl + tabac + atcd_familial
fref <- evenement_5ans ~ age + sexe
perf <- function(p, y) {
  lp <- qlogis(pmin(pmax(p, 1e-12), 1 - 1e-12))
  c(auc = as.numeric(auc(roc(y, p, direction = "<", levels = c(0, 1), quiet = TRUE))),
    slope = unname(coef(glm(y ~ lp, family = binomial, control = ctl))[2]),
    intercept = unname(coef(glm(y ~ offset(lp), family = binomial, control = ctl))[1]),
    brier = mean((p - y)^2))
}
B <- 100
idx <- lapply(1:B, function(b) sample.int(nrow(cc), replace = TRUE))
boot <- function(f) {
  full <- glm(f, data = cc, family = binomial, control = ctl)
  app <- perf(fitted(full), cc$evenement_5ans)
  opt <- rowMeans(sapply(idx, function(ii) {
    bd <- cc[ii, ]; fb <- glm(f, data = bd, family = binomial, control = ctl)
    perf(fitted(fb), bd$evenement_5ans) - perf(predict(fb, newdata = cc, type = "response"), cc$evenement_5ans)
  }))
  list(apparent = as.list(app), optimism = as.list(opt), corrected = as.list(app - opt), coef = unname(coef(full)), fitted = unname(fitted(full)))
}
bn <- boot(fnew); br <- boot(fref)
y <- cc$evenement_5ans
r1 <- roc(y, bn$fitted, direction = "<", levels = c(0, 1), quiet = TRUE)
r2 <- roc(y, br$fitted, direction = "<", levels = c(0, 1), quiet = TRUE)
ci1 <- ci.auc(r1, method = "delong"); rt <- roc.test(r1, r2, method = "delong", paired = TRUE)
dca <- sapply(c(.05, .1, .2, .3), function(t) { tp <- sum(bn$fitted >= t & y == 1); fp <- sum(bn$fitted >= t & y == 0); tp / length(y) - fp / length(y) * t / (1 - t) })
full <- glm(fnew, data = cc, family = binomial, control = ctl)
null <- glm(evenement_5ans ~ 1, data = cc, family = binomial)
r2cs <- 1 - exp(2 * (as.numeric(logLik(null)) - as.numeric(logLik(full))) / nrow(cc))
pm <- pmsampsize(type = "b", csrsquared = 0.15, parameters = 9, prevalence = mean(y), seed = 1)
pm2 <- pmsampsize(type = "b", csrsquared = 0.08, parameters = 4, prevalence = 0.2, seed = 1)
write_ref(list(n_complete = nrow(cc), indices = lapply(idx, function(v) v - 1L), new = bn[c("apparent", "optimism", "corrected", "coef")],
  ref = br[c("apparent", "optimism", "corrected", "coef")],
  auc_ci = as.numeric(ci1)[c(1, 3)], var_auc = var(r1), delta = list(z = unname(rt$statistic), p = rt$p.value, diff = unname(rt$estimate[1] - rt$estimate[2])),
  dca = list(t = c(.05, .1, .2, .3), nb = dca), r2cs = r2cs,
  riley = list(list(r2 = 0.15, p = 9, prev = mean(y), n = pm$results_table[, 1]), list(r2 = 0.08, p = 4, prev = 0.2, n = pm2$results_table[, 1]))), "prediction")
