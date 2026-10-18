# Séries chronologiques interrompues : régression segmentée (Bernal et al. 2017), références stats et sandwich :
#  - y_t = β₀ + β₁·t + β₂·après_t + β₃·(t − T₀)·après_t + ε_t, après_t = 1 si t ≥ T₀ ;
#  - issue continue : moindres carrés, ES de Newey-West (noyau de Bartlett, retard L, sans préblanchiment ni
#    correction de ddl : sandwich::NeweyWest(prewhite = FALSE, adjust = FALSE)) ; Durbin-Watson, autocorrélation des
#    résidus au retard 1 ;
#  - comptages : Poisson avec offset log(population), dispersion quasi-Poisson (Pearson) ; rapports de taux ;
#  - effet à un horizon h après T₀ : β₂ + β₃·h (IC de Wald avec la matrice de covariance) ; contrefactuel = tendance
#    antérieure prolongée.
# DONNÉES : série mensuelle simulée de 48 mois (politique de santé au mois 25) : admissions et population couverte
# (demos/serie_interrompue_simule.csv).
source("_common.R")
suppressPackageStartupMessages(library(sandwich))
set.seed(20261220)
n <- 48; T0 <- 25
mois <- 1:n; apres <- as.integer(mois >= T0); depuis <- (mois - T0) * apres
pop <- round(1200000 + 3000 * mois + rnorm(n, 0, 8000))
ar <- as.numeric(arima.sim(list(ar = 0.4), n, sd = 0.025))
taux <- exp(log(85e-5) + 0.004 * mois - 0.15 * apres - 0.008 * depuis + ar)
admissions <- rpois(n, taux * pop)
taux_100k <- round(admissions / pop * 1e5, 3)
d <- data.frame(mois, admissions, population = pop, taux_100k)
write.csv(d, file.path("..", "..", "demos", "serie_interrompue_simule.csv"), row.names = FALSE, quote = FALSE)
d$apres <- apres; d$depuis <- depuis
h <- n - T0
L <- 3
fl <- lm(taux_100k ~ mois + apres + depuis, data = d)
V <- NeweyWest(fl, lag = L, prewhite = FALSE, adjust = FALSE)
e <- residuals(fl)
eff <- function(b, V, h) { g <- c(0, 0, 1, h); c(sum(g * b), sqrt(drop(t(g) %*% V %*% g))) }
fp <- glm(admissions ~ mois + apres + depuis + offset(log(population)), data = d, family = quasipoisson, control = glm.control(epsilon = 1e-14, maxit = 100))
write_ref(list(T0 = T0, lag = L, h = h,
               lin = list(coef = unname(coef(fl)), se_nw = unname(sqrt(diag(V))), se_ols = unname(sqrt(diag(vcov(fl)))),
                          dw = sum(diff(e)^2) / sum(e^2), ac1 = acf(e, plot = FALSE)$acf[2], effect = eff(coef(fl), V, h)),
               pois = list(coef = unname(coef(fp)), se = unname(sqrt(diag(vcov(fp)))), dispersion = summary(fp)$dispersion,
                           effect = eff(coef(fp), vcov(fp), h))), "series_interrompues")
print(summary(fl)$coefficients); print(sqrt(diag(V))); print(summary(fp)$coefficients)
