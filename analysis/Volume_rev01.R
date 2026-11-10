# ============================================================
# PNE 2022-2024 - CHIRURGIA PANCREATICA
# FINAL PAPER VERSION - REVISION 01 (Updates in Surgery, UPIS-D-26-01647)
#
# Benchmark fisso = 5%
# Prior centrata sulla mortalità nazionale osservata
# Classificazione unica = 80 + delta
#
# Better: P(p_c < 5%) >= 0.80
# Worse:  P(p_c > 6%) >= 0.80
# Else:   Indeterminate
#
# Include:
# - Table 1: sample characteristics
# - Table 2: primary classification
# - Table 3: dilution-aware interpretation
# - Table 4: exemplar centers
# - Validation vs adjusted PNE
# - Multiple paper figures
#
# Output solo a video
# ============================================================


# ============================================================
# 0) PACCHETTI
# ============================================================

required_pkgs <- c(
  "readxl",
  "dplyr",
  "tidyr",
  "purrr",
  "ggplot2",
  "stringr",
  "scales"
)

installed <- rownames(installed.packages())
to_install <- setdiff(required_pkgs, installed)

if (length(to_install) > 0) {
  install.packages(to_install)
}

library(readxl)
library(dplyr)
library(tidyr)
library(purrr)
library(ggplot2)
library(stringr)
library(scales)


# ============================================================
# 1) PARAMETRI
# ============================================================

file_name <- "PNE_pancreas_2022_2024_clean.xlsx"
file_path <- file.path(path.expand("~/Desktop"), file_name)

if (!file.exists(file_path) && !exists("pne")) {
  cat("\nFile non trovato al percorso atteso:\n")
  cat(file_path, "\n\n")
  cat("File Excel trovati sul Desktop:\n")
  print(list.files(path.expand("~/Desktop"), pattern = "\\.xlsx$", full.names = TRUE))
  cat("\nSeleziona manualmente il file Excel.\n")
  file_path <- file.choose()
}

sheet_name <- "data"

m_prior <- 25

p0_benchmark <- 0.05
delta <- 0.01

digits_perc <- 2

thr_primary <- 0.80

min_advantage_abs <- 0.01


# ============================================================
# 2) FUNZIONI
# ============================================================

print_section <- function(title) {
  cat("\n")
  cat(strrep("=", 80), "\n", sep = "")
  cat(title, "\n")
  cat(strrep("=", 80), "\n", sep = "")
}

possible_deaths <- function(n, perc, digits = 2) {
  if (is.na(n) || is.na(perc) || n <= 0) return(integer(0))
  
  candidates <- 0:n
  target_perc <- perc * 100
  
  # REV01: PNE reports crude mortality rounded to two decimals, but its
  # rounding convention does not always match R's round() (e.g. 2/64 = 3.125%
  # is reported as 3.13, whereas round(3.125, 2) = 3.12 in R). An exact-match
  # rule therefore failed for 8 centers. We retain every integer count whose
  # exact percentage lies within the reporting precision (0.01 percentage
  # points) of the reported value, irrespective of the rounding direction.
  tol <- 10^(-digits) + 1e-9
  candidates[abs(100 * candidates / n - target_perc) <= tol]
}

posterior_metrics <- function(n, d, a, b, p0_benchmark, delta = 0.01) {
  alpha_post <- a + d
  beta_post  <- b + n - d
  
  tibble(
    d = d,
    observed_rate = d / n,
    post_mean = alpha_post / (alpha_post + beta_post),
    ci_low = qbeta(0.025, alpha_post, beta_post),
    ci_high = qbeta(0.975, alpha_post, beta_post),
    ccs = pbeta(p0_benchmark, alpha_post, beta_post),
    pc_delta = 1 - pbeta(p0_benchmark + delta, alpha_post, beta_post)
  )
}

classify_primary <- function(ccs_mid, pc_delta_mid, threshold = 0.80) {
  case_when(
    !is.na(ccs_mid) & ccs_mid >= threshold ~ "Better than 5% benchmark",
    !is.na(pc_delta_mid) & pc_delta_mid >= threshold ~ "Worse than 6% threshold",
    TRUE ~ "Indeterminate"
  )
}

classify_dilution <- function(ccs_mid, advantage_mid, pc_delta_mid,
                              threshold_ccs = 0.80,
                              threshold_pc = 0.80,
                              min_advantage = 0.01) {
  case_when(
    is.na(ccs_mid) | is.na(advantage_mid) ~ NA_character_,
    !is.na(pc_delta_mid) & pc_delta_mid >= threshold_pc ~ "Worse than 6% threshold",
    ccs_mid < threshold_ccs ~ "Weak evidence / not interpretable",
    ccs_mid >= threshold_ccs & advantage_mid >= 0 & advantage_mid < min_advantage ~ "Possible dilution effect",
    ccs_mid >= threshold_ccs & advantage_mid >= min_advantage ~ "Substantial favorable signal",
    TRUE ~ "Indeterminate"
  )
}

median_iqr <- function(x, digits = 1) {
  x <- x[!is.na(x)]
  if (length(x) == 0) return(NA_character_)
  
  med <- round(median(x), digits)
  q1 <- round(quantile(x, 0.25), digits)
  q3 <- round(quantile(x, 0.75), digits)
  
  paste0(med, " [", q1, "-", q3, "]")
}

median_range <- function(x, digits = 1) {
  x <- x[!is.na(x)]
  if (length(x) == 0) return(NA_character_)
  paste0(round(median(x), digits), " (", round(min(x), digits), " to ", round(max(x), digits), ")")
}

range_fmt <- function(x, digits = 1) {
  x <- x[!is.na(x)]
  if (length(x) == 0) return(NA_character_)
  
  paste0(round(min(x), digits), " to ", round(max(x), digits))
}


# ============================================================
# 3) LETTURA FILE
# ============================================================

print_section("3) LETTURA FILE")

# REV01: if the Excel file is not available, the data can be taken from the
# saved R workspace (object `pne`), e.g. load("~/Desktop/.RData")
if (exists("pne") && !file.exists(file_path)) {
  cat("Using object `pne` already in the workspace\n")
} else {
  pne <- read_excel(file_path, sheet = sheet_name)
}

cat("Percorso file usato:\n")
cat(file_path, "\n\n")

cat("Dimensioni dataset:\n")
cat("Righe:", nrow(pne), "\n")
cat("Colonne:", ncol(pne), "\n\n")

cat("Nomi colonne:\n")
print(names(pne))


# ============================================================
# 4) CONTROLLI E PREPARAZIONE
# ============================================================

print_section("4) CONTROLLI E PREPARAZIONE")

expected_cols <- c(
  "center_id", "is_italia", "struttura", "prov", "comune", "regione",
  "n", "perc_grezza_prop", "perc_adj_prop", "rr", "p_value"
)

missing_cols <- setdiff(expected_cols, names(pne))

if (length(missing_cols) > 0) {
  stop(
    paste(
      "Mancano queste colonne nel foglio 'data':",
      paste(missing_cols, collapse = ", ")
    )
  )
}

italia <- pne %>% filter(is_italia == TRUE)
centri <- pne %>% filter(is_italia == FALSE)

if (nrow(italia) != 1) {
  stop("Atteso un solo record con is_italia == TRUE.")
}

centri <- centri %>%
  filter(!is.na(n), n > 0, !is.na(perc_grezza_prop))

p0_national <- italia$perc_grezza_prop[1]
p0 <- p0_benchmark

a <- m_prior * p0_national
b <- m_prior * (1 - p0_national)

cat("Numero centri analizzati:", nrow(centri), "\n")
cat("Mortalità nazionale osservata:", round(p0_national * 100, 2), "%\n")
cat("Benchmark analitico fisso:", round(p0 * 100, 2), "%\n")
cat("Soglia underperformance:", round((p0 + delta) * 100, 2), "%\n")
cat("Prior centrata su mortalità nazionale osservata\n")
cat("m_prior:", m_prior, "\n")
cat("alpha:", round(a, 4), "\n")
cat("beta:", round(b, 4), "\n")
cat("Soglia decisionale:", thr_primary, "\n")


