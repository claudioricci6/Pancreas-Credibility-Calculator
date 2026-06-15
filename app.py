import numpy as np
import pandas as pd
import streamlit as st
from scipy.stats import beta


st.set_page_config(
    page_title="Pancreas Credibility Calculator",
    page_icon="🧮",
    layout="centered"
)

st.title("Pancreas Credibility Calculator")
st.caption("Credibility-based benchmarking for pancreatic surgery outcomes")

st.markdown(
    """
This calculator estimates center-level mortality credibility using a beta-binomial framework.
It requires only center volume and crude mortality.
"""
)

st.sidebar.header("Model settings")

benchmark = st.sidebar.number_input(
    "Fixed mortality benchmark (%)",
    min_value=0.1,
    max_value=50.0,
    value=5.0,
    step=0.1
) / 100

delta = st.sidebar.number_input(
    "Underperformance margin (%)",
    min_value=0.1,
    max_value=20.0,
    value=1.0,
    step=0.1
) / 100

national_mortality = st.sidebar.number_input(
    "Observed national mortality used for prior (%)",
    min_value=0.1,
    max_value=50.0,
    value=8.2,
    step=0.1
) / 100

m_prior = st.sidebar.number_input(
    "Prior effective sample size",
    min_value=1,
    max_value=500,
    value=25,
    step=1
)

threshold = st.sidebar.number_input(
    "Credibility threshold",
    min_value=0.50,
    max_value=0.99,
    value=0.80,
    step=0.01
)

st.header("Center input")

volume_period = st.number_input(
    "Number of procedures",
    min_value=1,
    value=50,
    step=1
)

crude_mortality_percent = st.number_input(
    "Observed crude mortality (%)",
    min_value=0.0,
    max_value=100.0,
    value=5.0,
    step=0.1
)

crude_mortality = crude_mortality_percent / 100

estimated_deaths = round(volume_period * crude_mortality)

st.markdown(f"Estimated deaths used in the model: **{estimated_deaths}**")

a = m_prior * national_mortality
b = m_prior * (1 - national_mortality)

alpha_post = a + estimated_deaths
beta_post = b + volume_period - estimated_deaths

bayesian_adjusted_mortality = alpha_post / (alpha_post + beta_post)

ccs = beta.cdf(benchmark, alpha_post, beta_post)

ppm = 1 - beta.cdf(benchmark + delta, alpha_post, beta_post)

db = benchmark - bayesian_adjusted_mortality

cas = ccs * max(0, db)

if ccs >= threshold:
    classification = "Credibly better than benchmark"
elif ppm >= threshold:
    classification = "Credibly worse than threshold"
else:
    classification = "Indeterminate"

st.header("Results")

results = pd.DataFrame(
    {
        "Metric": [
            "Bayesian-adjusted mortality",
            "Center Credibility Score (CCS)",
            "Posterior probability of mortality > threshold (PPM)",
            "Difference from benchmark (DB)",
            "Credible Advantage Signal (CAS)",
            "Classification",
        ],
        "Value": [
            f"{bayesian_adjusted_mortality * 100:.2f}%",
            f"{ccs:.3f}",
            f"{ppm:.3f}",
            f"{db * 100:.2f} percentage points",
            f"{cas * 100:.3f}",
            classification,
        ],
    }
)

st.table(results)

st.header("Interpretation")

st.markdown(
    f"""
- **CCS** is the posterior probability that true mortality is below **{benchmark * 100:.1f}%**.
- **PPM** is the posterior probability that true mortality exceeds **{(benchmark + delta) * 100:.1f}%**.
- **DB** is benchmark minus Bayesian-adjusted mortality.
- **CAS** combines credibility and favorable difference from benchmark.
"""
)

if classification == "Credibly better than benchmark":
    st.success(
        "This center has sufficient posterior credibility of being below the benchmark."
    )
elif classification == "Credibly worse than threshold":
    st.error(
        "This center has sufficient posterior probability of exceeding the underperformance threshold."
    )
else:
    st.warning(
        "This center does not meet the predefined credibility threshold for better or worse classification."
    )

st.divider()

st.caption(
    "This calculator is intended for methodological and research use. "
    "It does not perform patient-level case-mix adjustment."
)
