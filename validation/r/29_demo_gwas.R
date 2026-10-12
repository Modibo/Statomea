# Démonstration 5 : étude d'association cas-témoins pangénomique (simulée), de bout en bout.
# DONNÉES SIMULÉES : 2 sous-populations (F_ST = 0,03) dont la proportion de cas diffère (confusion par l'ascendance),
# 3 000 variants indépendants, 2 variants causaux (OR 2,6 et 1,6 par allèle) dont le second a un voisin en DL ;
# défauts : variants à manquants, sujets contaminés ; 3 doublons et 5 paires de frères/sœurs.
# Chaîne (règles identiques à Statoméa, validées module par module par 25 à 28_*.R) : contrôle de qualité → parenté
# KING-robust (exclusion gloutonne > 0,0884) → ACP sur les non-apparentés (élagage LD) → balayage brut → balayage ajusté
# (sexe, âge, CP1, CP2).
source("_common.R")
suppressPackageStartupMessages({ library(genio); library(HardyWeinberg) })
set.seed(20261029)
DEMO_DIR <- normalizePath(file.path("..", "..", "demos"))
m <- 3000; nf <- 487; Fst <- 0.03
pop <- rep(1:2, length.out = nf)
pa <- runif(m, 0.1, 0.9)
pp <- sapply(1:2, function(k) rbeta(m, pa * (1 - Fst) / Fst, (1 - pa) * (1 - Fst) / Fst))
gen <- function(k) rbinom(m, 2, pp[, k])
G <- t(sapply(pop, gen))
# Causal 1 (variant 1500, MAF ≈ 0,3, OR 2,6) ; causal 2 (variant 2200, OR 1,6) ; 2201 en DL avec 2200.
j1 <- 1500; j2 <- 2200
G[, j1] <- rbinom(nf, 2, 0.3); G[, j2] <- rbinom(nf, 2, 0.35)
lin <- -0.62 + 0.9 * (pop == 2) + log(2.6) * (G[, j1] - 0.6) + log(1.6) * (G[, j2] - 0.7)
statut <- rbinom(nf, 1, plogis(lin))
sexe <- sample(1:2, nf, TRUE); age <- round(rnorm(nf, 55, 9))
# Apparentés : 3 doublons (0,5 % d'erreurs) et 5 frères/sœurs (enfant des mêmes parents que le sujet, même population).
gamete <- function(g) ifelse(g == 1, rbinom(m, 1, 0.5), g / 2)
ids <- sprintf("G%03d", 1:nf)
for (i in 1:3) { g <- G[i, ]; e <- runif(m) < 0.005; g[e] <- sample(0:2, sum(e), TRUE)
  G <- rbind(G, g); ids <- c(ids, paste0(ids[i], "_dup")); statut <- c(statut, statut[i]); sexe <- c(sexe, sexe[i]); age <- c(age, age[i]); pop <- c(pop, pop[i]) }
for (k in 1:5) { i <- 10 + k; pa1 <- gen(pop[i]); pa2 <- gen(pop[i])
  s1 <- gamete(pa1) + gamete(pa2); s2 <- gamete(pa1) + gamete(pa2)
  G[i, ] <- s1; G <- rbind(G, s2); ids <- c(ids, paste0(ids[i], "_fr")); statut <- c(statut, statut[i]); sexe <- c(sexe, sample(1:2, 1)); age <- c(age, age[i] + sample(-5:5, 1)); pop <- c(pop, pop[i]) }
G <- unname(G); n <- nrow(G)
G[, j2 + 1] <- ifelse(runif(n) < 0.85, G[, j2], G[, j2 + 1])          # voisin en DL
G[sample(n, 3), ] <- ifelse(runif(3 * m) < 0.7, 1, G[sample(n, 3), ])  # 3 sujets « contaminés »
miss <- matrix(runif(n * m) < 0.004, n, m); miss[, 100:104] <- runif(n * 5) < 0.15
G[miss] <- NA
chrom <- rep(1:6, each = m / 6); pos <- unlist(lapply(1:6, function(c) sort(sample(1e5:9e7, m / 6))))
pos[j2 + 1] <- pos[j2] + 1500
snp <- sprintf("rs%06d", 200000 + 1:m)
nt <- c("A", "C", "G", "T"); ref <- sample(nt, m, TRUE); alt <- sapply(ref, function(r) sample(setdiff(nt, r), 1))
write_plink(file.path(DEMO_DIR, "gwas_simule"), t(G), bim = data.frame(chr = chrom, id = snp, posg = 0, pos = pos, alt = alt, ref = ref),
            fam = data.frame(fam = ids, id = ids, pat = 0, mat = 0, sex = sexe, pheno = statut + 1), verbose = FALSE)
write.csv(data.frame(id = ids, age = age), file.path(DEMO_DIR, "gwas_covariables_simule.csv"), row.names = FALSE, quote = FALSE)

