-- ******************************************************************************************************* 
-- STEP 8
--   Export the investigator data
-- *******************************************************************************************************
--------------------------------------------------------------------------------
-- STEP 8.1: Create encounter ID key table 
--------------------------------------------------------------------------------
DROP TABLE XDR_WHERRY_preg_ENCKEY PURGE;
CREATE TABLE XDR_WHERRY_preg_ENCKEY AS
select rownum as encounter_id
		,enc.pat_enc_csn_id
from (SELECT DISTINCT pat_enc_csn_id
FROM xdr_WHERRY_preg_enc) ENC
order by pat_enc_csn_id;

-- Create index to optimize final pull/join
CREATE INDEX XDR_WHERRY_preg_ENCKEY_CSNIDIX ON XDR_WHERRY_preg_DX(PAT_ENC_CSN_ID);

--Add counts for QA
INSERT INTO XDR_WHERRY_preg_COUNTS(TABLE_NAME,PAT_COUNT ,TOTAL_COUNT, DESCRIPTION)
SELECT 'XDR_WHERRY_preg_ENCKEY' AS TABLE_NAME
	,NULL AS PAT_COUNT	
	,COUNT(*) AS TOTAL_COUNT 	
    ,'Create encounter ID key table' AS 	DESCRIPTION
FROM XDR_WHERRY_preg_ENCKEY;
COMMIT;

--------------------------------------------------------------------------------
-- STEP 8.2: Demographics Pull  - Mothers
--			Adding insurance creates duplicates but PI is aware of it
--------------------------------------------------------------------------------
SELECT DISTINCT pat.study_id,
               CASE WHEN ROUND(MONTHS_BETWEEN('08/01/2018',pat.birth_date)/12) >= 90 THEN 90
                    ELSE   ROUND(MONTHS_BETWEEN('08/01/2018',pat.birth_date)/12)      END age,
               pat.sex                            	AS gender,
               pat.mapped_race_name               	AS race,
               pat.ethnic_group                   	AS ethnicity,
               pat.PATIENT_STATUS                 	AS vital_status,
			   extract(year from PAT.LAST_ENC_DATE) AS year_last_encounter,     
			   extract(year from PAT.FIRST_ENC_DATE) AS year_first_encounter,     
               prov.PROV_STUDY_ID,
			   prov.UC_PROVIDER,
			   clepp.BENEFIT_PLAN_NAME,
               fincls.name as FINANCIAL_CLASS,
               pat.mom_child_mc
FROM xdr_WHERRY_preg_pat 	                pat
left join clarity.pat_acct_cvg 			pac on pat.pat_id = pac.pat_id AND pac.account_active_yn = 'Y'
left join clarity.clarity_epp 			clepp on pac.plan_id = clepp.benefit_plan_id
left join clarity.zc_financial_class 		fincls on pac.fin_class = fincls.financial_class
left join xdr_Wherry_preg_prov            prov on pat.CUR_PCP_PROV_ID = prov.PROVIDER_ID
WHERE pat.mom_child_mc = 'M'
;
--------------------------------------------------------------------------------
-- STEP 8.3: Demographics Pull  - Children
--			Adding insurance creates duplicates but PI is aware of it
--------------------------------------------------------------------------------
SELECT DISTINCT pat.study_id,
                mom.study_id                            AS mom_study_id,
                ROUND(pat.birth_date - mom.first_enc_date)  AS age_days_mom_first_enc,
                pat.sex                            		AS gender,
                pat.mapped_race_name               		AS race,
                pat.ethnic_group                   		AS ethnicity,
                pat.PATIENT_STATUS                 		AS vital_status,
			    extract(year from PAT.LAST_ENC_DATE) AS year_last_encounter,     
			    extract(year from PAT.FIRST_ENC_DATE) AS year_first_encounter,   
                prov.PROV_STUDY_ID,
			    prov.UC_PROVIDER,
			    clepp.BENEFIT_PLAN_NAME,
                fincls.name as FINANCIAL_CLASS,
                pat.mom_child_mc
