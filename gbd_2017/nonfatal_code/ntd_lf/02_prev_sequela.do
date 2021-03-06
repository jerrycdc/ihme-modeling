// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		This step template should be submitted from the 00_master.do file either by submitting all steps or selecting one or more steps to run in "steps" global
// Description:	Correct dismod output for pre-control prevalence of infection and morbidity for the effect of mass treatment, and scale
// 				to the national level (dismod model is at level of population at risk).
// include "FILEPATH/01_prev_sequela.do"

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// LOAD SETTINGS FROM MASTER CODE (NO NEED TO EDIT THIS SECTION)

	// prep stata
	clear all
	set more off
	set maxvar 32000
	if c(os) == "Unix" {
		global prefix "FILEPATH"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "FILEPATH"
	}
	if "`1'" != "" {
		// base directory on J
		local root_j_dir `1'
		// base directory on clustertmp
		local root_tmp_dir `2'
		// timestamp of current run (i.e. 2014_01_17)
		local date `3'
		// step number of this step (i.e. 01a)
		local step_num `4'
		// name of current step (i.e. first_step_name)
		local step_name `5'
		// step numbers of immediately anterior parent step (i.e. for step 2: 01a 01b 01c)
		local hold_steps `6'
		// step numbers for final steps that you are running in the current run (i.e. 11a 11b 11c)
		local last_steps `7'
		// directory where the code lives
		local code_dir `8'
	}
	else if "`1'" == "" {
		// base directory on J
		local root_j_dir "FILEPATH"
		// base directory on clustertmp
		local root_tmp_dir "FILEPATH"
		// timestamp of current run (i.e. 2014_01_17)
		local date: display %tdCCYY_NN_DD date(c(current_date), "DMY")
		local date = subinstr("`date'"," ","_",.)
		// step number of this step (i.e. 01a)
		local step_num "02"
		// name of current step (i.e. first_step_name)
		local step_name "prev_sequela"
		// step numbers of immediately anterior parent step (i.e. for step 2: 01a 01b 01c)
		local hold_steps ""
		// step numbers for final steps that you are running in the current run (i.e. 11a 11b 11c)
		local last_steps ""
		// directory where the code lives
		local code_dir "FILEPATH"
	}
	// directory for external inputs
	local in_dir "FILEPATH"
	// directory for output on the J drive
	local out_dir "FILEPATH"
	// directory for output on clustertmp
	local tmp_dir "FILEPATH"

  ** set central functions
  adopath + "FILEPATH"

  // set shell file
  local shell_file "FILEPATH/stata_shell.sh"

	// write log if running in parallel and log is not already open
	cap log using "FILEPATH/`step_num'.smcl", replace
	if !_rc local close_log 1
	else local close_log 0

	// check for finished.txt produced by previous step
	if "`hold_steps'" != "" {
		foreach step of local hold_steps {
			local dir: dir "FILEPATH" dirs "`step'_*", respectcase
			// remove extra quotation marks
			local dir = subinstr(`"`dir'"',`"""',"",.)
			capture confirm file "FILEPATH/finished.txt"
			if _rc {
				di "`dir' failed"
				BREAK
			}
		}
	}

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Create directories for storing draw files
  foreach meid in 1491 1492 1493 {
	local root_tmp_dir_`meid' = "`root_tmp_dir'/`meid'"
  cap mkdir "`root_tmp_dir_`meid''"
	capture mkdir "FILEPATH"
	capture mkdir "FILEPATH"
	capture mkdir "FILEPATH"
	capture mkdir "FILEPATH"
  capture mkdir "FILEPATH"
	capture mkdir "FILEPATH"
  }
  local out_dir_infection "FILEPATH"
  local out_dir_lymphedema = FILEPATH
  local out_dir_hydrocele = FILEPATH
  capture mkdir "`out_dir_infection'"
  capture mkdir "`out_dir_lymphedema'"
  capture mkdir "`out_dir_hydrocele'"

// Create directory for storing inputs
  local tmp_in_dir "FILEPATH"
  capture mkdir "`tmp_in_dir'"

