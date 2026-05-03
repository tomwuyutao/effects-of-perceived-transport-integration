clear

local temp_dir "temp"
capture mkdir "`temp_dir'"

capture program drop prep_long
program define prep_long
    syntax, idvars(string) [post_year(integer 2021)]

    * Convert the wide monthly price columns exported from Python into a transaction-month panel.
    reshape long price_, i(`idvars') j(year_month) string
    rename price_ price

    gen year  = real(substr(year_month, 1, 4))
    gen month = real(substr(year_month, 6, 2))

    * Collapse year-specific housing-supply controls to one column aligned with each observation year.
    gen additional_dwellings = .
    forvalues y = 2016/2025 {
        capture replace additional_dwellings = additional_dwellings_`y' if year == `y'
    }
    capture drop additional_dwellings_*

    gen post         = (year >= `post_year')
    gen treated_post = treated * post

    drop if missing(price)
    gen log_price = ln(price)

    encode PROPERTY_TYPE,         gen(property_type_enc)
    encode BUILT_FORM,            gen(built_form_enc)
    encode CONSTRUCTION_AGE_BAND, gen(construction_age_enc)
    encode TENURE,                gen(tenure_enc)
end

* ============================================================================
* PREPARE DATA
* ============================================================================

quietly {
    use output/main_treated_1000.dta, clear
    gen treated = 1
    save "`temp_dir'/temp_treatment.dta", replace

    use output/main_control_1500_3000.dta, clear
    gen treated = 0
    save "`temp_dir'/temp_control_ring.dta", replace

    use output/robustness_control_swr.dta, clear
    gen treated = 0
    save "`temp_dir'/temp_control_swr.dta", replace

    use output/robustness_control_southeastern.dta, clear
    gen treated = 0
    save "`temp_dir'/temp_control_southeastern.dta", replace

    import delimited using "input/station_fare_zones.csv", varnames(1) clear
    rename station nearest_station
    save "`temp_dir'/temp_fare_zones.dta", replace
}

* Build base long dataset (reused by most regressions)
quietly {
    use "`temp_dir'/temp_treatment.dta", clear
    append using "`temp_dir'/temp_control_ring.dta"
    egen house_id = group(postcode PAON SAON)
    prep_long, idvars(house_id treated postcode PAON SAON local_authority nearest_station oa21cd dist_to_treated)
    save "`temp_dir'/temp_base_long.dta", replace
}

* Build a broader long dataset before postcode support filtering.
* This feeds the OA FE and station x ring FE checks, which apply their own support rules later.
quietly {
    use output/robustness_treated_ringfe.dta, clear
    gen treated = 1
    append using output/robustness_control_ringfe.dta
    replace treated = 0 if missing(treated)
    egen house_id = group(postcode PAON SAON)
    prep_long, idvars(house_id treated postcode PAON SAON local_authority nearest_station oa21cd dist_to_treated)
    save "`temp_dir'/temp_station_ring_long.dta", replace
}

* Count full-sample estimation observations before any support filter is applied.
quietly {
    use "`temp_dir'/temp_station_ring_long.dta", clear
    keep if !missing(additional_dwellings, TOTAL_FLOOR_AREA, NUMBER_HABITABLE_ROOMS, EXTENSION_COUNT)
    count
    local n_full_full = r(N)
    count if treated == 1
    local n_full_treat = r(N)
    count if treated == 0
    local n_full_control = r(N)
}

* ============================================================================
* BASELINE: Treatment vs Ring (Postcode FE)
* ============================================================================
* Table 3. Baseline Difference-in-Differences results.

quietly {
    use "`temp_dir'/temp_base_long.dta", clear
    bysort postcode: gen pc_count = _N
    keep if pc_count >= 2
    drop pc_count
    egen postcode_id  = group(postcode)
    egen station_year = group(nearest_station year)
}

reghdfe log_price treated_post additional_dwellings ///
    i.property_type_enc i.built_form_enc TOTAL_FLOOR_AREA ///
    NUMBER_HABITABLE_ROOMS i.construction_age_enc i.tenure_enc ///
    EXTENSION_COUNT i.month, ///
    absorb(postcode_id station_year) vce(cluster postcode_id)
estimates store baseline_ring

quietly {
    tempvar sample_baseline
    gen byte `sample_baseline' = e(sample)
    count if `sample_baseline'
    local n_postcode_full = r(N)
    count if `sample_baseline' & treated == 1
    local n_postcode_treat = r(N)
    count if `sample_baseline' & treated == 0
    local n_postcode_control = r(N)
}

