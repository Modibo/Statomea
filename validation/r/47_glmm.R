# Modèle linéaire mixte généralisé (intercept aléatoire par sujet) : logistique et Poisson.
#  - yᵢⱼ | bᵢ ~ Bernoulli(logit⁻¹(xᵢⱼᵀβ + bᵢ)) ou Poisson(exp(xᵢⱼᵀβ + bᵢ)), bᵢ ~ N(0, σ²).
# Références (trois niveaux) :
#  1) Laplace EXACTE recalculée ici : mode conditionnel par optimize (tol 1e-12), log Lᵢ = g(b̂) − log σ − ½ log(Σw + 1/σ²) ;
#     maximum par optim (BFGS, reltol 1e-15) ; ES par optimHess en (σ, β) ;
#  2) vraisemblance marginale EXACTE par intégration numérique (integrate) : maximum de vraisemblance de référence,
#     que la quadrature de Gauss-Hermite adaptative doit approcher quand le nombre de points augmente ;
#  3) lme4::glmer (nAGQ = 1 et 10) : sa déviance dépend de l'état final de PIRLS (devfun et logLik diffèrent d'environ
#     0,01 du Laplace exact aux mêmes paramètres) : comparaison à tolérance large.
# DONNÉES : essai simulé HbA1c (contrôle glycémique HbA1c < 7,8) ; grouseticks (lme4 ; tiques par poussin de lagopède,
# couvées) ; hypoglycémies (variance entre sujets nulle : cas limite).
source("_common.R")
suppressPackageStartupMessages(library(lme4))
d <- read.csv(file.path("..", "..", "demos", "hba1c_longitudinal_simule.csv"))
d$controle <- as.integer(d$hba1c < 7.8); d$bras <- factor(d$bras, levels = c("A", "B"))
data(grouseticks)
gt <- data.frame(couvee = paste0("C", grouseticks$BROOD), annee = paste0("a", grouseticks$YEAR), altitude = round(as.numeric(scale(grouseticks$HEIGHT)), 6), tiques = grouseticks$TICKS)
write.csv(gt, file.path("..", "..", "demos", "tiques_lagopede.csv"), row.names = FALSE, quote = FALSE)
ctl <- glmerControl(optimizer = "bobyqa", optCtrl = list(rhobeg = 0.2, rhoend = 1e-12, maxfun = 1e5))

refs <- function(f, data, grp, fam) {
  X0 <- model.matrix(f, data); y <- model.response(model.frame(f, data)); id <- split(seq_along(y), data[[grp]])
  # Covariables centrées (conditionnement de l'optimisation et de la hessienne), résultats ramenés à l'échelle d'origine.
  mX <- c(0, colMeans(X0)[-1]); X <- sweep(X0, 2, mX); A <- diag(ncol(X)); A[1, ] <- c(1, -mX[-1])
  ll <- function(eta) if (fam == "binomial") y * eta - log1p(exp(eta)) else y * eta - exp(eta) - lgamma(y + 1)
  w <- function(eta) if (fam == "binomial") plogis(eta) * (1 - plogis(eta)) else exp(eta)
  lap <- function(par) { s <- abs(par[1]); eta0 <- drop(X %*% par[-1])
    sum(sapply(id, function(r) { g <- function(u) -u^2 / (2 * s^2) + sum(ll(eta0[r] + u)[seq_along(r)])
      gg <- function(u) -u^2 / (2 * s^2) + sum((if (fam == "binomial") y[r] * (eta0[r] + u) - log1p(exp(eta0[r] + u)) else y[r] * (eta0[r] + u) - exp(eta0[r] + u) - lgamma(y[r] + 1)))
      u <- optimize(function(u) -gg(u), c(-40, 40), tol = 1e-12)$minimum
      ww <- if (fam == "binomial") plogis(eta0[r] + u) * (1 - plogis(eta0[r] + u)) else exp(eta0[r] + u)
      gg(u) - log(s) - 0.5 * log(sum(ww) + 1 / s^2) })) }
  exact <- function(par) { s <- abs(par[1]); eta0 <- drop(X %*% par[-1])
    sum(sapply(id, function(r) { f1 <- function(u) sapply(u, function(v) exp(sum(if (fam == "binomial") y[r] * (eta0[r] + v) - log1p(exp(eta0[r] + v)) else y[r] * (eta0[r] + v) - exp(eta0[r] + v) - lgamma(y[r] + 1)) + dnorm(v, 0, s, log = TRUE) + 50))
      log(integrate(f1, -Inf, Inf, rel.tol = 1e-12, subdivisions = 1000)$value) - 50 })) }
  g1 <- glmer(update(f, as.formula(paste(". ~ . + (1 |", grp, ")"))), data = data, family = fam, nAGQ = 1, control = ctl)
  g10 <- glmer(update(f, as.formula(paste(". ~ . + (1 |", grp, ")"))), data = data, family = fam, nAGQ = 10, control = ctl)
  toC <- function(b) { bc <- b; bc[1] <- b[1] + sum(b[-1] * mX[-1]); bc }   # β (origine) → β centré
  start <- c(getME(g1, "theta"), toC(fixef(g1)))
  oL <- optim(start, function(p) -lap(p), method = "BFGS", control = list(reltol = 1e-15, maxit = 1000))
  hL <- optimHess(oL$par, function(p) -lap(p))
  oE <- optim(c(getME(g10, "theta"), toC(fixef(g10))), function(p) -exact(p), method = "BFGS", control = list(reltol = 1e-15, maxit = 1000))
  Vc <- solve(hL)[-1, -1]; V <- A %*% Vc %*% t(A)
  back <- function(bc) drop(A %*% bc)
  pk <- function(m) list(theta = unname(getME(m, "theta")), beta = unname(fixef(m)), se = unname(sqrt(diag(as.matrix(vcov(m))))))
  list(laplace = list(sigma = abs(oL$par[1]), beta = unname(back(oL$par[-1])), loglik = -oL$value, se = unname(sqrt(diag(V)))),
       exact = list(sigma = abs(oE$par[1]), beta = unname(back(oE$par[-1])), loglik = -oE$value),
       glmer1 = pk(g1), glmer10 = pk(g10))
}
rb <- refs(controle ~ mois * bras + age, d, "patient", "binomial")
rt <- refs(tiques ~ annee + altitude, gt, "couvee", "poisson")
gp <- glmer(hypoglycemies ~ mois + bras + (1 | patient), data = d, family = poisson, control = ctl)
write_ref(list(bin = rb, ticks = rt, pois_singular = list(theta = unname(getME(gp, "theta")), beta = unname(fixef(gp)))), "glmm_long")
cat("binomial : Laplace", rb$laplace$beta[1:2], "σ", rb$laplace$sigma, " exact", rb$exact$beta[1:2], "σ", rb$exact$sigma, "\n")
cat("tiques : Laplace", rt$laplace$beta[1:2], "σ", rt$laplace$sigma, " exact σ", rt$exact$sigma, "\n")