# ============================================================
# 5) RICOSTRUZIONE DECESSI PLAUSIBILI
# ============================================================

print_section("5) RICOSTRUZIONE DECESSI PLAUSIBILI")

res <- centri %>%
  mutate(
    ei = 1 / n,
    expected_deaths_5pct = n * p0,
    expected_deaths_national = n * p0_national,
    d_set = map2(n, perc_grezza_prop, ~ possible_deaths(.x, .y, digits = digits_perc)),
    n_d_possible = map_int(d_set, length),
    d_min = map_int(d_set, ~ ifelse(length(.x) == 0, NA_integer_, min(.x))),
    d_max = map_int(d_set, ~ ifelse(length(.x) == 0, NA_integer_, max(.x)))
  )

cat("Centri con almeno un valore plausibile di decessi:",
    sum(res$n_d_possible > 0), "\n")
cat("Centri con ricostruzione univoca:",
    sum(res$n_d_possible == 1), "\n")
cat("Centri con più valori plausibili:",
    sum(res$n_d_possible > 1), "\n")


# ============================================================
# 6) CALCOLO POSTERIORI
# ============================================================

print_section("6) CALCOLO POSTERIORI")

res <- res %>%
  mutate(
    post = map2(
      n,
      d_set,
      \(n_i, ds) {
        if (length(ds) == 0) {
          return(
            tibble(
              d = NA_integer_,
              observed_rate = NA_real_,
              post_mean = NA_real_,
              ci_low = NA_real_,
              ci_high = NA_real_,
              ccs = NA_real_,
              pc_delta = NA_real_
            )
          )
        }
        
        map_dfr(
          ds,
          \(d_i) posterior_metrics(
            n = n_i,
            d = d_i,
            a = a,
            b = b,
            p0_benchmark = p0,
            delta = delta
          )
        )
      }
    )
  )

cat("Metriche posteriori calcolate.\n")


# ============================================================
# 7) DATASET ANALITICO PRINCIPALE
# ============================================================

print_section("7) DATASET ANALITICO PRINCIPALE")

summary_res <- res %>%
  mutate(
    observed_rate_min = map_dbl(post, ~ suppressWarnings(min(.x$observed_rate, na.rm = TRUE))),
    observed_rate_max = map_dbl(post, ~ suppressWarnings(max(.x$observed_rate, na.rm = TRUE))),
    post_mean_min     = map_dbl(post, ~ suppressWarnings(min(.x$post_mean, na.rm = TRUE))),
    post_mean_max     = map_dbl(post, ~ suppressWarnings(max(.x$post_mean, na.rm = TRUE))),
    ci_low_min        = map_dbl(post, ~ suppressWarnings(min(.x$ci_low, na.rm = TRUE))),
    ci_high_max       = map_dbl(post, ~ suppressWarnings(max(.x$ci_high, na.rm = TRUE))),
    ccs_min           = map_dbl(post, ~ suppressWarnings(min(.x$ccs, na.rm = TRUE))),
    ccs_max           = map_dbl(post, ~ suppressWarnings(max(.x$ccs, na.rm = TRUE))),
    pc_delta_min      = map_dbl(post, ~ suppressWarnings(min(.x$pc_delta, na.rm = TRUE))),
    pc_delta_max      = map_dbl(post, ~ suppressWarnings(max(.x$pc_delta, na.rm = TRUE)))
  ) %>%
  mutate(
    across(
      c(observed_rate_min, observed_rate_max,
        post_mean_min, post_mean_max,
        ci_low_min, ci_high_max,
        ccs_min, ccs_max,
        pc_delta_min, pc_delta_max),
      ~ ifelse(is.infinite(.x), NA_real_, .x)
    )
  ) %>%
  mutate(
    observed_rate_mid = (observed_rate_min + observed_rate_max) / 2,
    post_mean_mid     = (post_mean_min + post_mean_max) / 2,
    ccs_mid           = (ccs_min + ccs_max) / 2,
    pc_delta_mid      = (pc_delta_min + pc_delta_max) / 2,
    d_star            = ifelse(d_min == d_max, d_min, NA_integer_),
    
    class_primary = classify_primary(
      ccs_mid = ccs_mid,
      pc_delta_mid = pc_delta_mid,
      threshold = thr_primary
    ),
    
    advantage_obs_mid = p0 - observed_rate_mid,
    advantage_post_mid = p0 - post_mean_mid,
    
    observed_deaths_mid = (d_min + d_max) / 2,
    
    deaths_gap_vs_5pct = expected_deaths_5pct - observed_deaths_mid,
    deaths_gap_vs_national = expected_deaths_national - observed_deaths_mid,
    deaths_gap_per100_vs_5pct = deaths_gap_vs_5pct / n * 100,
    
    smr_vs_5pct = observed_deaths_mid / expected_deaths_5pct,
    
    signal_strength = ccs_mid * pmax(advantage_post_mid, 0),
    signal_deaths = ccs_mid * pmax(deaths_gap_vs_5pct, 0),
    
    dilution_flag = classify_dilution(
      ccs_mid = ccs_mid,
      advantage_mid = advantage_post_mid,
      pc_delta_mid = pc_delta_mid,
      threshold_ccs = thr_primary,
      threshold_pc = thr_primary,
      min_advantage = min_advantage_abs
    )
  )

cat("Dataset analitico costruito.\n")
cat("Righe:", nrow(summary_res), "\n")


# ============================================================
# 8) TABLE 1 - SAMPLE CHARACTERISTICS
# ============================================================

print_section("TABLE 1 - SAMPLE CHARACTERISTICS")

# Annual volume
summary_res <- summary_res %>%
  mutate(annual_volume = n / 3)

# Volume classes based on Balzano thresholds
summary_res <- summary_res %>%
  mutate(
    volume_class = case_when(
      annual_volume < 10 ~ "Very low volume",
      annual_volume >= 10 & annual_volume < 25 ~ "Low volume",
      annual_volume >= 25 & annual_volume < 60 ~ "Medium volume",
      annual_volume >= 60 & annual_volume < 167 ~ "High volume",
      annual_volume >= 167 ~ "Very high volume",
      TRUE ~ NA_character_
    )
  )

# Helper function for n (%)
n_pct <- function(x, total) {
  n_x <- sum(x, na.rm = TRUE)
  pct_x <- round(100 * n_x / total, 1)
  paste0(n_x, " (", pct_x, "%)")
}

total_centers <- nrow(summary_res)

table1 <- tibble(
  Characteristic = c(
    "Number of centers",
    "Total procedures (2022–2024)",
    "Mean annual procedures, all centers",
    "Median annual center volume (range)",
    
    "Very low-volume centers (<10/year)",
    "Low-volume centers (10–24/year)",
    "Medium-volume centers (25–59/year)",
    "High-volume centers (60–166/year)",
    "Very high-volume centers (≥167/year)",
    
    "Observed national 90-day mortality (%)",
    "Fixed analytic benchmark mortality (%)",
    "Underperformance threshold (%)",
    
    "Centers with uniquely reconstructable death counts",
    "Centers with adjusted mortality data available"
  ),
  
  Value = c(
    total_centers,
    sum(summary_res$n, na.rm = TRUE),
    round(sum(summary_res$n, na.rm = TRUE) / 3, 1),
    paste0(
      round(median(summary_res$annual_volume, na.rm = TRUE), 1),
      " (",
      round(min(summary_res$annual_volume, na.rm = TRUE), 1),
      "–",
      round(max(summary_res$annual_volume, na.rm = TRUE), 1),
      ")"
    ),
    
    n_pct(summary_res$volume_class == "Very low volume", total_centers),
    n_pct(summary_res$volume_class == "Low volume", total_centers),
    n_pct(summary_res$volume_class == "Medium volume", total_centers),
    n_pct(summary_res$volume_class == "High volume", total_centers),
    n_pct(summary_res$volume_class == "Very high volume", total_centers),
    
    round(p0_national * 100, 2),
    round(p0 * 100, 2),
    round((p0 + delta) * 100, 2),
    
    n_pct(summary_res$n_d_possible == 1, total_centers),
    n_pct(!is.na(summary_res$perc_adj_prop), total_centers)
  )
)