* ============================================================================
* EVENT STUDY: Treatment vs Ring Control
* ============================================================================
* Figure B3. Event-study estimates for the baseline specification.

* Data still in memory from baseline
quietly {
    gen event_time = year - 2021
    * Omit year -1 (2020) as the reference period and estimate all other event-time coefficients relative to it.
    foreach t in pre_5 pre_4 pre_3 pre_2 post_0 post_1 post_2 post_3 post_4 {
        local val = cond(strpos("`t'", "pre"), -(real(substr("`t'", 5, .))), ///
                        real(substr("`t'", 6, .)))
        gen `t' = (event_time == `val')
        gen treated_`t' = treated * `t'
    }
}

reghdfe log_price treated_pre_5 treated_pre_4 treated_pre_3 treated_pre_2 ///
    treated_post_0 treated_post_1 treated_post_2 treated_post_3 treated_post_4 ///
    additional_dwellings i.property_type_enc i.built_form_enc TOTAL_FLOOR_AREA ///
    NUMBER_HABITABLE_ROOMS i.construction_age_enc i.tenure_enc ///
    EXTENSION_COUNT i.month, ///
    absorb(postcode_id station_year) vce(cluster postcode_id)

local b_pre5 = _b[treated_pre_5]
local b_pre4 = _b[treated_pre_4]
local b_pre3 = _b[treated_pre_3]
local b_pre2 = _b[treated_pre_2]
local b_post0 = _b[treated_post_0]
local b_post1 = _b[treated_post_1]
local b_post2 = _b[treated_post_2]
local b_post3 = _b[treated_post_3]
local b_post4 = _b[treated_post_4]

local se_pre5 = _se[treated_pre_5]
local se_pre4 = _se[treated_pre_4]
local se_pre3 = _se[treated_pre_3]
local se_pre2 = _se[treated_pre_2]
local se_post0 = _se[treated_post_0]
local se_post1 = _se[treated_post_1]
local se_post2 = _se[treated_post_2]
local se_post3 = _se[treated_post_3]
local se_post4 = _se[treated_post_4]

capture graph set window fontface "Times New Roman"

preserve
clear
* Build a small plotting dataset from the regression output so the x-axis respects the missing reference period.
set obs 9
gen event_time = .
gen beta = .
gen se = .

replace event_time = -5 in 1
replace beta = `b_pre5' in 1
replace se = `se_pre5' in 1

replace event_time = -4 in 2
replace beta = `b_pre4' in 2
replace se = `se_pre4' in 2

replace event_time = -3 in 3
replace beta = `b_pre3' in 3
replace se = `se_pre3' in 3

replace event_time = -2 in 4
replace beta = `b_pre2' in 4
replace se = `se_pre2' in 4

replace event_time = 0 in 5
replace beta = `b_post0' in 5
replace se = `se_post0' in 5

replace event_time = 1 in 6
replace beta = `b_post1' in 6
replace se = `se_post1' in 6

replace event_time = 2 in 7
replace beta = `b_post2' in 7
replace se = `se_post2' in 7

replace event_time = 3 in 8
replace beta = `b_post3' in 8
replace se = `se_post3' in 8

replace event_time = 4 in 9
replace beta = `b_post4' in 9
replace se = `se_post4' in 9

gen ci_low = beta - 1.96 * se
gen ci_high = beta + 1.96 * se

twoway ///
    (rcap ci_high ci_low event_time, lcolor("31 78 121")) ///
    (scatter beta event_time, mcolor("168 77 77") msymbol(O) msize(medium)), ///
    xline(-1, lpattern(dash) lcolor("168 77 77")) ///
    yline(0, lpattern(dash) lcolor(black)) ///
    xlabel(-5(1)4, labsize(medium)) ///
    ylabel(-.10(.05).10, angle(horizontal) format(%4.2f) labsize(medium)) ///
    yscale(range(-.10 .10)) ///
    xtitle("Years relative to treatment (2021)", size(medlarge) margin(medsmall)) ///
    ytitle("Effect on log price", size(medlarge) margin(medsmall)) ///
    title("Event Study: Treatment vs Ring Control (Postcode FE)", size(large) margin(medium)) ///
    note("Reference period: year -1 (2020).", size(small) margin(medium)) ///
    legend(off) ///
    xsize(9) ysize(6.5) ///
    graphregion(color(white) margin(medium)) plotregion(color(white) margin(medium))
restore

* ============================================================================
* ROBUSTNESS: Alternative Operator Controls
* ============================================================================
* Table 4, columns (1) and (2): operator-control robustness using SWR and Southeastern.

