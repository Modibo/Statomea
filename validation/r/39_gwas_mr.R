# Randomisation mendélienne à partir de deux fichiers GWAS (statistiques résumées), spécification de Statoméa
# réimplémentée ici (règles de TwoSampleMR, paquet non distribué sur CRAN) :
#  - lecture : colonnes reconnues par alias (GWAS-SSF : variant_id, chromosome, base_pair_location, effect_allele,
#    other_allele, beta, standard_error, p_value, effect_allele_frequency ; TwoSampleMR / PLINK : SNP, CHR, BP, A1, A2,
#    BETA ou OR, SE, P, EAF) ; OR → β = log(OR) ; allèles en majuscules ;
#  - instruments : p_exposition < 5e-8, puis clumping par distance (meilleur p d'abord ; un variant écarte ceux du même
#    chromosome à ≤ 10 000 kb) ;
#  - harmonisation (TwoSampleMR, action 2) : allèles identiques → aligné ; inversés → β_issue = −β, EAF = 1 − EAF ;
#    sinon complément de brin de l'issue puis mêmes tests ; sinon rejet (incompatible) ;
#    palindromiques (A/T, G/C) : rejet si EAF exposition ∈ ]0,42 ; 0,58[ ou EAF manquante ; sinon β_issue retourné si
#    (EAF_exposition < 0,5) ≠ (EAF_issue < 0,5) ;
#  - randomisation mendélienne : MendelianRandomization::mr_ivw / mr_egger / mr_median sur les variants harmonisés.
# DONNÉES SIMULÉES : 12 000 variants sur 4 chromosomes ; 40 loci causaux pour l'exposition (effet causal θ = 0,3 sur
# l'issue) ; le fichier de l'issue est au format « TwoSampleMR » (OR au lieu de β) et contient volontairement des allèles
# inversés, des brins complémentaires, des palindromiques, des allèles incompatibles et des variants absents.
# Statuts écrits en codes ASCII (le R x86 de validation corrompt l'UTF-8 dans le JSON).
source("_common.R")
suppressPackageStartupMessages(library(MendelianRandomization))
set.seed(20261110)
DEMO_DIR <- normalizePath(file.path("..", "..", "demos"))
m <- 12000; nX <- 80000; nY <- 120000
chr <- rep(1:4, each = m / 4); pos <- unlist(lapply(1:4, function(c) sort(sample(1e6:2e8, m / 4))))
nt <- c("A", "C", "G", "T"); comp <- c(A = "T", T = "A", C = "G", G = "C")
ea <- sample(nt, m, TRUE); oa <- sapply(ea, function(a) sample(setdiff(nt, c(a, comp[a])), 1))   # non palindromiques
eaf <- runif(m, 0.05, 0.95)
seX <- 1 / sqrt(2 * eaf * (1 - eaf) * nX); seY <- 1 / sqrt(2 * eaf * (1 - eaf) * nY)
causal <- sample(m, 40); gX <- numeric(m); gX[causal] <- sample(c(-1, 1), 40, TRUE) * runif(40, 0.03, 0.07)
# Voisins en DL des loci causaux (même chromosome, < 200 kb) : signal partagé, à écarter par le clumping.
nb <- sapply(causal, function(j) { k <- which(chr == chr[j] & abs(pos - pos[j]) < 200000 & seq_len(m) != j); if (length(k)) k[1] else NA })
nb <- nb[!is.na(nb)]; gX[nb] <- 0.8 * gX[causal[seq_along(nb)]]
bX <- gX + rnorm(m, 0, seX); bY <- 0.3 * gX + rnorm(m, 0, seY)
pX <- 2 * pnorm(-abs(bX / seX)); pY <- 2 * pnorm(-abs(bY / seY))
# Instruments attendus (ne dépendent que de l'exposition) : on y place volontairement chaque cas d'harmonisation.
clump <- function(p, chr, pos, thr = 5e-8, kb = 10000) {
  s <- which(p < thr); s <- s[order(p[s], s)]; keep <- integer(0)
  for (i in s) if (!any(chr[keep] == chr[i] & abs(pos[keep] - pos[i]) <= kb * 1000)) keep <- c(keep, i)
  keep
}
I <- clump(signif(pX, 6), chr, pos)
palI <- I[1:4]; misI <- I[5:6]; goneI <- I[7]
pal <- union(sample(setdiff(seq_len(m), I), 400), palI); oa[pal] <- comp[ea[pal]]                 # palindromiques
eaf[palI[1:2]] <- c(0.45, 0.55)                                                                       # ambigus (écartés)
eaf[palI[3:4]] <- c(0.2, 0.75)
rsid <- sprintf("rs%07d", 1000000 + 1:m)
expo <- data.frame(variant_id = rsid, chromosome = chr, base_pair_location = pos, effect_allele = ea, other_allele = oa,
                   beta = signif(bX, 6), standard_error = signif(seX, 6), p_value = signif(pX, 6), effect_allele_frequency = round(eaf, 4))