print(table1)

# ============================================================
# 9) TABLE 2 - PRIMARY CLASSIFICATION
# ============================================================


# ============================================================
# 9) TABLE 2 - PRIMARY CLASSIFICATION
# ============================================================

print_section("TABLE 2 - PRIMARY CLASSIFICATION")

table2 <- summary_res %>%
  group_by(class_primary) %>%
  summarise(
    n_centers = n(),
    
    annual_volume_median = round(median(n / 3, na.rm = TRUE), 1),
    annual_volume_range = range_fmt(n / 3, digits = 1),
    
    crude_mortality_median = round(median(perc_grezza_prop * 100, na.rm = TRUE), 2),
    crude_mortality_range = range_fmt(perc_grezza_prop * 100, digits = 2),
    
    posterior_mean_median = round(median(post_mean_mid * 100, na.rm = TRUE), 2),
    posterior_mean_range = range_fmt(post_mean_mid * 100, digits = 2),
    
    CCS_median = round(median(ccs_mid, na.rm = TRUE), 3),
    CCS_range = range_fmt(ccs_mid, digits = 3),
    
    PC_delta_median = round(median(pc_delta_mid, na.rm = TRUE), 3),
    PC_delta_range = range_fmt(pc_delta_mid, digits = 3),
    
    advantage_median = round(median(advantage_post_mid * 100, na.rm = TRUE), 2),
    advantage_range = range_fmt(advantage_post_mid * 100, digits = 2),
    
    signal_strength_median = round(median(signal_strength * 100, na.rm = TRUE), 3),
    signal_strength_range = range_fmt(signal_strength * 100, digits = 3),
    
    .groups = "drop"
  ) %>%
  arrange(class_primary)

print(table2)


# ============================================================
# 10) TABLE 3 - DILUTION-AWARE INTERPRETATION
# ============================================================

print_section("TABLE 3 - DILUTION-AWARE INTERPRETATION")

table3 <- summary_res %>%
  group_by(dilution_flag) %>%
  summarise(
    n_centers = n(),
    median_volume_IQR = median_iqr(n, digits = 0),
    median_crude_mortality_IQR = median_iqr(perc_grezza_prop * 100, digits = 2),
    median_posterior_mean_IQR = median_iqr(post_mean_mid * 100, digits = 2),
    median_CCS_IQR = median_iqr(ccs_mid, digits = 3),
    median_advantage_IQR = median_iqr(advantage_post_mid * 100, digits = 2),
    median_deaths_gap_vs_5pct_IQR = median_iqr(deaths_gap_vs_5pct, digits = 2),
    median_signal_strength_IQR = median_iqr(signal_strength * 100, digits = 3),
    .groups = "drop"
  ) %>%
  arrange(desc(n_centers))

print(table3)


# ============================================================
# 11) TABLE 4 - EXEMPLAR CENTERS
# ============================================================

print_section("TABLE 4 - EXEMPLAR CENTERS")

ex_low_volume_zero <- summary_res %>%
  filter(
    n <= quantile(n, 0.25, na.rm = TRUE),
    perc_grezza_prop == 0
  ) %>%
  arrange(desc(ccs_mid)) %>%
  slice_head(n = 2)

ex_possible_dilution <- summary_res %>%
  filter(dilution_flag == "Possible dilution effect") %>%
  arrange(desc(ccs_mid), desc(n)) %>%
  slice_head(n = 3)

ex_substantial_signal <- summary_res %>%
  filter(dilution_flag == "Substantial favorable signal") %>%
  arrange(desc(signal_strength), desc(signal_deaths), desc(n)) %>%
  slice_head(n = 3)

ex_worse <- summary_res %>%
  filter(dilution_flag == "Worse than 6% threshold") %>%
  arrange(desc(pc_delta_mid), desc(n)) %>%
  slice_head(n = 3)

table4 <- bind_rows(
  ex_low_volume_zero,
  ex_possible_dilution,
  ex_substantial_signal,
  ex_worse
) %>%
  distinct(center_id, .keep_all = TRUE) %>%
  transmute(
    struttura,
    regione,
    n,
    crude_mortality = round(perc_grezza_prop * 100, 2),
    posterior_mean = round(post_mean_mid * 100, 2),
    ccs_under_5pct = round(ccs_mid, 4),
    pc_above_6pct = round(pc_delta_mid, 4),
    advantage_vs_5pct = round(advantage_post_mid * 100, 2),
    deaths_gap_vs_5pct = round(deaths_gap_vs_5pct, 2),
    signal_strength = round(signal_strength * 100, 3),
    class_primary,
    dilution_flag
  )

print(table4)


# ============================================================
# 12) VALIDATION VS ADJUSTED PNE
# ============================================================

print_section("VALIDATION VS ADJUSTED PNE")

adj_subset <- summary_res %>%
  filter(!is.na(perc_adj_prop))

cat("Centri con mortalità aggiustata disponibile:", nrow(adj_subset), "\n")

validation_table <- NULL

if (nrow(adj_subset) > 5) {
  
  test_ccs <- cor.test(
    adj_subset$perc_adj_prop,
    adj_subset$ccs_mid,
    method = "spearman"
  )
  
  test_post <- cor.test(
    adj_subset$perc_adj_prop,
    adj_subset$post_mean_mid,
    method = "spearman"
  )
  
  test_signal <- cor.test(
    adj_subset$perc_adj_prop,
    adj_subset$signal_strength,
    method = "spearman"
  )
  
  validation_table <- tibble(
    comparison = c(
      "Adjusted PNE mortality vs CCS",
      "Adjusted PNE mortality vs Bayesian-adjusted mortality",
      "Adjusted PNE mortality vs credible advantage signal"
    ),
    expected_direction = c(
      "Negative",
      "Positive",
      "Negative"
    ),
    spearman_rho = c(
      unname(test_ccs$estimate),
      unname(test_post$estimate),
      unname(test_signal$estimate)
    ),
    p_value = c(
      test_ccs$p.value,
      test_post$p.value,
      test_signal$p.value
    )
  ) %>%
    mutate(
      spearman_rho = round(spearman_rho, 3),
      p_value = signif(p_value, 3)
    )
  
  print(validation_table)
  
  if (sum(!is.na(adj_subset$rr)) > 5) {
    
    test_rr_ccs <- cor.test(
      adj_subset$rr,
      adj_subset$ccs_mid,
      method = "spearman"
    )
    
    validation_table_rr <- tibble(
      comparison = "Adjusted PNE risk ratio vs CCS",
      expected_direction = "Negative",
      spearman_rho = round(unname(test_rr_ccs$estimate), 3),
      p_value = signif(test_rr_ccs$p.value, 3)
    )
    
    print(validation_table_rr)
    
  } else {
    validation_table_rr <- NULL
  }
  
  adj_subset <- adj_subset %>%
    mutate(
      adjusted_rank = rank(perc_adj_prop, ties.method = "average"),
      ccs_rank = rank(-ccs_mid, ties.method = "average"),
      signal_rank = rank(-signal_strength, ties.method = "average")
    )
  
  rank_validation_table <- tibble(
    comparison = c(
      "Adjusted PNE rank vs CCS rank",
      "Adjusted PNE rank vs signal rank"
    ),
    expected_direction = c(
      "Positive rank agreement",
      "Positive rank agreement"
    ),
    spearman_rho = c(
      unname(cor.test(adj_subset$adjusted_rank, adj_subset$ccs_rank, method = "spearman")$estimate),
      unname(cor.test(adj_subset$adjusted_rank, adj_subset$signal_rank, method = "spearman")$estimate)
    ),
    p_value = c(
      cor.test(adj_subset$adjusted_rank, adj_subset$ccs_rank, method = "spearman")$p.value,
      cor.test(adj_subset$adjusted_rank, adj_subset$signal_rank, method = "spearman")$p.value
    )
  ) %>%
    mutate(
      spearman_rho = round(spearman_rho, 3),
      p_value = signif(p_value, 3)
    )
  
  print(rank_validation_table)
  
  n_top <- max(1, round(0.20 * nrow(adj_subset)))
  
  adj_subset <- adj_subset %>%
    arrange(perc_adj_prop) %>%
    mutate(
      adj_group = case_when(
        row_number() <= n_top ~ "Best adjusted",
        row_number() > n() - n_top ~ "Worst adjusted",
        TRUE ~ "Middle"
      ),
      ccs_group = case_when(
        rank(-ccs_mid, ties.method = "average") <= n_top ~ "Best CCS",
        rank(-ccs_mid, ties.method = "average") > n() - n_top ~ "Worst CCS",
        TRUE ~ "Middle"
      ),
      signal_group = case_when(
        rank(-signal_strength, ties.method = "average") <= n_top ~ "Best signal",
        rank(-signal_strength, ties.method = "average") > n() - n_top ~ "Worst signal",
        TRUE ~ "Middle"
      )
    )
  
  cat("\nAgreement: adjusted groups vs CCS groups\n")
  print(table(adj_subset$adj_group, adj_subset$ccs_group))
  
  cat("\nAgreement: adjusted groups vs signal groups\n")
  print(table(adj_subset$adj_group, adj_subset$signal_group))
  
} else {
  cat("Too few centers with adjusted PNE mortality for validation analysis.\n")
}