foreach op in swr southeastern {
    quietly {
        use "`temp_dir'/temp_treatment.dta", clear
        append using "`temp_dir'/temp_control_`op'.dta"
        egen house_id = group(postcode PAON SAON)
        prep_long, idvars(house_id treated postcode PAON SAON local_authority nearest_station oa21cd dist_to_treated)
        bysort postcode: gen pc_count = _N
        keep if pc_count >= 2
        drop pc_count
        egen postcode_id  = group(postcode)
        egen station_id = group(nearest_station)
    }

    reghdfe log_price treated_post additional_dwellings ///
        i.property_type_enc i.built_form_enc TOTAL_FLOOR_AREA ///
        NUMBER_HABITABLE_ROOMS i.construction_age_enc i.tenure_enc ///
        EXTENSION_COUNT i.month i.year, ///
        absorb(postcode_id station_id) vce(cluster postcode_id)
    estimates store control_`op'
}

* ============================================================================
* ROBUSTNESS: Alternative Treatment Radius (500m and 1.5km)
* ============================================================================
* Table 4, columns (5) and (6): alternative treatment-radius checks.

quietly {
    use output/robustness_treated_500.dta, clear
    gen treated = 1
    save "`temp_dir'/temp_treatment_500.dta", replace

    use output/robustness_treated_1500.dta, clear
    gen treated = 1
    save "`temp_dir'/temp_treatment_1500.dta", replace
}

quietly {
    use "`temp_dir'/temp_treatment_500.dta", clear
    append using "`temp_dir'/temp_control_ring.dta"
    egen house_id = group(postcode PAON SAON)
    prep_long, idvars(house_id treated postcode PAON SAON local_authority nearest_station oa21cd dist_to_treated)
    bysort postcode: gen pc_count = _N
    keep if pc_count >= 2
    drop pc_count
    egen postcode_id  = group(postcode)
    egen station_year = group(nearest_station year)
}

reghdfe log_price treated_post additional_dwellings ///
    i.property_type_enc i.built_form_enc TOTAL_FLOOR_AREA ///
    NUMBER_HABITABLE_ROOMS i.construction_age_enc i.tenure_enc ///
    EXTENSION_COUNT i.month, ///
    absorb(postcode_id station_year) vce(cluster postcode_id)
estimates store ring_500

quietly {
    use "`temp_dir'/temp_treatment_1500.dta", clear
    append using "`temp_dir'/temp_control_ring.dta"
    egen house_id = group(postcode PAON SAON)
    prep_long, idvars(house_id treated postcode PAON SAON local_authority nearest_station oa21cd dist_to_treated)
    bysort postcode: gen pc_count = _N
    keep if pc_count >= 2
    drop pc_count
    egen postcode_id  = group(postcode)
    egen station_year = group(nearest_station year)
}

reghdfe log_price treated_post additional_dwellings ///
    i.property_type_enc i.built_form_enc TOTAL_FLOOR_AREA ///
    NUMBER_HABITABLE_ROOMS i.construction_age_enc i.tenure_enc ///
    EXTENSION_COUNT i.month, ///
    absorb(postcode_id station_year) vce(cluster postcode_id)
estimates store ring_1500

* ============================================================================
* ROBUSTNESS: OA FE (Treatment vs Ring)
* ============================================================================
* Table 4, column (3): output-area fixed effects robustness.

quietly {
    use "`temp_dir'/temp_station_ring_long.dta", clear
    * Keep only output areas that contribute at least one pre and one post observation.
    bysort oa21cd: egen has_pre  = max(post == 0)
    bysort oa21cd: egen has_post = max(post == 1)
    keep if has_pre & has_post
    drop has_pre has_post
    egen oa_id        = group(oa21cd)
    egen station_year = group(nearest_station year)
}

reghdfe log_price treated_post additional_dwellings ///
    i.property_type_enc i.built_form_enc TOTAL_FLOOR_AREA ///
    NUMBER_HABITABLE_ROOMS i.construction_age_enc i.tenure_enc ///
    EXTENSION_COUNT i.month, ///
    absorb(oa_id station_year) vce(cluster oa_id)
estimates store oa_fe

quietly {
    tempvar sample_oa
    gen byte `sample_oa' = e(sample)
    count if `sample_oa'
    local n_oa_full = r(N)
    count if `sample_oa' & treated == 1
    local n_oa_treat = r(N)
    count if `sample_oa' & treated == 0
    local n_oa_control = r(N)
}

