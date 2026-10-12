# Score de risque polygénique (« clumping + seuil de p », C+T), spécification de Statoméa réimplémentée ici :
#  - répartition fixe des sujets dans l'ordre du fichier (indice i à partir de 0) : i mod 6 ∈ {0, 1, 2, 3} → découverte
#    (2/3), i mod 6 = 4 → validation (choix du seuil), i mod 6 = 5 → test (performance rapportée) ;
#  - découverte : régression logistique y ~ dosage pour chaque variant (allèle compté du fichier), β et p de Wald ;
#  - clumping sur les génotypes de découverte : variants triés par p croissant (à égalité, ordre du fichier) ; chaque
#    variant non écarté devient index et écarte les variants du même chromosome à ≤ 250 kb avec r² > 0,1 ;
#  - seuils T ∈ {5e-8, 1e-6, 1e-4, 1e-3, 0,01, 0,05, 0,1, 0,5, 1} : score = Σ β_j·dosage_ij sur les index de p ≤ T
#    (manquant → 2·fréquence de découverte) ;
#  - validation : score centré réduit (ET à n − 1) dans l'échantillon, glm y ~ z : OR par ET, p de Wald, AUC,
#    R² de Nagelkerke ; seuil retenu = R² de Nagelkerke maximal (à égalité, le plus petit seuil) ;
#  - test : mêmes mesures pour ce seuil, IC de l'AUC par DeLong (pROC).
# DONNÉES SIMULÉES : 3 000 sujets, 3 000 variants en blocs de DL (une seule population), liability h² = 0,5 portée par
# 150 variants causaux, maladie = 30 % des liabilités les plus élevées.
source("_common.R")
suppressPackageStartupMessages({ library(genio); library(pROC) })
set.seed(20261104)
GDIR <- file.path(REF_DIR, "genotypes")
n <- 3000; target_m <- 3000
blocks <- c(); m <- 0
while (m < target_m) { L <- min(sample(1:20, 1), target_m - m); blocks <- c(blocks, L); m <- m + L }
G <- matrix(0L, n, m); chrom <- integer(m); pos <- integer(m); j0 <- 0; pcur <- c(0, 0)
for (L in blocks) {
  rho <- runif(1, 0.3, 0.97); idx <- j0 + seq_len(L); ch <- if (j0 < m / 2) 1L else 2L
  p <- runif(L, 0.05, 0.5)
  for (h in 1:2) {
    z <- matrix(rnorm(n * L), n, L)
    if (L > 1) for (k in 2:L) z[, k] <- rho * z[, k - 1] + sqrt(1 - rho^2) * z[, k]
    G[, idx] <- G[, idx] + (z < matrix(qnorm(p), n, L, byrow = TRUE))
  }
  chrom[idx] <- ch; pos[idx] <- pcur[ch] + seq_len(L) * 1000L; pcur[ch] <- pcur[ch] + L * 1000L + 2e6
  j0 <- j0 + L
}
Z <- scale(G); causal <- sample(m, 150)
gv <- as.vector(Z[, causal] %*% rnorm(150)); gv <- gv / sd(gv) * sqrt(0.5)
liab <- gv + rnorm(n, 0, sqrt(0.5))
y <- as.integer(liab > quantile(liab, 0.7))
snp <- sprintf("ps%05d", 1:m)
write_plink(file.path(GDIR, "prs"), t(G), bim = data.frame(chr = chrom, id = snp, posg = 0, pos = pos, alt = "A", ref = "G"),
            fam = data.frame(fam = sprintf("P%04d", 1:n), id = sprintf("P%04d", 1:n), pat = 0, mat = 0, sex = 0, pheno = y + 1), verbose = FALSE)

