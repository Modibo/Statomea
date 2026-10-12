# Import de génotypes (VCF, PLINK texte .ped/.map, PLINK binaire .bed/.bim/.fam) et contrôle de qualité.
# Données SIMULÉES : 300 sujets (150 cas, 150 témoins), 250 variants bialléliques + 2 sites multialléliques (VCF).
# Défauts volontaires : variants à fort taux de manquants, rares, hors Hardy-Weinberg ; sujets à fort taux de
# manquants ou à hétérozygotie anormale (contamination).
# Lecteurs de référence indépendants : vcfR (VCF), snpStats::read.plink (PLINK binaire écrit par genio).
# Règles de QC (dans cet ordre) : sujets (taux d'appel < 0,95 ; hétérozygotie à plus de 3 ET de la moyenne),
# puis, sur les sujets retenus, variants (taux d'appel < 0,95 ; MAF < 0,01 ; HWE exact chez les témoins p < 1e-6).
source("_common.R")
suppressPackageStartupMessages({ library(vcfR); library(genio); library(snpStats); library(HardyWeinberg) })
set.seed(20261026)
GDIR <- file.path(REF_DIR, "genotypes"); dir.create(GDIR, showWarnings = FALSE)
n <- 300; m <- 250
ids <- sprintf("S%03d", 1:n)
statut <- rep(c(1, 0), each = n / 2)                       # 1 = cas
sexe <- sample(1:2, n, TRUE)                              # 1 = homme, 2 = femme (PLINK)
age <- round(rnorm(n, 50, 10))
maf <- runif(m, 0.05, 0.5); maf[1:5] <- runif(5, 0.001, 0.006)          # 5 variants rares
nt <- c("A", "C", "G", "T")
ref <- sample(nt, m, TRUE); alt <- sapply(ref, function(r) sample(setdiff(nt, r), 1))
chrom <- rep(1:3, length.out = m)[order(rep(1:3, length.out = m))]; pos <- unlist(lapply(table(chrom), function(k) sort(sample(1e6:5e6, k))))
G <- sapply(1:m, function(j) rbinom(n, 2, maf[j]))       # n × m, compte d'allèles ALT
for (j in c(10, 11, 12)) {                               # excès d'homozygotes (hors HWE)
  G[, j] <- sample(c(0, 2), n, TRUE, prob = c(0.6, 0.4)); G[sample(n, 20), j] <- 1
}
for (j in c(20, 21, 22)) {                               # 3 variants associés (OR ≈ 1,8 par allèle)
  p0 <- maf[j]; p1 <- 1.8 * p0 / (1 - p0 + 1.8 * p0)
  G[statut == 1, j] <- rbinom(sum(statut == 1), 2, p1)
}
for (i in c(5, 6)) G[i, ] <- ifelse(runif(m) < 0.8, 1, G[i, ])   # sujets « contaminés » : hétérozygotie excessive
G[cbind(sample(n, 1), 1)] <- G[cbind(sample(n, 1), 1)]
miss <- matrix(runif(n * m) < 0.005, n, m)
miss[, 30:34] <- runif(n * 5) < 0.12                     # 5 variants à fort taux de manquants
miss[c(7, 8, 9, 10), ] <- runif(4 * m) < 0.10            # 4 sujets à fort taux de manquants
G[miss] <- NA
snp <- sprintf("rs%05d", 1:m)

# --- VCF (avec 2 sites multialléliques et quelques génotypes phasés) -----------------------------------
gt <- function(g) ifelse(is.na(g), "./.", ifelse(g == 0, "0/0", ifelse(g == 1, sample(c("0/1", "0|1", "1|0"), 1), "1/1")))
lines <- c("##fileformat=VCFv4.2", "##source=Statomea-simulation", '##FORMAT=<ID=GT,Number=1,Type=String,Description="Genotype">',
           paste(c("#CHROM", "POS", "ID", "REF", "ALT", "QUAL", "FILTER", "INFO", "FORMAT", ids), collapse = "\t"))
for (j in 1:m) {
  lines <- c(lines, paste(c(chrom[j], pos[j], snp[j], ref[j], alt[j], ".", "PASS", ".", "GT", sapply(G[, j], gt)), collapse = "\t"))
  if (j == 100) lines <- c(lines, paste(c(1, pos[j] + 1, "multi1", "A", "C,G", ".", "PASS", ".", "GT", rep(c("0/1", "0/2", "1/2"), length.out = n)), collapse = "\t"))
  if (j == 200) lines <- c(lines, paste(c(3, pos[j] + 1, "multi2", "T", "A,C", ".", "PASS", ".", "GT", rep("0/0", n)), collapse = "\t"))
}
writeLines(lines, file.path(GDIR, "simule.vcf"))
v <- read.vcfR(file.path(GDIR, "simule.vcf"), verbose = FALSE)
gv <- extract.gt(v)                                       # lecteur indépendant
bial <- !grepl(",", getALT(v))
dos_vcf <- apply(gv[bial, ], 2, function(x) ifelse(is.na(x) | x == "./.", NA, (substr(x, 1, 1) == "1") + (substr(x, 3, 3) == "1")))
stopifnot(isTRUE(all.equal(unname(dos_vcf) + 0, unname(t(G)) + 0)))   # relecture vcfR identique