# ============================================================
# 13) RESULTS SUMMARY
# ============================================================

print_section("RESULTS SUMMARY")

cat("Primary classification:\n")
print(table(summary_res$class_primary, useNA = "ifany"))

cat("\nDilution-aware classification:\n")
print(table(summary_res$dilution_flag, useNA = "ifany"))


# ============================================================
# 14) FIGURE 1 - VOLUME VS CRUDE MORTALITY, COLOR CCS
# ============================================================

print_section("FIGURE 1 - VOLUME VS CRUDE MORTALITY")

fig1 <- summary_res %>%
  ggplot(aes(x = n, y = perc_grezza_prop * 100)) +
  geom_point(aes(color = ccs_mid), size = 2.8, alpha = 0.85) +
  geom_hline(yintercept = p0 * 100, linetype = 2, linewidth = 0.7) +
  geom_hline(yintercept = p0_national * 100, linetype = 3, linewidth = 0.7) +
  scale_x_continuous(trans = "log10") +
  scale_color_viridis_c(
    option = "C",
    end = 0.95,
    labels = percent_format(accuracy = 1)
  ) +
  labs(
    title = "Figure 1. Crude Mortality, Volume, and Cente Credibility Score",
    subtitle = "Dashed line = 5% benchmark; dotted line = observed national 90-day mortality",
    x = "Number of procedures during the observation period (three years)  in log10 scale",
    y = "Crude mortality (%)",
    color = "CCS"
  ) +
  theme_minimal(base_size = 12)

print(fig1)

# ============================================================
# ADDITIONAL ANALYSIS - CRUDE MORTALITY <=5% VS CLASSIFICATION
# ============================================================

print_section("CRUDE MORTALITY <=5% VS CREDIBILITY CLASSIFICATION")

crude_vs_class <- summary_res %>%
  mutate(
    crude_mortality_group = case_when(
      perc_grezza_prop <= 0.05 ~ "Crude mortality <=5%",
      perc_grezza_prop > 0.05 ~ "Crude mortality >5%",
      TRUE ~ NA_character_
    )
  ) %>%
  filter(!is.na(class_primary), !is.na(crude_mortality_group)) %>%
  count(class_primary, crude_mortality_group) %>%
  group_by(class_primary) %>%
  mutate(
    row_percent = round(100 * n / sum(n), 1),
    n_percent = paste0(n, " (", row_percent, "%)")
  ) %>%
  ungroup()

print(crude_vs_class)

crude_vs_class_wide <- crude_vs_class %>%
  select(class_primary, crude_mortality_group, n_percent) %>%
  tidyr::pivot_wider(
    names_from = crude_mortality_group,
    values_from = n_percent,
    values_fill = "0 (0%)"
  )

cat("\nSummary table:\n")
print(crude_vs_class_wide)

# Contingency table for statistical test
crude_class_matrix <- summary_res %>%
  mutate(
    crude_mortality_group = case_when(
      perc_grezza_prop <= 0.05 ~ "Crude mortality <=5%",
      perc_grezza_prop > 0.05 ~ "Crude mortality >5%",
      TRUE ~ NA_character_
    )
  ) %>%
  filter(!is.na(class_primary), !is.na(crude_mortality_group)) %>%
  with(table(class_primary, crude_mortality_group))

cat("\nContingency table:\n")
print(crude_class_matrix)

cat("\nFisher exact test:\n")
fisher_crude_class <- fisher.test(crude_class_matrix)
print(fisher_crude_class)

cat("\nChi-square test:\n")
chisq_crude_class <- chisq.test(crude_class_matrix)
print(chisq_crude_class)


# ============================================================
# 2x2 TABLE - CRUDE MORTALITY <=5% VS CCS >=0.80
# ============================================================

print_section("2x2 TABLE: CRUDE MORTALITY <=5% VS CCS >=0.80")

crude_ccs_data <- summary_res %>%
  mutate(
    crude_group = ifelse(
      perc_grezza_prop <= 0.05,
      "Crude mortality <=5%",
      "Crude mortality >5%"
    ),
    ccs_group = ifelse(
      ccs_mid >= 0.80,
      "CCS >=0.80",
      "CCS <0.80"
    )
  ) %>%
  filter(!is.na(crude_group), !is.na(ccs_group))

# matrice 2x2
crude_ccs_matrix <- table(
  crude_ccs_data$crude_group,
  crude_ccs_data$ccs_group
)

# Fisher test
fisher_crude_ccs <- fisher.test(crude_ccs_matrix)

# tabella leggibile con n (% per riga)
crude_ccs_table <- crude_ccs_data %>%
  count(crude_group, ccs_group) %>%
  group_by(crude_group) %>%
  mutate(
    row_total = sum(n),
    percent = round(100 * n / row_total, 1),
    value = paste0(n, " (", percent, "%)")
  ) %>%
  ungroup() %>%
  select(crude_group, ccs_group, value) %>%
  tidyr::pivot_wider(
    names_from = ccs_group,
    values_from = value,
    values_fill = "0 (0%)"
  ) %>%
  mutate(
    fisher_p_value = signif(fisher_crude_ccs$p.value, 3)
  )

print(crude_ccs_table)

cat("\nFisher exact test p-value:", signif(fisher_crude_ccs$p.value, 3), "\n")

# frase pronta per Results
n_low <- sum(crude_ccs_data$crude_group == "Crude mortality <=5%")
n_low_ccs <- sum(
  crude_ccs_data$crude_group == "Crude mortality <=5%" &
    crude_ccs_data$ccs_group == "CCS >=0.80"
)
pct_low_ccs <- round(100 * n_low_ccs / n_low, 1)

cat(
  "\nPaper-ready sentence:\n",
  n_low_ccs, " of ", n_low,
  " centers with crude mortality <=5% had CCS >=0.80 (",
  pct_low_ccs, "%). Fisher exact test p = ",
  signif(fisher_crude_ccs$p.value, 3),
  ".\n",
  sep = ""
)

# ============================================================
# RELATION BETWEEN VOLUME CLASS AND CCS
# Balzano volume categories
# ============================================================

print_section("CCS ACCORDING TO BALZANO VOLUME CATEGORIES")

