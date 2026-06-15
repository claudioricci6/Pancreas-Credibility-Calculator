import pandas as pd
import streamlit as st
from scipy.stats import beta


st.set_page_config(
    page_title="Pancreas Credibility Calculator",
    page_icon="🧮",
    layout="centered"
)

st.title("Pancreas Credibility Calculator")
st.caption("Credibility-based benchmarking framework for pancreatic surgery outcomes")

st.markdown(
    """
This tool estimates whether a hospital’s pancreatic surgery mortality is
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
to input **3-year cumulative volume and mortality** rather than annual or partial-period data.

Shorter observation periods may lead to unstable credibility estimates.
"""
)

# ============================================================
# SIDEBAR - MODEL SETTINGS
# ============================================================

st.sidebar.header("Model settings")

benchmark = st.sidebar.number_input(
    "Benchmark mortality (%)",
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
    "National mortality prior (%) (PNE 2022–2024 default)",
    min_value=0.1,
    max_value=50.0,
    value=8.2,
    step=0.1,
    format="%.1f"
) / 100

m_prior = st.sidebar.number_input(
    "Prior effective sample size (3-year equivalent)",
    min_value=1.0,
    max_value=500.0,
    value=25.0,
    step=0.1,
    format="%.1f"
)

threshold = st.sidebar.number_input(
    "Credibility threshold",
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

volume_period = st.number_input(
    "Number of procedures (preferably 3-year total)",
    min_value=1.0,
    value=50.0,
    step=0.1,
    format="%.1f"
)

crude_mortality_percent = st.number_input(
    "Observed crude mortality (%) (3-year period)",
    min_value=0.0,
    max_value=100.0,
    value=5.0,
    step=0.1,
    format="%.1f"
)

calculate = st.button("Calculate", type="primary")

# ============================================================
# CALCULATION
# ============================================================

if calculate:

    crude_mortality = crude_mortality_percent / 100
    estimated_deaths = round(volume_period * crude_mortality)

    a = m_prior * national_mortality
    b = m_prior * (1 - national_mortality)

    alpha_post = a + estimated_deaths
    beta_post = b + volume_period - estimated_deaths

    bayesian_adjusted_mortality = alpha_post / (alpha_post + beta_post)

    ccs = beta.cdf(benchmark, alpha_post, beta_post)

    ppm = 1 - beta.cdf(benchmark + delta, alpha_post, beta_post)

    db = benchmark - bayesian_adjusted_mortality

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
        f"Estimated deaths (from 3-year input): **{estimated_deaths}**"
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
        st.metric("Bayesian-adjusted mortality", f"{bayesian_adjusted_mortality * 100:.1f}%")
        st.metric("CCS", f"{ccs:.3f}")
        st.metric("PPM", f"{ppm:.3f}")

    with col2:
        st.metric("DB (pp)", f"{db * 100:.1f}")
        st.metric("CAS", f"{cas_percent:.2f}")
        st.metric("Benchmark", f"{benchmark * 100:.1f}%")

    st.subheader("Interpretation")

    st.markdown(
        f"""
- **CCS** = probability that true mortality is below {benchmark*100:.1f}%
- **PPM** = probability that true mortality exceeds {(benchmark+delta)*100:.1f}%
- **DB** = difference from benchmark (5% − adjusted mortality)
- **CAS** = credibility-weighted favorable signal

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
