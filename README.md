# README

## Folder structure

`input` contains raw data sources. Note that the data source files are almost 10 GB, so I did not upload `input`.

`build.ipynb` read the data files from `input`, clean them, build the datasets, then export the datasets to `output` as .dta files. I also did not upload `output` due to large file sizes.

`analysis.do` then read the .dta files from `output` and run regressions.

Note that some descriptive statistics tables and figures are produced in `build.ipynb`, some are in `analysis.do`. All regression tables are produced in `analysis.do`.

I have added titles and comments in both `build.ipynb` and `analysis.do` to indicate parts of the code that produces tables/figures for the dissertation. You can also look at the table below for the exact lines of code to look at.

`Stata log.smcl` is the log of running analysis.do. Note that the log and output of `build.ipynb` can be viewed directly in the `.ipynb` file, so I haven't attached a dedicated log for that. 

Github displays the cell number of the `.ipynb` file, for example, In [25] at the left of each cell denotes cell number 25. That's how I will be referring to the part of the `.ipynb` file used to produce tables and figures. 

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