# Fichier de l'issue : allèles inversés (1/3), brin complémentaire (1/4), OR, minuscules, variants retirés et incompatibles.
yA1 <- ea; yA2 <- oa; yB <- bY; yF <- eaf
sw <- union(setdiff(sample(m, m / 3), c(misI, palI[3])), palI[4]); yA1[sw] <- oa[sw]; yA2[sw] <- ea[sw]; yB[sw] <- -bY[sw]; yF[sw] <- 1 - eaf[sw]
st <- setdiff(sample(m, m / 4), c(pal, misI)); yA1[st] <- comp[yA1[st]]; yA2[st] <- comp[yA2[st]]
yA1[misI] <- ea[misI]; yA2[misI] <- comp[oa[misI]]                                                   # ni identique, ni inversé, ni complémentaire
gone <- union(sample(setdiff(seq_len(m), c(causal, I)), 499), goneI)
outc <- data.frame(SNP = rsid, CHR = chr, BP = pos, A1 = tolower(yA1), A2 = tolower(yA2), OR = signif(exp(yB), 7), SE = signif(seY, 6),
                   P = signif(pY, 6), EAF = round(yF, 4))[-gone, ]
write.table(expo, file.path(DEMO_DIR, "gwas_exposition_simule.tsv"), sep = "\t", row.names = FALSE, quote = FALSE)
write.table(outc, file.path(DEMO_DIR, "gwas_issue_simule.tsv"), sep = "\t", row.names = FALSE, quote = FALSE)

# --- Spécification ---
E <- read.delim(file.path(DEMO_DIR, "gwas_exposition_simule.tsv")); O <- read.delim(file.path(DEMO_DIR, "gwas_issue_simule.tsv"))
O$A1 <- toupper(O$A1); O$A2 <- toupper(O$A2); O$beta <- log(O$OR)
inst <- E[E$p_value < 5e-8, ]; inst <- inst[order(inst$p_value, seq_len(nrow(inst))), ]
keep <- logical(nrow(inst))
for (i in seq_len(nrow(inst))) {
  k <- which(keep & inst$chromosome == inst$chromosome[i] & abs(inst$base_pair_location - inst$base_pair_location[i]) <= 10000 * 1000)
  if (!length(k)) keep[i] <- TRUE
}
inst <- inst[keep, ]
palin <- function(a, b) paste0(a, b) %in% c("AT", "TA", "CG", "GC")
res <- lapply(seq_len(nrow(inst)), function(i) {
  e <- inst[i, ]; o <- O[O$SNP == e$variant_id, ]
  if (!nrow(o)) return(data.frame(id = e$variant_id, status = "absent", bx = NA, sx = NA, by = NA, sy = NA))
  A1 <- e$effect_allele; A2 <- e$other_allele; B1 <- o$A1; B2 <- o$A2; by <- o$beta; fy <- o$EAF
  if (palin(A1, A2)) {
    if (!setequal(c(A1, A2), c(B1, B2))) return(data.frame(id = e$variant_id, status = "incompatible", bx = NA, sx = NA, by = NA, sy = NA))
    if (is.na(e$effect_allele_frequency) || is.na(fy) || (e$effect_allele_frequency > 0.42 && e$effect_allele_frequency < 0.58)) return(data.frame(id = e$variant_id, status = "pal_ambiguous", bx = NA, sx = NA, by = NA, sy = NA))
    st <- if ((e$effect_allele_frequency < 0.5) != (fy < 0.5)) { by <- -by; "pal_flipped" } else "pal_aligned"
    return(data.frame(id = e$variant_id, status = st, bx = e$beta, sx = e$standard_error, by = by, sy = o$SE))
  }
  for (strand in 0:1) {
    b1 <- if (strand) comp[B1] else B1; b2 <- if (strand) comp[B2] else B2
    if (A1 == b1 && A2 == b2) return(data.frame(id = e$variant_id, status = if (strand) "strand" else "aligned", bx = e$beta, sx = e$standard_error, by = by, sy = o$SE))
    if (A1 == b2 && A2 == b1) return(data.frame(id = e$variant_id, status = if (strand) "strand_flipped" else "flipped", bx = e$beta, sx = e$standard_error, by = -by, sy = o$SE))
  }
  data.frame(id = e$variant_id, status = "incompatible", bx = NA, sx = NA, by = NA, sy = NA)
})
H <- do.call(rbind, res); U <- H[!is.na(H$bx), ]
inp <- mr_input(bx = U$bx, bxse = U$sx, by = U$by, byse = U$sy)
iv <- mr_ivw(inp); eg <- mr_egger(inp); wm <- mr_median(inp, weighting = "weighted", iterations = 100)
write_ref(list(n_significant = sum(E$p_value < 5e-8), instruments = inst$variant_id, status = setNames(as.list(H$status), H$id),
               used = U$id, by = unname(U$by), ivw = list(estimate = iv@Estimate, se = iv@StdError, p = iv@Pvalue),
               egger = list(estimate = eg@Estimate, se = eg@StdError.Est, intercept = eg@Intercept), median = wm@Estimate), "gwas_mr")
cat("significatifs", sum(E$p_value < 5e-8), "; instruments après clumping", nrow(inst), "\n"); print(table(H$status))
cat("IVW", iv@Estimate, "±", iv@StdError, " (θ simulé 0,3) ; Egger", eg@Estimate, "\n")
