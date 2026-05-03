-- ==========================================================================
-- Medicare Provider Fraud Risk Analysis — Virginia 2023
-- Exploratory SQL Queries
-- Author: Tomorrow Lake
-- Data Source: CMS Medicare Physician & Other Practitioners by Provider, CY2023
-- ==========================================================================
-- Database: va_medicare.db
-- Table:    providers (31,662 rows × 35 columns)
-- ==========================================================================


-- ==========================================================================
-- Q1: Statewide overview — the headline numbers
-- ==========================================================================
-- Purpose: Establish the scale of Virginia's Medicare program.
-- Result:  $3.03B in payments, 31,662 providers, 10.7M beneficiary
--          relationships, average patient risk score 1.43 (43% sicker
--          than national Medicare average of 1.0).

SELECT 
    COUNT(*) AS total_providers,
    SUM(Tot_Benes) AS total_beneficiary_relationships,
    ROUND(SUM(Tot_Mdcr_Pymt_Amt) / 1000000.0, 1) AS total_payments_millions,
    ROUND(SUM(Tot_Sbmtd_Chrg) / 1000000.0, 1) AS total_submitted_millions,
    ROUND(AVG(Tot_Mdcr_Pymt_Amt), 0) AS avg_payment_per_provider,
    ROUND(AVG(Bene_Avg_Risk_Scre), 2) AS avg_patient_risk_score
FROM providers;


-- ==========================================================================
-- Q2: Payment concentration — who captures the most?
-- ==========================================================================
-- Purpose: Quantify how concentrated Medicare payments are among providers.
--          This finding drives audit-prioritization strategy.
-- Result:  The top 1% (317 providers) captures 28.6% of all VA Medicare $.
--          The top 5% captures 48.7%. The bottom 50% shares 7.1%.
-- Implication: A risk-scoring system focused on the top 5% of providers
--              addresses nearly half of total Medicare spend in the state.

WITH ranked AS (
    SELECT 
        Tot_Mdcr_Pymt_Amt,
        NTILE(100) OVER (ORDER BY Tot_Mdcr_Pymt_Amt DESC) AS percentile
    FROM providers
)
SELECT
    CASE 
        WHEN percentile = 1 THEN 'Top 1%'
        WHEN percentile <= 5 THEN 'Top 2-5%'
        WHEN percentile <= 10 THEN 'Top 6-10%'
        WHEN percentile <= 25 THEN 'Top 11-25%'
        WHEN percentile <= 50 THEN 'Top 26-50%'
        ELSE 'Bottom 50%'
    END AS provider_tier,
    COUNT(*) AS provider_count,
    ROUND(SUM(Tot_Mdcr_Pymt_Amt) / 1000000.0, 1) AS total_payments_millions,
    ROUND(100.0 * SUM(Tot_Mdcr_Pymt_Amt) / 
          (SELECT SUM(Tot_Mdcr_Pymt_Amt) FROM providers), 1) AS pct_of_total
FROM ranked
GROUP BY provider_tier
ORDER BY 
    CASE provider_tier
        WHEN 'Top 1%' THEN 1
        WHEN 'Top 2-5%' THEN 2
        WHEN 'Top 6-10%' THEN 3
        WHEN 'Top 11-25%' THEN 4
        WHEN 'Top 26-50%' THEN 5
        ELSE 6
    END;


-- ==========================================================================
-- Q3: Top specialties by total payments and key billing metrics
-- ==========================================================================
-- Purpose: Demonstrate why specialty-adjusted peer comparison is necessary.
--          Compare billing intensity across specialties.
-- Result:  Specialties differ by orders of magnitude in legitimate billing
--          patterns: Ambulatory Surgery Centers average $885/service vs.
--          Diagnostic Radiology at $33/service. Rheumatology averages 118
--          services per beneficiary vs. Emergency Medicine at 1.6.
-- Implication: Naive outlier detection would generate massive false
--              positives. Peer comparison MUST be specialty-adjusted.

SELECT 
    Rndrng_Prvdr_Type AS specialty,
    COUNT(*) AS provider_count,
    ROUND(SUM(Tot_Mdcr_Pymt_Amt) / 1000000.0, 1) AS total_payments_M,
    ROUND(AVG(Tot_Mdcr_Pymt_Amt), 0) AS avg_payment,
    ROUND(AVG(Avg_Pymt_Per_Srvc), 2) AS avg_payment_per_service,
    ROUND(AVG(Srvcs_Per_Bene), 2) AS avg_services_per_bene,
    ROUND(AVG(Sbmt_to_Allwd_Ratio), 2) AS avg_submission_ratio
FROM providers
GROUP BY Rndrng_Prvdr_Type
HAVING COUNT(*) >= 50
ORDER BY total_payments_M DESC
LIMIT 20;


-- ==========================================================================
-- Q4: Geographic concentration — top cities by Medicare payments
-- ==========================================================================
-- Purpose: Identify where Virginia's Medicare spending is concentrated.
-- Result:  Richmond leads at 10.1% of state payments ($305M, 3,201 prov.).
--          Top 8 cities account for ~42% of all VA Medicare payments.
--          Williamsburg shows highest avg payment per provider ($163K),
--          likely reflecting older patient population and concentrated
--          specialty practices.