// Prep country population sizes into temp files for quickly looping through them later
  get_demographics, gbd_team(ADDRESS) clear
  local sex_ids `r(sex_id)'
  local year_ids `(year_id)'
  local age_group_ids `r(age_group_id)'
  get_location_metadata, location_set_id(35) clear
  save "`tmp_in_dir'/loc_met.dta", replace
  levelsof location_id if is_estimate == 1 & most_detailed == 1, local(location_ids)
  global location_ids `location_ids'

  get_population, year_id(1990 1995 2000 2005 2010 2017) location_id(`location_ids') sex_id(`sex_ids') age_group_id(`age_group_ids') clear
  keep location_id year_id age_group_id sex_id population
  rename population pop_scaled
  save "`tmp_in_dir'/pops.dta", replace

** don't need to do this part right now, no changes at the moment
/*
// Model for prevalence of morbidity, given mf prevalence, based on data from the Global LF Atlas (thiswormyworld.org)
  quietly insheet using "`in_dir'/Global_lf_atlas_data_extracted_2014_04_30.csv", double comma clear

  // Keep data for all ages
    keep if age_start == 0 & age_end == 99 & sex == "M/F"
  // Keep data points with relevant data
    drop if (pop_mf == 0 | missing(pop_mf) | missing(np_mf)) | ((pop_lymph == 0 | missing(pop_lymph) | missing(np_lymph)) & (pop_hydrocele == 0 | missing(pop_hydrocele) | missing(np_hydrocele)))
  // Recalculate prevalences
    drop prev_mf
    generate double prev_mf = np_mf / pop_mf
    generate double prev_lymph = np_lymph / pop_lymph
    generate double prev_hydrocele = np_hydrocele / pop_hydrocele
  // Scatter data
    ** scatter prev_hydrocele prev_mf
    ** scatter prev_lymph prev_mf
  // Outsheet selection of data so that it can be regressed in with Stan in R (Stata has no facilities to take account of
  // error in independent variables (mf prevalence).
    keep adm* year_survey lf_species sex age_start age_end *mf *hydrocele *lymph source_data1
    preserve
      keep if !missing(prev_hydrocele)
      drop if pop_hydrocele == pop_mf // why?
      drop *lymph
      outsheet using "FILEPATH/lf_atlas_hydrocele_compiled_`date'.csv", comma replace
    restore
    preserve
      keep if !missing(prev_lymph)
      drop *hydrocele
      outsheet using "FILEPATH/lf_atlas_lymphedema_compiled_`date'.csv", comma replace
    restore
*/
  // ========================================== //
  // Perform non-linear error-in-variables regression with Stan in R //
  // and store results in the `FILEPATH folder.    //
  // See the folder `FILEPATH.                            //
  // ========================================== //

  // Load thousand draws of parameter values for predicting morbidity from mf prevalence
  // Functional association hydrocele prevalence (y, scale 0-1) vs mf prevalence (x, scale 0-1): (a+bx^c)/(1+bx^c)
    insheet using "FILEPATH/lf_hydrocele_gnlm_logistic_stan_posterior.csv", double clear
    format %16.0g *
    generate int index = _n
	save "`tmp_in_dir'/hyd_regression.dta", replace

  // Functional association lymphedema prevalence (y, scale 0-1) vs mf prevalence (x, scale 0-1): (a+bx^c)/(1+bx^c)
    insheet using "FILEPATH/lf_lymphedema_gnlm_logistic_stan_posterior.csv", double clear
    format %16.0g *
    generate int index = _n
	save "`tmp_in_dir'/oed_regression.dta", replace


// Model for reduction in hydrocele prevalence as function of number of rounds of treatment
// (we will use treatments per person as a predictor, rather than rounds of treatment, which
// might underestimate the effect of mass treatment).
  quietly insheet using "`in_dir'/MDA_effect_on_hydrocele.csv", double comma clear

  // Fit non-linear regression (OLS), using a logistic function and limiting parameters
  // to have positive values by means of exponentiation
    nl (reduction = 1 / (1 + 1/(exp({b0=-4}) * rounds^(exp({b1=0.1}))))), vce(hc3)
    local n_data = _N
    local n_new = `n_data' + 1001
    set obs `n_new'
    replace rounds = 12.5 * (_n - `n_data') / 1000 if missing(rounds)
    predict mu
      replace mu = 0 if mu < 0
    twoway (scatter reduction rounds)(line mu rounds, sort), aspect(1)
    matrix mu = e(b)'
    matrix sigma = e(V)
    local covars: rownames mu
    local num_covars: word count `covars'
    local betas
    forvalues j = 1/`num_covars' {
      local p = `j' - 1
      local betas `betas' b`p'
    }

  clear
  set obs 1000
  generate index = _n
  drawnorm `betas', means(mu) cov(sigma) double
  tempfile effect_hyd
  quietly save `effect_hyd', replace


// Prepare data on history of mass treatment (coverage of mass treatment against LF in populations at risk)
** save cumulative treatments per person
  get_covariate_estimates, covariate_id(255) clear
  rename mean_value tpp_cum
  keep tpp_cum location_id year_id
  tempfile cumtpp
  save `cumtpp', replace

** save single year treatments per person
  reshape wide tpp_cum, i(location_id) j(year_id)
  forvalues i = 2017(-1)1991 {
    local j = `i' - 1
    replace tpp_cum`i' = tpp_cum`i' - tpp_cum`j'
  }
  reshape long tpp_cum, i(location_id) j(year_id)
  rename tpp_cum coverage
  merge 1:1 location_id year_id using `cumtpp', nogen keep(3)

  ** Calculate the five-year moving average coverage (to be used to estimate proportion of population
  ** that experiences zero incidence of lymphedema)
    bysort location_id: generate cov_avg5 = (coverage[_n-4] + coverage[_n-3] + coverage[_n-2] + coverage[_n-1] + coverage) / 5
    replace cov_avg5 = 0 if cov_avg5 == .

  // Predict effect on prevalence of infection, based on non-linear regression of reduction vs. treatments per person
  /*  generate index = _n
    merge 1:1 index using `effect_inf', nogen

    forvalues i = 0/999 {
      quietly generate double effect_inf_`i' = 1 - 1 / (1 + 1/(exp(b0[`i'+1]) * tpp_cum^(exp(b1[`i'+1]))))
      quietly replace effect_inf_`i' = 1 if tpp_cum == 0
    }
    drop index b*
    */

  // Predict effect on prevalence of hydrocele
    generate index = _n
    merge 1:1 index using `effect_hyd', nogen

    forvalues i = 0/999 {
      quietly generate double effect_hyd_`i' = 1 - 1 / (1 + 1/(exp(b0[`i'+1]) * tpp_cum^(exp(b1[`i'+1]))))
      quietly replace effect_hyd_`i' = 1 if tpp_cum == 0
    }
    drop index b*

    keep if inlist(year_id,1990,1995,2000,2005,2010,2017)
    keep location_id year_id coverage cov_avg5 tpp_cum effect_*
    save "`tmp_in_dir'/coverage.dta", replace