* ============================================================================
* ROBUSTNESS: Station x Ring FE (Treatment vs Ring)
* Use 500m distance bins and keep only station-ring cells with pre and post data.
* ============================================================================
* Table 4, column (4): station x ring fixed effects robustness.

quietly {
    use "`temp_dir'/temp_station_ring_long.dta", clear

    * Match the baseline geometry but split the treated and control areas into narrower distance bands.
    gen ring_bin = .
    replace ring_bin = 1 if dist_to_treated < 500
    replace ring_bin = 2 if inrange(dist_to_treated, 500, 999.999)
    replace ring_bin = 3 if inrange(dist_to_treated, 1500, 1999.999)
    replace ring_bin = 4 if inrange(dist_to_treated, 2000, 2499.999)
    replace ring_bin = 5 if inrange(dist_to_treated, 2500, 3000)
    drop if missing(ring_bin)

    egen station_ring = group(nearest_station ring_bin)
    egen station_year = group(nearest_station year)

    bysort station_ring: egen has_pre  = max(post == 0)
    bysort station_ring: egen has_post = max(post == 1)
    keep if has_pre & has_post
    drop has_pre has_post
}

reghdfe log_price treated_post additional_dwellings ///
    i.property_type_enc i.built_form_enc TOTAL_FLOOR_AREA ///
    NUMBER_HABITABLE_ROOMS i.construction_age_enc i.tenure_enc ///
    EXTENSION_COUNT i.month, ///
    absorb(station_ring station_year) vce(cluster station_ring)
estimates store station_ring_fe

quietly {
    tempvar sample_station_ring
    gen byte `sample_station_ring' = e(sample)
    count if `sample_station_ring'
    local n_station_ring_full = r(N)
    count if `sample_station_ring' & treated == 1
    local n_station_ring_treat = r(N)
    count if `sample_station_ring' & treated == 0
    local n_station_ring_control = r(N)
}

* ============================================================================
* ROBUSTNESS: Post-COVID Only (post = Jan 2023 onwards)
* ============================================================================
* Table 4, column (7): exclude 2021-2022 and redefine post from 2023 onward.

quietly {
    use "`temp_dir'/temp_base_long.dta", clear
    drop if year == 2021 | year == 2022
    replace post        = (year >= 2023)
    replace treated_post = treated * post
    bysort postcode: gen pc_count = _N
    keep if pc_count >= 2
    drop pc_count
    egen postcode_id  = group(postcode)
    egen station_year = group(nearest_station year)
}

reghdfe log_price treated_post additional_dwellings ///
    i.property_type_enc i.built_form_enc TOTAL_FLOOR_AREA ///
    NUMBER_HABITABLE_ROOMS i.construction_age_enc i.tenure_enc ///
    EXTENSION_COUNT i.month, ///
    absorb(postcode_id station_year) vce(cluster postcode_id)
estimates store post_covid

* ============================================================================
* PLACEBO: Fake Treatment Date (Jan 2018)
* ============================================================================
* Table 4, column (8): placebo treatment date in the pre-treatment years only.

quietly {
    use "`temp_dir'/temp_base_long.dta", clear
    keep if inrange(year, 2016, 2020)
    replace post         = (year >= 2018)
    replace treated_post = treated * post
    bysort postcode: gen pc_count = _N
    keep if pc_count >= 2
    drop pc_count
    egen postcode_id  = group(postcode)
    egen station_year = group(nearest_station year)
}

reghdfe log_price treated_post additional_dwellings ///
    i.property_type_enc i.built_form_enc TOTAL_FLOOR_AREA ///
    NUMBER_HABITABLE_ROOMS i.construction_age_enc i.tenure_enc ///
    EXTENSION_COUNT i.month, ///
    absorb(postcode_id station_year) vce(cluster postcode_id)
estimates store placebo_2018

* ============================================================================
* ROBUSTNESS: Composition Placebo Using Predicted Prices from 2016-2017
* ============================================================================

quietly {
    use "`temp_dir'/temp_base_long.dta", clear
    bysort postcode: gen pc_count = _N
    keep if pc_count >= 2
    drop pc_count
    egen postcode_id  = group(postcode)
    egen station_year = group(nearest_station year)
}

regress log_price additional_dwellings ///
    i.property_type_enc i.built_form_enc TOTAL_FLOOR_AREA ///
    NUMBER_HABITABLE_ROOMS i.construction_age_enc i.tenure_enc ///
    EXTENSION_COUNT i.month if inrange(year, 2016, 2017)

* Predicted prices strip out the treatment effect by construction and retain only composition on observables.
predict pred_log_price, xb

reghdfe pred_log_price treated_post i.month, ///
    absorb(postcode_id station_year) vce(cluster postcode_id)
