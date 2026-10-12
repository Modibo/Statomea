#!/usr/bin/env bash
# Régénère toutes les valeurs de référence avec R puis exécute les tests.
# Prérequis : R ≥ 4.2 avec jsonlite, metafor, logistf, pROC, sandwich, car, pmsampsize, survival, mada, mice, rstatix,
# HardyWeinberg, MASS, statmod, vcfR, genio, rrBLUP, GMMAT, MendelianRandomization, psych ; Bioconductor : edgeR, limma, Biostrings, snpStats, SNPRelate ; BLAST+ 2.17 (variable BLAST_BIN, par défaut
# ~/development/ncbi-blast-2.17.0+/bin) ; Flutter (Dart) dans le PATH.
set -euo pipefail
cd "$(dirname "$0")/r"
for f in [0-9][0-9]_*.R; do echo "== $f"; Rscript "$f"; done
cp ../../demos/*.csv ../../demos/*.fasta ../../app/statomea/assets/demos/
cp ../../demos/tb_* ../../demos/mr_ldl_chd.csv ../../demos/mr_bidirectionnel_simule.csv ../../packages/statomea_core/test/reference/
for e in bed bim fam; do cp ../../packages/statomea_core/test/reference/genotypes/ldsc_app.$e ../../app/statomea/assets/demos/genotypes_dl_simule.$e; done
for e in bed bim fam; do cp ../../packages/statomea_core/test/reference/genotypes/prs.$e ../../app/statomea/assets/demos/genotypes_prs_simule.$e; done
cp ../../packages/statomea_core/test/reference/genotypes/prs_covariables.csv ../../app/statomea/assets/demos/genotypes_prs_covariables.csv
cp ../../packages/statomea_core/test/reference/genotypes/ldsc_app_traits.csv ../../app/statomea/assets/demos/genotypes_dl_traits.csv
cd ../../packages/statomea_core
dart test --reporter expanded | tail -3
cd ../../app/statomea
flutter test | tail -1