SELECT 
    Rndrng_Prvdr_City AS city,
    COUNT(*) AS provider_count,
    ROUND(SUM(Tot_Mdcr_Pymt_Amt) / 1000000.0, 1) AS total_payments_M,
    ROUND(AVG(Tot_Mdcr_Pymt_Amt), 0) AS avg_payment_per_provider,
    ROUND(100.0 * SUM(Tot_Mdcr_Pymt_Amt) / 
          (SELECT SUM(Tot_Mdcr_Pymt_Amt) FROM providers), 1) AS pct_of_state_payments
FROM providers
GROUP BY Rndrng_Prvdr_City
HAVING COUNT(*) >= 100
ORDER BY total_payments_M DESC
LIMIT 15;


-- ==========================================================================
-- Q5: Providers with extreme billing patterns (unadjusted view)
-- ==========================================================================
-- Purpose: Surface the providers most extreme on raw thresholds. This is
--          a DELIBERATE first pass — the methodological point is that most
--          of these are NOT fraud signals once specialty is accounted for.
-- Result:  15 of 20 raw outliers are oncology/rheumatology providers
--          delivering legitimate infusion-based care. Day 3 specialty-
--          adjusted scoring will distinguish signal from noise.
-- Implication: Reinforces NIST AI RMF guidance on disparate-impact testing
--              and the need for explainable, peer-aware models.

SELECT 
    Rndrng_Prvdr_Last_Org_Name AS provider,
    Rndrng_Prvdr_Type AS specialty,
    Rndrng_Prvdr_City AS city,
    Tot_Benes AS beneficiaries,
    Tot_Srvcs AS services,
    ROUND(Tot_Mdcr_Pymt_Amt, 0) AS total_payments,
    ROUND(Avg_Pymt_Per_Srvc, 2) AS pymt_per_srvc,
    ROUND(Srvcs_Per_Bene, 2) AS srvcs_per_bene,
    ROUND(Sbmt_to_Allwd_Ratio, 2) AS submission_ratio
FROM providers
WHERE 
    Tot_Mdcr_Pymt_Amt > 100000
    AND (
        Avg_Pymt_Per_Srvc > 1000
        OR Srvcs_Per_Bene > 100
        OR Sbmt_to_Allwd_Ratio > 15
    )
ORDER BY Tot_Mdcr_Pymt_Amt DESC
LIMIT 20;


-- ==========================================================================
-- Q6: Data quality — defining the analysis-ready population for Day 3
-- ==========================================================================
-- Purpose: Establish exclusion criteria for specialty-adjusted peer
--          comparison. Smaller providers and tiny specialty groups produce
--          unreliable per-provider statistics.
-- Result:  25,446 providers (80.4%) have >=50 beneficiaries — the threshold
--          for stable peer comparison. 309 providers belong to specialty
--          groups with fewer than 30 VA peers and will be flagged but not
--          scored. Zero missing values in any key metric.

SELECT 'All providers' AS category, COUNT(*) AS n FROM providers
UNION ALL
SELECT 'Provider type missing', COUNT(*) FROM providers 
    WHERE Rndrng_Prvdr_Type IS NULL OR Rndrng_Prvdr_Type = ''
UNION ALL
SELECT 'Beneficiaries < 50 (peer comparison less reliable)', COUNT(*) 
    FROM providers WHERE Tot_Benes < 50
UNION ALL
SELECT 'Beneficiaries >= 50 (good for peer comparison)', COUNT(*) 
    FROM providers WHERE Tot_Benes >= 50
UNION ALL
SELECT 'Tiny specialty group (< 30 peers in VA)', COUNT(*) 
    FROM providers WHERE Rndrng_Prvdr_Type IN (
        SELECT Rndrng_Prvdr_Type FROM providers 
        GROUP BY Rndrng_Prvdr_Type HAVING COUNT(*) < 30
    )
UNION ALL
SELECT 'Has all key billing metrics (analysis-ready)', COUNT(*) FROM providers 
    WHERE Tot_Mdcr_Pymt_Amt IS NOT NULL 
    AND Avg_Pymt_Per_Srvc IS NOT NULL
    AND Srvcs_Per_Bene IS NOT NULL
    AND Sbmt_to_Allwd_Ratio IS NOT NULL;


-- ==========================================================================
-- END OF DAY 2 EXPLORATORY QUERIES
-- ==========================================================================
-- Day 3 will calculate specialty-adjusted z-scores using these features:
--   - Avg_Pymt_Per_Srvc       (vs. specialty median)
--   - Srvcs_Per_Bene          (vs. specialty median)
--   - Pymt_Per_Bene           (vs. specialty median)
--   - Sbmt_to_Allwd_Ratio     (vs. specialty median)
-- Providers flagged on multiple dimensions will be classified as high-risk.
-- ==========================================================================