// ****************************************************************************************************
// ****************************************************************************************************
// Submit jobs by location to scale scale for population at risk and effect of MDA

    foreach location_id of local location_ids {
      capture confirm file "`out_dir_lymphedema'/`location_id'.csv"
      if _rc {
        !qsub -N "LF_custom_model_lid_`location_id'" -P proj_custom_models -pe multi_slot 4 -l mem_free=8 "`shell_file'" "`code_dir'/`step_num'_parallel.do" "`location_id' `tmp_in_dir' `out_dir' `out_dir_infection' `out_dir_lymphedema' `out_dir_hydrocele' `in_dir' `date'"
      }
    }
// Wait for results (check for the last file saved)
    foreach location_id of local location_ids {
		use "`tmp_in_dir'/loc_met.dta" if location_id == `location_id', clear
		quietly levelsof ihme_loc_id, local(iso3) c
		capture confirm file "`out_dir_lymphedema'/`location_id'.csv"
		if _rc == 601 noisily display "Searching for `location_id' (`iso3') -- `c(current_time)'"
		while _rc == 601 {
			capture confirm file "`out_dir_lymphedema'/`location_id'.csv"
			sleep 1000
		}
		if _rc == 0 {
			noisily display "`iso3' FOUND!"
		}
    }

  // Set the model number and saving parameters
	  ** Microfilaria
	  get_best_model_versions, entity(modelable_entity) ids(1491) clear
	  local mod_num_inf = model_version_id
	  ** Lymphedema
	  get_best_model_versions, entity(modelable_entity) ids(10993) clear
	  local mod_num_oed = model_version_id
	  ** Hydrocele
	  get_best_model_versions, entity(modelable_entity) ids(10994) clear
	  local mod_num_hyd = model_version_id

// Upload to central database
  **qui run "FILEPATH/save_results.do"

  save_results_epi, modelable_entity_id(1492) db_env("prod") input_dir(`out_dir_lymphedema') measure_id(5) description(LF lymphedema prev from dismod model `mod_num_oed' corrected for effect of MDA - `date') input_file_pattern({location_id}.csv) mark_best(TRUE) clear
  save_results_epi, modelable_entity_id(1493) db_env("prod") input_dir(`out_dir_hydrocele') measure_id(5) description(LF hydrocele prev from dismod model `mod_num_hyd' corrected for effect of MDA - `date') input_file_pattern({location_id}.csv) mark_best(TRUE) clear

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// CHECK FILES (NO NEED TO EDIT THIS SECTION)

	// write check file to indicate step has finished
		file open finished using "`out_dir'/finished.txt", replace write
		file close finished

	// if step is last step, write finished.txt file
		local i_last_step 0
		foreach i of local last_steps {
			if "`i'" == "`this_step'" local i_last_step 1
		}

		// only write this file if this is one of the last steps
		if `i_last_step' {

			// account for the fact that last steps may be parallel and don't want to write file before all steps are done
			local num_last_steps = wordcount("`last_steps'")

			// if only one last step
			local write_file 1

			// if parallel last steps
			if `num_last_steps' > 1 {
				foreach i of local last_steps {
					local dir: dir "FILEPATH" dirs "`i'_*", respectcase
					local dir = subinstr(`"`dir'"',`"""',"",.)
					cap confirm file "FILEPATH/finished.txt"
					if _rc local write_file 0
				}
			}

			// write file if all steps finished
			if `write_file' {
				file open all_finished using "FILEPATH/finished.txt", replace write
				file close all_finished
			}
		}

	// close log if open
		if `close_log' log close
