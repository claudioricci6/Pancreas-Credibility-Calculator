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
st.caption("A credibility-based benchmarking tool for pancreatic surgery outcomes")

st.markdown(
    """
This tool estimates whether a center's observed pancreatic surgery mortality is
**credibly below**, **indeterminate**, or **credibly above** a predefined mortality benchmark.
"""
)

st.sidebar.header("Model settings")

benchmark = st.sidebar.number_input(
    "Fixed mortality benchmark (%)",
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
    "Observed national mortality used for prior (%)",
    min_value=0.1,
    max_value=50.0,
    value=8.2,
    step=0.1,
    format="%.1f"
) / 100

m_prior = st.sidebar.number_input(
    "Prior effective sample size",
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

st.header("Center input")

volume_period = st.number_input(
    "Number of procedures",
    min_value=1.0,
    value=50.0,
    step=0.1,
    format="%.1f"
)

crude_mortality_percent = st.number_input(
    "Observed crude mortality (%)",
    min_value=0.0,
    max_value=100.0,
    value=5.0,
    step=0.1,
    format="%.1f"
)

crude_mortality = crude_mortality_percent / 100
estimated_deaths = round(volume_period * crude_mortality)

st.info(
    f"Estimated deaths used in the model: **{estimated_deaths}** "
    f"from {volume_period:.1f} procedures."
)

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

if ccs >= threshold:
    classification = "Credibly better than benchmark"
elif ppm >= threshold:
    classification = "Credibly worse than threshold"
else:
    classification = "Indeterminate"

st.header("Classification")

if classification == "Credibly better than benchmark":
    st.success(classification)
elif classification == "Credibly worse than threshold":
    st.error(classification)
else:
    st.warning(classification)

st.header("Results")

col1, col2 = st.columns(2)

with col1:
    st.metric(
        "Bayesian-adjusted mortality",
        f"{bayesian_adjusted_mortality * 100:.1f}%"
    )
    st.metric(
        "CCS",
        f"{ccs:.3f}"
    )
    st.metric(
        "PPM",
        f"{ppm:.3f}"
    )

with col2:
    st.metric(
        "Difference from benchmark",
        f"{db * 100:.1f} pp"
    )
    st.metric(
        "Credible Advantage Signal",
        f"{cas_percent:.2f}"
    )
    st.metric(
        "Benchmark",
        f"{benchmark * 100:.1f}%"
    )

results = pd.DataFrame(
    {
        "Metric": [
            "Bayesian-adjusted mortality",
            "Center Credibility Score (CCS)",
            "Posterior Probability of Mortality > threshold (PPM)",
            "Difference from Benchmark (DB)",
            "Credible Advantage Signal (CAS)",
            "Classification",
        ],
        "Value": [
            f"{bayesian_adjusted_mortality * 100:.1f}%",
            f"{ccs:.3f}",
            f"{ppm:.3f}",
            f"{db * 100:.1f} percentage points",
            f"{cas_percent:.2f}",
            classification,
        ],
    }
)

st.table(results)

st.header("How to interpret the metrics")

st.markdown(
    f"""
**CCS** is the probability that the center's true mortality is below the fixed benchmark of **{benchmark * 100:.1f}%**.

- CCS ≥ {threshold:.2f}: credibly below benchmark
- CCS < {threshold:.2f}: not enough credibility to be considered better

**PPM** is the probability that the center's true mortality exceeds **{(benchmark + delta) * 100:.1f}%**.

- PPM ≥ {threshold:.2f}: credibly worse than threshold
- PPM < {threshold:.2f}: not enough credibility to be considered worse

**DB** is the difference from benchmark:

`DB = benchmark - Bayesian-adjusted mortality`

- positive DB: mortality below benchmark
- negative DB: mortality above benchmark

**CAS** is the Credible Advantage Signal:

`CAS = CCS × max(0, DB)`

CAS combines **credibility** and **magnitude of advantage**.  
A CAS of 0 means that there is no credible favorable advantage over the benchmark.  
Higher CAS values indicate a stronger favorable signal.
"""
)

st.header("Plain-language interpretation")

if classification == "Credibly better than benchmark":
    st.success(
        f"The center has at least {threshold * 100:.0f}% posterior probability "
        f"of being below the {benchmark * 100:.1f}% benchmark."
    )
elif classification == "Credibly worse than threshold":
    st.error(
        f"The center has at least {threshold * 100:.0f}% posterior probability "
        f"of exceeding the {(benchmark + delta) * 100:.1f}% underperformance threshold."
    )
else:
    st.warning(
        "The available data do not provide enough posterior evidence to classify "
        "the center as either credibly better or credibly worse."
    )

st.divider()

st.caption(
    "Model developed from the Italian National Outcomes Program (PNE) pancreatic surgery dataset. "
    "All rights reserved © Prof. Claudio Ricci, University of Bologna."
)

st.caption(
    "This calculator is intended for research and methodological use only. "
    "It does not perform patient-level case-mix adjustment and should not be used as a standalone clinical quality assessment tool."
)
