/*==================================================
  KC20260325001 ICI 코호트 STEP 01  (최종본)
  2026-07-27
==================================================*/

/*===== STEP 0. 세션 준비 =====*/
libname kcure "/home/sasuser/project/kc20260325001/src/data";
options dlcreatedir;
libname out "/home/sasuser/out";

options nodate nonumber;
ods graphics off;

data out.test; x=1; run;
proc print data=out.test; run;

ods rtf   file="/home/sasuser/out/RESULT_step01_0727.rtf" bodytitle;
ods excel file="/home/sasuser/out/RESULT_step01_0727.xlsx"
          options(sheet_interval="proc" embedded_titles="yes");

/*----- 0-1. 테이블 목록 (파티션 확인) -----*/
title1 "0-1. KCURE 테이블 목록";
proc sql;
  select memname, nobs, nvar
  from dictionary.tables
  where libname='KCURE'
  order by memname;
quit;

/*----- 0-2. ★ 조직형 실제 값 (블로커 판정) -----*/
title1 "0-2. RGST 변수 목록";
proc contents data=kcure.kc20260325001_rgst varnum; run;

title1 "0-2b. ★ MCODE_GRP 실제 값 분포";
proc freq data=kcure.kc20260325001_rgst order=freq;
  tables MCODE_GRP / missing;
run;

/*  판정
    5자리('80203' 등)  -> 그대로 진행
    1~17 / '01'~'17'   -> 45코드 매칭 0건. 요청그룹 값 확인 후 STEP 1-2 교체
    MCODE 컬럼 별도    -> keep= 과 mcode= 를 MCODE 로 변경             */


/*===== STEP 1. NSCLC 코호트 =====*/

/*----- 1-1. 결측 판정 + 분리 -----*/
data nsclc_all nsclc_drop;
  set kcure.kc20260325001_rgst(keep=SNKEY MCODE_GRP FDX);
  length mcode $8;
  mcode = upcase(strip(cats(MCODE_GRP)));

  miss_key   = missing(SNKEY);
  miss_mcode = (mcode in ('','.','NULL','NA','9999','999999'));
  miss_fdx   = (cats(FDX) in ('','.','NULL') or missing(FDX));

  fdx_ymd = input(cats(FDX), ??8.);

  if miss_key or miss_mcode then output nsclc_drop;
  else output nsclc_all;
run;

title1 "A-1. RGST 구조적 결측 제외 건수";
proc sql;
  select count(*)        as n_drop     label='제외 총건',
         sum(miss_key)   as miss_snkey label='SNKEY 결측',
         sum(miss_mcode) as miss_mcode label='조직형 결측'
  from nsclc_drop;
quit;

title1 "A-2. FDX 결측 (제외 안 함, 기록만)";
proc freq data=nsclc_all; tables miss_fdx / out=out.a2_missfdx; run;

/*----- 1-2. 45개 조직형 코드 양성 선택 -----*/
data nsclc_sel;
  set nsclc_all;
  if mcode in (
    '80203','80213','80223',
    '80303','80313','80323','80333','80343','80353',
    '80463',
    '80502','80503','80513','80522','80523','80702','80703','80713',
    '80723','80733','80743','80753','80762','80763','80783','80823',
    '80833','80843',
    '81402','81403','81413','81433','81473',
    '82502','82503','82513','82523','82532','82533','82543','82553',
    '85603','85623',
    '89723','89733'
  );
run;

title1 "B-1. 조직형 코드별 레코드 빈도";
proc freq data=nsclc_sel order=freq;
  tables mcode / out=out.b1_mcode;
run;

/*----- 1-3. 환자당 중복 레코드 -----*/
proc sql;
  create table dup_chk as
  select SNKEY, count(*) as n_rec from nsclc_sel group by SNKEY;
quit;

title1 "B-2. 환자당 NSCLC 레코드 수 분포";
proc freq data=dup_chk; tables n_rec / out=out.b2_dup; run;

