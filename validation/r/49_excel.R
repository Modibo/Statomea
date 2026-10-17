# Import Excel (.xlsx) et dictionnaire de variables : fichier de référence écrit par openxlsx 4.2, relu par readxl 1.4.
#  - feuille « patients » : identifiant (texte), âge (décimal), sexe, date d'inclusion (date Excel), poids (vides et code
#    manquant 999), fumeur (booléen), groupe (codes 1/2), score ordinal (faible < moyen < fort), commentaire (texte libre,
#    caractères spéciaux & < >) ;
#  - feuille « dictionnaire » : variable, type, unité, min, max, référence, libellé, codes manquants, modalités ;
#  - référence : valeurs lues par readxl (dates au format AAAA-MM-JJ, nombres en notation décimale, booléens TRUE/FALSE),
#    et effet attendu du dictionnaire (codes manquants retirés, codes de groupe remplacés par leurs libellés).
# Locale UTF-8 indispensable : sans elle, le R x86 de validation corrompt les accents dans le fichier écrit.
invisible(Sys.setlocale("LC_CTYPE", "en_US.UTF-8"))
source("_common.R")
suppressPackageStartupMessages({ library(openxlsx); library(readxl) })
DEMO_DIR <- normalizePath(file.path("..", "..", "demos"))
set.seed(20261120)
n <- 40
p <- data.frame(
  id = sprintf("P%03d", 1:n),
  age = round(rnorm(n, 52, 12), 1),
  sexe = sample(c("F", "M"), n, TRUE),
  date_inclusion = as.Date("2025-01-06") + sample(0:400, n, TRUE),
  poids = round(rnorm(n, 72, 13), 1),
  fumeur = sample(c(TRUE, FALSE), n, TRUE),
  groupe = sample(1:2, n, TRUE),
  score = sample(c("faible", "moyen", "fort"), n, TRUE),
  commentaire = sample(c("RAS", "perdu de vue & relancé", "HbA1c < 7 %", "dose > 2 mg", ""), n, TRUE),
  stringsAsFactors = FALSE)
p$poids[c(3, 17)] <- NA; p$poids[c(8, 25, 31)] <- 999; p$age[12] <- NA; p$commentaire[p$commentaire == ""] <- NA
dico <- data.frame(
  variable = c("id", "age", "sexe", "date_inclusion", "poids", "fumeur", "groupe", "score", "commentaire"),
  type = c("identifiant", "quantitative", "binaire", "date", "quantitative", "binaire", "qualitative", "ordinale", "texte"),
  unite = c("", "ans", "", "", "kg", "", "", "", ""),
  min = c(NA, 18, NA, NA, 30, NA, NA, NA, NA), max = c(NA, 100, NA, NA, 200, NA, NA, NA, NA),
  reference = c("", "", "F", "", "", "FALSE", "témoin", "faible", ""),
  libelle = c("Identifiant", "Âge à l'inclusion", "Sexe", "Date d'inclusion", "Poids", "Fumeur actuel", "Groupe de traitement", "Score de gravité", "Commentaire"),
  manquants = c("", "", "", "", "999", "", "", "", ""),
  modalites = c("", "", "", "", "", "", "1=témoin;2=traité", "faible;moyen;fort", ""),
  stringsAsFactors = FALSE)
wb <- createWorkbook(); addWorksheet(wb, "patients"); addWorksheet(wb, "dictionnaire")
writeData(wb, "patients", p); writeData(wb, "dictionnaire", dico)
f <- file.path(DEMO_DIR, "exemple_excel.xlsx"); saveWorkbook(wb, f, overwrite = TRUE)

r <- read_excel(f, sheet = "patients")
fmtcol <- function(x) if (inherits(x, "POSIXct") || inherits(x, "Date")) format(as.Date(x), "%Y-%m-%d") else if (is.logical(x)) ifelse(is.na(x), NA, ifelse(x, "TRUE", "FALSE")) else if (is.numeric(x)) ifelse(is.na(x), NA, sub("\\.0+$", "", format(x, digits = 15, trim = TRUE))) else x
cols <- lapply(r, fmtcol)
d <- read_excel(f, sheet = "dictionnaire")
write_ref(list(names = names(r), cols = cols, sheets = excel_sheets(f), dico_names = names(d), n_dico = nrow(d),
               poids_missing_after = sum(is.na(p$poids) | p$poids == 999), groupe_labels = unname(c("1" = "témoin", "2" = "traité")[as.character(p$groupe)])), "excel")
print(head(r, 3)); cat("feuilles :", excel_sheets(f), "\n")
