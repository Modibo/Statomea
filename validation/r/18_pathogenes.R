# Génomique des pathogènes : concordance mutations ↔ phénotype de résistance (Se, Sp, VPP, VPN avec IC de Wilson
# comme prop.test(correct = FALSE) ; kappa de Cohen et ES asymptotique de Fleiss, Cohen et Everitt 1969),
# diversité des types (indice de Hunter-Gaston, IC de Grundmann 2001 ; Shannon). Isolats simulés.
source("_common.R")
set.seed(20261014)
n <- 160
R <- rbinom(n, 1, 0.35)
mut <- function(pR, pS) ifelse(R == 1, rbinom(n, 1, pR), rbinom(n, 1, pS))
d <- data.frame(isolat = sprintf("MTB%03d", 1:n), rifampicine = ifelse(R == 1, "R", "S"),
                rpoB_S450L = mut(0.62, 0.01), rpoB_H445Y = mut(0.15, 0.02), rpoB_D435V = mut(0.10, 0.03),
                lignee = sample(c("L1", "L2", "L3", "L4", "L5", "L6"), n, TRUE, prob = c(.1, .25, .1, .35, .12, .08)))
d$rpoB_S450L[c(3, 50)] <- NA
write.csv(d, file.path(REF_DIR, "pathogenes_simule.csv"), row.names = FALSE, na = "")
wil <- function(x, k) if (k == 0) c(NA, NA, NA) else c(x / k, prop.test(x, k, correct = FALSE)$conf.int)
conc <- function(m, y) {
  ok <- !is.na(m) & !is.na(y); m <- m[ok]; y <- y[ok]
  tp <- sum(m == 1 & y == 1); fp <- sum(m == 1 & y == 0); fn <- sum(m == 0 & y == 1); tn <- sum(m == 0 & y == 0); N <- tp + fp + fn + tn
  po <- (tp + tn) / N; pe <- ((tp + fp) * (tp + fn) + (fn + tn) * (fp + tn)) / N^2; k <- (po - pe) / (1 - pe)
  # ES asymptotique sous H1 (Fleiss, Cohen, Everitt 1969).
  p <- matrix(c(tp, fn, fp, tn), 2) / N; r <- rowSums(p); cc <- colSums(p)
  a <- sum(diag(p) * (1 - (r + cc) * (1 - k))^2)
  b <- (1 - k)^2 * (p[1, 2] * (cc[1] + r[2])^2 + p[2, 1] * (cc[2] + r[1])^2)
  cterm <- (k - pe * (1 - k))^2
  se <- sqrt((a + b - cterm) / N) / (1 - pe)
  list(counts = c(tp, fp, fn, tn), se = wil(tp, tp + fn), sp = wil(tn, tn + fp), ppv = wil(tp, tp + fp), npv = wil(tn, tn + fn),
       kappa = k, kappa_se = se, kappa_ci = k + c(-1, 1) * qnorm(.975) * se)
}
y <- as.integer(d$rifampicine == "R")
anyM <- ifelse(is.na(d$rpoB_S450L) & d$rpoB_H445Y == 0 & d$rpoB_D435V == 0, NA,
               as.integer((d$rpoB_S450L %in% 1) | d$rpoB_H445Y == 1 | d$rpoB_D435V == 1))
tab <- table(d$lignee); Nn <- sum(tab); pi <- tab / Nn
D <- 1 - sum(tab * (tab - 1)) / (Nn * (Nn - 1))
v <- 4 / Nn * (sum(pi^3) - sum(pi^2)^2)
write_ref(list(
  S450L = conc(d$rpoB_S450L, y), H445Y = conc(d$rpoB_H445Y, y), D435V = conc(d$rpoB_D435V, y), any = conc(anyM, y),
  hg = D, hg_ci = D + c(-2, 2) * sqrt(v), shannon = -sum(pi * log(pi)), types = length(tab), counts = as.vector(tab)
), "pathogenes")
