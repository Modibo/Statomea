# Alignement local de type BLAST, hors ligne :
#  - scores Smith-Waterman (pénalités affines) contre Biostrings::pairwiseAlignment(type = "local") ;
#  - scores, bit scores, E-values, ajustement de longueur et espace de recherche effectif contre BLAST+ local
#    (blastn -task blastn 2/−3, gaps 5/2 ; blastp BLOSUM62, gaps 11/1, sans statistiques de composition).
# BLAST+ attendu dans ~/development/ncbi-blast-2.17.0+/bin (ou variable BLAST_BIN).
source("_common.R")
suppressPackageStartupMessages(library(Biostrings))
data(BLOSUM62)
BLAST_BIN <- Sys.getenv("BLAST_BIN", path.expand("~/development/ncbi-blast-2.17.0+/bin"))
stopifnot(file.exists(file.path(BLAST_BIN, "blastn")))
set.seed(20261018)

mutate <- function(s, alphabet, p_sub, p_indel) {
  s <- strsplit(s, "")[[1]]; out <- character(0)
  for (ch in s) {
    u <- runif(1)
    if (u < p_indel / 2) next                                         # délétion
    if (u < p_indel) out <- c(out, sample(alphabet, 1))               # insertion
    out <- c(out, if (runif(1) < p_sub) sample(setdiff(alphabet, ch), 1) else ch)
  }
  paste(out, collapse = "")
}
rand_seq <- function(n, alphabet) paste(sample(alphabet, n, TRUE), collapse = "")
write_fasta <- function(seqs, path) writeLines(paste0(">", names(seqs), "\n", seqs), path)
tmp <- tempfile("blast"); dir.create(tmp)   # makeblastdb refuse les chemins avec espaces : copie dans un dossier temporaire

run_blast <- function(prog, query, db, extra) {
  qf <- file.path(tmp, "q.fa"); writeLines(paste0(">query\n", query), qf)
  fmt <- "6 sseqid score bitscore evalue length nident gaps qstart qend sstart send"
  out <- system2(file.path(BLAST_BIN, prog), c("-query", shQuote(qf), "-db", shQuote(db), "-outfmt", shQuote(fmt), "-max_hsps", "1", extra), stdout = TRUE)
  tab <- read.table(text = out, col.names = strsplit(sub("^6 ", "", fmt), " ")[[1]], stringsAsFactors = FALSE)
  full <- system2(file.path(BLAST_BIN, prog), c("-query", shQuote(qf), "-db", shQuote(db), "-outfmt", "0", "-max_hsps", "1", extra), stdout = TRUE)
  num_after <- function(pat) as.numeric(sub(".*:\\s*", "", grep(pat, full, value = TRUE)[1]))
  gl <- grep("^Gapped", full)                                       # Lambda K H (alignements avec gaps)
  lkh <- as.numeric(strsplit(trimws(full[gl + 2]), "\\s+")[[1]])
  list(hits = tab, length_adjustment = num_after("^Length adjustment"), eff_space = num_after("^Effective search space used"),
       lambda = lkh[1], K = lkh[2], H = lkh[3])
}

# --- ADN : bibliothèque de 8 séquences, requête dérivée de la 3e (substitutions + indels) -------------
nt <- c("A", "C", "G", "T")
lib_nt <- setNames(sapply(c(820, 760, 900, 640, 700, 880, 610, 750), rand_seq, alphabet = nt), sprintf("ref%02d", 1:8))
lib_nt["ref05"] <- mutate(lib_nt["ref03"], nt, 0.25, 0.03)          # parent éloigné de ref03
q_nt <- mutate(substr(lib_nt["ref03"], 101, 620), nt, 0.06, 0.02)
q_nt <- as.character(reverseComplement(DNAString(q_nt)))             # brin inverse : la recherche doit tester les deux brins
write_fasta(lib_nt, file.path(REF_DIR, "alignement_adn.fasta"))
system2(file.path(BLAST_BIN, "makeblastdb"), c("-in", local({x <- file.path(tmp, "nt.fa"); file.copy(file.path(REF_DIR, "alignement_adn.fasta"), x); x}), "-dbtype", "nucl", "-out", shQuote(file.path(tmp, "nt"))), stdout = FALSE)
bn <- run_blast("blastn", q_nt, file.path(tmp, "nt"), c("-task", "blastn", "-reward", "2", "-penalty", "-3", "-gapopen", "5", "-gapextend", "2",
                                                         "-dust", "no", "-soft_masking", "false", "-evalue", "10"))
nsm <- nucleotideSubstitutionMatrix(match = 2, mismatch = -3, baseOnly = TRUE)
sw_nt <- sapply(lib_nt, function(s) {
  f <- score(pairwiseAlignment(DNAString(q_nt), DNAString(s), type = "local", substitutionMatrix = nsm, gapOpening = 5, gapExtension = 2))
  r <- score(pairwiseAlignment(reverseComplement(DNAString(q_nt)), DNAString(s), type = "local", substitutionMatrix = nsm, gapOpening = 5, gapExtension = 2))
  c(plus = f, minus = r)
})

# --- Protéines : BLOSUM62, gaps 11/1 ------------------------------------------------------------------
aa <- strsplit("ARNDCQEGHILKMFPSTWYV", "")[[1]]
lib_aa <- setNames(sapply(c(310, 280, 350, 240, 400, 290), rand_seq, alphabet = aa), sprintf("prot%d", 1:6))
lib_aa["prot4"] <- mutate(lib_aa["prot2"], aa, 0.45, 0.03)
q_aa <- mutate(substr(lib_aa["prot2"], 21, 260), aa, 0.20, 0.02)
write_fasta(lib_aa, file.path(REF_DIR, "alignement_proteines.fasta"))
system2(file.path(BLAST_BIN, "makeblastdb"), c("-in", local({x <- file.path(tmp, "aa.fa"); file.copy(file.path(REF_DIR, "alignement_proteines.fasta"), x); x}), "-dbtype", "prot", "-out", shQuote(file.path(tmp, "aa"))), stdout = FALSE)
bp <- run_blast("blastp", q_aa, file.path(tmp, "aa"), c("-matrix", "BLOSUM62", "-gapopen", "11", "-gapextend", "1", "-comp_based_stats", "0",
                                                         "-seg", "no", "-evalue", "10"))
sw_aa <- sapply(lib_aa, function(s) score(pairwiseAlignment(AAString(q_aa), AAString(s), type = "local", substitutionMatrix = BLOSUM62,
                                                            gapOpening = 11, gapExtension = 1)))

write_ref(list(
  blast_version = system2(file.path(BLAST_BIN, "blastn"), "-version", stdout = TRUE)[1],
  dna = list(query = q_nt, db_letters = sum(nchar(lib_nt)), db_seqs = length(lib_nt), sw_plus = unname(sw_nt["plus", ]), sw_minus = unname(sw_nt["minus", ]),
             blast = bn$hits, length_adjustment = bn$length_adjustment, eff_space = bn$eff_space, lambda = bn$lambda, K = bn$K, H = bn$H),
  protein = list(query = q_aa, db_letters = sum(nchar(lib_aa)), db_seqs = length(lib_aa), sw = unname(sw_aa),
                 blast = bp$hits, length_adjustment = bp$length_adjustment, eff_space = bp$eff_space, lambda = bp$lambda, K = bp$K, H = bp$H),
  blosum62 = list(letters = rownames(BLOSUM62), matrix = unname(BLOSUM62))
), "alignement")
