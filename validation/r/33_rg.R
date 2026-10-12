# Corrélation génétique par régression LD score croisée (Bulik-Sullivan et al. 2015b), spécification de Statoméa
# réimplémentée ici à l'identique :
#  - z signés des deux balayages (mêmes sujets) ; variants retenus si z1² et z2² ≤ max(80 ; 0,001·N) ;
#  - h²₁, h²₂ : régression LD score univariée (32_ldsc.R) sur ces variants (intercepts a₁, a₂) ;
#  - régression pondérée de z₁z₂ sur (1, ℓ), deux itérations, départ ρ = 0 et ρg = M·mean(z₁z₂)/(N·ℓ̄) ;
#    poids 1/(max(ℓ, 1)·[(a₁ + N·h̃²₁·ℓ/M)(a₂ + N·h̃²₂·ℓ/M) + (ρ + N·ρ̃g·ℓ/M)²]), h̃² bornés à [0 ; 1], ρ̃g à [−1 ; 1] ;
#    ρg = pente·M/N ; intercept ρ = corrélation des statistiques due au recouvrement des échantillons (ici : corrélation
#    phénotypique non génétique, mêmes sujets) ;
#  - rg = ρg/√(h²₁·h²₂) (si les deux h² > 0) ; ES par jackknife sur blocs contigus (poids fixés, rg recalculé par bloc
#    à partir des trois régressions) ; p bilatéral de rg = 0 par z = rg/ES.
# DONNÉES SIMULÉES : génotypes de 32_ldsc.R. (1) Validation : deux traits quantitatifs, 800 variants causaux communs,
# corrélation des effets 0,6, h² 0,4 et 0,3, corrélation environnementale −0,2. (2) Exemple de l'application : génotypes
# « blocs de DL » (1 000 sujets), deux maladies (diabète, coronaropathie) issues de liabilités h² = 0,5, rg = 0,7.
source("_common.R")
suppressPackageStartupMessages(library(genio))
set.seed(20261103)
GDIR <- file.path(REF_DIR, "genotypes")

ldscores <- function(G, chrom, pos) {
  n <- nrow(G); Z <- scale(G); r2adj <- function(r2) r2 - (1 - r2) / (n - 2)
  sapply(seq_len(ncol(G)), function(j) {
    w <- which(chrom == chrom[j] & abs(pos - pos[j]) <= 1e6)
    sum(r2adj((as.vector(crossprod(Z[, w], Z[, j])) / (n - 1))^2))
  })
}
clip <- function(x, lo, hi) min(max(x, lo), hi)
uni <- function(c2, l, N, M) {
  h2 <- M * (mean(c2) - 1) / (N * mean(l)); a <- 1
  for (it in 1:2) {
    w <- 1 / (pmax(l, 1) * (a + N * clip(h2, 0, 1) * l / M)^2)
    f <- lm.wfit(cbind(1, l), c2, w); a <- unname(f$coefficients[1]); h2 <- unname(f$coefficients[2]) * M / N
  }
  list(a = a, h2 = h2, w = w)
}
rg_fit <- function(z1, z2, ell, N, M) {
  keep <- z1^2 <= max(80, 0.001 * N) & z2^2 <= max(80, 0.001 * N)
  z1 <- z1[keep]; z2 <- z2[keep]; l <- ell[keep]; J <- length(l); y <- z1 * z2
  u1 <- uni(z1^2, l, N, M); u2 <- uni(z2^2, l, N, M)
  rho <- 0; rhog <- M * mean(y) / (N * mean(l))
  for (it in 1:2) {
    h1 <- clip(u1$h2, 0, 1); h2 <- clip(u2$h2, 0, 1); rgc <- clip(rhog, -1, 1)
    w <- 1 / (pmax(l, 1) * ((u1$a + N * h1 * l / M) * (u2$a + N * h2 * l / M) + (rho + N * rgc * l / M)^2))
    f <- lm.wfit(cbind(1, l), y, w); rho <- unname(f$coefficients[1]); rhog <- unname(f$coefficients[2]) * M / N
  }
  rg <- if (u1$h2 > 0 && u2$h2 > 0) rhog / sqrt(u1$h2 * u2$h2) else NA
  B <- min(50, floor(J / 10)); blk <- floor((seq_len(J) - 1) * B / J) + 1
  slope <- function(yy, ww, sel) unname(lm.wfit(cbind(1, l[sel]), yy[sel], ww[sel])$coefficients) * c(1, M / N)
  jk <- t(sapply(1:B, function(b) {
    sel <- blk != b
    e1 <- slope(z1^2, u1$w, sel); e2 <- slope(z2^2, u2$w, sel); ec <- slope(y, w, sel)
    c(ec[1], ec[2], ec[2] / sqrt(e1[2] * e2[2]))
  }))
  se <- sqrt((B - 1) / B * colSums(sweep(jk, 2, colMeans(jk))^2))
  list(J = J, B = B, h2_1 = u1$h2, h2_2 = u2$h2, int_1 = u1$a, int_2 = u2$a, rho = rho, rhog = rhog, rg = rg,
       se_rho = unname(se[1]), se_rhog = unname(se[2]), se_rg = unname(se[3]), p_rg = 2 * pnorm(-abs(rg / se[3])))
}