/*----- 1-4. 환자별 최초진단 1건 (FDX 결측은 뒤로) -----*/
data nsclc_sel2;
  set nsclc_sel;
  srt = ifn(missing(fdx_ymd), 99999999, fdx_ymd);
run;

proc sort data=nsclc_sel2; by SNKEY srt; run;

data nsclc_cohort;
  set nsclc_sel2;
  by SNKEY;
  if first.SNKEY;
run;

title1 "B-3. NSCLC 코호트 최종 인원";
proc sql; select count(*) as N_nsclc from nsclc_cohort; quit;

data out.nsclc_cohort; set nsclc_cohort; run;


/*===== STEP 2. T200 제한 =====*/
proc sql;
  create table t200_sub as
  select b.SNKEY, b.fdx_ymd, b.mcode,
         a.MID,
         input(cats(a.RECU_FR_DD), ??8.) as ymd,
         a.PAT_AGE, a.CL_CD, a.INSUP_TP_CD, a.MAIDCL_CD,
         a.OINJ_TP_CD, a.RVD_PLC_CD, a.FOM_TP_CD
  from kcure.kc20260325001_t200_1623 as a
  inner join nsclc_cohort as b
    on a.SNKEY = b.SNKEY
  where a.MID is not null and a.RECU_FR_DD is not null;
quit;

title1 "C-1. T200 제한 후 청구 건수 및 날짜 결측";
proc means data=t200_sub n nmiss maxdec=0; var ymd; run;


/*===== STEP 3. ICI 청구 추출 =====*/
data t300_ici;
  set kcure.kc20260325001_t300_1517
      kcure.kc20260325001_t300_1820
      kcure.kc20260325001_t300_2123;
  if missing(MID) or missing(GNL_CD) then delete;
  code4 = substr(cats(GNL_CD),1,4);
  if code4 in ('6577','6384','6390');
  keep MID code4;
run;

proc sort data=t300_ici nodupkey; by MID code4; run;

title1 "C-2. T300 ICI 청구 건수 (약제별)";
proc freq data=t300_ici; tables code4 / out=out.c2_ici; run;

proc sql;
  create table ici_claims as
  select a.*, b.code4
  from t200_sub as a
  inner join t300_ici as b on a.MID = b.MID
  where a.ymd is not null;
quit;

title1 "C-3. MID 조인 후 ICI 청구·환자 수";
proc sql;
  select count(*) as n_claims, count(distinct SNKEY) as n_pts
  from ici_claims;
quit;

data out.ici_claims; set ici_claims; run;


/*===== STEP 4. 환자별 최초 ICI = index =====*/
title1 "D-0. 같은 날 2종 이상 ICI 청구 환자";
proc sql;
  select count(*) as n_sameday from
    (select SNKEY from ici_claims group by SNKEY, ymd
     having count(distinct code4) > 1);
quit;

proc sort data=ici_claims; by SNKEY ymd code4; run;

data ici_index;
  set ici_claims;
  by SNKEY;
  if first.SNKEY;
  index_ymd = ymd;
  length index_drug $6;
  if      code4='6577' then index_drug='atezo';
  else if code4='6384' then index_drug='nivo';
  else if code4='6390' then index_drug='pembro';
  index_yr = int(index_ymd/10000);
run;

title1 "D-1. 약제별 환자 N (index 기준)";
proc freq data=ici_index; tables index_drug / out=out.d1_drug; run;


/*===== STEP 5. 기간 제한 + 정책 전후 =====*/
data cohort_final;
  set ici_index;
  if 20170821 <= index_ymd <= 20211231;

  length period $2 ctrl $8;
  if index_ymd < 20190723 then period='P1';
  else                         period='P2';

  yr = int(index_ymd/10000);
  mo = int(mod(index_ymd,10000)/100);
  yq = cats(put(yr,4.),'Q',put(ceil(mo/3),1.));

  if index_drug='atezo' then ctrl='atezo';
  else                       ctrl='control';
run;

data out.cohort_final; set cohort_final; run;