# --- Contrôle de qualité (25_genotypes.R) ---
callS <- rowMeans(!is.na(G)); het <- rowSums(G == 1, na.rm = TRUE) / rowSums(!is.na(G))
k1 <- callS >= 0.95; hz <- (het - mean(het[k1])) / sd(het[k1]); keepS <- k1 & abs(hz) <= 3
Gk <- G[keepS, ]; st <- statut[keepS]
callV <- colMeans(!is.na(Gk)); mafV <- apply(Gk, 2, function(g) { p <- sum(g, na.rm = TRUE) / (2 * sum(!is.na(g))); min(p, 1 - p) })
hweV <- apply(Gk[st == 0, ], 2, function(g) { g <- g[!is.na(g)]; HWExact(c(AA = sum(g == 0), AB = sum(g == 1), BB = sum(g == 2)), verbose = FALSE)$pval })
keepV <- callV >= 0.95 & mafV >= 0.01 & hweV >= 1e-6
Q <- Gk[, keepV]; qid <- ids[keepS]; qst <- st; qsexe <- sexe[keepS]; qage <- age[keepS]
qchrom <- chrom[keepV]; qpos <- pos[keepV]; qsnp <- snp[keepV]

# --- Parenté (27_parente.R) ---
nm <- !is.na(Q); H <- ((Q == 1) & nm) * 1; N0 <- ((Q == 0) & nm) * 1; N2 <- ((Q == 2) & nm) * 1; NM <- nm * 1
H[is.na(H)] <- 0; N0[is.na(N0)] <- 0; N2[is.na(N2)] <- 0
Nhh <- H %*% t(H); Nopp <- N0 %*% t(N2) + N2 %*% t(N0); Hi <- H %*% t(NM); Hj <- t(Hi)
Hmin <- pmin(Hi, Hj); Hmax <- pmax(Hi, Hj)
phi <- (Nhh - 2 * Nopp) / (2 * Hmin) + 0.5 - (Hmin + Hmax) / (4 * Hmin); diag(phi) <- NA
call <- rowMeans(nm); keepU <- rep(TRUE, nrow(Q))
repeat {
  rel <- which(upper.tri(phi) & phi > 0.0884 & outer(keepU, keepU, "&"), arr.ind = TRUE)
  if (nrow(rel) == 0) break
  cnt <- tabulate(c(rel[, 1], rel[, 2]), nrow(Q)); cand <- which(cnt == max(cnt)); cand <- cand[call[cand] == min(call[cand])]
  keepU[max(cand)] <- FALSE
}
U <- Q[keepU, ]; ust <- qst[keepU]; usexe <- qsexe[keepU]; uage <- qage[keepU]

# --- ACP (26_acp.R) ---
maf <- apply(U, 2, function(g) { p <- mean(g, na.rm = TRUE) / 2; min(p, 1 - p) })
r2 <- function(a, b) { ok <- !is.na(a) & !is.na(b); if (sd(a[ok]) == 0 || sd(b[ok]) == 0) return(0); cor(a[ok], b[ok])^2 }
keepP <- rep(TRUE, ncol(U))
for (c in unique(qchrom)) {
  idx <- which(qchrom == c); idx <- idx[order(qpos[idx], idx)]
  s <- 1
  while (s <= length(idx)) {
    w <- idx[s:min(s + 49, length(idx))]
    for (a in seq_along(w)) for (b in seq_along(w)) if (a < b) {
      i <- w[a]; j <- w[b]
      if (keepP[i] && keepP[j] && r2(U[, i], U[, j]) > 0.2) { if (maf[j] <= maf[i]) keepP[j] <- FALSE else keepP[i] <- FALSE }
    }
    s <- s + 5
  }
}
P <- U[, keepP]; pf <- colMeans(P, na.rm = TRUE) / 2
X <- sweep(sweep(P, 2, 2 * pf), 2, sqrt(2 * pf * (1 - pf)), "/"); X[is.na(X)] <- 0
e <- eigen(tcrossprod(X) / ncol(X), symmetric = TRUE)
pcs <- e$vectors[, 1:2]; for (k in 1:2) if (pcs[which.max(abs(pcs[, k])), k] < 0) pcs[, k] <- -pcs[, k]

# --- Balayages ---
gc <- function(pv) median(qchisq(pv, 1, lower.tail = FALSE)) / qchisq(0.5, 1)
fit <- function(j, adj) {
  d <- data.frame(y = ust, g = U[, j], sexe = factor(usexe), age = uage, pc1 = pcs[, 1], pc2 = pcs[, 2])
  f <- if (adj) y ~ g + sexe + age + pc1 + pc2 else y ~ g
  summary(glm(f, binomial, d, control = glm.control(epsilon = 1e-14)))$coefficients["g", c(1, 4)]
}
s0 <- t(sapply(seq_len(ncol(U)), fit, adj = FALSE)); s1 <- t(sapply(seq_len(ncol(U)), fit, adj = TRUE))
top <- order(s1[, 2])[1:3]

write_ref(list(
  n = n, m = m, qc_removed_samples = which(!keepS), qc_removed_variants = which(!keepV),
  related_removed = qid[!keepU], n_unrelated = sum(keepU), pruned = sum(!keepP), eigen = e$values[1:4],
  lambda_raw = gc(s0[, 2]), lambda_adj = gc(s1[, 2]), top_snps = qsnp[top], top_p_adj = s1[top, 2], top_beta_adj = s1[top, 1],
  p_raw_causal = s0[match(snp[c(j1, j2)], qsnp), 2], n_sig_raw_bh = sum(p.adjust(s0[, 2], "BH") < 0.05), n_gw_adj = sum(s1[, 2] < 5e-8)
), "demo_gwas")
cat("QC : sujets", sum(!keepS), "variants", sum(!keepV), "; apparentés retirés", sum(!keepU), "; λ brut", gc(s0[, 2]), "ajusté", gc(s1[, 2]),
    "; top", qsnp[top], format(s1[top, 2], digits = 3), "; causaux", snp[c(j1, j2)], "\n")
