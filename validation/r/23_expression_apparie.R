# Expression différentielle RNA-seq, plans appariés (guide de limma, § 9.4 et 9.7) :
#  (1) avant/après chez 6 patients : sujet en effet fixe, ~ sujet + temps ;
#  (2) 4 patients et 4 témoins prélevés chacun sur 2 sites : le sujet est emboîté dans le statut, l'effet fixe
#      absorberait le statut ; corrélation intra-sujet par duplicateCorrelation (statmod::mixedModel2Fit) et
#      moindres carrés généralisés par bloc. Chaîne recommandée : voom → duplicateCorrelation → voom(block,
#      correlation) → duplicateCorrelation → lmFit(block, correlation) → eBayes.
source("_common.R")
suppressPackageStartupMessages({ library(edgeR); library(limma); library(statmod) })
set.seed(20261023)

simule <- function(G, mu_fun, n, disp) {
  mu <- sapply(1:n, mu_fun)
  matrix(rnbinom(G * n, mu = mu, size = 1 / disp), G, n)
}
prepare <- function(cnt, k) {
  y <- DGEList(cnt)
  keep <- rowSums(cpm(y) >= 1) >= k
  calcNormFactors(y[keep, , keep.lib.sizes = FALSE])
}
tt <- function(f, coef) topTable(f, coef = coef, number = Inf, sort.by = "none")

# --- (1) Avant / après, 6 patients ------------------------------------------------------------------
G <- 1200
patient <- factor(rep(sprintf("P%d", 1:6), each = 2)); temps <- factor(rep(c("avant", "apres"), 6), levels = c("avant", "apres"))
base <- rgamma(G, 0.6, 0.006) + 1
effet_sujet <- matrix(rnorm(G * 6, 0, 0.6), G, 6)             # forte variabilité entre patients
lfc <- rep(0, G); de <- sample(G, 80); lfc[de] <- sample(c(-1, 1), 80, TRUE) * runif(80, 0.6, 2)
disp <- exp(rnorm(G, log(0.03), 0.7)); libf <- runif(12, 0.7, 1.3)
cnt1 <- simule(G, function(j) base * libf[j] * 2^(effet_sujet[, as.integer(patient[j])] + lfc * (temps[j] == "apres")), 12, disp)
rownames(cnt1) <- sprintf("G%04d", 1:G); colnames(cnt1) <- paste0(patient, "_", temps)
write.csv(data.frame(gene = rownames(cnt1), cnt1, check.names = FALSE), file.path(REF_DIR, "rnaseq_apparie_simule.csv"), row.names = FALSE)
y1 <- prepare(cnt1, 6)
d1 <- model.matrix(~ patient + temps)
v1 <- voom(y1, d1)
f1 <- eBayes(lmFit(v1, d1))
t1 <- tt(f1, "tempsapres")
# Même données analysées SANS appariement (pour documenter la perte de puissance).
f1n <- eBayes(lmFit(voom(y1, model.matrix(~ temps)), model.matrix(~ temps)))

# --- (2) Patients / témoins, 2 sites par sujet --------------------------------------------------------
sujet <- factor(rep(sprintf("S%d", 1:8), each = 2))
statut <- factor(rep(c("temoin", "patient"), each = 8), levels = c("temoin", "patient"))
site <- factor(rep(c("peau", "sang"), 8))
eff_s <- matrix(rnorm(G * 8, 0, 0.5), G, 8)
eff_site <- ifelse(runif(G) < 0.3, rnorm(G, 0, 1), 0)
lfc2 <- rep(0, G); de2 <- sample(G, 80); lfc2[de2] <- sample(c(-1, 1), 80, TRUE) * runif(80, 0.8, 2.5)
libf2 <- runif(16, 0.7, 1.3)
cnt2 <- simule(G, function(j) base * libf2[j] * 2^(eff_s[, as.integer(sujet[j])] + eff_site * (site[j] == "sang") + lfc2 * (statut[j] == "patient")), 16, disp)
rownames(cnt2) <- sprintf("G%04d", 1:G); colnames(cnt2) <- paste0(sujet, "_", site)
write.csv(data.frame(gene = rownames(cnt2), cnt2, check.names = FALSE), file.path(REF_DIR, "rnaseq_bloc_simule.csv"), row.names = FALSE)
y2 <- prepare(cnt2, 8)
d2 <- model.matrix(~ statut + site)
va <- voom(y2, d2)
ca <- duplicateCorrelation(va, d2, block = sujet)
vb <- voom(y2, d2, block = sujet, correlation = ca$consensus.correlation)
cb <- duplicateCorrelation(vb, d2, block = sujet)
f2 <- eBayes(lmFit(vb, d2, block = sujet, correlation = cb$consensus.correlation))
t2 <- tt(f2, "statutpatient"); t2s <- tt(f2, "sitesang")

write_ref(list(
  paired = list(kept = rownames(y1), patient = as.character(patient), temps = as.character(temps),
                df_prior = f1$df.prior, s2_prior = f1$s2.prior,
                logFC = t1$logFC, t = t1$t, p = t1$P.Value, adj = t1$adj.P.Val, n_sig = sum(t1$adj.P.Val < 0.05),
                n_sig_unpaired = sum(p.adjust(f1n$p.value[, 2], "BH") < 0.05)),
  block = list(kept = rownames(y2), sujet = as.character(sujet), statut = as.character(statut), site = as.character(site),
               rho1 = ca$consensus.correlation, rho2 = cb$consensus.correlation,
               atanh1_head = head(ca$atanh.correlations, 20), atanh2_head = head(cb$atanh.correlations, 20),
               w_head = unname(vb$weights[1:3, ]),
               df_prior = f2$df.prior, s2_prior = f2$s2.prior,
               status = list(logFC = t2$logFC, t = t2$t, p = t2$P.Value, adj = t2$adj.P.Val),
               site = list(logFC = t2s$logFC, t = t2s$t, p = t2s$P.Value),
               n_sig = sum(t2$adj.P.Val < 0.05))
), "expression_apparie")
cat("rho :", ca$consensus.correlation, cb$consensus.correlation, " ; appariés :", sum(t1$adj.P.Val < 0.05),
    "(non appariés :", sum(p.adjust(f1n$p.value[, 2], "BH") < 0.05), ") ; bloc :", sum(t2$adj.P.Val < 0.05), "\n")
