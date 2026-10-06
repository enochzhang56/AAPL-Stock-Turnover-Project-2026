<p align="center">
<img width="775" height="249" alt="Screenshot 2026-10-05 at 9 00 13 PM" src="https://github.com/user-attachments/assets/92e673b8-d7d8-4fed-a323-dc95e9092ad8" />

</p>

# AAPL-Stock-Turnover-Project-2026
Identifying which factors are associated with large institutional investors increasing or decreasing their Apple stock holdings, using SEC Form 13F filings, FRED economic data and market data. SQL, Python.

# Table of Contents

1. [Background and Overview](#background-and-overview)
2. [Data Sources](#data-sources)
3. [Data Structure](#data-structure)
4. [Executive Summary](#executive-summary)
5. [Recommendations](#recommendations)

# Background and Overview

Individual investors often follow large investment firms and bigger managers of assets because these firms have access to extensive resources that are not available to the public. However, it is not always clear whether adjustments in Apple stock holdings are a reflection of broader market conditions such as interest rates and inflation, or a change in confidence of the company and other factors that are not available to the public.

This project combines SEC Form 13F filings with economic data from FRED and stock market data from Alpha Vantage. The goal of the project is to determine which factors are most closely associated with institutional investors increasing or decreasing their Apple Stock holdings. The goal is to help individual investors determine whether changes in larger manager ownership of Apple reflect genuine confidence in the company or simply routine trading activity.

Recommendations and insights were based off of 2 categories of information:

Two questions are modeled, using a “change” defined as a move of more than 5% in the number of Apple shares a manager holds from one quarter to the next:

- **Changed vs. Flat:** did the manager change more than 5%?
- **Bought vs. Sold:** did the manager who changed buy or sell?

Three groups of factors are compared:

- **Manager habits:** How large Apple is in the manager’s portfolio, how actively the manager trades in general (turnover), and the manager’s total size of assets.
- **Macro conditions:** The federal funds rate, the VIX (market fear index), and inflation (calculated using CPI).
- **Apple-Specific Performance:** Apple’s return compared to the S&P 500 and to similar large tech companies, earnings surprise (results above or below analyst expectations) and Apple’s price-to-earnings ratios.

# Data Sources

Data was pulled from the following sources:

- **SEC EDGAR Form 13F bulk data:** quarterly holdings reported by institutional managers, filtered to Apple (between 2018 to 2026).
- **FRED (Federal Reserve Economic Data):** federal funds rate, Treasury yields, inflation (CPI), and the VIX.
- **Alpha Vantage:** Apple earnings results and surprises.

Python data pulling code can be found [here](https://github.com/enochzhang56/AAPL-Stock-Turnover-Project-2026/blob/main/ETL/AAPL_python_api.ipynb).

Raw data joined and combined using SQL. Code for it can be found [here](https://github.com/enochzhang56/AAPL-Stock-Turnover-Project-2026/blob/main/ETL/AAPL_sql_joining.sql).

# Data Structure

<img width="685" height="386" alt="aapl_data_structure" src="https://github.com/user-attachments/assets/df0960d2-4046-4f78-ba45-9c8b3981f201" />


# Executive Summary

Across about 116,000 manager-quarter observations, about 2 in 5 involved a change of more than 5% in the Apple shares held. Among those changers, buyers and sellers were close to evenly split.

Changes in large manager's Apple holdings are most closely associated with the manager’s own characteristics and tendencies, rather than the economic or Apple’s performance.

- **Manager habits matter most.** Managers with a larger share of Apple in their portfolio were less likely to change their position and more likely to sell when they did. Managers who trade heavily in general were more likely to change their Apple holdings, and when they did, they were more often more likely to buy.
- **Macro conditions had small effects.** In the data set’s training years, a higher VIX (market fear factor) was associated with more changes, and a higher inflation with fewer changes in the manager’s portfolios. But these effects were much lower when put in the data’s test years.
- **Apple-specific performance had even smaller effects.** Earnings surprise, Apple’s return compared to peers in the market, and price-to-earnings ratio had nearly 0 impact on any model’s predictive performance, indicating small influence in manager’s decisions.
- **Predictive power of the models were modest.** Even manager habit could only reach a test AUC of 0.63 with logistic regression, and 0.65 to 0.67 with XGBoost, meaning that the model could predict whether a manager changes or not slightly better than random chance (0.50).

**In-depth data analysis can be found [here](https://github.com/enochzhang56/AAPL-Stock-Turnover-Project-2026/blob/main/EDA_AAPL.ipynb).**

# Recommendations

- **Treat changes in large managers’ Apple holdings as mostly routine portfolio management.** The largest pattern that the models showed was rebalancing of assets: managers with large Apple positions tended to trim, while managers with smaller Apple positions tended to add.
- **Look at the specific manager before reading into their move.** A manager’s Apple weight and general trading activity explain their change in asset, rather than other explanatory factors.
- **Do not expect the economy or Apple’s performance to explain any movement.** All models show that these factors play a very limited role in whether larger managers buy or sell at all.