summary_res <- summary_res %>%
  mutate(
    annual_volume = n / 3,
    volume_class = case_when(
      annual_volume < 10 ~ "Very low volume (<10/year)",
      annual_volume >= 10 & annual_volume < 25 ~ "Low volume (10-24/year)",
      annual_volume >= 25 & annual_volume < 60 ~ "Medium volume (25-59/year)",
      annual_volume >= 60 & annual_volume < 167 ~ "High volume (60-166/year)",
      annual_volume >= 167 ~ "Very high volume (>167/year)",
      TRUE ~ NA_character_
    ),
    volume_class = factor(
      volume_class,
      levels = c(
        "Very low volume (<10/year)",
        "Low volume (10-24/year)",
        "Medium volume (25-59/year)",
        "High volume (60-166/year)",
        "Very high volume (>167/year)"
      )
    ),
    ccs_credible = ccs_mid >= 0.80
  )

ccs_by_volume <- summary_res %>%
  filter(!is.na(volume_class), !is.na(ccs_mid)) %>%
  group_by(volume_class) %>%
  summarise(
    centers = n(),
    annual_volume_median_range = paste0(
      round(median(annual_volume, na.rm = TRUE), 1),
      " (",
      round(min(annual_volume, na.rm = TRUE), 1),
      " to ",
      round(max(annual_volume, na.rm = TRUE), 1),
      ")"
    ),
    CCS_median_range = paste0(
      round(median(ccs_mid, na.rm = TRUE), 3),
      " (",
      round(min(ccs_mid, na.rm = TRUE), 3),
      " to ",
      round(max(ccs_mid, na.rm = TRUE), 3),
      ")"
    ),
    centers_with_CCS_ge_080 = sum(ccs_mid >= 0.80, na.rm = TRUE),
    percent_with_CCS_ge_080 = round(
      100 * centers_with_CCS_ge_080 / centers,
      1
    ),
    centers_with_CCS_ge_080_n_pct = paste0(
      centers_with_CCS_ge_080,
      " (",
      percent_with_CCS_ge_080,
      "%)"
    ),
    .groups = "drop"
  )

print(ccs_by_volume)

# ============================================================
# STATISTICAL TESTS
# ============================================================

print_section("STATISTICAL TESTS: CCS AND VOLUME CLASS")

# Kruskal-Wallis test for continuous CCS across volume classes
cat("\nKruskal-Wallis test: CCS across volume classes\n")
print(
  kruskal.test(ccs_mid ~ volume_class, data = summary_res)
)

# Fisher exact test for CCS >=0.80 across volume classes
ccs_volume_matrix <- summary_res %>%
  filter(!is.na(volume_class), !is.na(ccs_mid)) %>%
  mutate(
    CCS_group = ifelse(ccs_mid >= 0.80, "CCS >=0.80", "CCS <0.80")
  ) %>%
  with(table(volume_class, CCS_group))

cat("\nContingency table: volume class vs CCS >=0.80\n")
print(ccs_volume_matrix)

cat("\nFisher exact test: volume class vs CCS >=0.80\n")
print(fisher.test(ccs_volume_matrix))





# ============================================================
# 15) FIGURE 2 - POSTERIOR MEAN AND CREDIBLE INTERVALS
# ============================================================

print_section("FIGURE 2 - POSTERIOR MEAN AND CREDIBLE INTERVALS")

plot_df <- summary_res %>%
  arrange(post_mean_mid) %>%
  mutate(center_order = row_number())

fig2 <- plot_df %>%
  ggplot(aes(x = center_order, y = post_mean_mid)) +
  geom_errorbar(aes(ymin = ci_low_min, ymax = ci_high_max), width = 0, alpha = 0.5) +
  geom_point(aes(color = n), size = 2.2) +
  geom_hline(yintercept = p0, linetype = 2, linewidth = 0.7) +
  geom_hline(yintercept = p0_national, linetype = 3, linewidth = 0.7) +
  scale_y_continuous(labels = percent_format(accuracy = 0.1)) +
  scale_color_viridis_c(option = "C", end = 0.95) +
  labs(
    title = "eFigure 1. Posterior 90-day mortality estimates and 95% credible intervals",
    subtitle = "Dashed line = 5% benchmark; dotted line = observed national 90-day mortality",
    x = "Centers ordered by posterior mean",
    y = "Posterior 90-day mortality",
    color = "Volume during three years"
  ) +
  theme_minimal(base_size = 12)

print(fig2)


# ============================================================
# 16) FIGURE 3 - CCS VS ADVANTAGE
# ============================================================

print_section("FIGURE 3 - CCS VS ADVANTAGE")

fig3 <- summary_res %>%
  ggplot(aes(x = advantage_post_mid * 100, y = ccs_mid)) +
  geom_vline(xintercept = min_advantage_abs * 100, linetype = 2, linewidth = 0.7) +
  geom_hline(yintercept = thr_primary, linetype = 2, linewidth = 0.7) +
  geom_point(aes(size = n, color = dilution_flag), alpha = 0.85) +
  labs(
    title = "Figure 2. Center Credibility Score (CCS) versus Difference from Benchmark (DB)",
    subtitle = "Horizontal line = CCS 0.80; vertical line = 1 percentage-point advantage",
    x = "DB (percentage points)",
    y = "CCS",
    color = "Interpretation",
    size = "Volume during three years"
  ) +
  theme_minimal(base_size = 12)

print(fig3)

# ============================================================
# DILUTION EFFECT ANALYSIS
# ============================================================

print_section("DILUTION EFFECT ANALYSIS")

dilution_analysis <- summary_res %>%
  mutate(
    DB = p0 - post_mean_mid,
    dilution_effect = case_when(
      ccs_mid >= 0.80 & DB >= 0 & DB < 0.01 ~ "Possible dilution effect",
      ccs_mid >= 0.80 & DB >= 0.01 ~ "Substantial favorable signal",
      TRUE ~ "No dilution effect"
    )
  )

dilution_table <- dilution_analysis %>%
  count(dilution_effect) %>%
  mutate(
    percent = round(100 * n / sum(n), 1),
    n_percent = paste0(n, " (", percent, "%)")
  )

print(dilution_table)

cat("\nAmong centers with CCS >=0.80:\n")

dilution_among_credible <- dilution_analysis %>%
  filter(ccs_mid >= 0.80) %>%
  count(dilution_effect) %>%
  mutate(
    percent = round(100 * n / sum(n), 1),
    n_percent = paste0(n, " (", percent, "%)")
  )

print(dilution_among_credible)

cat("\nPaper-ready sentence:\n")

n_dilution <- dilution_analysis %>%
  filter(dilution_effect == "Possible dilution effect") %>%
  nrow()

n_credible <- dilution_analysis %>%
  filter(ccs_mid >= 0.80) %>%
  nrow()

pct_dilution <- round(100 * n_dilution / n_credible, 1)

cat(
  n_dilution, " of ", n_credible,
  " centers with CCS >=0.80 had a possible dilution effect, defined as a credible probability of being below the 5% benchmark but with an absolute advantage <1 percentage point (",
  pct_dilution, "%).\n",
  sep = ""
)

# ============================================================
# DILUTION AMONG CCS < 0.80 WITH POSITIVE SIGNAL
# ============================================================

print_section("DILUTION AMONG NON-CREDIBLE CENTERS WITH POSITIVE SIGNAL")

dilution_non_credible <- summary_res %>%
  mutate(
    DB = p0 - post_mean_mid,
    group = case_when(
      ccs_mid >= 0.80 & DB < 0.01 ~ "Credible + small advantage",
      ccs_mid < 0.80 & DB >= 0 & DB < 0.01 ~ "Possible dilution effect (non-credible)",
      ccs_mid < 0.80 & DB >= 0.01 ~ "Positive signal but not credible enough",
      DB < 0 ~ "Above benchmark"
    )
  )

table_dilution <- dilution_non_credible %>%
  count(group) %>%
  mutate(
    percent = round(100 * n / sum(n), 1),
    n_percent = paste0(n, " (", percent, "%)")
  )

print(table_dilution)

# focus: CCS < 0.80 but positive advantage
focus_dilution <- dilution_non_credible %>%
  filter(ccs_mid < 0.80, DB > 0) %>%
  summarise(
    n_centers = n(),
    mean_DB = mean(DB, na.rm = TRUE),
    median_volume = median(n / 3, na.rm = TRUE)
  )

print(focus_dilution)