FROM xdr_WHERRY_preg_pat 	                  pat
JOIN xdr_WHERRY_preg_pat 	                  mom on pat.mom_pat_id = mom.pat_id
left join clarity.pat_acct_cvg 				pac on pat.pat_id = pac.pat_id AND pac.account_active_yn = 'Y'
left join clarity.clarity_epp 				clepp on pac.plan_id = clepp.benefit_plan_id
left join clarity.zc_financial_class 		fincls on pac.fin_class = fincls.financial_class
left join xdr_Wherry_preg_prov            prov on pat.CUR_PCP_PROV_ID = prov.PROVIDER_ID
WHERE pat.mom_child_mc = 'C'
;                 
  
  
--------------------------------------------------------------------------------
-- STEP 8.4: Encounters Pull 
--				i2b2.lz_enc_visit_types is an ad hoc table used at UCLA to match encounters to 
--				their PCORNET visit type equivalent (other sites will have to leverage 
--				their own resources to calculate the visit_type)
--------------------------------------------------------------------------------
SELECT DISTINCT pat.study_id
			,enck.ENCOUNTER_ID
            ,enc.ENCOUNTER_TYPE
            ,enc.disposition
            ,enc.ed_disposition
            ,EXTRACT(YEAR FROM enc.EFFECTIVE_DATE_DT) year_enc_date
            ,CASE WHEN pat.mom_child_mc = 'M' THEN ROUND(enc.EFFECTIVE_DATE_DT - pat.first_enc_date) 
				WHEN pat.mom_child_mc = 'C'  THEN ROUND(enc.EFFECTIVE_DATE_DT - mom.first_enc_date) 
				ELSE 9999999
			END enc_dt_days_first_enc
            
            ,EXTRACT(YEAR FROM enc.HOSP_ADMSN_TIME) year_adm_date
            ,CASE WHEN pat.mom_child_mc = 'M' THEN ROUND(enc.HOSP_ADMSN_TIME - pat.first_enc_date) 
				WHEN pat.mom_child_mc = 'C'  THEN ROUND(enc.HOSP_ADMSN_TIME - mom.first_enc_date) 
				ELSE 9999999
			END adm_dt_days_first_enc
            
            ,EXTRACT(YEAR FROM enc.HOSP_DISCHRG_TIME) year_dsch_date
            ,CASE WHEN pat.mom_child_mc = 'M' THEN ROUND(enc.HOSP_DISCHRG_TIME - pat.first_enc_date) 
				WHEN pat.mom_child_mc = 'C'  THEN ROUND(enc.HOSP_DISCHRG_TIME - mom.first_enc_date) 
				ELSE 9999999
			END dsch_dt_days_first_enc
            ,CASE evt.visit_type
					WHEN 'ED' THEN 'Emergency Department only'
					WHEN 'EI' THEN 'Emergency to Inpatient'
					WHEN 'ES' THEN 'Still in ED'
					WHEN 'IP' THEN 'Inpatient'
					WHEN 'AV' THEN 'Ambulatory Visit'
					WHEN 'OT' THEN 'Other'
					WHEN 'UN' THEN 'Unknown'
					WHEN 'OA' THEN 'Other Ambulatory Visit'
					WHEN 'NI' THEN 'No Information'
					WHEN 'IS' THEN 'Non-Acute Institutional Stay' 
					WHEN 'EO' THEN 'Observation'
					WHEN 'IO' THEN 'Observation'
                  ELSE NULL
                END                                                             AS visit_type
            ,prov.PROV_STUDY_ID
            ,enc.SPECIALTY
			,enc.DEPARTMENT_NAME
            ,pat.mom_child_mc
            ,enc.LOC_NAME   location
