# Stratification de population : élagage LD, ACP standardisée (Patterson, Price, Reich 2006), inflation génomique.
# DONNÉES SIMULÉES : 400 sujets de 2 sous-populations (modèle de Balding-Nichols, F_ST = 0,03) ; la proportion de cas
# diffère entre sous-populations (0,35 contre 0,65) : confusion par l'ascendance, sans variant causal.
# 1 000 variants (chromosomes 1 à 4), dont 60 paires fortement corrélées (variants voisins) pour l'élagage.
# Règle d'élagage (réimplémentée à l'identique dans Statoméa ; inspirée de plink --indep-pairwise 50 5 0.2, sans
# prétendre la reproduire) : par chromosome, fenêtres de 50 variants avançant de 5 ; dans une fenêtre, paires (i < j)
# encore retenues parcourues dans l'ordre ; si r² > 0,2 (corrélation de Pearson des dosages, observations complètes
# deux à deux), on écarte celui de plus faible MAF (à égalité, le second).
# ACP : p = fréquence observée ; x = (g − 2p)/√(2p(1 − p)) ; manquant → 0 ; G = X Xᵀ / m ; eigen(G).
source("_common.R")
suppressPackageStartupMessages({ library(genio) })
set.seed(20261027)
GDIR <- file.path(REF_DIR, "genotypes"); dir.create(GDIR, showWarnings = FALSE)
n <- 400; m <- 1000; Fst <- 0.03
pop <- rep(1:2, each = n / 2)
pa <- runif(m, 0.1, 0.9)
pp <- sapply(1:2, function(k) rbeta(m, pa * (1 - Fst) / Fst, (1 - pa) * (1 - Fst) / Fst))
G <- sapply(1:m, function(j) rbinom(n, 2, pp[j, pop]))
pairs <- seq(2, 120, by = 2)                              # variant j copie bruitée de j − 1 (même chromosome)
for (j in pairs) { k <- runif(n) < 0.9; G[k, j] <- G[k, j - 1] }
G[matrix(runif(n * m) < 0.003, n, m)] <- NA
statut <- rbinom(n, 1, ifelse(pop == 1, 0.35, 0.65))
sexe <- sample(1:2, n, TRUE)
chrom <- rep(1:4, each = m / 4); pos <- unlist(lapply(1:4, function(c) sort(sample(1e5:9e6, m / 4))))
snp <- sprintf("rs%05d", 10000 + 1:m)
nt <- c("A", "C", "G", "T"); ref <- sample(nt, m, TRUE); alt <- sapply(ref, function(r) sample(setdiff(nt, r), 1))
ids <- sprintf("P%03d", 1:n)
write_plink(file.path(GDIR, "strat"), t(G), bim = data.frame(chr = chrom, id = snp, posg = 0, pos = pos, alt = alt, ref = ref),
            fam = data.frame(fam = ids, id = ids, pat = 0, mat = 0, sex = sexe, pheno = statut + 1), verbose = FALSE)

maf <- apply(G, 2, function(g) { p <- mean(g, na.rm = TRUE) / 2; min(p, 1 - p) })
r2 <- function(a, b) { ok <- !is.na(a) & !is.na(b); if (sd(a[ok]) == 0 || sd(b[ok]) == 0) return(0); cor(a[ok], b[ok])^2 }
keep <- rep(TRUE, m)
for (c in 1:4) {
  idx <- which(chrom == c)
  s <- 1
  while (s <= length(idx)) {
    w <- idx[s:min(s + 49, length(idx))]
    for (a in seq_along(w)) for (b in seq_along(w)) if (a < b) {
      i <- w[a]; j <- w[b]
      if (keep[i] && keep[j] && r2(G[, i], G[, j]) > 0.2) {
        if (maf[j] <= maf[i]) keep[j] <- FALSE else keep[i] <- FALSE
      }
    }
    s <- s + 5
  }
}
Gp <- G[, keep]
p <- colMeans(Gp, na.rm = TRUE) / 2
X <- sweep(Gp, 2, 2 * p); X <- sweep(X, 2, sqrt(2 * p * (1 - p)), "/"); X[is.na(X)] <- 0
GRM <- tcrossprod(X) / ncol(X)
e <- eigen(GRM, symmetric = TRUE)
pcs <- e$vectors[, 1:10]
for (k in 1:10) if (pcs[which.max(abs(pcs[, k])), k] < 0) pcs[, k] <- -pcs[, k]   # signe : plus grande coordonnée positive

# Inflation génomique sans et avec ajustement sur 2 CP (logistique additive par variant, sexe en covariable).
gc_lambda <- function(pv) median(qchisq(pv, 1, lower.tail = FALSE)) / qchisq(0.5, 1)
scan <- function(adj) sapply(1:m, function(j) {
  d <- data.frame(y = statut, g = G[, j], sexe = factor(sexe), pc1 = pcs[, 1], pc2 = pcs[, 2])
  f <- if (adj) y ~ g + sexe + pc1 + pc2 else y ~ g + sexe
  summary(glm(f, binomial, d, control = glm.control(epsilon = 1e-14)))$coefficients["g", 4]
})
p0 <- scan(FALSE); p2 <- scan(TRUE)

write_ref(list(
  ids = ids, keep = which(keep), n_pruned_out = sum(!keep), maf = maf,
  eigenvalues = e$values[1:10], trace = sum(diag(GRM)), pcs = unname(pcs), pop = pop,
  p_unadj = p0, p_pc = p2, lambda_unadj = gc_lambda(p0), lambda_pc = gc_lambda(p2)
), "acp")
cat("élagués :", sum(!keep), "; λ brut =", gc_lambda(p0), "; λ ajusté 2 CP =", gc_lambda(p2), "; VP1-3 :", e$values[1:3], "\n")
