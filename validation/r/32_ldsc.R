# LD score regression (Bulik-Sullivan et al. 2015), spécification de Statoméa réimplémentée ici à l'identique :
#  - scores LD dans l'échantillon : ℓ_j = Σ_k r²_adj(j, k) sur les variants du même chromosome à moins de 1 Mb (k = j inclus),
#    r²_adj = r² − (1 − r²)/(n − 2) ;
#  - variants avec χ² > max(80 ; 0,001·N) exclus ;
#  - régression pondérée de χ² sur (1, ℓ), deux itérations, poids w = 1 / (max(ℓ, 1) · (a + N·h²·ℓ/M)²) avec h² borné à
#    [0 ; 1], départ a = 1, h² = M(χ̄² − 1)/(N·ℓ̄) ; h² = pente·M/N ;
#  - erreurs types par jackknife sur B = min(50, ⌊J/10⌋) blocs contigus (bloc de k = ⌊(k − 1)·B/J⌋ + 1) (poids de l'ajustement complet fixés) ;
#  - ratio = (intercept − 1)/(χ̄² − 1).
# DONNÉES SIMULÉES avec DL réel : blocs de variants corrélés (copule gaussienne sur les haplotypes, corrélation AR(1)
# variable selon le bloc). Scénario A : trait polygénique (h² = 0,4), pas de confusion → intercept ≈ 1.
# Scénario B : mêmes génotypes, deux sous-populations dont la moyenne du trait et les fréquences diffèrent → intercept > 1.
source("_common.R")
suppressPackageStartupMessages(library(genio))
set.seed(20261101)
GDIR <- file.path(REF_DIR, "genotypes"); dir.create(GDIR, showWarnings = FALSE)
# Génotypes en blocs de DL : copule gaussienne AR(1) par haplotype ; fréquences décalées entre les deux sous-populations.
simulate <- function(n, target_m, shift_sd = 0.15) {
  pop <- rep(1:2, each = n / 2)
  blocks <- c(); m <- 0
  while (m < target_m) { L <- min(sample(1:20, 1), target_m - m); blocks <- c(blocks, L); m <- m + L }
  G <- matrix(0L, n, m); chrom <- integer(m); pos <- integer(m); j0 <- 0; pcur <- c(0, 0)
  for (L in blocks) {
    rho <- runif(1, 0.3, 0.97); idx <- j0 + seq_len(L)
    ch <- if (j0 < m / 2) 1L else 2L
    p <- runif(L, 0.05, 0.5)
    shift <- rnorm(L, 0, shift_sd)                         # différence de fréquence entre sous-populations
    for (h in 1:2) {
      z <- matrix(rnorm(n * L), n, L)
      if (L > 1) for (k in 2:L) z[, k] <- rho * z[, k - 1] + sqrt(1 - rho^2) * z[, k]
      thr <- outer(ifelse(pop == 1, 0, 1), shift) + matrix(qnorm(p), n, L, byrow = TRUE)
      G[, idx] <- G[, idx] + (z < thr)
    }
    chrom[idx] <- ch; pos[idx] <- pcur[ch] + seq_len(L) * 1000L; pcur[ch] <- pcur[ch] + L * 1000L + 2e6
    j0 <- j0 + L
  }
  list(G = G, pop = pop, chrom = chrom, pos = pos, m = m)
}
ldscores <- function(G, chrom, pos) {
  n <- nrow(G); Z <- scale(G); r2adj <- function(r2) r2 - (1 - r2) / (n - 2)
  sapply(seq_len(ncol(G)), function(j) {
    w <- which(chrom == chrom[j] & abs(pos - pos[j]) <= 1e6)
    sum(r2adj((as.vector(crossprod(Z[, w], Z[, j])) / (n - 1))^2))
  })
}
n <- 2000
S <- simulate(n, 4000); G <- S$G; pop <- S$pop; chrom <- S$chrom; pos <- S$pos; m <- S$m
snp <- sprintf("ld%05d", 1:m)
write_plink(file.path(GDIR, "ldsc"), t(G), bim = data.frame(chr = chrom, id = snp, posg = 0, pos = pos, alt = "A", ref = "G"),
            fam = data.frame(fam = 1:n, id = sprintf("D%04d", 1:n), pat = 0, mat = 0, sex = 0, pheno = -9), verbose = FALSE)

ell <- ldscores(G, chrom, pos)
Z <- scale(G)