FROM xdr_Wherry_preg_enc              		enc
JOIN xdr_WHerry_preg_pat               		pat on enc.pat_id = pat.pat_id
--This is an ad hoc table used at UCLA to match encounters to their PCORNET visit type 
LEFT JOIN i2b2.lz_enc_visit_types               evt ON enc.pat_enc_csn_id = evt.pat_enc_csn_id
LEFT JOIN XDR_WHERRY_preg_ENCKEY       		enck on enc.pat_enc_csn_id = enck.pat_enc_csn_id
LEFT JOIN xdr_WHERRY_preg_pat 	    		mom  on pat.mom_pat_id = mom.pat_id AND pat.pat_id = 'C' AND mom.mom_child_mc = 'M'
left join xdr_Wherry_preg_prov            	prov on enc.VISIT_PROV_ID = prov.PROVIDER_ID
;
--------------------------------------------------------------------------------
-- STEP 8.5: Diagnoses Pull 
--			Use the reference table provided to map the ICD code to its description (lz_dx_px_lookup)
--------------------------------------------------------------------------------
select DISTINCT pat.study_id
            ,enck.encounter_id
            ,EXTRACT(YEAR FROM dx.CONTACT_DATE) year_dx_date
            ,CASE WHEN pat.mom_child_mc = 'M' THEN ROUND(dx.CONTACT_DATE - pat.first_enc_date) 
				WHEN pat.mom_child_mc = 'C'  THEN ROUND(dx.CONTACT_DATE - mom.first_enc_date) 
				ELSE 9999999
			END dx_dt_days_first_enc
            ,dx.icd_type
            ,dx.icd_code
            ,dx.PRIMARY_SEC_FLAG
            ,dx.poa_flag
            ,dx.hsp_final_dx_flag
            ,dx.ADMIT_DX_FLAG
            ,case when dx.icd_type = 9 then icd9.icd_desc
                else icd10.icd_desc
            end icd_description
            ,pat.mom_child_mc
from XDR_WHERRY_preg_DX     				dx
JOIN XDR_WHERRY_preg_pat    				pat on dx.pat_id = pat.pat_id
JOIN XDR_WHERRY_preg_ENCKEY    				enck on dx.pat_enc_csn_id = enck.pat_enc_csn_id
LEFT JOIN xdr_WHERRY_preg_pat 	    		mom  on pat.mom_pat_id = mom.pat_id AND pat.pat_id = 'C' AND mom.mom_child_mc = 'M'
LEFT JOIN XDR_WHERRY_preg_DX_LOOKUP        	icd9  ON dx.icd_code = icd9.code
                                              AND icd9.icd_type = 9
LEFT JOIN XDR_WHERRY_preg_DX_LOOKUP        	icd10  ON dx.icd_code = icd10.code
                                              AND icd10.icd_type = 10
;
--------------------------------------------------------------------------------
-- STEP 8.6: Procedures Pull 
--------------------------------------------------------------------------------
select  DISTINCT pat.study_id
               ,enck.encounter_id
               ,EXTRACT(YEAR FROM PRC.PROC_DATE) year_proc_date
               --,ROUND(PRC.PROC_DATE - pat.first_enc_date) proc_dt_days_first_enc
			   
			   ,CASE WHEN pat.mom_child_mc = 'M' THEN ROUND(PRC.PROC_DATE - pat.first_enc_date) 
						WHEN pat.mom_child_mc = 'C' THEN ROUND(PRC.PROC_DATE - mom.first_enc_date) 
					ELSE 9999999
				END proc_dt_days_first_enc
			
               ,prc.ICD_CODE_SET as code_type
               ,prc.PX_CODE as procedure_code
               ,prc.PROCEDURE_NAME
               ,pat.mom_child_mc
from xdr_WHERRY_preg_prc     		prc
JOIN XDR_WHERRY_preg_pat           	pat  on prc.pat_id = pat.pat_id
JOIN XDR_WHERRY_preg_ENCKEY        	enck on prc.pat_enc_csn_id = enck.pat_enc_csn_id
LEFT JOIN xdr_WHERRY_preg_pat 	    mom  on pat.mom_pat_id = mom.pat_id AND pat.pat_id = 'C' AND mom.mom_child_mc = 'M'
;

--------------------------------------------------------------------------------
-- STEP 8.7: Flowsheets Pull 
--------------------------------------------------------------------------------
SELECT DISTINCT flo.study_id
               ,enck.encounter_id
			   ,EXTRACT(YEAR FROM flo.recorded_time) year_recorded_date		   
			   ,CASE WHEN pat.mom_child_mc = 'M' THEN ROUND(flo.recorded_time - pat.first_enc_date) 
						WHEN pat.mom_child_mc = 'C' THEN ROUND(flo.recorded_time - mom.first_enc_date) 
					ELSE 9999999
				END rec_dt_days_first_enc
               ,flo.measure_name      AS vital_sign_type
               ,flo.measure_value     AS vital_sign_value
               ,flo.mom_child_mc
