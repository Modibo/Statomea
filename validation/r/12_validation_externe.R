# Validation externe : cohorte SIMULÉE indépendante (pédagogique), différente
# de la cohorte de développement (plus âgée, risque de base plus élevé, effets
# atténués) ; références glm (offset), pROC.
source("_common.R")
suppressPackageStartupMessages(library(pROC))
dev <- read.csv(file.path(REF_DIR, "cardiometabolique_simule.csv"), na.strings = "")
cc <- dev[complete.cases(dev), ]
for (v in c("sexe", "tabac", "atcd_familial")) cc[[v]] <- relevel(factor(cc[[v]]), ref = ifelse(v == "sexe", "F", "non"))
ctl <- glm.control(epsilon = 1e-14, maxit = 100)
fit <- glm(evenement_5ans ~ age + sexe + tour_taille + pas + glycemie + hdl + tabac + atcd_familial, data = cc, family = binomial, control = ctl)
set.seed(777)
n <- 600
age <- round(runif(n, 40, 78)); sexe <- sample(c("F", "H"), n, TRUE)
imc <- round(rnorm(n, 28.5, 4.5), 1)
tour_taille <- round(0.9 * imc * 3.2 + ifelse(sexe == "H", 8, 0) + rnorm(n, 0, 6))
pas <- round(110 + 0.6 * age + 0.7 * (imc - 27) + rnorm(n, 0, 14))
glycemie <- round(rlnorm(n, log(5.4) + 0.012 * (imc - 27), 0.13), 2)
hdl <- round(rnorm(n, ifelse(sexe == "F", 1.4, 1.15) - 0.02 * (imc - 27), 0.3), 2)
tabac <- sample(c("non", "oui"), n, TRUE, prob = c(.7, .3)); atcd_familial <- sample(c("non", "oui"), n, TRUE, prob = c(.65, .35))
lp_true <- -10.95 + 0.8 * (0.045 * age + 0.07 * tour_taille + 0.018 * pas + 0.55 * glycemie - 0.9 * hdl + 0.35 * (tabac == "oui") + 0.4 * (atcd_familial == "oui"))
evenement_5ans <- rbinom(n, 1, plogis(lp_true))
hdl[sample(n, 6)] <- NA
ext <- data.frame(id = 1:n, age, sexe, imc, tour_taille, pas, glycemie, hdl, tabac, atcd_familial, evenement_5ans)
write.csv(ext, file.path("..", "..", "demos", "cardiometabolique_externe_simule.csv"), row.names = FALSE, na = "")
file.copy(file.path("..", "..", "demos", "cardiometabolique_externe_simule.csv"), file.path(REF_DIR, "cardiometabolique_externe_simule.csv"), overwrite = TRUE)
ec <- ext[complete.cases(ext), ]
for (v in c("sexe", "tabac", "atcd_familial")) ec[[v]] <- factor(ec[[v]], levels = levels(cc[[v]]))
lp <- predict(fit, newdata = ec); p <- plogis(lp); y <- ec$evenement_5ans
r <- roc(y, p, direction = "<", levels = c(0, 1), quiet = TRUE); ci <- ci.auc(r, method = "delong")
citl <- glm(y ~ offset(lp), family = binomial, control = ctl); sl <- glm(y ~ lp, family = binomial, control = ctl)
write_ref(list(n = nrow(ec), events = sum(y), auc = as.numeric(auc(r)), auc_ci = as.numeric(ci)[c(1, 3)],
  citl = unname(coef(citl)), citl_se = unname(sqrt(diag(vcov(citl)))), slope = unname(coef(sl)[2]), slope_se = unname(sqrt(diag(vcov(sl)))[2]),
  slope_a = unname(coef(sl)[1]), oe = sum(y) / sum(p), brier = mean((p - y)^2), lp_head = unname(lp[1:5])), "validation_externe")
cat("n", nrow(ec), "événements", sum(y), "AUC", as.numeric(auc(r)), "CITL", coef(citl), "pente", coef(sl)[2], "O/E", sum(y)/sum(p), "\n")
