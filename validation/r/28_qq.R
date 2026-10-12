# QQ plot des p d'un balayage de variants : quantiles attendus ppoints(n) (a = 3/8 si n ≤ 10, sinon 1/2) et bande de
# confiance ponctuelle à 95 % : i-ème plus petite p ~ Beta(i, n − i + 1). Données : p bruts du balayage de 26_acp.R.
source("_common.R")
suppressPackageStartupMessages(library(jsonlite))
acp <- fromJSON(file.path(REF_DIR, "acp.json"))
p <- sort(acp$p_unadj); n <- length(p); i <- seq_len(n)
small <- c(0.03, 0.2, 0.5, 0.7, 0.9, 0.01, 0.6)
write_ref(list(
  n = n, expected = ppoints(n), lower = qbeta(0.025, i, n - i + 1), upper = qbeta(0.975, i, n - i + 1),
  small_p = small, small_expected = ppoints(length(small))
), "qq")
cat("écrit\n")
