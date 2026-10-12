source("_common.R")
suppressPackageStartupMessages({library(sandwich); library(car); library(logistf)})
set.seed(4242)
n <- 300
age <- round(runif(n, 25, 75))
sexe <- sample(c("F", "H"), n, TRUE)
tabac <- sample(c("non", "ancien", "actuel"), n, TRUE, prob = c(.55, .25, .2))
imc <- round(rnorm(n, 26 + 0.03 * (age - 50), 4), 1)
pas <- round(110 + 0.5 * age + 0.8 * (imc - 26) + 5 * (sexe == "H") + rnorm(n, 0, 12))
lp <- -9 + 0.06 * age + 0.12 * imc + 0.5 * (tabac == "actuel") + 0.2 * (tabac == "ancien")
hta <- rbinom(n, 1, plogis(lp))
imc[c(5, 77, 190)] <- NA   # valeurs manquantes
df <- data.frame(id = 1:n, age, sexe, tabac, imc, pas, hta)
write.csv(df, file.path(REF_DIR, "regression_data.csv"), row.names = FALSE, na = "")
cc <- df[complete.cases(df), ]
cc$tabac <- relevel(factor(cc$tabac), ref = "non")
cc$sexe <- relevel(factor(cc$sexe), ref = "F")
# Linéaire
lm1 <- lm(pas ~ age + sexe + imc + tabac, data = cc)
s <- summary(lm1)
X <- model.matrix(lm1); e2 <- residuals(lm1)^2
aux <- lm(e2 ~ X[, -1]); bp <- nrow(X) * summary(aux)$r.squared
vf <- car::vif(lm1)
lin <- list(coef = unname(coef(lm1)), se = unname(s$coefficients[, 2]), p = unname(s$coefficients[, 4]),
  ci = unname(confint(lm1)), r2 = s$r.squared, adj_r2 = s$adj.r.squared, sigma = s$sigma,
  F = unname(s$fstatistic[1]), bp = bp, bp_p = pchisq(bp, ncol(X) - 1, lower.tail = FALSE),
  max_cook = max(cooks.distance(lm1)), gvif = as.list(setNames(vf[, 1], rownames(vf))), names = colnames(X))
# Logistique
gl <- glm(hta ~ age + sexe + imc + tabac, data = cc, family = binomial, control = glm.control(epsilon = 1e-14, maxit = 100))
sg <- summary(gl)
logi <- list(coef = unname(coef(gl)), se = unname(sg$coefficients[, 2]), p = unname(sg$coefficients[, 4]),
  ci_wald = unname(confint.default(gl)), deviance = gl$deviance, null_deviance = gl$null.deviance, aic = gl$aic,
  iter = gl$iter)
# Poisson robuste
gp <- glm(hta ~ age + sexe + imc + tabac, data = cc, family = poisson, control = glm.control(epsilon = 1e-14, maxit = 100))
vr <- sandwich::vcovHC(gp, type = "HC0")
pois <- list(coef = unname(coef(gp)), se = unname(sqrt(diag(vr))))
# Firth (petit échantillon avec séparation quasi complète)
set.seed(7)
m <- 40
x1 <- round(rnorm(m, 50, 10)); grp <- c(rep("A", 20), rep("B", 20))
y <- c(rep(0, 20), rbinom(20, 1, 0.3))   # aucun événement dans le groupe A
fd <- data.frame(y, x1, grp)
write.csv(fd, file.path(REF_DIR, "firth_data.csv"), row.names = FALSE)
ff <- logistf(y ~ x1 + grp, data = fd, pl = FALSE, control = logistf.control(xconv = 1e-12, gconv = 1e-12, maxit = 200))
gsep <- suppressWarnings(glm(y ~ x1 + grp, data = fd, family = binomial))
firth <- list(coef = unname(coef(ff)), se = unname(sqrt(diag(vcov(ff)))), ci = unname(cbind(ff$ci.lower, ff$ci.upper)),
  loglik = unname(ff$loglik["full"]), ml_coef = unname(coef(gsep)), ml_converged = gsep$converged)
write_ref(list(linear = lin, logistic = logi, poisson = pois, firth = firth, n_complete = nrow(cc)), "regression")