# Traits.
causal <- sample(m, 800); beta <- rnorm(800, 0, sqrt(0.4 / 800))
gval <- as.vector(Z[, causal] %*% beta)
gval <- gval - ave(gval, pop)                               # A : valeur génétique centrée par sous-population (pas de confusion)
yA <- gval + rnorm(n, 0, sqrt(0.6))
yB <- yA + 0.5 * (pop == 2)                                  # B : la moyenne du trait diffère entre sous-populations
chi2 <- function(y) sapply(1:m, function(j) summary(lm(y ~ G[, j]))$coefficients[2, 3]^2)
cA <- chi2(yA); cB <- chi2(yB)

ldsc <- function(c2, ell, N, M) {
  keep <- c2 <= max(80, 0.001 * N); c2 <- c2[keep]; l <- ell[keep]; J <- length(c2)
  h2 <- min(max(M * (mean(c2) - 1) / (N * mean(l)), 0), 1); a <- 1
  for (it in 1:2) {
    w <- 1 / (pmax(l, 1) * (a + N * min(max(h2, 0), 1) * l / M)^2)
    f <- lm.wfit(cbind(1, l), c2, w); a <- f$coefficients[1]; h2 <- f$coefficients[2] * M / N
  }
  B <- min(50, floor(J / 10)); blk <- floor((seq_len(J) - 1) * B / J) + 1
  est <- function(sel) { f <- lm.wfit(cbind(1, l[sel]), c2[sel], w[sel]); c(f$coefficients[1], f$coefficients[2] * M / N) }
  full <- c(a, h2)
  jk <- t(sapply(1:B, function(b) est(blk != b)))
  se <- sqrt((B - 1) / B * colSums(sweep(jk, 2, colMeans(jk))^2))
  list(intercept = unname(full[1]), h2 = unname(full[2]), se_intercept = unname(se[1]), se_h2 = unname(se[2]),
       mean_chi2 = mean(c2), ratio = unname((full[1] - 1) / (mean(c2) - 1)), J = J, B = B)
}
rA <- ldsc(cA, ell, n, m); rB <- ldsc(cB, ell, n, m)

# Exemple de l'application : 1 000 sujets, 3 000 variants ; statut cas/témoin = moitié supérieure d'une liability polygénique
# (h² = 0,5) dont la moyenne diffère entre sous-populations (confusion). Référence de la chaîne : régression logistique
# non ajustée (χ² de Wald) → LDSC.
set.seed(20261102)
na <- 1000; E <- simulate(na, 3000); Ga <- E$G; ma <- E$m
Za <- scale(Ga); ca <- sample(ma, 600)
liab <- as.vector(Za[, ca] %*% rnorm(600, 0, sqrt(0.5 / 600))); liab <- liab - ave(liab, E$pop)
liab <- liab + rnorm(na, 0, sqrt(0.5)) + 0.8 * (E$pop == 2)
statut <- as.integer(liab > median(liab))
sexe <- sample(1:2, na, TRUE)
write_plink(file.path(GDIR, "ldsc_app"), t(Ga), bim = data.frame(chr = E$chrom, id = sprintf("dl%05d", 1:ma), posg = 0, pos = E$pos, alt = "A", ref = "G"),
            fam = data.frame(fam = sprintf("E%04d", 1:na), id = sprintf("E%04d", 1:na), pat = 0, mat = 0, sex = sexe, pheno = statut + 1), verbose = FALSE)
ella <- ldscores(Ga, E$chrom, E$pos)
wald <- sapply(1:ma, function(j) { co <- summary(glm(statut ~ Ga[, j], binomial, control = glm.control(epsilon = 1e-14)))$coefficients[2, 1:2]; (co[1] / co[2])^2 })
rApp <- ldsc(wald, ella, na, ma)

write_ref(list(n = n, m = m, ell = ell, chi2_A = cA, chi2_B = cB, A = rA, B = rB, app = c(rApp, list(chi2 = unname(wald), ell = ella))), "ldsc")
cat("ℓ moyen", mean(ell), "(", min(ell), "à", max(ell), ")\nA : intercept", rA$intercept, "±", rA$se_intercept, " h²", rA$h2, "±", rA$se_h2,
    "\nB : intercept", rB$intercept, "±", rB$se_intercept, " h²", rB$h2, " ratio", rB$ratio, "\nApp : intercept", rApp$intercept, "±", rApp$se_intercept, " h²", rApp$h2, "\n")
