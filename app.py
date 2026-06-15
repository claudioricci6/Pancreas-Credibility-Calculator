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
Enter center volume and crude mortality to estimate credibility of performance
against a fixed mortality benchmark.
"""
)

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
    "National mortality prior (%)",
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

st.sidebar.caption(
    "Default settings were validated using Italian PNE pancreatic resection data, 2022–2024. "
    "The default national mortality prior is 8.2%."
)

st.header("Center input")

volume_period = st.number_input(
    "Number of procedures",
    min_value=0.0,
    value=None,
    step=0.1,
    format="%.1f",
    placeholder="Enter number of procedures"
)

crude_mortality_percent = st.number_input(
    "Observed crude mortality (%)",
    min_value=0.0,
    max_value=100.0,
    value=None,
    step=0.1,
    format="%.1f",
    placeholder="Enter crude mortality"
)

calculate = st.button("Calculate", type="primary")

if calculate:
    if volume_period is None or crude_mortality_percent is None:
        st.error("Please enter both number of procedures and crude mortality.")
        st.stop()

    if volume_period <= 0:
        st.error("Number of procedures must be greater than 0.")
        st.stop()

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

    if ccs >= threshold:
        classification = "Credibly better than benchmark"
        classification_type = "success"
    elif ppm >= threshold:
        classification = "Credibly worse than threshold"
        classification_type = "error"
    else:
        classification = "Indeterminate"
        classification_type = "warning"

    st.info(
        f"Estimated deaths used in the model: **{estimated_deaths}** "
        f"from {volume_period:.1f} procedures."
    )

    st.header("Classification")

    if classification_type == "success":
        st.success(classification)
    elif classification_type == "error":
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
        st.metric("DB", f"{db * 100:.1f} pp")
        st.metric("CAS", f"{cas_percent:.2f}")
        st.metric("Benchmark", f"{benchmark * 100:.1f}%")

    results = pd.DataFrame(
        {
            "Metric": [
                "Bayesian-adjusted mortality",
                "CCS",
                "PPM",
                "DB",
                "CAS",
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

    st.subheader("Metric guide")

    st.markdown(
        f"""
**CCS**: probability that true mortality is below **{benchmark * 100:.1f}%**.  
**PPM**: probability that true mortality exceeds **{(benchmark + delta) * 100:.1f}%**.  
**DB**: benchmark minus Bayesian-adjusted mortality. Positive values favor the center.  
**CAS**: CCS × max(0, DB), expressed in percentage-point units.

**CAS interpretation:** 0 = no favorable credible advantage; <1 = weak or marginal signal; ≥1 = substantial credible favorable signal.
"""
    )

    st.subheader("Plain-language interpretation")

    if classification_type == "success":
        st.success(
            f"The center has at least {threshold * 100:.0f}% posterior probability "
            f"of being below the {benchmark * 100:.1f}% benchmark."
        )
    elif classification_type == "error":
        st.error(
            f"The center has at least {threshold * 100:.0f}% posterior probability "
            f"of exceeding the {(benchmark + delta) * 100:.1f}% threshold."
        )
    else:
        st.warning(
            "The data do not provide enough posterior evidence to classify the center "
            "as credibly better or credibly worse."
        )

st.divider()

st.caption(
    "Default settings can be modified by the user. The default configuration was developed "
    "and validated using the Italian National Outcomes Program (PNE) pancreatic resection dataset, "
    "2022–2024. The national mortality prior default of 8.2% corresponds to the observed Italian "
    "national 90-day mortality in that dataset."
)

st.caption(
    "Research use only. This calculator does not perform patient-level case-mix adjustment."
)

st.caption(
    "All rights reserved © Prof. Claudio Ricci, University of Bologna."
)
