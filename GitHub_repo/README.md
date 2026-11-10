# Pancreas Credibility Calculator

Code accompanying the manuscript *“The Denominator Problem: Credibility-Based Hospital Performance in Pancreatic Surgery”* (Ricci C, et al.).

The framework evaluates center-level 90-day mortality after pancreatic resection with a Bayesian beta-binomial model, using only the number of procedures and crude mortality (or the number of deaths). For each center it reports:

| Metric | Definition | Used for classification |
|---|---|---|
| Bayesian-smoothed mortality | Posterior mean of 90-day mortality (not adjusted for case mix) | No |
| CCS (Center Credibility Score) | Posterior probability that true mortality is below the benchmark (default 5%) | Yes |
| PPM (Posterior Probability of Mortality) | Posterior probability that true mortality exceeds benchmark + margin (default 6%) | Yes |
| DB (Difference from Benchmark) | Benchmark − Bayesian-smoothed mortality, percentage points | No (descriptive) |
| CAS (Credible Advantage Signal) | CCS × max(0, DB) | No (descriptive) |

Classification: credibly better if CCS ≥ 0.80; credibly worse if PPM ≥ 0.80; otherwise indeterminate.

Default prior: Beta(m·p, m·(1 − p)) with p = 8.16% (Italian national 90-day mortality, PNE 2022–2024) and effective sample size m = 25 procedures over 3 years.

## Contents

- `app.py` – Streamlit calculator (online version: https://pancreas-credibility-calculator-epavad5ewtuoaxkdffmsw7.streamlit.app/)
- `analysis/Volume_rev01.R` – complete R code of the analyses reported in the paper (main analysis, validation against PNE risk-adjusted mortality, sensitivity analyses, tables)
- `analysis/Figures_rev01.py` – Python code for Figures 1–3 and S1–S2
- `data/PNE_pancreas_2022_2024_clean.xlsx` – hospital-level data exported from the public portal of the Italian National Outcomes Program (Programma Nazionale Esiti, Agenas; indicator “Intervento chirurgico di resezione pancreatica per TM: mortalità a 90 giorni”, 2022–2024)

## Reconstruction of death counts

PNE reports crude mortality as a percentage with two decimals. The number of deaths d is reconstructed by retaining every integer 0 ≤ d ≤ n with |100·d/n − reported %| ≤ 0.01, a rule that does not depend on the rounding convention of the source. With the volumes in the dataset the reconstruction is unique for every center. The calculator applies the same rule, or accepts the number of deaths directly.

## Run locally

```
pip install -r requirements.txt
streamlit run app.py
```

The R script requires R ≥ 4.2 and the packages readxl, dplyr, tidyr, purrr, ggplot2, stringr and scales; set the path of the data file at the top of the script.

© Claudio Ricci, University of Bologna. All rights reserved.
