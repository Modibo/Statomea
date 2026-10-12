# Modèle mixte LOCO (« leave one chromosome out ») : pour les variants du chromosome c, K₋c = GRM standardisée calculée
# sans les variants de c ; composantes de variance réestimées par REML pour chaque chromosome (comme GCTA --mlma-loco),
# puis test P3D. Mêmes données et mêmes formules que 30_lmm.R (recalcul serré), covariables sexe + âge.
source("_common.R")
suppressPackageStartupMessages(library(genio))
GDIR <- file.path(REF_DIR, "genotypes")
pl <- read_plink(file.path(GDIR, "lmm"), verbose = FALSE)
G <- t(pl$X); n <- nrow(G); m <- ncol(G); chrom <- pl$bim$chr
ph <- read.csv(file.path(GDIR, "lmm_phenotypes.csv"))
y <- ph$trait[match(pl$fam$id, ph$id)]; age <- ph$age[match(pl$fam$id, ph$id)]; sexe <- pl$fam$sex
Xf <- cbind(1, sexe == 2, age)
pf <- colMeans(G) / 2
Z <- sweep(sweep(G, 2, 2 * pf), 2, sqrt(2 * pf * (1 - pf)), "/")
fit_null <- function(K) {
  ek <- eigen(K, symmetric = TRUE); U <- ek$vectors; s <- ek$values
  ys <- crossprod(U, y); Xs <- crossprod(U, Xf)
  reml <- function(lam) { w <- 1 / (s + lam); A <- crossprod(Xs, Xs * w); b <- solve(A, crossprod(Xs, ys * w)); r <- ys - Xs %*% b
    (n - ncol(Xf)) * log(sum(w * r^2)) + sum(log(s + lam)) + as.numeric(determinant(A)$modulus) }
  lam <- exp(optimize(function(l) reml(exp(l)), c(log(1e-9), log(1e9)), tol = 1e-12)$minimum)
  list(U = U, s = s, lam = lam, ys = ys, Xs = Xs)
}
test <- function(f, j) { w <- 1 / (f$s + f$lam); X3 <- cbind(f$Xs, crossprod(f$U, G[, j])); W <- crossprod(X3, X3 * w); Wi <- solve(W)
  b <- Wi %*% crossprod(X3, f$ys * w); res <- f$ys - X3 %*% b; v2 <- n - ncol(X3); s2 <- sum(w * res^2) / v2
  pf(b[ncol(X3)]^2 / (s2 * Wi[ncol(X3), ncol(X3)]), 1, v2, lower.tail = FALSE) }
p <- numeric(m); lam_c <- c()
for (c in sort(unique(chrom))) {
  keep <- chrom != c
  Kc <- tcrossprod(Z[, keep]) / sum(keep)
  f <- fit_null(Kc); lam_c <- c(lam_c, f$lam)
  for (j in which(chrom == c)) p[j] <- test(f, j)
}
gc <- function(pv) median(qchisq(pv, 1, lower.tail = FALSE)) / qchisq(0.5, 1)
write_ref(list(p = p, lambda_by_chrom = lam_c, gc = gc(p)), "lmm_loco")
cat("λ_GC LOCO :", gc(p), " ; λ REML par chromosome :", lam_c, "\n")
