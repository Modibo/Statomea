# Laboratoire : intervalles de référence (CLSI EP28-A3c) et fidélité (CLSI EP05-A3, EP15-A3).
# Références : referenceIntervals 1.3.0 (chargé sans son interface tcltk, qui exige X11 : fonctions lues par
# lazyLoad), MASS (boxcox), VCA 1.4.5 (anovaVCA, VCAinference).
#  - non paramétrique : quantiles de type 6 ; IC à 90 % des bornes par rangs binomiaux (table CLSI, n ≥ 120) :
#    rang inférieur = max{k : P(X ≤ k) ≤ 0,05} + 1, supérieur = min{k : P(X ≤ k) ≥ 0,95} + 1, X ~ Bin(n ; 0,025) ;
#  - paramétrique : m ± z·s, IC m ± z·s ± z₀.₉₀·√(s²/n + z²s²/2n) ;
#  - robuste (Horn et Pesce 2005) : bipoids itéré (c = 3,7) et marge t·√(s_bi(205,6)² + S_T(3,7)²) ;
#  - valeurs aberrantes (Horn) : Box-Cox (λ sur la grille −2…2 par 0,1, MASS) puis barrières de Tukey ;
#  - partition (Harris et Boyd 1990) : z = |m₁ − m₂|/√(s₁²/n₁ + s₂²/n₂) contre 3·√(n̄/120), rapport des ÉT > 1,5 ;
#  - fidélité : composantes de la variance par ANOVA (plans équilibrés jour, ou jour/série), IC du total et de la
#    répétabilité par χ² (ddl de Satterthwaite pour le total), des autres par Wald borné à 0 ; limite de vérification
#    EP15 = σ annoncé × √(χ²(1 − α/l ; ddl)/ddl).
# DONNÉES : set50, set120, set200 (referenceIntervals) ; dataEP05A2_1 (VCA, 20 jours × 2 séries × 2) ; plan EP15
# simulé (5 jours × 5 répétitions, deux niveaux) ; partition simulée (hommes et femmes).
source("_common.R")
suppressPackageStartupMessages({ library(MASS); library(VCA) })
e <- new.env(); lazyLoad(file.path(find.package("referenceIntervals"), "R", "referenceIntervals"), envir = e)
for (f in ls(e)) if (is.function(e[[f]])) environment(e[[f]]) <- e   # les fonctions s'appellent entre elles
ri <- function(x) {
  x <- as.numeric(x)
  p <- get("singleRefLimit", e)(x, out.method = "horn", out.rm = FALSE, RI = "p", CI = "p")
  r <- get("robust", e)(x, 1:length(x), 0.95)
  np <- get("nonparRI", e)(sort(x), 1:length(x), 0.95)
  ho <- get("horn.outliers", e)(x)
  b <- boxcox(lm(x ~ 1, y = TRUE), plotit = FALSE)
  n <- length(x); k <- 0:n
  lo <- if (n >= 120) max(k[pbinom(k, n, 0.025) <= 0.05]) + 1 else NA; up <- if (n >= 120) min(k[pbinom(k, n, 0.025) >= 0.95]) + 1 else NA
  s <- sort(x)
  list(x = x, param = unname(c(p$Ref_Int, p$Conf_Int)), robust = unname(r), nonpar = unname(np),
       ranks = c(lo, up), nonpar_ci = if (n >= 120) c(s[lo], s[up], s[n + 1 - up], s[n + 1 - lo]) else NULL,
       lambda = b$x[which.max(b$y)], outliers = sort(as.numeric(ho$outliers)))
}
s50 <- get("set50", e); s120 <- get("set120", e); s200 <- get("set200", e)
set.seed(20261218)
hommes <- round(rnorm(130, 88, 12), 1); femmes <- round(rnorm(140, 71, 10), 1)
hb <- function(a, b) {
  z <- abs(mean(a) - mean(b)) / sqrt(var(a) / length(a) + var(b) / length(b))
  list(z = z, zstar = 3 * sqrt(((length(a) + length(b)) / 2) / 120), sd_ratio = max(sd(a), sd(b)) / min(sd(a), sd(b)))
}
write.csv(data.frame(creatinine = c(hommes, femmes), sexe = rep(c("H", "F"), c(130, 140))),
          file.path("..", "..", "demos", "creatinine_reference_simule.csv"), row.names = FALSE, quote = FALSE)
data(dataEP05A2_1)
vc <- function(fit, claims = NULL, levels = 1) {
  inf <- VCAinference(fit, VarVC = TRUE)
  a <- fit$aov.tab
  list(names = rownames(a), df = unname(a[, "DF"]), ms = unname(a[, "MS"]), vc = unname(a[, "VC"]), sd = unname(a[, "SD"]),
       cv = unname(a[, "CV[%]"]), mean = fit$Mean,
       sd_lcl = unname(inf$ConfInt$SD$TwoSided[, "LCL"]), sd_ucl = unname(inf$ConfInt$SD$TwoSided[, "UCL"]),
       vc_lcl = unname(inf$ConfInt$VC$TwoSided[, "LCL"]), vc_ucl = unname(inf$ConfInt$VC$TwoSided[, "UCL"]),
       cv_ucl = unname(inf$ConfInt$CV$TwoSided[, "UCL"]),
       verif = if (!is.null(claims)) {
         d <- unname(a[, "DF"]); n <- nrow(a)
         list(repeat_uvl = claims[1] * sqrt(qchisq(1 - 0.05 / levels, d[n]) / d[n]),
              wl_uvl = claims[2] * sqrt(qchisq(1 - 0.05 / levels, d[1]) / d[1]))
       })
}
ep05 <- vc(anovaVCA(y ~ day/run, dataEP05A2_1))
ep15 <- data.frame(jour = factor(rep(1:5, each = 5)), y = round(100 + rep(rnorm(5, 0, 1.2), each = 5) + rnorm(25, 0, 2), 2))
# Mêmes 5 valeurs chaque jour (ordre permuté) : moyennes journalières identiques, variance entre jours estimée < 0.
v5 <- c(48.7, 49.6, 50.1, 50.8, 51.9)
ep15neg <- data.frame(jour = factor(rep(1:5, each = 5)), y = c(sapply(0:4, function(k) v5[(0:4 + k) %% 5 + 1])))
write.csv(dataEP05A2_1, file.path(REF_DIR, "ep05_vca.csv"), row.names = FALSE, quote = FALSE)
write.csv(ep15, file.path("..", "..", "demos", "fidelite_ep15_simule.csv"), row.names = FALSE, quote = FALSE)
write.csv(ep15neg, file.path(REF_DIR, "ep15_negatif.csv"), row.names = FALSE, quote = FALSE)
f15 <- anovaVCA(y ~ jour, ep15); f15n <- anovaVCA(y ~ jour, ep15neg)
write_ref(list(set50 = ri(s50), set120 = ri(s120), set200 = ri(s200), partition = hb(hommes, femmes),
               ep05 = ep05, ep15 = vc(f15, claims = c(2.0, 2.5), levels = 2), ep15neg = vc(f15n)), "laboratoire")
print(get("singleRefLimit", e)(as.numeric(s120), RI = "n", CI = "n"))
print(ep05[c("names", "vc", "sd", "sd_lcl", "sd_ucl")])
print(vc(f15n)[c("names", "vc", "df", "sd_lcl", "sd_ucl")])