/*===== STEP 6. Attrition + ★ 약제 x 기간 =====*/
title1 "E-1. 코호트 구축 단계별 인원 (Table S0)";
proc sql;
  create table out.e1_attr as
  select 'a. RGST 전체 레코드' as step, count(*) as n
         from kcure.kc20260325001_rgst
  union all select 'b. 구조적 결측 제외',    count(*) from nsclc_all
  union all select 'c. NSCLC 45코드 레코드', count(*) from nsclc_sel
  union all select 'd. NSCLC 환자(코호트)',  count(*) from nsclc_cohort
  union all select 'e. ICI 청구 있음', count(distinct SNKEY) from ici_claims
  union all select 'f. index 기간 제한 후',  count(*) from cohort_final;
quit;
proc print data=out.e1_attr noobs; run;

title1 "E-2. ★ 약제 x 기간 교차 (최우선)";
proc freq data=cohort_final;
  tables index_drug*period / out=out.e2_drugperiod;
  tables ctrl*period       / out=out.e3_ctrlperiod;
run;


/*===== STEP 7. 분기별 추이 (Table S1) =====*/
title1 "F-1. 분기별 index ICI initiator";
proc freq data=cohort_final;
  tables yq*index_drug / out=out.f1_quarter;
run;

title1 "F-2. 분기별 교차표";
proc tabulate data=cohort_final;
  class yq index_drug;
  table yq, index_drug*n all*n / rts=14;
run;


/*===== STEP 8. BFC 연도 매칭 (★ 1:1 확인) =====*/
proc sql;
  create table bfc_chk as
  select SNKEY, count(*) as n_yr
  from kcure.kc20260325001_bfc group by SNKEY;
quit;

title1 "G-1. BFC 환자당 연도 레코드 수";
proc freq data=bfc_chk; tables n_yr / out=out.g1_bfcyr; run;

proc sql;
  create table cohort_bfc as
  select a.*,
         b.GAIBJA_TYPE, b.SIDO_CD, b.CALC_CTRB_VTILE_FD,
         b.CNT_ID_HHHI_FD, b.STD_YYYY
  from cohort_final as a
  left join kcure.kc20260325001_bfc as b
    on a.SNKEY = b.SNKEY
   and a.index_yr = input(cats(b.STD_YYYY), ??4.);
quit;

title1 "G-2. ★ 매칭 후 행수 vs 환자수 (같아야 정상)";
proc sql;
  select count(*) as n_rows, count(distinct SNKEY) as n_pts
  from cohort_bfc;
quit;

/*  다르면 여기서 멈추고 원인 확인. 진행하면 사회경제 변수 전부 뻥튀기. */


