-- ============================================================
-- AAPL 13F Institutional Turnover Analysis
-- SQL pipeline: unit correction + join/aggregation of SEC 13F,
-- FRED, and market data into a model-ready table.
-- ============================================================


-- ============================================================
-- SECTION 1: Unit correction
--
-- SEC Form 13F changed reporting units in two ways this data set
-- has to account for:
--   1. Rule effective Jan 3, 2023: report periods ending 12/31/2022
--      onward must report VALUE in whole dollars; prior periods
--      report in thousands of dollars.
--   2. AAPL's 4-for-1 stock split (Aug 31, 2020) means any price
--      reference used to validate reported values must reflect the
--      actual historical (pre-split) price, not a split-adjusted one.
--
-- Correction approach:
--   - AAPL positions: validated against AAPL's actual closing price
--     for that quarter (reconstructed pre-split by multiplying the
--     split-adjusted close by 4 for quarters before 2020-08-31).
--     If the implied per-share price (value / shares) is ~500-2000x
--     lower than the real price, the row is still in thousands.
--   - All other securities in the full-portfolio table: no
--     per-security price reference exists at this scale, so the
--     date-based rule is applied directly.
-- ============================================================

CREATE TABLE clean_aapl_holdings AS
SELECT
    h.*,
    CASE
        WHEN h.sshprnamt = 0 OR h.sshprnamt IS NULL THEN
            CASE WHEN h.periodofreport::date < '2022-12-31' THEN h.value * 1000 ELSE h.value END
        WHEN (
            (CASE WHEN mm.quarter_end::date < '2020-08-31'
                  THEN mm.aapl_quarter_close * 4
                  ELSE mm.aapl_quarter_close END)::numeric
            / NULLIF(h.value::numeric / NULLIF(h.sshprnamt::numeric, 0), 0)
        ) BETWEEN 500 AND 2000
            THEN h.value * 1000
        ELSE h.value
    END AS value_corrected
FROM raw_aapl_holdings h
LEFT JOIN raw_quarterly_macro_market mm
    ON h.periodofreport::date = mm.quarter_end::date;


CREATE TABLE clean_manager_full_portfolio AS
SELECT
    mfp.*,
    CASE
        WHEN mfp.cusip = '037833100' THEN
            CASE
                WHEN mfp.sshprnamt = 0 OR mfp.sshprnamt IS NULL THEN
                    CASE WHEN mfp.periodofreport::date < '2022-12-31' THEN mfp.value * 1000 ELSE mfp.value END
                WHEN (
                    (CASE WHEN mm.quarter_end::date < '2020-08-31'
                          THEN mm.aapl_quarter_close * 4
                          ELSE mm.aapl_quarter_close END)::numeric
                    / NULLIF(mfp.value::numeric / NULLIF(mfp.sshprnamt::numeric, 0), 0)
                ) BETWEEN 500 AND 2000
                    THEN mfp.value * 1000
                ELSE mfp.value
            END
        ELSE
            CASE WHEN mfp.periodofreport::date < '2022-12-31' THEN mfp.value * 1000 ELSE mfp.value END
    END AS value_corrected
FROM raw_manager_full_portfolio mfp
LEFT JOIN raw_quarterly_macro_market mm
    ON mfp.periodofreport::date = mm.quarter_end::date;

CREATE INDEX idx_clean_full_portfolio_cik_cusip_period
    ON clean_manager_full_portfolio (cik, cusip, periodofreport);
CREATE INDEX idx_clean_full_portfolio_cik_period
    ON clean_manager_full_portfolio (cik, periodofreport);


-- Manager-level quarterly totals, rebuilt from corrected position values
CREATE TABLE clean_manager_quarter_summary AS
SELECT
    c.accession_number,
    c.cik,
    c.filingmanager_name,
    c.periodofreport,
    COUNT(*) AS manager_position_count,
    SUM(c.value_corrected) AS manager_total_aum_corrected,
    s.is_index_fund_flag
FROM clean_manager_full_portfolio c
LEFT JOIN raw_manager_quarter_summary s
    ON c.accession_number = s.accession_number
GROUP BY c.accession_number, c.cik, c.filingmanager_name, c.periodofreport, s.is_index_fund_flag;


-- ============================================================
-- SECTION 2: Manager turnover
--
-- Turnover is computed as the sum of absolute dollar changes across
-- a manager's entire portfolio between consecutive filings, divided
-- by portfolio AUM. A FULL OUTER JOIN (not LAG) is used between each
-- manager's consecutive filings, matched on CUSIP, so that both
-- exited positions (present in the prior filing, absent from the
-- current one) and newly initiated positions are captured as real
-- dollar changes rather than silently dropped.
--
-- Filing sequence and pairs are materialized as their own tables
-- (not CTEs) to guarantee correct deduplication before the self-join
-- runs -- ROW_NUMBER() computed inside a SELECT DISTINCT evaluates
-- before the DISTINCT is applied, so it must be computed over an
-- already-distinct set.
-- ============================================================