FROM xdr_WHERRY_preg_flo          flo
JOIN XDR_WHERRY_preg_pat          pat  on flo.pat_id = pat.pat_id
JOIN XDR_WHERRY_preg_ENCKEY       enck on flo.pat_enc_csn_id = enck.pat_enc_csn_id
LEFT JOIN xdr_WHERRY_preg_pat 	    		mom  on pat.mom_pat_id = mom.pat_id AND pat.pat_id = 'C' AND mom.mom_child_mc = 'M'
;

--------------------------------------------------------------------------------
-- STEP 8.8: Lab Pull 
--------------------------------------------------------------------------------
SELECT DISTINCT lab.study_id
               ,enck.encounter_id
               ,lab.proc_id                
               ,lab.description           
               ,lab.component_id       
               ,lab.component_name                     
               ,EXTRACT(YEAR FROM lab.order_time) year_order_date
			   ,CASE WHEN pat.mom_child_mc = 'M' THEN ROUND(lab.order_time - pat.first_enc_date) 
						WHEN pat.mom_child_mc = 'C' THEN ROUND(lab.order_time - mom.first_enc_date) 
					ELSE 9999999
				END order_dt_days_first_enc				
               ,EXTRACT(YEAR FROM lab.RESULT_time) year_RESULT_date
			   ,CASE WHEN pat.mom_child_mc = 'M' THEN ROUND(lab.RESULT_time - pat.first_enc_date) 
						WHEN pat.mom_child_mc = 'C' THEN ROUND(lab.RESULT_time - mom.first_enc_date) 
					ELSE 9999999
				END RESULT_dt_days_first_enc
               ,lab.ord_value               AS results
               ,lab.reference_unit          
			   ,lab.reference_low 
               ,lab.reference_high
               ,lab.mom_child_mc
FROM xdr_WHERRY_preg_lab          			lab 
JOIN XDR_WHERRY_preg_pat          			pat  on lab.pat_id = pat.pat_id
JOIN XDR_WHERRY_preg_ENCKEY       			enck on lab.pat_enc_csn_id = enck.pat_enc_csn_id
LEFT JOIN xdr_WHERRY_preg_pat 	    		mom  on pat.mom_pat_id = mom.pat_id AND pat.pat_id = 'C' AND mom.mom_child_mc = 'M'
LEFT JOIN clarity.clarity_component                 cc ON lab.component_id = cc.component_id
;


--------------------------------------------------------------------------------
-- STEP 8.9: medications Pull 
--------------------------------------------------------------------------------
SELECT DISTINCT med.study_id
               ,enck.encounter_id
               ,med.order_med_id
               ,EXTRACT(YEAR FROM nvl(med.taken_time, med.ORDER_INST))   AS taken_time_order_date
               ,CASE WHEN pat.mom_child_mc = 'M' THEN ROUND(nvl(med.taken_time, med.ORDER_INST) - pat.first_enc_date) 
						WHEN pat.mom_child_mc = 'C' THEN ROUND(nvl(med.taken_time, med.ORDER_INST)- mom.first_enc_date) 
					ELSE 9999999
				END order_dt_days_first_enc                
               ,EXTRACT(YEAR FROM med.ORDER_INST) year_order_date
			   ,CASE WHEN pat.mom_child_mc = 'M' THEN ROUND(med.ORDER_INST - pat.first_enc_date) 
						WHEN pat.mom_child_mc = 'C' THEN ROUND(med.ORDER_INST - mom.first_enc_date) 
					ELSE 9999999
				END taken_dt_days_first_enc				
               ,EXTRACT(YEAR FROM med.ORDER_START_TIME) year_start_date
			   ,CASE WHEN pat.mom_child_mc = 'M' THEN ROUND(med.ORDER_START_TIME - pat.first_enc_date) 
						WHEN pat.mom_child_mc = 'C' THEN ROUND(med.ORDER_START_TIME - mom.first_enc_date) 
					ELSE 9999999
				END start_dt_days_first_enc
               ,EXTRACT(YEAR FROM med.ORDER_END_TIME) year_end_date
			   ,CASE WHEN pat.mom_child_mc = 'M' THEN ROUND(med.ORDER_END_TIME - pat.first_enc_date) 
						WHEN pat.mom_child_mc = 'C' THEN ROUND(med.ORDER_END_TIME - mom.first_enc_date) 
					ELSE 9999999
				END end_dt_days_first_enc
               ,med.medication_name
               ,med.generic_name
               ,med.sig
               ,med.HV_DISCRETE_DOSE            AS dose
               ,med.DOSE_UNIT
               ,med.FREQ_NAME                   AS FREQUENCY        
               ,med.pharm_class
               ,med.pharm_subclass
               ,MED.ORDER_STATUS
               ,MED.ORDER_CLASS
               ,med.mom_child_mc
