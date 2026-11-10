"""Figures 1-3 and S1-S2 (rev01) — Python/matplotlib reproduction of the ggplot style used at submission."""
import numpy as np, pandas as pd, matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.legend
from matplotlib.lines import Line2D
from matplotlib.ticker import FuncFormatter

d = pd.read_csv('fig_data_rev01.csv')
OUT = './'
import os; os.makedirs(OUT, exist_ok=True)
P0, PNAT = 5.0, 8.16
RED, GREEN, BLUE = '#F8766D', '#00BA38', '#619CFF'
plt.rcParams.update({'font.family': 'DejaVu Sans', 'font.size': 15, 'axes.titlesize': 15,
                     'axes.labelsize': 17, 'xtick.labelsize': 14, 'ytick.labelsize': 14,
                     'legend.fontsize': 14, 'legend.title_fontsize': 16})

def style(ax):
    ax.set_facecolor('white')
    ax.grid(True, color='#EBEBEB', lw=1.0); ax.grid(True, which='minor', color='#F5F5F5', lw=0.6)
    for s in ax.spines.values(): s.set_visible(False)
    ax.tick_params(length=0)
    ax.set_axisbelow(True)

def save(fig, name, tiff=True):
    extra = [c for a in fig.axes for c in a.get_children() if isinstance(c, matplotlib.legend.Legend)]
    fig.savefig(OUT + name + '.pdf', bbox_inches='tight', bbox_extra_artists=extra)
    if tiff:
        fig.savefig(OUT + name + '.tiff', dpi=600, bbox_inches='tight', bbox_extra_artists=extra, pil_kwargs={'compression': 'tiff_lzw'})
    plt.close(fig)

# size legend helper (area proportional to 3-year volume, as ggplot scale_size)
SMIN, SMAX = 25, 420
nmin, nmax = d.n.min(), d.n.max()
def size(n): return SMIN + (SMAX - SMIN) * (np.sqrt(n) - np.sqrt(nmin)) / (np.sqrt(nmax) - np.sqrt(nmin))
def size_handles():
    return [plt.scatter([], [], s=size(v), color='black') for v in (200, 400, 600, 800)], ['200', '400', '600', '800']

# ---------------- Figure 1: crude mortality vs volume, colour = CCS
fig, ax = plt.subplots(figsize=(13, 8))
style(ax)
sc = ax.scatter(d.n, d.perc_grezza_prop * 100, c=d.ccs_mid, cmap='plasma', vmin=0, vmax=1 / 0.95 * 0.95, s=70, alpha=0.9, lw=0)
sc.set_clim(0, 1)
ax.axhline(P0, ls=(0, (6, 4)), color='black', lw=2.2)
ax.axhline(PNAT, ls=(0, (1, 3)), color='black', lw=2.2)
ax.set_xscale('log'); ax.set_xlim(0.8, 1100)
ax.set_xticks([1, 10, 100, 1000]); ax.set_xticklabels(['1', '10', '100', '1000'])
ax.set_yticks([0, 25, 50, 75, 100])
ax.set_xlabel('Number of procedures during the observation period (three years), log10 scale')
ax.set_ylabel('Crude 90-day mortality (%)')
cb = fig.colorbar(sc, ax=ax, fraction=0.04, pad=0.03, ticks=[0.25, 0.5, 0.75])
cb.ax.set_yticklabels(['25%', '50%', '75%']); cb.outline.set_visible(False); cb.ax.set_title('CCS', fontsize=16, pad=12)
save(fig, 'Figure_1_rev01')

# ---------------- Figure 2: CCS vs DB, colour = interpretation, size = volume
fig, ax = plt.subplots(figsize=(13, 8))
style(ax)
cmap = {'Substantial favorable signal': RED, 'Weak evidence / not interpretable': GREEN, 'Worse than 6% threshold': BLUE}
for k, col in cmap.items():
    s = d[d.dilution_flag == k]
    ax.scatter(s.advantage_post_mid * 100, s.ccs_mid, s=size(s.n), color=col, alpha=0.85, lw=0)
ax.axvline(1, ls=(0, (6, 4)), color='black', lw=2.2)
ax.axhline(0.8, ls=(0, (6, 4)), color='black', lw=2.2)
ax.set_xlabel('DB (percentage points)'); ax.set_ylabel('CCS')
ax.set_yticks([0, 0.25, 0.5, 0.75, 1.0]); ax.set_yticklabels(['0.00', '0.25', '0.50', '0.75', '1.00'])
h1 = [Line2D([], [], marker='o', ls='', color=c, ms=10) for c in cmap.values()]
l1 = ax.legend(h1, list(cmap.keys()), title='Interpretation', loc='upper left', bbox_to_anchor=(1.02, 1.0), frameon=False, alignment='left')
ax.add_artist(l1)
hs, ls_ = size_handles()
ax.legend(hs, ls_, title='Volume during three years', loc='upper left', bbox_to_anchor=(1.02, 0.55), frameon=False, labelspacing=1.4, alignment='left')
save(fig, 'Figure_2_rev01')