cat("\nPaper-ready sentence:\n")

cat(
  focus_dilution$n_centers,
  " centers with CCS <0.80 showed a positive advantage over the 5% benchmark, consistent with a potential dilution effect characterized by insufficient statistical power to reach the credibility threshold despite favorable point estimates.\n"
)


# ============================================================
# SUPPLEMENTARY TABLE - DB CATEGORY VS CCS THRESHOLD
# ============================================================

print_section("SUPPLEMENTARY TABLE: DB CATEGORY VS CCS THRESHOLD")

db_ccs_data <- summary_res %>%
  mutate(
    DB = p0 - post_mean_mid,
    DB_group = case_when(
      DB >= 0.01 ~ "DB >=1%",
      DB >= 0 & DB < 0.01 ~ "DB between 0 to 1%",
      TRUE ~ NA_character_
    ),
    CCS_group = case_when(
      ccs_mid >= 0.80 ~ "CCS >=0.80",
      ccs_mid < 0.80 ~ "CCS <0.80",
      TRUE ~ NA_character_
    )
  ) %>%
  filter(!is.na(DB_group), !is.na(CCS_group))

db_ccs_matrix <- table(db_ccs_data$DB_group, db_ccs_data$CCS_group)

fisher_db_ccs <- fisher.test(db_ccs_matrix)

db_ccs_table <- db_ccs_data %>%
  count(DB_group, CCS_group) %>%
  group_by(DB_group) %>%
  mutate(
    row_total = sum(n),
    percent = round(100 * n / row_total, 1),
    value = paste0(n, " (", percent, "%)")
  ) %>%
  ungroup() %>%
  select(DB_group, CCS_group, value) %>%
  tidyr::pivot_wider(
    names_from = CCS_group,
    values_from = value,
    values_fill = "0 (0%)"
  ) %>%
  mutate(
    p_value = signif(fisher_db_ccs$p.value, 3)
  ) %>%
  rename(
    Parameters = DB_group
  ) %>%
  select(
    Parameters,
    `CCS <0.80`,
    `CCS >=0.80`,
    p_value
  )

print(db_ccs_table)

cat("\nFisher exact test p-value:", signif(fisher_db_ccs$p.value, 3), "\n")




# ============================================================
# 17) FIGURE 4 - VOLUME VS SIGNAL STRENGTH
# ============================================================

print_section("FIGURE 4 - VOLUME VS SIGNAL STRENGTH")

fig4 <- summary_res %>%
  ggplot(aes(x = n, y = signal_strength * 100)) +
  geom_point(aes(color = dilution_flag), size = 2.8, alpha = 0.85) +
  scale_x_continuous(trans = "log10") +
  labs(
    title = "eFigure 2. Credible Advantage Signal (CAS) across centers",
    x = "Number of procedures during three years in log10 scale",
    y = "CAS",
    color = "Interpretation"
  ) +
  theme_minimal(base_size = 12)

print(fig4)

# ============================================================
# SUBGROUP ANALYSIS - CRUDE MORTALITY <5%
# ============================================================

print_section("CENTERS WITH CRUDE MORTALITY <5%")

low_crude_data <- summary_res %>%
  mutate(
    annual_volume = n / 3,
    DB = p0 - post_mean_mid,
    CCS_group = ifelse(ccs_mid >= 0.80, "CCS >=0.80", "CCS <0.80")
  ) %>%
  filter(perc_grezza_prop < 0.05)

# Summary table
low_crude_table <- low_crude_data %>%
  summarise(
    centers = n(),
    CCS_ge_080 = sum(ccs_mid >= 0.80),
    CCS_lt_080 = sum(ccs_mid < 0.80),
    percent_CCS_ge_080 = round(100 * CCS_ge_080 / centers, 1)
  )

print(low_crude_table)

# Detailed descriptive table
low_crude_detail <- low_crude_data %>%
  group_by(CCS_group) %>%
  summarise(
    centers = n(),
    annual_volume = median_range(annual_volume, digits = 1),
    crude_mortality = median_range(perc_grezza_prop * 100, digits = 2),
    bayesian_mortality = median_range(post_mean_mid * 100, digits = 2),
    CCS = median_range(ccs_mid, digits = 3),
    DB = median_range(DB * 100, digits = 2),
    CAS = median_range(signal_strength * 100, digits = 3),
    .groups = "drop"
  )

print(low_crude_detail)

# 2x2 table + Fisher test
low_crude_matrix <- table(
  low_crude_data$CCS_group
)

cat("\nCCS distribution among centers with crude mortality <5%:\n")
print(low_crude_matrix)

# Paper-ready sentence
cat("\nPaper-ready sentence:\n")

cat(
  sum(low_crude_data$ccs_mid >= 0.80), " of ",
  nrow(low_crude_data),
  " centers with crude mortality <5% achieved CCS >=0.80 (",
  round(100 * sum(low_crude_data$ccs_mid >= 0.80) / nrow(low_crude_data), 1),
  "%).\n",
  sep = ""
)










# ============================================================
# 18) FIGURE 5 - ADJUSTED PNE VS CCS
# ============================================================

print_section("FIGURE 5 - ADJUSTED PNE VS CCS")

if (exists("adj_subset") && nrow(adj_subset) > 5) {
  
  fig5 <- adj_subset %>%
    ggplot(aes(x = perc_adj_prop * 100, y = ccs_mid)) +
    geom_point(aes(size = n, color = class_primary), alpha = 0.85) +
    geom_vline(xintercept = p0 * 100, linetype = 2, linewidth = 0.7) +
    geom_vline(xintercept = p0_national * 100, linetype = 3, linewidth = 0.7) +
    labs(
      title = "Figure 3. Adjusted PNE 90-day mortality and Center Credibility Score",
      subtitle = "Dashed vertical line = 5% benchmark; dotted line = observed national 90-day mortality",
      x = "Adjusted PNE 90-day mortality (%)",
      y = "CCS",
      size = "Volume during three years",
      color = "Primary classification"
    ) +
    theme_minimal(base_size = 12)
  
  print(fig5)
  
} else {
  cat("Figure 5 not produced: too few centers with adjusted mortality.\n")
}


# ============================================================
# 19) FIGURE 6 - ADJUSTED PNE VS SIGNAL STRENGTH
# ============================================================

print_section("FIGURE 6 - ADJUSTED PNE VS SIGNAL STRENGTH")

if (exists("adj_subset") && nrow(adj_subset) > 5) {
  
  fig6 <- adj_subset %>%
    ggplot(aes(x = perc_adj_prop * 100, y = signal_strength * 100)) +
    geom_point(aes(size = n, color = class_primary), alpha = 0.85) +
    geom_vline(xintercept = p0 * 100, linetype = 2, linewidth = 0.7) +
    geom_vline(xintercept = p0_national * 100, linetype = 3, linewidth = 0.7) +
    labs(
      title = "Figure 6. Adjusted PNE mortality and signal strength",
      x = "Adjusted PNE mortality (%)",
      y = "Signal strength",
      size = "Volume",
      color = "Primary classification"
    ) +
    theme_minimal(base_size = 12)
  
  print(fig6)
  
} else {
  cat("Figure 6 not produced: too few centers with adjusted mortality.\n")
}


# ============================================================
# 20) FIGURE 7 - EVENT INFLUENCE
# ============================================================

print_section("FIGURE 7 - EVENT INFLUENCE")

fig7 <- summary_res %>%
  ggplot(aes(x = n, y = ei * 100)) +
  geom_point(alpha = 0.85, size = 2.6) +
  scale_x_continuous(trans = "log10") +
  labs(
    title = "Figure 7. Event influence decreases with center volume",
    x = "Number of procedures (log10 scale)",
    y = "Mortality change from one additional death (%)"
  ) +
  theme_minimal(base_size = 12)

print(fig7)


# ============================================================
# 21) FIGURE 8 - DEATHS GAP VS VOLUME
# ============================================================

print_section("FIGURE 8 - DEATHS GAP VS VOLUME")