part <- (seq_len(n) - 1) %% 6
D <- part <= 3; V <- part == 4; Tt <- part == 5
gd <- G[D, ]; yd <- y[D]
fitv <- t(sapply(1:m, function(j) {
  co <- summary(glm(yd ~ gd[, j], binomial, control = glm.control(epsilon = 1e-14)))$coefficients[2, 1:2]
  c(co[1], co[2], 2 * pnorm(-abs(co[1] / co[2])))
}))
beta <- fitv[, 1]; pv <- fitv[, 3]
# Clumping.
ord <- order(pv, seq_len(m)); removed <- rep(FALSE, m); index <- rep(FALSE, m)
for (j in ord) {
  if (removed[j]) next
  index[j] <- TRUE
  w <- which(!removed & !index & chrom == chrom[j] & abs(pos - pos[j]) <= 250000)
  if (length(w)) { r2 <- as.vector(cor(gd[, j], gd[, w]))^2; removed[w[r2 > 0.1]] <- TRUE }
}
thr <- c(5e-8, 1e-6, 1e-4, 1e-3, 0.01, 0.05, 0.1, 0.5, 1)
metrics <- function(score, yy) {
  zz <- (score - mean(score)) / sd(score)
  f <- glm(yy ~ zz, binomial, control = glm.control(epsilon = 1e-14)); f0 <- glm(yy ~ 1, binomial)
  co <- summary(f)$coefficients[2, ]
  nn <- length(yy); ll <- as.numeric(logLik(f)); ll0 <- as.numeric(logLik(f0))
  cs <- 1 - exp(2 * (ll0 - ll) / nn); nk <- cs / (1 - exp(2 * ll0 / nn))
  list(beta = unname(co[1]), se = unname(co[2]), p = unname(2 * pnorm(-abs(co[1] / co[2]))), auc = as.numeric(auc(roc(yy, zz, quiet = TRUE, direction = "<"))), r2 = nk)
}
prs <- function(rows, T) { s <- index & pv <= T; as.vector(G[rows, s, drop = FALSE] %*% beta[s]) }
val <- lapply(thr, function(T) if (sum(index & pv <= T) == 0) NULL else c(list(T = T, k = sum(index & pv <= T)), metrics(prs(V, T), y[V])))
val <- Filter(Negate(is.null), val)
r2s <- sapply(val, `[[`, "r2"); best <- val[[which.max(r2s)]]
tst <- metrics(prs(Tt, best$T), y[Tt])
rc <- roc(y[Tt], prs(Tt, best$T), quiet = TRUE, direction = "<"); ci <- as.numeric(ci.auc(rc, method = "delong"))

