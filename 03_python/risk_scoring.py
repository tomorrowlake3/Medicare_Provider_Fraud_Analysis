"""
================================================================================
Medicare Provider Fraud Risk Analysis — Virginia 2023
Specialty-Adjusted Anomaly Scoring
================================================================================
Author:   Tomorrow Lake
Source:   CMS Medicare Physician & Other Practitioners by Provider, CY2023
Input:    01_data/va_providers_2023_cleaned.csv  (31,662 providers, 35 columns)
Output:   03_python/va_providers_risk_scored.csv (25,239 providers, 33 columns)
================================================================================

METHODOLOGY
-----------
This script implements a peer-comparison anomaly detection approach for
identifying Medicare providers whose billing patterns deviate from their
specialty norms. The methodology was chosen for three reasons:

1. INTERPRETABILITY — Every flag can be explained: "this provider bills X
   times the median for their specialty on metric Y."

2. FAIRNESS — By comparing providers to their specialty peers (rather than
   the population), the method avoids penalizing specialties with naturally
   high billing intensity (oncology, rheumatology) for legitimate reasons.

3. ALIGNMENT WITH FEDERAL STANDARDS — The approach reflects the principles
   in the NIST AI Risk Management Framework: explainable, auditable, and
   amenable to disparate-impact testing.

PROCESS
-------
Step 1: Apply exclusion criteria
  - Drop providers with fewer than 50 beneficiaries (peer comparison less
    reliable for small practices).
  - Drop providers in specialties with fewer than 30 Virginia peers (no
    stable specialty median).

Step 2: Calculate specialty-level medians
  - For each specialty, compute the MEDIAN value of four fraud signals.
  - Median (rather than mean) is used because it is robust to the very
    outliers we are trying to detect.

Step 3: Compute peer-relative ratios
  - For each provider: (their_value) / (specialty_median).
  - A ratio of 2.0 means the provider's value is 2x their specialty median.

Step 4: Flag dimensional outliers
  - A provider is "flagged" on a dimension if their ratio exceeds 2.0.
  - Threshold of 2x was chosen as a defensible, interpretable cutoff
    approximately equivalent to the top 10-15% of one's specialty.

Step 5: Aggregate to risk score
  - Risk score = number of dimensions flagged (0 to 4).
  - Multiple-dimension flags indicate billing patterns unusual on
    several axes simultaneously, a stronger signal than any single
    extreme value.

THE FOUR FRAUD SIGNALS
----------------------
1. Avg_Pymt_Per_Srvc       — Per-service payment vs. specialty median
                              (signal for upcoding to higher-cost codes)
2. Srvcs_Per_Bene          — Services per patient vs. specialty median
                              (signal for over-servicing or phantom billing)
3. Pymt_Per_Bene           — Total payment per patient vs. specialty median
                              (composite signal combining the above)
4. Sbmt_to_Allwd_Ratio     — Submission aggression vs. specialty median
                              (signal for systematic claim denials or
                              broken billing software)

LIMITATIONS
-----------
- This is an UNSUPERVISED screening tool, not a determination of fraud.
  Flagged providers warrant further investigation, not adverse action.
- A 2x threshold is calibrated for screening; an audit shop might tune it
  higher (3x-5x) for prioritization with smaller investigator capacity.
- Some specialties (e.g., Clinical Laboratory) have business models that
  produce unusual patterns by design — should be evaluated separately.
- Ratios are sensitive to small denominators. The 50-beneficiary minimum
  helps but does not eliminate this concern.
================================================================================
"""

import pandas as pd
import numpy as np

# ============================================================================
# LOAD AND FILTER
# ============================================================================
df = pd.read_csv("01_data/va_providers_2023_cleaned.csv", low_memory=False)
print(f"Loaded {len(df):,} providers")

# Keep only specialties with adequate peer counts
specialty_counts = df['Rndrng_Prvdr_Type'].value_counts()
adequate_specialties = specialty_counts[specialty_counts >= 30].index.tolist()

# Apply both exclusion criteria
analysis_df = df[
    (df['Tot_Benes'] >= 50) & 
    (df['Rndrng_Prvdr_Type'].isin(adequate_specialties))
].copy()
print(f"After exclusions: {len(analysis_df):,} providers across "
      f"{len(adequate_specialties)} specialties")

# ============================================================================
# CALCULATE SPECIALTY MEDIANS
# ============================================================================
specialty_medians = analysis_df.groupby('Rndrng_Prvdr_Type').agg(
    med_pymt_per_srvc=('Avg_Pymt_Per_Srvc',  'median'),
    med_srvcs_per_bene=('Srvcs_Per_Bene',    'median'),
    med_pymt_per_bene=('Pymt_Per_Bene',      'median'),
    med_sbmt_ratio=('Sbmt_to_Allwd_Ratio',   'median'),
).reset_index()

analysis_df = analysis_df.merge(specialty_medians, 
                                 on='Rndrng_Prvdr_Type', how='left')