fig8 <- summary_res %>%
  ggplot(aes(x = n, y = deaths_gap_vs_5pct)) +
  geom_hline(yintercept = 0, linetype = 2, linewidth = 0.7) +
  geom_point(aes(color = dilution_flag), alpha = 0.85, size = 2.6) +
  scale_x_continuous(trans = "log10") +
  labs(
    title = "Figure 8. Deaths gap relative to the fixed 5% benchmark",
    x = "Number of procedures (log10 scale)",
    y = "Expected deaths at 5% minus observed deaths",
    color = "Interpretation"
  ) +
  theme_minimal(base_size = 12)

print(fig8)


# ============================================================
# 22) FIGURE 9 - RANK COMPARISON WITH ADJUSTED PNE
# ============================================================

print_section("FIGURE 9 - RANK COMPARISON WITH ADJUSTED PNE")

if (exists("adj_subset") && nrow(adj_subset) > 5) {
  
  fig9 <- adj_subset %>%
    ggplot(aes(x = adjusted_rank, y = ccs_rank)) +
    geom_point(aes(size = n, color = class_primary), alpha = 0.85) +
    geom_abline(slope = 1, intercept = 0, linetype = 2, linewidth = 0.7) +
    labs(
      title = "Figure 9. Rank agreement between adjusted PNE mortality and CCS",
      x = "Adjusted PNE rank",
      y = "CCS rank",
      size = "Volume",
      color = "Primary classification"
    ) +
    theme_minimal(base_size = 12)
  
  print(fig9)
  
} else {
  cat("Figure 9 not produced: too few centers with adjusted mortality.\n")
}


# ============================================================
# 23) SUPPLEMENTARY TABLE
# ============================================================

print_section("SUPPLEMENTARY TABLE S1 - FULL CENTER-LEVEL RESULTS PREVIEW")

supp_table_s1 <- summary_res %>%
  transmute(
    struttura,
    regione,
    n,
    crude_mortality = round(perc_grezza_prop * 100, 2),
    adjusted_mortality = round(perc_adj_prop * 100, 2),
    event_influence = round(ei * 100, 3),
    d_min,
    d_max,
    posterior_mean = round(post_mean_mid * 100, 2),
    ci_low = round(ci_low_min * 100, 2),
    ci_high = round(ci_high_max * 100, 2),
    ccs_under_5pct = round(ccs_mid, 4),
    pc_above_6pct = round(pc_delta_mid, 4),
    advantage_vs_5pct = round(advantage_post_mid * 100, 2),
    deaths_gap_vs_5pct = round(deaths_gap_vs_5pct, 2),
    deaths_gap_vs_national = round(deaths_gap_vs_national, 2),
    signal_strength = round(signal_strength * 100, 3),
    class_primary,
    dilution_flag
  ) %>%
  arrange(desc(signal_strength), desc(n))

print(supp_table_s1 %>% slice_head(n = 30))


# ============================================================
# 24) OGGETTI DISPONIBILI
# ============================================================

print_section("OGGETTI DISPONIBILI")

cat("summary_res\n")
cat("table1\n")
cat("table2\n")
cat("table3\n")
cat("table4\n")
cat("adj_subset\n")
cat("supp_table_s1\n")
cat("fig1, fig2, fig3, fig4, fig5, fig6, fig7, fig8, fig9\n")
cat("validation_table\n")
cat("validation_table_rr\n")
cat("rank_validation_table\n")

cat("\nPer ispezione:\n")
cat("View(summary_res)\n")
cat("View(table1)\n")
cat("View(table2)\n")
cat("View(table3)\n")
cat("View(validation_table)\n")
cat("View(rank_validation_table)\n")
cat("View(table4)\n")
cat("View(adj_subset)\n")
cat("View(supp_table_s1)\n")



# ============================================================
# FIGURE 5 SUPPORTING ANALYSIS
# ADJUSTED MORTALITY BY CCS CLASSIFICATION
# ============================================================

print_section("ADJUSTED MORTALITY BY CLASSIFICATION")

fig5_table <- summary_res %>%
  filter(!is.na(perc_adj_prop)) %>%
  mutate(
    adj_group = ifelse(
      perc_adj_prop <= 0.05,
      "Adjusted mortality <=5%",
      "Adjusted mortality >5%"
    )
  ) %>%
  count(class_primary, adj_group) %>%
  group_by(class_primary) %>%
  mutate(
    total = sum(n),
    percent = round(100 * n / total, 1),
    value = paste0(n, " (", percent, "%)")
  ) %>%
  ungroup() %>%
  select(class_primary, adj_group, value) %>%
  tidyr::pivot_wider(
    names_from = adj_group,
    values_from = value,
    values_fill = "0 (0%)"
  )

print(fig5_table)

# statistical test
fig5_matrix <- summary_res %>%
  filter(!is.na(perc_adj_prop)) %>%
  mutate(
    adj_group = ifelse(
      perc_adj_prop <= 0.05,
      "Adjusted mortality <=5%",
      "Adjusted mortality >5%"
    )
  ) %>%
  with(table(class_primary, adj_group))

print(fig5_matrix)

fisher_fig5 <- fisher.test(fig5_matrix)

cat("\nFisher exact test p-value:\n")
print(fisher_fig5$p.value)

# ============================================================
# ============================================================
# REVISION 01 - ADDITIONAL ANALYSES REQUESTED BY THE REVIEWERS
# ============================================================
# ============================================================

dir.create("rev01_output", showWarnings = FALSE)

# Generic re-run of the framework under alternative assumptions
run_framework <- function(m = 25, thr = 0.80, p0b = 0.05, dlt = 0.01) {
  a_s <- m * p0_national
  b_s <- m * (1 - p0_national)
  out <- res %>%
    transmute(
      center_id, n,
      post = map2(n, d_set, \(n_i, ds) map_dfr(ds, \(d_i)
        posterior_metrics(n_i, d_i, a_s, b_s, p0_benchmark = p0b, delta = dlt)))
    ) %>%
    mutate(
      ccs = map_dbl(post, ~ (min(.x$ccs) + max(.x$ccs)) / 2),
      ppm = map_dbl(post, ~ (min(.x$pc_delta) + max(.x$pc_delta)) / 2),
      post_mean = map_dbl(post, ~ (min(.x$post_mean) + max(.x$post_mean)) / 2),
      cls = classify_primary(ccs, ppm, threshold = thr)
    ) %>%
    select(center_id, n, post_mean, ccs, ppm, cls)
  out
}

base_run <- run_framework()
stopifnot(all(base_run$cls == summary_res$class_primary))

# ------------------------------------------------------------
# R1.2 / R2-minor-1: sensitivity analysis (prior weight, probability
# threshold, underperformance margin)
# ------------------------------------------------------------
print_section("REV01 - SENSITIVITY ANALYSIS")

scenarios <- list(
  "Main analysis (m = 25; threshold 0.80; 5% / 6%)" = list(),
  "Prior effective sample size m = 10" = list(m = 10),
  "Prior effective sample size m = 50" = list(m = 50),
  "Probability threshold 0.70" = list(thr = 0.70),
  "Probability threshold 0.90" = list(thr = 0.90),
  "Underperformance threshold 7% (2-pp margin)" = list(dlt = 0.02)
)

adj_ids <- summary_res$center_id[!is.na(summary_res$perc_adj_prop)]

