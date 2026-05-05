Medicare Provider Fraud Risk Analysis | Virginia 2023
A federal data science portfolio project applying specialty-adjusted peer-comparison anomaly detection to public CMS Medicare claims data. The goal: identify a small, high-priority audit population of providers whose billing patterns deviate substantially from specialty norms.
🔴 Live Interactive Dashboard
📄 Executive Memo (PDF)
---
Recommendation
Initiate review of 155 High and Critical risk providers, prioritized by total Medicare payments. This 0.6% of the analyzed population represents $108 million in 2023 Medicare disbursements and was flagged on three or more independent billing-pattern dimensions versus specialty peers. The top 15 of these providers alone account for $53.6 million.
---
Headline Numbers
Metric	Value
Providers analyzed	25,239
Total Medicare payments (VA, 2023)	$3.03 billion
Top 1% of providers capture	28.6% of payments
Top 5% of providers capture	48.7% of payments
High / Critical risk providers	155 (0.6%)
Payments flowing to High / Critical providers	$108 million
Top 15 high-risk providers represent	$53.6 million
---
Methodology
The analysis uses a specialty-adjusted peer-comparison approach rather than a black-box machine learning model. The choice was deliberate: detection systems used in regulated federal contexts must be explainable, auditable, and amenable to disparate-impact testing, consistent with the NIST AI Risk Management Framework.
For each provider, four billing-pattern metrics are compared to the median for their specialty:
Average payment per service (signal for upcoding)
Services per beneficiary (signal for over-servicing)
Total payment per beneficiary (composite signal)
Submission-to-allowed ratio (signal for aggressive billing)
A provider is flagged on a metric if their value exceeds 2x the specialty median. Risk score = total flag count (0 to 4). Providers flagged on 3+ dimensions are classified as High or Critical risk.
This produces a screening tool, not a determination of fraud. Flagged providers warrant further investigation, not adverse action.
---
Why peer comparison matters
A naive (specialty-blind) outlier detection method flags oncologists, rheumatologists, and other infusion-heavy specialties as suspicious because they bill at high intensity by design. Specialty-adjusted scoring removes this noise:
Rheumatology median: 118 services per beneficiary
Emergency Medicine median: 1.6 services per beneficiary
Ambulatory Surgical Center median payment per service: $885
Diagnostic Radiology median payment per service: $33
Without peer adjustment, these specialties would dominate any "top outlier" list. With it, flagged providers spread across 15+ specialties, and the methodology surfaces real deviations from peer norms.
---
Repository Contents
```
Medicare_Provider_Fraud_Analysis/
├── 01_data/
│   └── va_providers_2023_cleaned.csv   (31,662 VA providers, 35 columns)
├── 02_sql/
│   ├── exploratory_queries.sql         (6 documented analytical queries)
│   └── va_medicare.db                   (SQLite database for re-analysis)
├── 03_python/
│   ├── risk_scoring.py                  (specialty-adjusted scoring methodology)
│   └── va_providers_risk_scored.csv    (25,239 scored providers, Tableau-ready)
├── 04_tableau/
│   └── medicare_dashboard.twbx          (packaged Tableau workbook)
├── 05_deliverables/
│   ├── executive_memo.pdf               (2-page leadership summary)
│   └── executive_memo.docx              (editable version)
└── README.md
```
---
Data Source
CMS Medicare Physician & Other Practitioners - by Provider, calendar year 2023. Public-use file from data.cms.gov. Filtered to Virginia (state code VA) at the data-cleaning step.
Dataset documentation
---
Tools Used
Stage	Tool
Data cleaning and feature engineering	Python (pandas, numpy)
Exploratory analysis	SQL (SQLite)
Anomaly scoring	Python
Visualization	Tableau Public
Reporting	Microsoft Word, PDF
---
Limitations and Caveats
This is an unsupervised screening tool. Flagged providers warrant further investigation, not adverse action.
The 2x specialty-median threshold is defensible but not unique. Tuning it tighter reduces investigator workload but lets more fraud through; loosening it captures more fraud but increases false positives. The trade-off should be made explicit and revisited periodically.
Some specialties (e.g., Clinical Laboratory) operate under business models that produce statistically unusual patterns by design and should be evaluated separately.
The 50-beneficiary minimum applied during analysis reduces but does not eliminate small-sample sensitivity.
---
Companion Materials
This project is paired with a research-backed paper, Anomaly Detection at Scale: Methods and Trade-offs for Identifying Improper Payments in Federal Programs, which surveys the academic and federal literature on improper payment detection and discusses the false-positive problem and its distributional consequences.
---
Author
Tomorrow Lake | Data Scientist
GitHub @tomorrowlake3