# ============================================================================
# CALCULATE PEER-RELATIVE RATIOS
# ============================================================================
analysis_df['ratio_pymt_per_srvc']  = (
    analysis_df['Avg_Pymt_Per_Srvc']    / analysis_df['med_pymt_per_srvc']
)
analysis_df['ratio_srvcs_per_bene'] = (
    analysis_df['Srvcs_Per_Bene']       / analysis_df['med_srvcs_per_bene']
)
analysis_df['ratio_pymt_per_bene']  = (
    analysis_df['Pymt_Per_Bene']        / analysis_df['med_pymt_per_bene']
)
analysis_df['ratio_sbmt_ratio']     = (
    analysis_df['Sbmt_to_Allwd_Ratio']  / analysis_df['med_sbmt_ratio']
)

# Remove infinities (would occur if specialty median was 0)
analysis_df = analysis_df.replace([np.inf, -np.inf], np.nan)

# ============================================================================
# FLAG OUTLIERS AND CALCULATE RISK SCORE
# ============================================================================
THRESHOLD = 2.0  # 2x specialty median = flagged

analysis_df['flag_pymt_per_srvc']  = (
    analysis_df['ratio_pymt_per_srvc']  > THRESHOLD
).astype(int)
analysis_df['flag_srvcs_per_bene'] = (
    analysis_df['ratio_srvcs_per_bene'] > THRESHOLD
).astype(int)
analysis_df['flag_pymt_per_bene']  = (
    analysis_df['ratio_pymt_per_bene']  > THRESHOLD
).astype(int)
analysis_df['flag_sbmt_ratio']     = (
    analysis_df['ratio_sbmt_ratio']     > THRESHOLD
).astype(int)

analysis_df['risk_flag_count'] = (
    analysis_df['flag_pymt_per_srvc']  + 
    analysis_df['flag_srvcs_per_bene'] + 
    analysis_df['flag_pymt_per_bene']  + 
    analysis_df['flag_sbmt_ratio']
)

def risk_category(n):
    return ['0 - Low', '1 - Moderate', '2 - Elevated', 
            '3 - High', '4 - Critical'][n]

analysis_df['Risk_Category'] = analysis_df['risk_flag_count'].apply(risk_category)

# ============================================================================
# BUILD FRIENDLY PROVIDER NAME FOR TABLEAU
# ============================================================================
analysis_df['Provider_Name'] = analysis_df.apply(
    lambda r: f"{r['Rndrng_Prvdr_Last_Org_Name']}, {r['Rndrng_Prvdr_First_Name']}" 
              if pd.notna(r['Rndrng_Prvdr_First_Name']) 
              else r['Rndrng_Prvdr_Last_Org_Name'],
    axis=1
)

# ============================================================================
# REPORT
# ============================================================================
print("\nRISK FLAG DISTRIBUTION:")
print(f"{'Flags':<8}{'Risk Level':<18}{'Providers':>12}{'$ Payments':>15}")
print("-"*53)
for n_flags in sorted(analysis_df['risk_flag_count'].unique()):
    subset = analysis_df[analysis_df['risk_flag_count'] == n_flags]
    n     = len(subset)
    cat   = risk_category(n_flags)
    pmts  = subset['Tot_Mdcr_Pymt_Amt'].sum()
    print(f"{n_flags:<8}{cat:<18}{n:>12,}{pmts/1e6:>13.1f}M")

# ============================================================================
# SAVE
# ============================================================================
final_cols = [
    'Rndrng_NPI', 'Provider_Name', 'Rndrng_Prvdr_Type', 'Rndrng_Prvdr_Crdntls',
    'Rndrng_Prvdr_City', 'Rndrng_Prvdr_State_Abrvtn', 'Rndrng_Prvdr_Zip5',
    'Tot_Benes', 'Tot_Srvcs', 'Tot_HCPCS_Cds',
    'Tot_Mdcr_Pymt_Amt', 'Tot_Sbmtd_Chrg', 'Tot_Mdcr_Alowd_Amt',
    'Avg_Pymt_Per_Srvc', 'Srvcs_Per_Bene', 'Pymt_Per_Bene', 'Sbmt_to_Allwd_Ratio',
    'med_pymt_per_srvc', 'med_srvcs_per_bene', 
    'med_pymt_per_bene', 'med_sbmt_ratio',
    'ratio_pymt_per_srvc', 'ratio_srvcs_per_bene', 
    'ratio_pymt_per_bene', 'ratio_sbmt_ratio',
    'flag_pymt_per_srvc', 'flag_srvcs_per_bene', 
    'flag_pymt_per_bene', 'flag_sbmt_ratio',
    'risk_flag_count', 'Risk_Category',
    'Bene_Avg_Age', 'Bene_Avg_Risk_Scre',
]

final = analysis_df[final_cols].copy()
final.to_csv("03_python/va_providers_risk_scored.csv", index=False)
print(f"\nSaved: 03_python/va_providers_risk_scored.csv "
      f"({len(final):,} providers × {len(final.columns)} columns)")
