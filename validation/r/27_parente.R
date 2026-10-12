# Apparentement : coefficient de parenté KING-robust (Manichaikul et al. 2010) et IBS0, classement par degré,
# choix d'un ensemble maximal de sujets non apparentés.
# DONNÉES SIMULÉES : 200 fondateurs non apparentés, 20 000 variants indépendants (à 3 000, le bruit de l'estimateur, ET ≈ 0,018, crée de faux 3e degré) ; apparentés générés par transmission
# mendélienne : 4 doublons de génotypage (0,5 % d'erreurs), 3 enfants avec leurs deux parents, 3 fratries de 2 avec
# leurs parents, 2 demi-frères (père commun), 2 cousins germains (grands-parents et parents non échantillonnés).
# KING-robust : φ = (N_Aa,Aa − 2 N_AA,aa) / (2 N_Aa(i)) + 1/2 − (N_Aa(i) + N_Aa(j)) / (4 N_Aa(i)), N_Aa(i) ≤ N_Aa(j),
# comptes sur les variants non manquants chez les deux sujets ; IBS0 = N_AA,aa / N. Référence : SNPRelate
# (snpgdsIBDKING, type = "KING-robust").
# Ensemble non apparenté (seuil 2e degré, φ > 0,0884) : on retire itérativement le sujet impliqué dans le plus de
# paires au-dessus du seuil ; à égalité, celui de plus faible taux d'appel, puis le dernier dans le fichier.
source("_common.R")
suppressPackageStartupMessages({ library(genio); library(SNPRelate) })
set.seed(20261028)
GDIR <- file.path(REF_DIR, "genotypes"); dir.create(GDIR, showWarnings = FALSE)
m <- 20000
p <- runif(m, 0.05, 0.5)
founder <- function() rbinom(m, 2, p)
gamete <- function(g) ifelse(g == 1, rbinom(m, 1, 0.5), g / 2)      # allèle transmis (variants indépendants)
child <- function(a, b) gamete(a) + gamete(b)
F <- t(sapply(1:200, function(i) founder()))
ids <- sprintf("F%03d", 1:200)
add <- function(g, id) { F <<- rbind(F, g); ids <<- c(ids, id) }
for (i in 1:4) { g <- F[i, ]; e <- runif(m) < 0.005; g[e] <- sample(0:2, sum(e), TRUE); add(g, paste0(ids[i], "_dup")) }
for (k in 0:2) add(child(F[5 + 2 * k, ], F[6 + 2 * k, ]), sprintf("E%d", k + 1))                # enfants (parents F005–F010)
for (k in 0:2) for (s in 1:2) add(child(F[11 + 2 * k, ], F[12 + 2 * k, ]), sprintf("FR%d_%d", k + 1, s))   # fratries
add(child(F[17, ], F[18, ]), "DS1"); add(child(F[17, ], F[19, ]), "DS2")                                      # demi-frères
gpA <- founder(); gpB <- founder(); sibA <- child(gpA, gpB); sibB <- child(gpA, gpB)                          # non échantillonnés
add(child(sibA, founder()), "CG1"); add(child(sibB, founder()), "CG2")                                         # cousins germains
G <- unname(F); n <- nrow(G)
G[matrix(runif(n * m) < 0.005, n, m)] <- NA
write_plink(file.path(GDIR, "parente"), t(G), bim = data.frame(chr = 1, id = sprintf("v%05d", 1:m), posg = 0, pos = 1:m * 1000, alt = "A", ref = "G"),
            fam = data.frame(fam = ids, id = ids, pat = 0, mat = 0, sex = 0, pheno = -9), verbose = FALSE)

# KING-robust par la formule.
nm <- !is.na(G); het <- (G == 1) & nm; h0 <- (G == 0) & nm; h2 <- (G == 2) & nm
het[is.na(het)] <- FALSE; h0[is.na(h0)] <- FALSE; h2[is.na(h2)] <- FALSE
H <- het * 1; N0 <- h0 * 1; N2 <- h2 * 1; NM <- nm * 1
Nhh <- H %*% t(H); Nopp <- N0 %*% t(N2) + N2 %*% t(N0); Nboth <- NM %*% t(NM)
Hi <- H %*% t(NM)               # Hi[i, j] = hétérozygotes de i sur les variants non manquants chez j
Hj <- t(Hi)
Hmin <- pmin(Hi, Hj); Hmax <- pmax(Hi, Hj)
phi <- (Nhh - 2 * Nopp) / (2 * Hmin) + 0.5 - (Hmin + Hmax) / (4 * Hmin)
ibs0 <- Nopp / Nboth
diag(phi) <- NA

# Référence indépendante : SNPRelate.
gfile <- tempfile(fileext = ".gds")
Gs <- G; Gs[is.na(Gs)] <- 3
snpgdsCreateGeno(gfile, genmat = Gs, sample.id = ids, snp.id = sprintf("v%05d", 1:m), snpfirstdim = FALSE)
gds <- snpgdsOpen(gfile)
k <- snpgdsIBDKING(gds, type = "KING-robust", verbose = FALSE)
snpgdsClose(gds)
dif <- max(abs(k$kinship[upper.tri(phi)] - phi[upper.tri(phi)]))
dif0 <- max(abs(k$IBS0[upper.tri(phi)] - ibs0[upper.tri(phi)]))

# Paires apparentées et degrés (seuils de KING).
deg <- function(x) ifelse(x > 0.354, 0, ifelse(x > 0.177, 1, ifelse(x > 0.0884, 2, ifelse(x > 0.0442, 3, NA))))
ut <- which(upper.tri(phi) & phi > 0.0442, arr.ind = TRUE)
ut <- ut[order(ut[, 1], ut[, 2]), , drop = FALSE]
pairs <- data.frame(i = ut[, 1], j = ut[, 2], phi = phi[ut], ibs0 = ibs0[ut], degree = deg(phi[ut]))

# Ensemble non apparenté.
call <- rowMeans(nm); keep <- rep(TRUE, n)
repeat {
  rel <- which(upper.tri(phi) & phi > 0.0884 & outer(keep, keep, "&"), arr.ind = TRUE)
  if (nrow(rel) == 0) break
  cnt <- tabulate(c(rel[, 1], rel[, 2]), n)
  cand <- which(cnt == max(cnt))
  cand <- cand[call[cand] == min(call[cand])]
  keep[max(cand)] <- FALSE
}

write_ref(list(
  ids = ids, phi_upper = phi[upper.tri(phi)], ibs0_upper = ibs0[upper.tri(phi)],
  snprelate_max_diff_kinship = dif, snprelate_max_diff_ibs0 = dif0,
  pairs = list(i = pairs$i, j = pairs$j, phi = pairs$phi, ibs0 = pairs$ibs0, degree = pairs$degree),
  removed = which(!keep)
), "parente")
cat("écart max à SNPRelate : φ", dif, " IBS0", dif0, "\n")
print(table(pairs$degree, useNA = "ifany")); cat("retirés :", ids[!keep], "\n")