FROM xdr_WHERRY_preg_med          			med
JOIN XDR_WHERRY_preg_pat          			pat  on med.pat_id = pat.pat_id
JOIN XDR_WHERRY_preg_ENCKEY       			enck on med.pat_enc_csn_id = enck.pat_enc_csn_id
LEFT JOIN xdr_WHERRY_preg_pat 	    		mom  on pat.mom_pat_id = mom.pat_id AND pat.pat_id = 'C' AND mom.mom_child_mc = 'M'
WHERE nvl(med.taken_time, med.ORDER_INST) BETWEEN '01/01/2006' AND '02/05/2018'
;


--------------------------------------------------------------------------------
-- STEP 8.10: Allergies Pull 
--------------------------------------------------------------------------------
SELECT DISTINCT alg.study_id
               ,alg.DESCRIPTION             AS allergen_name
               ,EXTRACT(YEAR FROM alg.DATE_NOTED) year_noted_date
			   ,CASE WHEN pat.mom_child_mc = 'M' THEN ROUND(alg.DATE_NOTED - pat.first_enc_date) 
						WHEN pat.mom_child_mc = 'C' THEN ROUND(alg.DATE_NOTED - mom.first_enc_date) 
					ELSE 9999999
				END noted_dt_days_first_enc

               ,alg.reaction
               ,alg.allergy_status
               ,alg.severity
               ,alg.mom_child_mc
FROM xdr_WHERRY_preg_alg                alg
JOIN XDR_WHERRY_preg_pat    		    pat ON alg.pat_id = pat.pat_id
LEFT JOIN xdr_WHERRY_preg_pat 	    	mom ON pat.mom_pat_id = mom.pat_id AND pat.pat_id = 'C' AND mom.mom_child_mc = 'M'
;


--------------------------------------------------------------------------------
-- STEP 8.11: Family History Pull 
--------------------------------------------------------------------------------
SELECT DISTINCT fam.study_id
                ,enck.encounter_id
                ,fam.line
                ,fam.medical_hx
                ,fam.relation
                ,fam.mom_child_mc
FROM xdr_Wherry_preg_fam        fam
JOIN XDR_WHERRY_preg_pat    	pat on fam.pat_id = pat.pat_id
JOIN XDR_WHERRY_preg_ENCKEY     enck on fam.pat_enc_csn_id = enck.pat_enc_csn_id
;


--------------------------------------------------------------------------------
-- STEP 8.12: Social History Pull 
--------------------------------------------------------------------------------
SELECT DISTINCT soc.study_id
               ,soc.tobacco_user            
               ,soc.tobacco_pak_per_dy
               ,soc.tobacco_used_years
               ,soc.cigarettes_yn
               ,soc.smoking_tob_status
               ,EXTRACT(YEAR FROM soc.smoking_start_date) year_smk_start_date
			   ,CASE WHEN pat.mom_child_mc = 'M' THEN ROUND(soc.smoking_start_date - pat.first_enc_date) 
						WHEN pat.mom_child_mc = 'C' THEN ROUND(soc.smoking_start_date - mom.first_enc_date) 
					ELSE 9999999
				END smk_start_days_after_first_enc
               ,EXTRACT(YEAR FROM soc.smoking_quit_date) year_smk_quit_date
               ,CASE WHEN pat.mom_child_mc = 'M' THEN ROUND(soc.smoking_quit_date - pat.first_enc_date) 
						WHEN pat.mom_child_mc = 'C' THEN ROUND(soc.smoking_quit_date - mom.first_enc_date) 
					ELSE 9999999
				END smk_quit_days_after_first_enc
			   ,soc.alcohol_user
               ,soc.alcohol_oz_per_wk
               ,soc.alcohol_type
               ,soc.iv_drug_user_yn 
               ,soc.illicit_drug_freq  
               ,soc.mom_child_mc
  FROM xdr_WHERRY_preg_soc          soc
  JOIN XDR_WHERRY_preg_pat    	    pat on soc.pat_id = pat.pat_id
  --LEFT JOIN xdr_wherry_all_mom_child 			lnk  on lab.pat_id = lnk.nb_pat_id AND pat.mom_child_mc = 'C'
  LEFT JOIN xdr_WHERRY_preg_pat 	    		mom  on pat.mom_pat_id = mom.pat_id AND pat.pat_id = 'C' AND mom.mom_child_mc = 'M'
  ;
  