sens_table <- imap_dfr(scenarios, \(args, lab) {
  r <- do.call(run_framework, args)
  adj_r <- r %>% filter(center_id %in% adj_ids) %>%
    left_join(summary_res %>% select(center_id, perc_adj_prop), by = "center_id")
  tibble(
    Scenario = lab,
    Better = sum(r$cls == "Better than 5% benchmark"),
    Indeterminate = sum(r$cls == "Indeterminate"),
    Worse = sum(r$cls == "Worse than 6% threshold" ),
    Reclassified_vs_main = sum(r$cls != base_run$cls),
    Better_to_Indet = sum(base_run$cls == "Better than 5% benchmark" & r$cls == "Indeterminate"),
    Indet_to_Better = sum(base_run$cls == "Indeterminate" & r$cls == "Better than 5% benchmark"),
    Worse_to_Indet = sum(base_run$cls == "Worse than 6% threshold" & r$cls == "Indeterminate"),
    Indet_to_Worse = sum(base_run$cls == "Indeterminate" & r$cls == "Worse than 6% threshold"),
    Better_Worse_switch = sum((base_run$cls == "Better than 5% benchmark" & r$cls == "Worse than 6% threshold") |
                              (base_run$cls == "Worse than 6% threshold" & r$cls == "Better than 5% benchmark")),
    rho_CCS_adj = unname(cor.test(adj_r$perc_adj_prop, adj_r$ccs, method = "spearman", exact = FALSE)$estimate),
    rho_post_adj = unname(cor.test(adj_r$perc_adj_prop, adj_r$post_mean, method = "spearman", exact = FALSE)$estimate),
    Fisher_p_adj = fisher.test(table(adj_r$cls, adj_r$perc_adj_prop <= 0.05))$p.value
  )
})
print(sens_table, width = Inf)
write.csv(sens_table, "rev01_output/sens_table.csv", row.names = FALSE)

# Reclassified centers by volume (who moves?)
moved <- imap_dfr(scenarios[-1], \(args, lab) {
  r <- do.call(run_framework, args)
  r %>% mutate(main = base_run$cls, scenario = lab) %>% filter(cls != main)
})
cat("\nAnnual volume of reclassified centers, by scenario:\n")
print(moved %>% group_by(scenario) %>%
        summarise(k = n(), median_annual = median(n / 3), min_annual = min(n / 3), max_annual = max(n / 3)))
write.csv(moved, "rev01_output/reclassified_centers.csv", row.names = FALSE)

# ------------------------------------------------------------
# R1.2 / R2-minor-1: weight of the prior vs centre data
# ------------------------------------------------------------
print_section("REV01 - WEIGHT OF CENTRE DATA n/(n+m)")
summary_res <- summary_res %>% mutate(w_data = n / (n + m_prior))
w_tab <- summary_res %>%
  mutate(group = ifelse(is.na(perc_adj_prop), "No risk-adjusted estimate", "Risk-adjusted estimate available")) %>%
  group_by(group) %>%
  summarise(centers = n(),
            annual_volume = paste0(round(median(n / 3), 1), " (", round(min(n / 3), 1), "-", round(max(n / 3), 1), ")"),
            w_data = paste0(round(median(w_data), 2), " (", round(min(w_data), 2), "-", round(max(w_data), 2), ")"),
            .groups = "drop")
print(w_tab)
write.csv(w_tab, "rev01_output/weight_by_validation_subset.csv", row.names = FALSE)
cat("Overall median w_data:", round(median(summary_res$w_data), 2), "\n")
cat("Volume (3-y) at which centre data weigh 50%/80%/90%:", m_prior, 4 * m_prior, 9 * m_prior, "\n")

# ------------------------------------------------------------
# R2.1: classification among centres meeting Italian volume requirements
# ------------------------------------------------------------
print_section("REV01 - CLASSIFICATION BY VOLUME REQUIREMENT")
vol_req <- summary_res %>%
  mutate(req = case_when(
    n >= 90 ~ ">=30/year (>=90 in 3 years)",
    n >= 50 ~ "50-89 in 3 years",
    TRUE ~ "<50 in 3 years")) %>%
  count(req, class_primary) %>%
  tidyr::pivot_wider(names_from = class_primary, values_from = n, values_fill = 0)
print(vol_req)
write.csv(vol_req, "rev01_output/class_by_volume_requirement.csv", row.names = FALSE)
cat("Centres >=50 in 3 years:", sum(summary_res$n >= 50), " | >=90 in 3 years:", sum(summary_res$n >= 90), "\n")

# ------------------------------------------------------------
# R2.2: the 44 centres with risk-adjusted PNE estimates
# ------------------------------------------------------------
print_section("REV01 - 44 CENTRES WITH RISK-ADJUSTED ESTIMATES")
t44 <- summary_res %>%
  filter(!is.na(perc_adj_prop)) %>%
  arrange(desc(n)) %>%
  mutate(
    Centre = paste0("C", sprintf("%02d", row_number())),
    pne_flag = case_when(
      !is.na(p_value) & p_value < 0.05 & rr > 1 ~ "Significantly higher",
      !is.na(p_value) & p_value < 0.05 & rr < 1 ~ "Significantly lower",
      TRUE ~ "Not significant"),
    adj_cat = case_when(perc_adj_prop <= 0.05 ~ "<=5%", perc_adj_prop <= 0.06 ~ ">5-6%", TRUE ~ ">6%")
  ) %>%
  transmute(
    Centre,
    annual_volume = round(n / 3, 1),
    crude_mortality = round(perc_grezza_prop * 100, 1),
    adjusted_mortality = round(perc_adj_prop * 100, 1),
    rr = round(rr, 2), p_value = signif(p_value, 2), pne_flag, adj_cat,
    bayes_smoothed = round(post_mean_mid * 100, 1),
    cri = paste0(round(ci_low_min * 100, 1), "-", round(ci_high_max * 100, 1)),
    ccs = round(ccs_mid, 2), ppm = round(pc_delta_mid, 2),
    class_primary
  )
print(as.data.frame(t44))
write.csv(t44, "rev01_output/table_44_centres.csv", row.names = FALSE)

cat("\nClassification vs PNE statistical flag:\n")
print(table(t44$class_primary, t44$pne_flag))
cat("\nClassification vs risk-adjusted category:\n")
print(table(t44$class_primary, t44$adj_cat))
cat("\nCrude mortality category vs risk-adjusted category:\n")
print(table(ifelse(t44$crude_mortality <= 5, "crude<=5", "crude>5"), t44$adj_cat))
cat("\nSpearman crude vs adjusted (44):\n")
a44 <- summary_res %>% filter(!is.na(perc_adj_prop))
print(cor.test(a44$perc_adj_prop, a44$perc_grezza_prop, method = "spearman", exact = FALSE))

# ------------------------------------------------------------
# R2-minor-2: redundancy among metrics
# ------------------------------------------------------------
print_section("REV01 - CORRELATION AMONG METRICS")
print(round(cor(summary_res %>% transmute(CCS = ccs_mid, PPM = pc_delta_mid,
                                          DB = advantage_post_mid, CAS = signal_strength),
                method = "spearman"), 3))
cat("Centres with CAS > 0:", sum(summary_res$signal_strength > 0), "\n")

# ------------------------------------------------------------
# R1.4: reconstruction diagnostics
# ------------------------------------------------------------
print_section("REV01 - DEATH-COUNT RECONSTRUCTION")
cat("Unique reconstruction:", sum(summary_res$n_d_possible == 1), "of", nrow(summary_res), "\n")
exact_rule <- map2_int(summary_res$n, summary_res$perc_grezza_prop, \(n, p) {
  cc <- 0:n; sum(round(100 * cc / n, 2) == round(p * 100, 2)) })
cat("Centres not matched by the exact-rounding rule of the original submission:", sum(exact_rule == 0), "\n")
print(summary_res %>% filter(exact_rule == 0) %>%
        transmute(n, reported = perc_grezza_prop * 100, d_star, exact = round(100 * d_star / n, 4), class_primary))

# ------------------------------------------------------------
# Save figures (to be restyled by the authors)
# ------------------------------------------------------------
ggsave("rev01_output/Figure_1_rev01.pdf", fig1, width = 11, height = 7)
ggsave("rev01_output/Figure_2_rev01.pdf", fig3, width = 11, height = 7)
ggsave("rev01_output/Figure_3_rev01.pdf", fig5, width = 11, height = 7)
ggsave("rev01_output/Figure_S1_rev01.pdf", fig2, width = 11, height = 7)
ggsave("rev01_output/Figure_S2_rev01.pdf", fig4, width = 11, height = 7)
saveRDS(list(summary_res=summary_res, table2=table2, p_nat=p0_national), "rev01_output/objects.rds")
