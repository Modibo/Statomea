# Score de propension, références MatchIt 4.5.5, WeightIt 0.14.2, cobalt 4.5.2 et sandwich :
#  - score = P(traité | covariables) par régression logistique ;
#  - appariement 1:1 au plus proche voisin sans remise (MatchIt « nearest », ordre des traités par score décroissant),
#    caliper facultatif en écarts-types du score (ÉT sur tous les sujets) ;
#  - pondération IPTW : ATE w = t/e + (1 − t)/(1 − e) ; ATT w = t + (1 − t)·e/(1 − e) (WeightIt, method = "glm") ;
#  - équilibre (cobalt, binary = "std") : différence standardisée des moyennes (pondérées), dénominateur = ÉT non pondéré
#    des traités (ATT) ou ÉT poolé √((s₁² + s₀²)/2) (ATE) ; rapport des variances pondérées (traités/témoins) ;
#    taille d'échantillon effective (Σw)²/Σw² ;
#  - effet : coefficient du traitement dans lm(y ~ t, poids) ; ES robuste HC0 (pondération) ou robuste par paire
#    (appariement : sandwich::vcovCL, type HC1, grappe = paire) ; IC normal.
# DONNÉES : étude observationnelle simulée (statines et événement cardiovasculaire, confusion par l'âge, le diabète et
# le LDL ; demos/statines_observationnel_simule.csv) ; lalonde (MatchIt ; formation professionnelle, revenu 1978).
source("_common.R")
suppressPackageStartupMessages({ library(MatchIt); library(WeightIt); library(cobalt); library(sandwich) })
set.seed(20261201)
n <- 600
age <- round(rnorm(n, 62, 10)); sexe <- sample(c("F", "H"), n, TRUE, prob = c(0.45, 0.55))
diabete <- rbinom(n, 1, plogis(-1.6 + 0.04 * (age - 62))); ldl <- round(rnorm(n, 3.4 + 0.2 * diabete, 0.8), 2)
tabac <- rbinom(n, 1, 0.28)
statine <- rbinom(n, 1, plogis(-0.4 + 0.05 * (age - 62) + 1.1 * diabete + 0.7 * (ldl - 3.4) + 0.2 * (sexe == "H")))
risk <- plogis(-2.3 + 0.05 * (age - 62) + 0.8 * diabete + 0.4 * (ldl - 3.4) + 0.6 * tabac + 0.3 * (sexe == "H") - 0.45 * statine)
evenement <- rbinom(n, 1, risk)
sim <- data.frame(id = 1:n, age, sexe, diabete = ifelse(diabete == 1, "oui", "non"), ldl, tabac = ifelse(tabac == 1, "oui", "non"),
                  statine = ifelse(statine == 1, "oui", "non"), evenement)
write.csv(sim, file.path("..", "..", "demos", "statines_observationnel_simule.csv"), row.names = FALSE, quote = FALSE)
data(lalonde)
lal <- lalonde; lal$id <- rownames(lal); lal$traite <- ifelse(lal$treat == 1, "oui", "non")
write.csv(lal[c("id", "traite", "age", "educ", "race", "married", "nodegree", "re74", "re75", "re78")], file.path(REF_DIR, "lalonde.csv"), row.names = FALSE, quote = FALSE)

run <- function(d, f, tvar, y, caliper = NULL) {
  d$t <- as.integer(d[[tvar]] == "oui")
  ff <- update(f, t ~ .)
  ctl <- list(epsilon = 1e-14, maxit = 100)   # convergence resserrée (défaut 1e-8 : écart de 1e-9 sur les scores de lalonde)
  ps <- fitted(glm(ff, data = d, family = binomial, control = ctl))
  m <- if (is.null(caliper)) matchit(ff, data = d, method = "nearest", distance.options = list(control = ctl))
       else matchit(ff, data = d, method = "nearest", caliper = caliper, distance.options = list(control = ctl))
  md <- match.data(m)
  pairs <- unname(match(m$match.matrix[, 1], rownames(d)))   # index (1-based) du témoin apparié à chaque traité, NA sinon
  bal_m <- bal.tab(m, binary = "std", s.d.denom = "treated", stats = c("m", "v"), un = TRUE)$Balance
  fit_m <- lm(as.formula(paste(y, "~ t")), data = md, weights = weights)
  vm <- vcovCL(fit_m, cluster = ~subclass, type = "HC1")
  wt <- function(est) {
    W <- weightit(ff, data = d, method = "glm", estimand = est, control = ctl)
    b <- bal.tab(W, binary = "std", s.d.denom = if (est == "ATE") "pooled" else "treated", stats = c("m", "v"), un = TRUE)$Balance
    fw <- lm(as.formula(paste(y, "~ t")), data = d, weights = W$weights)
    v <- vcovHC(fw, type = "HC0")
    list(w = W$weights, smd_un = b$Diff.Un, smd = b$Diff.Adj, vr = b$V.Ratio.Adj, rows = rownames(b),
         ess = c(sum(W$weights[d$t == 0])^2 / sum(W$weights[d$t == 0]^2), sum(W$weights[d$t == 1])^2 / sum(W$weights[d$t == 1]^2)),
         effect = c(coef(fw)[["t"]], sqrt(v["t", "t"])))
  }
  list(ps = unname(ps), caliper_width = if (is.null(caliper)) NA else caliper * sd(ps), pairs = pairs,
       n_matched = sum(!is.na(pairs)), smd_un = bal_m$Diff.Un, smd = bal_m$Diff.Adj, vr = bal_m$V.Ratio.Adj, rows = rownames(bal_m),
       effect_m = c(coef(fit_m)[["t"]], sqrt(vm["t", "t"])), ate = wt("ATE"), att = wt("ATT"))
}
rs <- run(sim, ~ age + sexe + diabete + ldl + tabac, "statine", "evenement", caliper = 0.2)
rl <- run(lal, ~ age + educ + race + married + nodegree + re74 + re75, "traite", "re78")
write_ref(list(sim = rs, lalonde = rl), "propension")
cat("sim : appariés", rs$n_matched, " effet", rs$effect_m, " ATE", rs$ate$effect, "\n")
cat("lalonde : appariés", rl$n_matched, " effet", rl$effect_m, " ATT", rl$att$effect, "\n")
print(data.frame(row = rs$rows, un = rs$smd_un, m = rs$smd))