/*===== STEP 9. 파생변수 + 결측 기록 =====*/
data cohort_flag;
  set cohort_bfc;

  /* 문자형 -> 숫자 정규화 */
  _gaib = input(cats(GAIBJA_TYPE),        ??2.);
  _sido = input(cats(SIDO_CD),            ??2.);
  _prem = input(cats(CALC_CTRB_VTILE_FD), ??2.);
  _hh   = input(cats(CNT_ID_HHHI_FD),     ??2.);

  /* 결측 플래그 (제외하지 않고 기록) */
  m_gaibja = missing(_gaib);
  m_sido   = missing(_sido);
  m_prem   = missing(_prem);
  m_hh     = missing(_hh);
  m_maidcl = (cats(MAIDCL_CD) in ('','.','0'));
  m_age    = missing(PAT_AGE);
  m_fdx    = missing(fdx_ymd);
  m_stdyy  = missing(STD_YYYY);
  n_miss   = sum(of m_:);
  complete = (n_miss = 0);

  length maid_cl $4 ins_type $10 prem_g $8 hh_g $8
         resid_g $12 age_g $8;

  /* 의료급여 종별 */
  if      cats(MAIDCL_CD) in ('1','4','N') then maid_cl='1종';
  else if cats(MAIDCL_CD) in ('2','6','8') then maid_cl='2종';
  else                                          maid_cl='NA';

  /* 보험 유형 */
  if      _gaib in (5,6) then ins_type='직장';
  else if _gaib in (1,2) then ins_type='지역';
  else if _gaib in (7,8) then ins_type='의료급여';
  else                        ins_type='Unknown';

  /* 보험료 분위 */
  if      _prem = 0       then prem_g='0_MA';
  else if _prem in (1,2)  then prem_g='1-2';
  else if _prem in (3,4)  then prem_g='3-4';
  else if _prem in (5,6)  then prem_g='5-6';
  else if _prem in (7,8)  then prem_g='7-8';
  else if _prem in (9,10) then prem_g='9-10';
  else                         prem_g='Unknown';

  /* 가구원수 */
  if      _hh = 1      then hh_g='1인';
  else if _hh = 2      then hh_g='2인';
  else if _hh in (3,4) then hh_g='3-4인';
  else if _hh = 5      then hh_g='5인+';
  else                      hh_g='Unknown';

  /* 거주지 */
  if      _sido = 11                               then resid_g='서울';
  else if _sido in (28,41)                         then resid_g='인천경기';
  else if _sido in (26,27,29,30,31)                then resid_g='광역시';
  else if _sido in (36,42,43,44,45,46,47,48,50,51) then resid_g='도세종제주';
  else                                                  resid_g='Unknown';

  /* 연령대 */
  if      PAT_AGE < 65 then age_g='<65';
  else if PAT_AGE < 70 then age_g='65-69';
  else if PAT_AGE < 75 then age_g='70-74';
  else if PAT_AGE >=75 then age_g='75+';
  else                      age_g='Unknown';

  /* 이진 outcome - 결측은 결측으로 유지 */
  nearpoor = (cats(OINJ_TP_CD) in ('C','E','F'));
  if not m_gaibja then medaid     = (_gaib in (7,8));
  if not m_sido   then noncapital = (_sido not in (11,28,41));
  if not m_age    then age70      = (PAT_AGE >= 70);
run;

title1 "H-1. 변수별 결측 인원 (약제 x 기간)";
ods output CrossTabFreqs=out.h1_missing;
proc freq data=cohort_flag;
  tables (m_gaibja m_sido m_prem m_hh m_maidcl m_age m_fdx m_stdyy)
         *index_drug*period;
run;
ods output close;

title1 "H-2. 환자별 결측 변수 개수 / complete-case";
proc freq data=cohort_flag;
  tables n_miss / out=out.h2_nmiss;
  tables complete*index_drug*period / out=out.h3_complete;
run;

data out.cohort_flag; set cohort_flag; run;


/*===== STEP 10. Table 1 - 사회경제·거주 =====*/
title1 "I-1. 사회경제·거주 특성 (약제 x 기간)";
ods output CrossTabFreqs=out.i1_ses;
proc freq data=cohort_flag;
  tables (medaid maid_cl nearpoor ins_type prem_g hh_g
          noncapital resid_g age70 age_g)
         *index_drug*period / missing;
run;
ods output close;

title1 "I-2. 연령 중앙값 (IQR)";
proc means data=cohort_flag median q1 q3 maxdec=1;
  class index_drug period;
  var PAT_AGE;
  output out=out.i2_age median=med q1=q1 q3=q3;
run;


/*===== STEP 11. 반출 대비 - 5 미만 셀 =====*/
title1 "Z-1. 반출 제한 후보: 5 미만 셀";
data out.z1_smallcell;
  length source $32;
  set out.e2_drugperiod(keep=index_drug period count)
      out.f1_quarter(keep=yq index_drug count)
      out.h1_missing(keep=_TABLE_ index_drug period Frequency
                     rename=(Frequency=count))
      out.i1_ses(keep=_TABLE_ index_drug period Frequency
                 rename=(Frequency=count))
      indsname=src;
  source = src;
  if 0 < count < 5;
run;
proc print data=out.z1_smallcell noobs; run;


/*===== STEP 12. 결과 파일 닫기 (필수) =====*/
title;
ods excel close;
ods rtf close;

proc datasets library=out; run;