# --- Score AJUSTÉ sur des covariables (sexe, âge) : âge associé à la maladie indépendamment des génotypes.
#  - découverte : glm y ~ dosage + sexe + âge ; clumping identique sur ces p ;
#  - évaluation : modèle de base y ~ sexe + âge, modèle complet y ~ sexe + âge + z (score centré réduit) ;
#    OR par ET ajusté, p de Wald, R² de Nagelkerke INCRÉMENTAL (complet − base, tous deux contre le modèle vide), AUC du
#    score seul, du modèle de base et du modèle complet (prédicteurs linéaires) ; seuil = R² incrémental maximal ;
#  - test : mêmes mesures, IC de DeLong de l'AUC du modèle complet, différence appariée complet − base (roc.test DeLong).
set.seed(20261106)
sexe <- sample(1:2, n, TRUE); age <- round(55 + 8 * rnorm(n) + 6 * y)
write.csv(data.frame(id = sprintf("P%04d", 1:n), sexe = ifelse(sexe == 1, "H", "F"), age = age), file.path(GDIR, "prs_covariables.csv"), row.names = FALSE, quote = FALSE)
sx <- factor(ifelse(sexe == 1, "H", "F"), levels = c("H", "F"))
fitA <- t(sapply(1:m, function(j) {
  co <- summary(glm(yd ~ gd[, j] + sx[D] + age[D], binomial, control = glm.control(epsilon = 1e-14)))$coefficients[2, 1:2]
  c(co[1], co[2], 2 * pnorm(-abs(co[1] / co[2])))
}))
betaA <- fitA[, 1]; pA <- fitA[, 3]
ordA <- order(pA, seq_len(m)); remA <- rep(FALSE, m); idxA <- rep(FALSE, m)
for (j in ordA) {
  if (remA[j]) next
  idxA[j] <- TRUE
  w <- which(!remA & !idxA & chrom == chrom[j] & abs(pos - pos[j]) <= 250000)
  if (length(w)) { r2 <- as.vector(cor(gd[, j], gd[, w]))^2; remA[w[r2 > 0.1]] <- TRUE }
}
nk <- function(ll, ll0, nn) (1 - exp(2 * (ll0 - ll) / nn)) / (1 - exp(2 * ll0 / nn))
metricsA <- function(score, rows) {
  yy <- y[rows]; zz <- (score - mean(score)) / sd(score); s2 <- sx[rows]; a2 <- age[rows]
  ctl <- glm.control(epsilon = 1e-14)
  f0 <- glm(yy ~ s2 + a2, binomial, control = ctl); f1 <- glm(yy ~ s2 + a2 + zz, binomial, control = ctl); fe <- glm(yy ~ 1, binomial)
  ll0 <- as.numeric(logLik(fe)); nn <- length(yy); co <- summary(f1)$coefficients["zz", ]
  list(beta = unname(co[1]), se = unname(co[2]), p = unname(2 * pnorm(-abs(co[1] / co[2]))),
       r2 = nk(as.numeric(logLik(f1)), ll0, nn) - nk(as.numeric(logLik(f0)), ll0, nn),
       r2_base = nk(as.numeric(logLik(f0)), ll0, nn), r2_full = nk(as.numeric(logLik(f1)), ll0, nn),
       auc = as.numeric(auc(roc(yy, zz, quiet = TRUE, direction = "<"))),
       auc_base = as.numeric(auc(roc(yy, predict(f0), quiet = TRUE, direction = "<"))),
       auc_full = as.numeric(auc(roc(yy, predict(f1), quiet = TRUE, direction = "<"))), lp_full = unname(predict(f1)), lp_base = unname(predict(f0)))
}
prsA <- function(rows, T) { s <- idxA & pA <= T; as.vector(G[rows, s, drop = FALSE] %*% betaA[s]) }
valA <- lapply(thr, function(T) if (sum(idxA & pA <= T) == 0) NULL else { mm <- metricsA(prsA(V, T), V); mm$lp_full <- NULL; mm$lp_base <- NULL; c(list(T = T, k = sum(idxA & pA <= T)), mm) })
valA <- Filter(Negate(is.null), valA)
bestA <- valA[[which.max(sapply(valA, `[[`, "r2"))]]
tA <- metricsA(prsA(Tt, bestA$T), Tt)
rF <- roc(y[Tt], tA$lp_full, quiet = TRUE, direction = "<"); rB <- roc(y[Tt], tA$lp_base, quiet = TRUE, direction = "<")
ciA <- as.numeric(ci.auc(rF, method = "delong")); cmp <- roc.test(rF, rB, method = "delong", paired = TRUE)
dA <- as.numeric(auc(rF) - auc(rB)); ciD <- as.numeric(attr(cmp$conf.int, "conf.level")); ciDiff <- as.numeric(cmp$conf.int)
tA$lp_full <- NULL; tA$lp_base <- NULL
adjusted <- list(beta = unname(betaA), p = unname(pA), index = which(idxA), validation = valA, best_T = bestA$T,
                 test = c(tA, list(auc_full_lower = ciA[1], auc_full_upper = ciA[3], delta_auc = dA, delta_lower = ciDiff[1], delta_upper = ciDiff[2], delta_p = cmp$p.value)))
cat("ajusté : seuil", bestA$T, "(", bestA$k, ") ; test ΔR²", tA$r2, " AUC base", tA$auc_base, "complet", tA$auc_full, " Δ", dA, "p", cmp$p.value, "\n")

write_ref(list(n = n, m = m, beta = unname(beta), p = unname(pv), index = which(index), validation = val, best_T = best$T,
               test = c(tst, list(auc_lower = ci[1], auc_upper = ci[3])), n_disc = sum(D), n_val = sum(V), n_test = sum(Tt), adjusted = adjusted), "prs")
cat("index", sum(index), "; seuil retenu", best$T, "(", best$k, "variants ) ; validation R²", best$r2, "\ntest : OR/ET", exp(tst$beta), " AUC", tst$auc, "[", ci[1], ";", ci[3], "] R²", tst$r2, "\n")