# ---------------- Figure 3: CCS vs risk-adjusted mortality (44 centres)
a = d[d.perc_adj_prop.notna()]
fig, ax = plt.subplots(figsize=(13, 8))
style(ax)
cmap3 = {'Better than 5% benchmark': RED, 'Indeterminate': GREEN, 'Worse than 6% threshold': BLUE}
for k, col in cmap3.items():
    s = a[a.class_primary == k]
    ax.scatter(s.perc_adj_prop * 100, s.ccs_mid, s=size(s.n), color=col, alpha=0.85, lw=0)
ax.axvline(P0, ls=(0, (6, 4)), color='black', lw=2.2)
ax.axvline(PNAT, ls=(0, (1, 3)), color='black', lw=2.2)
ax.set_xlabel('Risk-adjusted PNE 90-day mortality (%)'); ax.set_ylabel('CCS')
ax.set_yticks([0, 0.25, 0.5, 0.75, 1.0]); ax.set_yticklabels(['0.00', '0.25', '0.50', '0.75', '1.00'])
h1 = [Line2D([], [], marker='o', ls='', color=c, ms=10) for c in cmap3.values()]
l1 = ax.legend(h1, ['Better than 5% benchmark', 'Indeterminate', 'Worse than 6% threshold'], title='Primary classification',
               loc='upper left', bbox_to_anchor=(1.02, 1.0), frameon=False, alignment='left')
ax.add_artist(l1)
hs, ls_ = size_handles()
ax.legend(hs, ls_, title='Volume during three years', loc='upper left', bbox_to_anchor=(1.02, 0.55), frameon=False, labelspacing=1.4, alignment='left')
save(fig, 'Figure_3_rev01')

# ---------------- Figure S1: posterior mean and 95% CrI, ordered
s = d.sort_values('post_mean_mid').reset_index(drop=True)
fig, ax = plt.subplots(figsize=(13, 8))
style(ax)
ax.vlines(s.index + 1, s.ci_low_min, s.ci_high_max, color='grey', alpha=0.5, lw=1)
sc = ax.scatter(s.index + 1, s.post_mean_mid, c=s.n, cmap='plasma', vmax=s.n.max() / 0.95, s=28, lw=0, zorder=3)
ax.axhline(P0 / 100, ls=(0, (6, 4)), color='black', lw=2); ax.axhline(PNAT / 100, ls=(0, (1, 3)), color='black', lw=2)
ax.yaxis.set_major_formatter(FuncFormatter(lambda v, _: f'{v * 100:.1f}%'))
ax.set_xlabel('Centers ordered by Bayesian-smoothed mortality'); ax.set_ylabel('Bayesian-smoothed 90-day mortality')
ax.set_title('Figure S1. Bayesian-smoothed 90-day mortality and 95% credible intervals\nDashed line = 5% benchmark; dotted line = observed national 90-day mortality', loc='left', fontsize=14)
cb = fig.colorbar(sc, ax=ax, fraction=0.04, pad=0.03); cb.outline.set_visible(False); cb.ax.set_title('Volume during\nthree years', fontsize=13, pad=10)
save(fig, 'ESM_3_Figure_S1_rev01', tiff=False)

# ---------------- Figure S2: CAS vs volume
fig, ax = plt.subplots(figsize=(13, 8))
style(ax)
for k, col in cmap.items():
    t = d[d.dilution_flag == k]
    ax.scatter(t.n, t.signal_strength * 100, color=col, s=70, alpha=0.85, lw=0, label=k)
ax.set_xscale('log'); ax.set_xticks([1, 10, 100, 1000]); ax.set_xticklabels(['1', '10', '100', '1000'])
ax.set_xlabel('Number of procedures during three years, log10 scale'); ax.set_ylabel('CAS')
ax.set_title('Figure S2. Credible Advantage Signal (CAS) across centers', loc='left', fontsize=14)
ax.legend(title='Interpretation', loc='upper left', bbox_to_anchor=(1.02, 1.0), frameon=False, alignment='left')
save(fig, 'ESM_4_Figure_S2_rev01', tiff=False)
print('ok')
