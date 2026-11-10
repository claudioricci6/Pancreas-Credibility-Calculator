import pandas as pd
import streamlit as st
from scipy.stats import beta


st.set_page_config(
    page_title="Pancreatic Resection 90-day Mortality Credibility Calculator",
    page_icon="🧮",
    layout="centered"
)

st.title("Pancreatic Resection 90-day Mortality Credibility Calculator")
st.caption("Credibility-based benchmarking framework for pancreatic surgery outcomes")

st.markdown(
    """
This tool estimates whether a hospital’s pancreatic surgery 90-day mortality is
**credibly below**, **indeterminate**, or **credibly above** a fixed benchmark
using a Bayesian beta-binomial framework.
"""
)

# ============================================================
# METHODOLOGICAL WARNING (IMPORTANT)
# ============================================================

st.warning(
    """
⚠️ This model was developed and validated using **3-year aggregated data (2022–2024 PNE)**.

For methodological consistency and validity of CCS estimates, users are strongly recommended
to input **3-year cumulative volume and 90-day mortality** rather than annual or partial-period data.

Shorter observation periods may lead to unstable credibility estimates.
"""
)

# ============================================================
# SIDEBAR - MODEL SETTINGS
# ============================================================

st.sidebar.header("Model settings")

benchmark = st.sidebar.number_input(
    "Benchmark 90-day mortality (%)",
    min_value=0.1,
    max_value=50.0,
    value=5.0,
    step=0.1,
    format="%.1f"
) / 100

delta = st.sidebar.number_input(
    "Underperformance margin (%)",
    min_value=0.1,
    max_value=20.0,
    value=1.0,
    step=0.1,
    format="%.1f"
) / 100

national_mortality = st.sidebar.number_input(
    "Reference national 90-day mortality (%)",
    min_value=0.1,
    max_value=50.0,
    value=8.16,
    step=0.01,
    format="%.2f"
) / 100

st.sidebar.caption(
    "Default: 8.16%, corresponding to the observed Italian national 90-day mortality after pancreatic resection in PNE 2022–2024 (prior mean)."
)

m_prior = st.sidebar.number_input(
    "Prior effective sample size (weight of national reference data, procedures)",
    min_value=1.0,
    max_value=500.0,
    value=25.0,
    step=0.1,
    format="%.1f"
)

st.sidebar.caption(
    "Default: 25 procedures over 3 years. The weight of the center's own data is n/(n + 25): 50% at 25, 80% at 100 and 90% at 225 procedures. Values of 10 and 50 were explored in the sensitivity analysis of the paper."
)

threshold = st.sidebar.number_input(
    "Posterior probability threshold for classification",
    min_value=0.50,
    max_value=0.99,
    value=0.80,
    step=0.01,
    format="%.2f"
)

# ============================================================
# INPUT SECTION
# ============================================================

st.header("Center input (3-year cumulative data recommended)")

volume_period = int(st.number_input(
    "Number of procedures (preferably 3-year total)",
    min_value=1,
    value=50,
    step=1
))

input_mode = st.radio(
    "Mortality input",
    ["Crude 90-day mortality (%), as reported by PNE", "Number of 90-day deaths"],
    horizontal=False
)

if input_mode.startswith("Crude"):
    crude_mortality_percent = st.number_input(
        "Observed crude 90-day mortality (%) (3-year period)",
        min_value=0.0,
        max_value=100.0,
        value=4.0,
        step=0.01,
        format="%.2f"
    )
    deaths_input = None
else:
    deaths_input = int(st.number_input(
        "Number of 90-day deaths (3-year period)",
        min_value=0,
        max_value=volume_period,
        value=min(2, volume_period),
        step=1
    ))
    crude_mortality_percent = 100 * deaths_input / volume_period


def reconstruct_deaths(n, perc, tol=0.01):
    """Integer death counts compatible with a percentage reported to two decimals.

    Every integer d in 0..n is retained if |100*d/n - perc| <= tol (the reporting
    precision), irrespective of the rounding convention used by the source.
    This is the rule used in the paper (Online Resource 1, Section 3).
    """
    return [d for d in range(n + 1) if abs(100 * d / n - perc) <= tol + 1e-9]

