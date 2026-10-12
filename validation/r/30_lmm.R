# Association par modèle linéaire mixte (EMMAX / P3D, Kang et al. 2010) : y = Xβ + g + e, g ~ N(0, Vu·K),
# e ~ N(0, Ve·I) ; K = GRM standardisée (x = (g − 2p)/√(2p(1 − p)), K = XXᵀ/m) ; composantes de variance par REML sous
# le modèle nul, puis pour chaque variant moindres carrés généralisés avec H = K + λI (λ = Ve/Vu fixé) et test F(1, n − p).
# DONNÉES SIMULÉES : 150 fratries de 3 + 150 sujets non apparentés (600), 1 500 variants indépendants complets ; trait
# quantitatif polygénique (h² ≈ 0,5, 300 variants à petits effets) + 1 variant causal (0,35 ET par allèle) ; sexe, âge.
# Références : rrBLUP 4.6 (mixed.solve REML ; GWAS P3D avec le sexe en effet fixe, seul type d'effet fixe que GWAS
# accepte sans le transformer en facteur) ; recalcul R à tolérance serrée (optimize tol = 1e-12) avec sexe + âge.
source("_common.R")
suppressPackageStartupMessages({ library(genio); library(rrBLUP) })
set.seed(20261031)
GDIR <- file.path(REF_DIR, "genotypes"); dir.create(GDIR, showWarnings = FALSE)
m <- 1500; nfam <- 150; nsingle <- 150
p <- runif(m, 0.05, 0.5)
founder <- function() rbinom(m, 2, p)
gamete <- function(g) ifelse(g == 1, rbinom(m, 1, 0.5), g / 2)
G <- NULL; fam <- c()
for (f in 1:nfam) { a <- founder(); b <- founder(); for (k in 1:3) { G <- rbind(G, gamete(a) + gamete(b)); fam <- c(fam, f) } }
for (s in 1:nsingle) { G <- rbind(G, founder()); fam <- c(fam, nfam + s) }
G <- unname(G); n <- nrow(G)
ids <- sprintf("L%03d", 1:n)
sexe <- sample(1:2, n, TRUE); age <- round(rnorm(n, 45, 12))
poly <- sample(m, 300); jc <- 777
Xs <- scale(G)                                            # génotypes standardisés pour le fond polygénique
gpoly <- Xs[, poly] %*% rnorm(300, 0, sqrt(0.5 / 300))
y <- as.vector(0.35 * Xs[, jc] + gpoly + 0.02 * (age - 45) + 0.2 * (sexe == 2) + rnorm(n, 0, sqrt(0.45)))
write_plink(file.path(GDIR, "lmm"), t(G), bim = data.frame(chr = rep(1:3, each = m / 3), id = sprintf("m%04d", 1:m), posg = 0, pos = rep(1:(m / 3), 3) * 5000, alt = "A", ref = "G"),
            fam = data.frame(fam = ids, id = ids, pat = 0, mat = 0, sex = sexe, pheno = -9), verbose = FALSE)
write.csv(data.frame(id = ids, trait = round(y, 6), age = age), file.path(GDIR, "lmm_phenotypes.csv"), row.names = FALSE, quote = FALSE)
y <- round(y, 6)                                            # valeur exactement relue par Statoméa

# GRM standardisée.
pf <- colMeans(G) / 2
X <- sweep(sweep(G, 2, 2 * pf), 2, sqrt(2 * pf * (1 - pf)), "/")
K <- tcrossprod(X) / m
rownames(K) <- colnames(K) <- ids

# 1) rrBLUP, sexe seul en effet fixe.
ms <- mixed.solve(y, X = cbind(1, sexe == 2), K = K, method = "REML")
geno <- data.frame(marker = sprintf("m%04d", 1:m), chrom = rep(1:3, each = m / 3), pos = rep(1:(m / 3), 3) * 5000, t(G - 1), check.names = FALSE)
colnames(geno)[-(1:3)] <- ids
pheno <- data.frame(gid = ids, trait = y, sexe = sexe)
gw <- suppressMessages(capture.output(res <- GWAS(pheno, geno, fixed = "sexe", K = K, min.MAF = 0, P3D = TRUE, plot = FALSE)))
p_rrblup <- 10^-res$trait[match(sprintf("m%04d", 1:m), res$marker)]

# 2) Recalcul serré (formules de rrBLUP, optimize tol = 1e-12), sexe + âge.
p3d <- function(Xf) {
  ek <- eigen(K, symmetric = TRUE); U <- ek$vectors; s <- ek$values
  ys <- crossprod(U, y); Xs2 <- crossprod(U, Xf)
  reml <- function(lam) {                                     # −2 log L_REML à une constante près
    w <- 1 / (s + lam); A <- crossprod(Xs2, Xs2 * w); b <- crossprod(Xs2, ys * w)
    beta <- solve(A, b); r <- ys - Xs2 %*% beta
    (n - ncol(Xf)) * log(sum(w * r^2)) + sum(log(s + lam)) + as.numeric(determinant(A)$modulus)
  }
  lam <- exp(optimize(function(l) reml(exp(l)), c(log(1e-9), log(1e9)), tol = 1e-12)$minimum)
  w <- 1 / (s + lam); A <- crossprod(Xs2, Xs2 * w); beta <- solve(A, crossprod(Xs2, ys * w)); r <- ys - Xs2 %*% beta
  Vu <- sum(w * r^2) / (n - ncol(Xf)); Ve <- lam * Vu
  pv <- sapply(1:m, function(j) {
    X3 <- cbind(Xs2, crossprod(U, G[, j])); W <- crossprod(X3, X3 * w); Wi <- solve(W)
    b <- Wi %*% crossprod(X3, ys * w); res <- ys - X3 %*% b; v2 <- n - ncol(X3)
    s2 <- sum(w * res^2) / v2; Fs <- b[ncol(X3)]^2 / (s2 * Wi[ncol(X3), ncol(X3)])
    pf(Fs, 1, v2, lower.tail = FALSE)
  })
  list(lambda = lam, Vu = Vu, Ve = Ve, p = pv)
}
t_sexe <- p3d(cbind(1, sexe == 2))
t_full <- p3d(cbind(1, sexe == 2, age))
naive <- sapply(1:m, function(j) summary(lm(y ~ G[, j] + factor(sexe) + age))$coefficients[2, 4])
gc <- function(pv) median(qchisq(pv, 1, lower.tail = FALSE)) / qchisq(0.5, 1)

write_ref(list(
  rrblup_Vu = ms$Vu, rrblup_Ve = ms$Ve, p_rrblup = p_rrblup,
  sexe = list(lambda = t_sexe$lambda, Vu = t_sexe$Vu, Ve = t_sexe$Ve, p = t_sexe$p),
  full = list(lambda = t_full$lambda, Vu = t_full$Vu, Ve = t_full$Ve, p = t_full$p, gc = gc(t_full$p)),
  naive_gc = gc(naive), causal = sprintf("m%04d", jc), mean_diag_K = mean(diag(K))
), "lmm")
cat("rrBLUP Vu/Ve", ms$Vu, ms$Ve, " ; serré", t_sexe$Vu, t_sexe$Ve, " ; max |Δ log10 p| rrBLUP–serré",
    max(abs(log10(p_rrblup) - log10(t_sexe$p))), "\nλGC naïf", gc(naive), " LMM", gc(t_full$p), " ; p causal", t_full$p[jc], "\n")
