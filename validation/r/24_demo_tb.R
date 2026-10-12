# Démonstration 4 : tuberculose résistante à la rifampicine — que vaut le génotypage moléculaire ?
# DONNÉES SIMULÉES (aucun isolat ni patient réel). 220 isolats de 3 centres : antibiogramme phénotypique (MGIT,
# référence), mutations rpoB détectées par le test moléculaire, lignée ; série de dilutions du test (LOD) ;
# bibliothèque FASTA de séquences fictives pour l'identification d'un isolat.
source("_common.R")
suppressPackageStartupMessages({ library(MASS); library(Biostrings) })
set.seed(20261025)
DEMO_DIR <- normalizePath(file.path("..", "..", "demos"))
n <- 220
lignee <- sample(c("L1", "L2", "L3", "L4", "L5", "L6"), n, TRUE, prob = c(.08, .22, .10, .40, .12, .08))
centre <- sample(c("C1", "C2", "C3"), n, TRUE, prob = c(.45, .35, .20))
pR <- ifelse(lignee == "L2", 0.40, 0.28)                      # résistance un peu plus fréquente en L2
R <- rbinom(n, 1, pR)
mut <- function(pr, ps) ifelse(R == 1, rbinom(n, 1, pr), rbinom(n, 1, ps))
d <- data.frame(isolat = sprintf("TB%03d", 1:n), centre = centre, rifampicine = ifelse(R == 1, "R", "S"),
                rpoB_S450L = mut(0.62, 0.005), rpoB_H445Y = mut(0.14, 0.01), rpoB_D435V = mut(0.10, 0.01),
                rpoB_L430P = mut(0.06, 0.05),                  # mutation « limite » : souvent sensible en MGIT
                lignee = lignee)
d$rpoB_S450L[c(17, 88, 141)] <- NA                            # échecs d'amplification (non imputés)
write.csv(d, file.path(DEMO_DIR, "tb_rifampicine_simule.csv"), row.names = FALSE, na = "")

wil <- function(x, k) c(x / k, prop.test(x, k, correct = FALSE)$conf.int)
conc <- function(m, y) {
  ok <- !is.na(m) & !is.na(y); m <- m[ok]; y <- y[ok]
  tp <- sum(m == 1 & y == 1); fp <- sum(m == 1 & y == 0); fn <- sum(m == 0 & y == 1); tn <- sum(m == 0 & y == 0); N <- tp + fp + fn + tn
  po <- (tp + tn) / N; pe <- ((tp + fp) * (tp + fn) + (fn + tn) * (fp + tn)) / N^2
  list(counts = c(tp, fp, fn, tn), se = wil(tp, tp + fn), sp = wil(tn, tn + fp), kappa = (po - pe) / (1 - pe))
}
y <- as.integer(d$rifampicine == "R")
any_of <- function(cols) {
  m <- as.matrix(d[, cols]); pos <- rowSums(m == 1, na.rm = TRUE) > 0; miss <- rowSums(is.na(m)) > 0
  ifelse(pos, 1L, ifelse(miss, NA, 0L))
}
tab <- table(d$lignee); Nn <- sum(tab); pi <- tab / Nn
D <- 1 - sum(tab * (tab - 1)) / (Nn * (Nn - 1)); v <- 4 / Nn * (sum(pi^3) - sum(pi^2)^2)
L2 <- d$lignee == "L2"
ft <- fisher.test(matrix(c(sum(L2 & y == 1), sum(L2 & y == 0), sum(!L2 & y == 1), sum(!L2 & y == 0)), 2, byrow = TRUE))

ct <- chisq.test(table(d$centre, d$rifampicine), correct = FALSE)

# Limite de détection du test moléculaire : 20 réplicats par niveau (UFC/mL).
conc_lod <- c(5, 10, 20, 40, 80, 160); det <- c(4, 9, 14, 18, 20, 20); tot <- rep(20, 6)
g <- glm(cbind(det, tot - det) ~ log10(conc_lod), family = binomial(link = "probit"), control = glm.control(epsilon = 1e-14))
lod <- dose.p(g, p = 0.95)

# Identification : 6 séquences de référence FICTIVES (≈ fragment de 600 pb) et un isolat à identifier.
nt <- c("A", "C", "G", "T")
mutate <- function(s, p) { s <- strsplit(s, "")[[1]]; k <- runif(length(s)) < p; s[k] <- sapply(s[k], function(ch) sample(setdiff(nt, ch), 1)); paste(s, collapse = "") }
anc <- paste(sample(nt, 600, TRUE), collapse = "")
refs <- c(
  "MTBC_sim"   = mutate(anc, 0.00),
  "MBOV_sim"   = mutate(anc, 0.004),
  "MAV_sim"    = mutate(anc, 0.07),
  "MINT_sim"   = mutate(anc, 0.075),
  "MKAN_sim"   = mutate(anc, 0.09),
  "MABS_sim"   = mutate(anc, 0.12))
desc <- c("complexe tuberculosis (séquence fictive)", "variante proche, même complexe (fictive)", "mycobactérie non tuberculeuse A (fictive)",
          "mycobactérie non tuberculeuse B (fictive)", "mycobactérie non tuberculeuse C (fictive)", "mycobactérie à croissance rapide (fictive)")
writeLines(paste0(">", names(refs), " ", desc, "\n", refs), file.path(DEMO_DIR, "tb_references_simule.fasta"))
isolat <- substr(mutate(refs["MTBC_sim"], 0.002), 31, 560)
writeLines(paste0(">isolat_TB-X séquence de l'isolat à identifier (fictive)\n", isolat), file.path(DEMO_DIR, "tb_isolat_simule.fasta"))
nsm <- nucleotideSubstitutionMatrix(match = 2, mismatch = -3, baseOnly = TRUE)
sw <- sapply(refs, function(s) score(pairwiseAlignment(DNAString(isolat), DNAString(s), type = "local", substitutionMatrix = nsm, gapOpening = 5, gapExtension = 2)))

write_ref(list(
  n = n, n_R = sum(y),
  S450L = conc(d$rpoB_S450L, y),
  any3 = conc(any_of(c("rpoB_S450L", "rpoB_H445Y", "rpoB_D435V")), y),
  any4 = conc(any_of(c("rpoB_S450L", "rpoB_H445Y", "rpoB_D435V", "rpoB_L430P")), y),
  hg = D, hg_ci = D + c(-2, 2) * sqrt(v),
  centre_chi2 = unname(ct$statistic), centre_p = ct$p.value, centre_table = unname(unclass(table(factor(d$centre), factor(d$rifampicine, levels = c("R", "S"))))[, , drop = FALSE] + 0L),
  L2_fisher_p = ft$p.value, L2_counts = c(sum(L2 & y == 1), sum(L2 & y == 0), sum(!L2 & y == 1), sum(!L2 & y == 0)),
  lod = list(conc = conc_lod, det = det, tot = tot, lod95 = 10^as.vector(lod)),
  sw = as.list(sw)
), "demo_tb")
cat("R :", sum(y), "/", n, "; centres p =", ct$p.value, "; Fisher L2 p =", ft$p.value, "; Se S450L =", conc(d$rpoB_S450L, y)$se[1],
    "; Sp any4 =", conc(any_of(c("rpoB_S450L", "rpoB_H445Y", "rpoB_D435V", "rpoB_L430P")), y)$sp[1], "; LOD95 =", 10^as.vector(lod), "\n")
print(sw)