calculate = st.button("Calculate", type="primary")

# ============================================================
# CALCULATION
# ============================================================

if calculate:

    if deaths_input is not None:
        compatible = [deaths_input]
    else:
        compatible = reconstruct_deaths(volume_period, crude_mortality_percent)
        if not compatible:
            nearest = round(volume_period * crude_mortality_percent / 100)
            st.error(
                f"No integer number of deaths out of {volume_period} procedures gives "
                f"{crude_mortality_percent:.2f}% (the closest is {nearest} deaths = "
                f"{100 * nearest / volume_period:.2f}%). Please check the input, or enter the number of deaths."
            )
            st.stop()
    # with two-decimal percentages and realistic volumes the count is unique;
    # if several counts were compatible, metrics would be averaged (midpoint) as in the paper
    estimated_deaths = compatible[0] if len(compatible) == 1 else (compatible[0] + compatible[-1]) / 2

    a = m_prior * national_mortality
    b = m_prior * (1 - national_mortality)

    alpha_post = a + estimated_deaths
    beta_post = b + volume_period - estimated_deaths

    bayesian_smoothed_mortality = alpha_post / (alpha_post + beta_post)
    cri_low, cri_high = beta.ppf([0.025, 0.975], alpha_post, beta_post)

    ccs = beta.cdf(benchmark, alpha_post, beta_post)

    ppm = 1 - beta.cdf(benchmark + delta, alpha_post, beta_post)

    db = benchmark - bayesian_smoothed_mortality

    cas = ccs * max(0, db)
    cas_percent = cas * 100

    # ============================================================
    # CLASSIFICATION
    # ============================================================

    if ccs >= threshold:
        classification = "Credibly better than benchmark"
        tag = "success"
    elif ppm >= threshold:
        classification = "Credibly worse than threshold"
        tag = "error"
    else:
        classification = "Indeterminate"
        tag = "warning"

    # ============================================================
    # OUTPUT
    # ============================================================

    st.info(
        f"Number of deaths used (3-year period): **{estimated_deaths}** of {volume_period} procedures"
    )

    st.header("Classification")

    if tag == "success":
        st.success(classification)
    elif tag == "error":
        st.error(classification)
    else:
        st.warning(classification)

    st.header("Results")

    col1, col2 = st.columns(2)

    with col1:
        st.metric("Bayesian-smoothed 90-day mortality", f"{bayesian_smoothed_mortality * 100:.1f}%",
                  help=f"95% credible interval {cri_low * 100:.1f}–{cri_high * 100:.1f}%. Not adjusted for case mix.")
        st.metric("CCS", f"{ccs:.3f}")
        st.metric("PPM", f"{ppm:.3f}")

    with col2:
        st.metric("DB (pp)", f"{db * 100:.1f}")
        st.metric("CAS", f"{cas_percent:.2f}")
        st.metric("Benchmark", f"{benchmark * 100:.1f}%")

    st.caption(
        f"Bayesian-smoothed mortality 95% credible interval: {cri_low * 100:.1f}–{cri_high * 100:.1f}%. "
        "Bayesian-smoothed mortality accounts for the instability due to small denominators; "
        "it is NOT adjusted for case mix and should not be confused with risk-adjusted mortality."
    )

    st.subheader("Interpretation")

    st.markdown(
        f"""
- **CCS** = probability that true 90-day mortality is below {benchmark*100:.1f}%
- **PPM** = probability that true 90-day mortality exceeds {(benchmark+delta)*100:.1f}%
- **DB** = difference from benchmark ({benchmark*100:.1f}% − Bayesian-smoothed 90-day mortality), in percentage points
- **CAS** = credibility-weighted favorable signal
- Classification uses only CCS and PPM; DB and CAS are descriptive

**CAS interpretation:**
- 0 → no credible advantage  
- <1 → weak or marginal signal (possible dilution zone)  
- ≥1 → substantial credible favorable signal
"""
    )

    st.divider()

    st.caption(
        "This model was developed and validated using 3-year aggregated PNE data (2022–2024). "
        "Use of shorter observation periods may reduce statistical validity of CCS estimates."
    )

    st.caption(
        "All rights reserved © Prof. Claudio Ricci, University of Bologna."
    )