estimates store composition_placebo

* ============================================================================
* MECHANISM: Transaction Volume
* ============================================================================
* Table 6, column (3)

quietly {
    use output/mechanism_transactions.dta, clear
    gen year  = real(substr(year_month, 1, 4))
    gen month = real(substr(year_month, 6, 2))
    gen post        = (year >= 2021)
    gen treated_post = treated * post
    gen log_transactions = ln(n_transactions)
    egen station_id      = group(nearest_station)
    egen station_treated = group(nearest_station treated)
}

reghdfe log_transactions treated_post i.month, ///
    absorb(station_treated year) vce(cluster station_id)
estimates store tx_volume

* ============================================================================
* MECHANISM: Fare Zone Heterogeneity (Treatment vs Ring)
* ============================================================================
* Table 6, column (1)(2)

quietly {
    use "`temp_dir'/temp_base_long.dta", clear
    bysort postcode: gen pc_count = _N
    keep if pc_count >= 2
    drop pc_count
    egen postcode_id  = group(postcode)
    egen station_year = group(nearest_station year)

    merge m:1 nearest_station using "`temp_dir'/temp_fare_zones.dta", keep(master match) nogenerate

    * Estimate separate post-treatment effects for inner (zones 1-3) and outer (zones 4+) station areas.
    gen outer              = (fare_zone >= 4)
    gen treated_post_inner = treated_post * (outer == 0)
    gen treated_post_outer = treated_post * (outer == 1)
}

reghdfe log_price treated_post_inner treated_post_outer ///
    additional_dwellings i.property_type_enc i.built_form_enc TOTAL_FLOOR_AREA ///
    NUMBER_HABITABLE_ROOMS i.construction_age_enc i.tenure_enc ///
    EXTENSION_COUNT i.month, ///
    absorb(postcode_id station_year) vce(cluster postcode_id)
estimates store fare_zone

* ============================================================================
* SUMMARY TABLE
* ============================================================================
foreach row in ///
    "baseline_ring|Baseline ring (<1km vs 1.5-3km)|treated_post" ///
    "control_swr|Operator control (SWR; station FE + year FE)|treated_post" ///
    "control_southeastern|Operator control (Southeastern; station FE + year FE)|treated_post" ///
    "ring_500|Ring radius (<500m vs 1.5-3km)|treated_post" ///
    "ring_1500|Ring radius (<1.5km vs 1.5-3km)|treated_post" ///
    "oa_fe|OA FE|treated_post" ///
    "station_ring_fe|Station x ring FE (500m bins; pre/post supported cells)|treated_post" ///
    "post_covid|Post-2023 sample|treated_post" ///
    "placebo_2018|Placebo treatment date (Jan 2018-Dec 2020)|treated_post" ///
    "composition_placebo|Composition placebo (predicted price)|treated_post" ///
    "fare_zone|Fare zone heterogeneity (inner)|treated_post_inner" ///
    "fare_zone|Fare zone heterogeneity (outer)|treated_post_outer" ///
    "tx_volume|Transaction volume (log transactions)|treated_post" {
    gettoken m rest : row, parse("|")
    gettoken bar rest : rest, parse("|")
    gettoken label rest : rest, parse("|")
    gettoken bar coefvar : rest, parse("|")
    estimates restore `m'
    local b  = _b[`coefvar']
    local se = _se[`coefvar']
    local n  = e(N)
    display %60s "`label'" %12.4f `b' %12.4f `se' %8.0f `n'
}

* ============================================================================
* CLEAN UP
* ============================================================================

quietly {
    erase "`temp_dir'/temp_treatment.dta"
    erase "`temp_dir'/temp_control_ring.dta"
    erase "`temp_dir'/temp_control_swr.dta"
    erase "`temp_dir'/temp_control_southeastern.dta"
    erase "`temp_dir'/temp_fare_zones.dta"
    erase "`temp_dir'/temp_treatment_500.dta"
    erase "`temp_dir'/temp_treatment_1500.dta"
    erase "`temp_dir'/temp_base_long.dta"
    erase "`temp_dir'/temp_station_ring_long.dta"

    capture erase temp_treatment.dta
    capture erase temp_control_ring.dta
    capture erase temp_control_swr.dta
    capture erase temp_control_southeastern.dta
    capture erase temp_fare_zones.dta
    capture erase temp_treatment_500.dta
    capture erase temp_treatment_1500.dta
    capture erase temp_base_long.dta
    capture erase temp_station_ring_long.dta

    capture rmdir "`temp_dir'"
}
