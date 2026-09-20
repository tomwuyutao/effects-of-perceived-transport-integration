# Effects of Perceived Transport Integration

## Research overview

This dissertation asks whether making existing transport links more visible can change housing valuations even when the underlying service does not improve. It uses the January 2021 addition of Thameslink to the London Tube map as a natural experiment: 47 stations appeared on the map, but no new infrastructure was built and no major service improvement occurred.

Using HM Land Registry transactions and a difference-in-differences design, I compare properties within 1 km of treated stations with properties in a 1.5-3 km ring around the same stations. The map change is associated with a statistically significant **2.8% increase in house prices** near treated stations. The result is robust to alternative controls and specifications, is larger in outer fare zones (3.8%) than inner zones (2.0%), and is not accompanied by a detectable change in transaction volume. The findings suggest that transport visibility and informational salience can affect high-stakes housing decisions.

## Repository structure

`input` contains raw data sources. Note that the data source files are almost 10 GB, so I did not upload `input`.

`Build.ipynb` reads the data files from `input`, cleans them, builds the datasets, then exports the datasets to `output` as `.dta` files. I also did not upload `output` due to large file sizes.

`Analysis.do` reads the `.dta` files from `output` and runs the regressions.

Some descriptive-statistics tables and figures are produced in `Build.ipynb`; all regression tables are produced in `Analysis.do`.

Titles and comments in both files identify the code that produces each dissertation table and figure. The tables below provide exact locations.

`Stata log.smcl` records the execution of `Analysis.do`. The output of `Build.ipynb` can be viewed directly in the notebook.

GitHub displays notebook cell numbers (for example, `In [25]`); the reproduction guide refers to those numbers.

## Tables Reproduction

|                                                                                                                                        | Raw output source                                                                                                                                                                                                                                                                                   |
| -------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Table 1. Descriptive comparison of treatment and ring-control groups in the restricted estimation sample                               | `Build.ipynb` cell `[28]`                                                                                                                                                                                                                                                                           |
| Table 2. Descriptive comparison before and after the postcode pre/post filter                                                          | `Build.ipynb` cell `[29]`                                                                                                                                                                                                                                                                           |
| Table 3. Baseline Difference-in-Differences results                                                                                    | Model: `Analysis.do:98-114`; summary output: `Analysis.do:519-542`                                                                                                                                                                                                                                  |
| Table 4. Robustness checks                                                                                                             | Operator controls: `Analysis.do:240-261`; alternative treatment radii: `Analysis.do:266-315`; OA FE: `Analysis.do:319-337`; station x ring FE: `Analysis.do:354-382`; post-2023 sample: `Analysis.do:398-417`; placebo treatment date: `Analysis.do:422-441`; summary output: `Analysis.do:519-542` |
| Table 5. Sample sizes under alternative fixed-effects structures                                                                       | Stata summary table: `Analysis.do:519-542`; `Stata log.smcl:1665-1689`                                                                                                                                                                                                                              |
| Table 6. Mechanism: fare-zone heterogeneity and transaction volume                                                                     | Fare-zone heterogeneity, columns (1) and (2): `Analysis.do:491-514`; transaction volume, column (3): `Analysis.do:471-486`; summary output: `Analysis.do:519-542`                                                                                                                                   |
| Appendix Table B1. Baseline characteristics of the treatment group, ring control, and operator control groups in the restricted sample | `Build.ipynb` cell `[30]`                                                                                                                                                                                                                                                                           |

## Figures Reproduction

|                                                                                                     | Raw output source               |
| --------------------------------------------------------------------------------------------------- | ------------------------------- |
| Figure 1. Simplified illustration of the London Tube map before and after Thameslink's inclusion    | Created by Photoshop, not code  |
| Figure 2. Baseline treatment and ring-control areas around treated Thameslink stations              | `Build.ipynb` cell `[31]`       |
| Figure B1. Thameslink and South Western Railway areas used in the operator-control robustness check | `Build.ipynb` cell `[32]`       |
| Figure B2. Thameslink and Southeastern areas used in the operator-control robustness check          | `Build.ipynb` cells `[33]-[34]` |
| Figure B3. Event-study estimates for the baseline specification                                     | `Analysis.do:138-227`           |