CREATE TABLE manager_filing_sequence AS
SELECT
    cik, periodofreport,
    ROW_NUMBER() OVER (PARTITION BY cik ORDER BY periodofreport) AS filing_seq
FROM (
    SELECT DISTINCT cik, periodofreport FROM clean_manager_full_portfolio
) AS distinct_filings;

CREATE INDEX ON manager_filing_sequence (cik, filing_seq);

CREATE TABLE filing_pairs AS
SELECT
    curr.cik,
    curr.periodofreport AS curr_period,
    prev.periodofreport AS prev_period
FROM manager_filing_sequence curr
LEFT JOIN manager_filing_sequence prev
    ON curr.cik = prev.cik AND curr.filing_seq = prev.filing_seq + 1
WHERE prev.periodofreport IS NOT NULL;


-- ============================================================
-- SECTION 3: Final model table
-- One row per manager x quarter x AAPL position.
-- ============================================================

SET work_mem = '512MB';

ANALYZE manager_filing_sequence;
ANALYZE filing_pairs;
ANALYZE clean_manager_full_portfolio;
ANALYZE clean_aapl_holdings;

WITH aapl_with_target AS (
    SELECT
        accession_number,
        cik,
        filingmanager_name,
        periodofreport,
        value_corrected AS aapl_value,
        sshprnamt AS aapl_shares,
        LAG(value_corrected) OVER (PARTITION BY cik ORDER BY periodofreport) AS prior_aapl_value
    FROM clean_aapl_holdings
),

aapl_target AS (
    SELECT
        *,
        CASE
            WHEN prior_aapl_value IS NULL THEN NULL
            WHEN aapl_value > prior_aapl_value THEN 1
            ELSE 0
        END AS target_increased,
        CASE
            WHEN prior_aapl_value IS NULL OR prior_aapl_value = 0 THEN NULL
            ELSE (aapl_value - prior_aapl_value) / prior_aapl_value
        END AS pct_change_value
    FROM aapl_with_target
),

position_changes AS (
    SELECT
        fp.cik,
        fp.curr_period,
        ABS(COALESCE(curr.value_corrected, 0) - COALESCE(prev.value_corrected, 0)) AS abs_value_change
    FROM filing_pairs fp
    JOIN clean_manager_full_portfolio curr
        ON curr.cik = fp.cik AND curr.periodofreport = fp.curr_period
    FULL OUTER JOIN clean_manager_full_portfolio prev
        ON prev.cik = fp.cik
        AND prev.periodofreport = fp.prev_period
        AND prev.cusip = curr.cusip
),

manager_turnover AS (
    SELECT
        cik,
        curr_period AS periodofreport,
        SUM(abs_value_change) AS total_abs_position_change
    FROM position_changes
    GROUP BY cik, curr_period
),

final_model_table AS (
    SELECT
        t.accession_number,
        t.cik,
        t.filingmanager_name,
        t.periodofreport,
        t.aapl_value,
        t.aapl_shares,
        t.pct_change_value,
        t.target_increased,
        mqs.manager_position_count,
        mqs.is_index_fund_flag,
        mqs.manager_total_aum_corrected,
        CASE
            WHEN mqs.manager_total_aum_corrected IS NULL OR mqs.manager_total_aum_corrected = 0 THEN NULL
            ELSE t.aapl_value / mqs.manager_total_aum_corrected
        END AS pct_of_manager_aum,
        mt.total_abs_position_change,
        CASE
            WHEN mqs.manager_total_aum_corrected IS NULL OR mqs.manager_total_aum_corrected = 0 THEN NULL
            ELSE mt.total_abs_position_change / mqs.manager_total_aum_corrected
        END AS manager_turnover_rate,
        mm.fed_funds_rate,
        mm.yield_10y,
        mm.yield_2y,
        mm.yield_spread_10y_2y,
        mm.fed_funds_rate_change_qoq,
        mm.cpi_yoy_pct,
        mm.vix,
        mm.aapl_price_return,
        mm.aapl_realized_volatility,
        mm.spy_return,
        mm.megacap_peer_avg_return,
        mm.earnings_surprise_pct,
        mm.trailing_pe
    FROM aapl_target t
    LEFT JOIN clean_manager_quarter_summary mqs
        ON t.accession_number = mqs.accession_number
    LEFT JOIN manager_turnover mt
        ON t.cik = mt.cik AND t.periodofreport = mt.periodofreport
    LEFT JOIN raw_quarterly_macro_market mm
        ON t.periodofreport::date = mm.quarter_end::date
)

SELECT * INTO model_ready_table FROM final_model_table;