# --- PLINK binaire (genio) puis relecture par snpStats ----------------------------------------------------
bim <- data.frame(chr = chrom, id = snp, posg = 0, pos = pos, alt = alt, ref = ref)
fam <- data.frame(fam = ids, id = ids, pat = 0, mat = 0, sex = sexe, pheno = statut + 1)
write_plink(file.path(GDIR, "simule"), t(G), bim = bim, fam = fam, verbose = FALSE)
pl <- read.plink(file.path(GDIR, "simule.bed"), file.path(GDIR, "simule.bim"), file.path(GDIR, "simule.fam"))
cs <- col.summary(pl$genotypes); rs <- row.summary(pl$genotypes)
writeLines(paste(ids, age), file.path(GDIR, "simule_age.txt"))

# --- PLINK texte (.ped/.map) ---------------------------------------------------------------------------------
al <- function(g, j) if (is.na(g)) "0 0" else c(paste(ref[j], ref[j]), paste(ref[j], alt[j]), paste(alt[j], alt[j]))[g + 1]
ped <- sapply(1:n, function(i) paste(c(ids[i], ids[i], 0, 0, sexe[i], statut[i] + 1, sapply(1:m, function(j) al(G[i, j], j))), collapse = " "))
writeLines(ped, file.path(GDIR, "simule.ped"))
writeLines(paste(chrom, snp, 0, pos), file.path(GDIR, "simule.map"))

# --- Contrôle de qualité ------------------------------------------------------------------------------------
callS <- rowMeans(!is.na(G)); het <- rowSums(G == 1, na.rm = TRUE) / rowSums(!is.na(G))
keepS1 <- callS >= 0.95
hz <- (het - mean(het[keepS1])) / sd(het[keepS1])
keepS <- keepS1 & abs(hz) <= 3
Gk <- G[keepS, ]; st <- statut[keepS]
callV <- colMeans(!is.na(Gk))
mafV <- apply(Gk, 2, function(g) { p <- sum(g, na.rm = TRUE) / (2 * sum(!is.na(g))); min(p, 1 - p) })
hweV <- apply(Gk[st == 0, ], 2, function(g) { g <- g[!is.na(g)]; x <- c(AA = sum(g == 0), AB = sum(g == 1), BB = sum(g == 2)); HWExact(x, verbose = FALSE)$pval })
keepV <- callV >= 0.95 & mafV >= 0.01 & hweV >= 1e-6

# Balayage additif ajusté (sexe, âge) sur les données nettoyées : p de Wald pour les variants retenus.
sk <- data.frame(statut = st, sexe = factor(sexe[keepS]), age = age[keepS])
scan_p <- sapply(which(keepV), function(j) { d <- cbind(sk, g = Gk[, j]); summary(glm(statut ~ g + sexe + age, binomial, d, control = glm.control(epsilon = 1e-14)))$coefficients["g", 4] })
scan_b <- sapply(which(keepV), function(j) { d <- cbind(sk, g = Gk[, j]); coef(glm(statut ~ g + sexe + age, binomial, d, control = glm.control(epsilon = 1e-14)))["g"] })

write_ref(list(
  scan = list(snps = snp[keepV], p = unname(scan_p), abs_beta = unname(abs(scan_b)), padj_bh = p.adjust(scan_p, "BH")),
  n = n, m = m, ids = ids, snp = snp, ref = ref, alt = alt, chrom = chrom, pos = pos,
  dosage_first = unname(G[1:5, 1:6]),
  snpstats = list(call_rate = unname(cs$Call.rate), maf = unname(cs$MAF), sample_call = unname(rs$Call.rate), sample_het = unname(rs$Heterozygosity)),
  qc = list(sample_call = callS, sample_het = het, het_z = hz, keep_samples = which(keepS), removed_call = which(!keepS1), removed_het = which(keepS1 & !keepS),
            call_rate = callV, maf = mafV, hwe_p = hweV, keep_snps = which(keepV),
            removed_snp_call = which(callV < 0.95), removed_snp_maf = which(mafV < 0.01), removed_snp_hwe = which(hweV < 1e-6))
), "genotypes")
cat("sujets retirés :", which(!keepS), " ; variants retirés :", which(!keepV), "\n")