--------------------------------------------------------------------------------
-- STEP 8.13: Providers table
--------------------------------------------------------------------------------
SELECT DISTINCT PROV_STUDY_ID
		,PRIMARY_SPECIALTY
		,PROVIDER_TYPE
		,UC_PROVIDER
		,ACTIVE_PROVIDERS
FROM xdr_Wherry_preg_prov
;

--------------------------------------------------------------------------------
-- STEP 8.14: Problem List Diagnosis Pull 
--------------------------------------------------------------------------------
SELECT DISTINCT pat.study_id
               ,enck.encounter_id
               ,pdx.diagnosis_source
               ,pdx.icd_type
               ,pdx.icd_code
               ,pdx.icd_desc
               ,EXTRACT(YEAR FROM pdx.diagnosis_date) year_diagnosis_date
			   ,CASE WHEN pat.mom_child_mc = 'M' THEN ROUND(pdx.diagnosis_date - pat.first_enc_date) 
						WHEN pat.mom_child_mc = 'C' THEN ROUND(pdx.diagnosis_date - mom.first_enc_date) 
					ELSE 9999999
				END diagnosis_dt_days_first_enc				
               ,EXTRACT(YEAR FROM pdx.RESOLVED_DATE) year_RESOLVED_DATE
			   ,CASE WHEN pat.mom_child_mc = 'M' THEN ROUND(pdx.RESOLVED_DATE - pat.first_enc_date) 
						WHEN pat.mom_child_mc = 'C' THEN ROUND(pdx.RESOLVED_DATE - mom.first_enc_date) 
					ELSE 9999999
				END resolved_dt_days_first_enc
               ,pdx.priority
               ,pdx.problem_status
               ,pdx.primary_dx_yn
			   ,pat.mom_child_mc
  FROM xdr_Wherry_preg_pldx              pdx
  JOIN xdr_WHerry_preg_pat               pat on pdx.pat_id = pat.pat_id
  LEFT JOIN XDR_WHERRY_preg_ENCKEY       enck on pdx.pat_enc_csn_id = enck.pat_enc_csn_id
  LEFT JOIN xdr_WHERRY_preg_pat 	    		mom  on pat.mom_pat_id = mom.pat_id AND pat.pat_id = 'C' AND mom.mom_child_mc = 'M'
  ;
  
--------------------------------------------------------------------------------
-- STEP 8.15: Pull mother - child linkage
--------------------------------------------------------------------------------
SELECT mom.study_id as mom_study_id
		,cld.study_id as child_study_id
		--flags
		,lnk.address_match
		,lnk.phone_match
		,lnk.email_match
		,lnk.proxy_match
		,lnk.SIMILAR_ADDRESS
FROM xdr_wherry_all_mom_child				lnk
left JOIN xdr_WHerry_preg_pat               mom on lnk.mom_pat_id = mom.pat_id AND mom.mom_child_mc = 'M'
left JOIN xdr_WHerry_preg_pat               cld on lnk.child_pat_id = cld.pat_id AND cld.mom_child_mc = 'C';
 
--------------------------------------------------------------------------------
-- STEP 8.16: Data counts 
--------------------------------------------------------------------------------
SELECT * FROM XDR_WHERRY_preg_COUNTS;


--------------------------------------------------------------------------------
-- STEP 8.17: Mother child matching vector
--------------------------------------------------------------------------------
SELECT * FROM XDR_WHERRY_PREG_MTCHING_VECTOR;