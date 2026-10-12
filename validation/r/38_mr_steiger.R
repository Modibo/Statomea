# Sens causal en randomisation mendélienne : MR bidirectionnelle et test de Steiger (Hemani et al. 2017), spécification
# de TwoSampleMR réimplémentée (paquet non distribué sur CRAN) :
#  - r d'un variant à partir de (β, ES, N) : F = (β/ES)², r² = F/(N − 2 + F), r signé (get_r_from_bsen) ;
#  - test agrégé : r_X = √Σr²_X, r_Y = √Σr²_Y ; comparaison de deux corrélations indépendantes (psych::r.test) :
#    z = (atanh r_X − atanh r_Y)/√(1/(N_X − 3) + 1/(N_Y − 3)), p bilatérale ; sens X → Y si r²_X > r²_Y ;
#  - même test variant par variant (filtrage de Steiger) ;
#  - MR dans chaque sens avec MendelianRandomization::mr_ivw (instruments de X pour X → Y, instruments de Y pour Y → X).
# DONNÉES SIMULÉES (statistiques résumées) : X cause Y (θ = 0,4 par ET) ; 25 instruments de X, 20 instruments de Y sans
# effet sur X (pas de causalité inverse) ; N_X = 60 000, N_Y = 90 000 ; deux variants de X « inversés » (effet direct
# plus fort sur Y que sur X) pour le filtrage.
source("_common.R")
suppressPackageStartupMessages({ library(MendelianRandomization); library(psych) })
set.seed(20261109)
DEMO_DIR <- normalizePath(file.path("..", "..", "demos"))
nX <- 60000; nY <- 90000
maf <- function(k) runif(k, 0.1, 0.5)
seFor <- function(p, n) 1 / sqrt(2 * p * (1 - p) * n)                       # ES d'un β par ET et par allèle
kA <- 25; pA <- maf(kA); bxA <- sample(c(-1, 1), kA, TRUE) * runif(kA, 0.03, 0.08)
bxA_obs <- bxA + rnorm(kA, 0, seFor(pA, nX))
byA <- 0.4 * bxA + rnorm(kA, 0, 0.004); byA[1:2] <- byA[1:2] + sign(bxA[1:2]) * 0.09   # 2 variants à effet direct fort sur Y
byA_obs <- byA + rnorm(kA, 0, seFor(pA, nY))
kB <- 20; pB <- maf(kB); byB <- sample(c(-1, 1), kB, TRUE) * runif(kB, 0.03, 0.07)
byB_obs <- byB + rnorm(kB, 0, seFor(pB, nY)); bxB_obs <- rnorm(kB, 0, seFor(pB, nX))  # aucun effet de Y sur X
d <- data.frame(variant = c(sprintf("x%02d", 1:kA), sprintf("y%02d", 1:kB)), instrument = c(rep("X", kA), rep("Y", kB)),
                beta_x = round(c(bxA_obs, bxB_obs), 6), se_x = round(c(seFor(pA, nX), seFor(pB, nX)), 6),
                beta_y = round(c(byA_obs, byB_obs), 6), se_y = round(c(seFor(pA, nY), seFor(pB, nY)), 6))
write.csv(d, file.path(DEMO_DIR, "mr_bidirectionnel_simule.csv"), row.names = FALSE, quote = FALSE)
rFrom <- function(b, se, n) { F <- (b / se)^2; sign(b) * sqrt(F / (n - 2 + F)) }
steiger <- function(bx, sx, by, sy) {
  rx <- rFrom(bx, sx, nX); ry <- rFrom(by, sy, nY)
  rX <- sqrt(sum(rx^2)); rY <- sqrt(sum(ry^2))
  t <- r.test(n = nX, r12 = rX, r34 = rY, n2 = nY)
  z <- (atanh(rX) - atanh(rY)) / sqrt(1 / (nX - 3) + 1 / (nY - 3))
  per <- sapply(seq_along(bx), function(j) { tt <- r.test(n = nX, r12 = abs(rx[j]), r34 = abs(ry[j]), n2 = nY); c(rx[j]^2, ry[j]^2, tt$p) })
  list(r2x = rX^2, r2y = rY^2, z = unname(z), z_psych = unname(t$z), p = unname(t$p), r2x_snp = per[1, ], r2y_snp = per[2, ], p_snp = per[3, ])
}
A <- d[d$instrument == "X", ]; B <- d[d$instrument == "Y", ]
sA <- steiger(A$beta_x, A$se_x, A$beta_y, A$se_y)
fwd <- mr_ivw(mr_input(A$beta_x, A$se_x, A$beta_y, A$se_y)); rev <- mr_ivw(mr_input(B$beta_y, B$se_y, B$beta_x, B$se_x))
keep <- sA$r2x_snp > sA$r2y_snp
fwdF <- mr_ivw(mr_input(A$beta_x[keep], A$se_x[keep], A$beta_y[keep], A$se_y[keep]))
s <- function(o) list(estimate = o@Estimate, se = o@StdError, lower = o@CILower, upper = o@CIUpper, p = o@Pvalue)
write_ref(list(nX = nX, nY = nY, steiger = sA, forward = s(fwd), reverse = s(rev), forward_filtered = s(fwdF), n_flagged = sum(!keep)), "mr_steiger")
cat("Steiger : r²X", sA$r2x, "r²Y", sA$r2y, "z", sA$z, "(psych", sA$z_psych, ") p", sA$p, "; variants inversés", sum(!keep),
    "\nX → Y", fwd@Estimate, "±", fwd@StdError, " ; Y → X", rev@Estimate, "±", rev@StdError, " ; X → Y filtré", fwdF@Estimate, "\n")