# (1) Validation sur les génotypes de 32_ldsc.R.
P <- read_plink(file.path(GDIR, "ldsc"), verbose = FALSE)
G <- t(P$X); n <- nrow(G); m <- ncol(G); pop <- rep(1:2, each = n / 2)
ell <- ldscores(G, P$bim$chr, P$bim$pos); Z <- scale(G)
causal <- sample(m, 800)
b1 <- rnorm(800); b2 <- 0.6 * b1 + sqrt(1 - 0.6^2) * rnorm(800)
g1 <- as.vector(Z[, causal] %*% b1); g2 <- as.vector(Z[, causal] %*% b2)
g1 <- g1 - ave(g1, pop); g2 <- g2 - ave(g2, pop)
g1 <- g1 / sd(g1) * sqrt(0.4); g2 <- g2 / sd(g2) * sqrt(0.3)
e1 <- rnorm(n); e2 <- -0.2 * e1 + sqrt(1 - 0.04) * rnorm(n)
y1 <- g1 + sqrt(0.6) * e1; y2 <- g2 + sqrt(0.7) * e2
zs <- function(y) sapply(1:m, function(j) summary(lm(y ~ G[, j]))$coefficients[2, 3])
z1 <- zs(y1); z2 <- zs(y2)
V <- rg_fit(z1, z2, ell, n, m)

# (2) Exemple de l'application.
Pa <- read_plink(file.path(GDIR, "ldsc_app"), verbose = FALSE)
Ga <- t(Pa$X); na <- nrow(Ga); ma <- ncol(Ga); popa <- rep(1:2, each = na / 2); Za <- scale(Ga)
ca <- sample(ma, 600); c1 <- rnorm(600); c2 <- 0.7 * c1 + sqrt(1 - 0.49) * rnorm(600)
lia <- function(b) { g <- as.vector(Za[, ca] %*% b); g <- g - ave(g, popa); g / sd(g) * sqrt(0.5) + rnorm(na, 0, sqrt(0.5)) }
l1 <- lia(c1); l2 <- lia(c2)
diab <- l1 > quantile(l1, 0.6); coro <- l2 > quantile(l2, 0.6)
ida <- Pa$fam$id
write.csv(data.frame(id = ida, diabete = ifelse(diab, "oui", "non"), coronaropathie = ifelse(coro, "oui", "non")),
          file.path(GDIR, "ldsc_app_traits.csv"), row.names = FALSE, quote = FALSE)
wz <- function(yb) sapply(1:ma, function(j) { co <- summary(glm(yb ~ Ga[, j], binomial, control = glm.control(epsilon = 1e-14)))$coefficients[2, 1:2]; co[1] / co[2] })
za1 <- wz(as.integer(diab)); za2 <- wz(as.integer(coro))
ella <- ldscores(Ga, Pa$bim$chr, Pa$bim$pos)
A <- rg_fit(za1, za2, ella, na, ma)

write_ref(list(n = n, m = m, z1 = z1, z2 = z2, ell = ell, valid = V, app = c(A, list(z1 = unname(za1), z2 = unname(za2)))), "rg")
cat("Validation : rg", V$rg, "±", V$se_rg, " h²", V$h2_1, V$h2_2, " ρ", V$rho, "±", V$se_rho, " (cor y", cor(y1, y2), ")\n",
    "App : rg", A$rg, "±", A$se_rg, " h²", A$h2_1, A$h2_2, " ρ", A$rho, "\n")
