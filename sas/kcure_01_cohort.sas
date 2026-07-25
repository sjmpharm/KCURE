/*==============================================================================
  K-CURE 진행성 NSCLC ICI 코호트 연구 (과제 KC20260325001)
  01. 코호트 구축 + Table S0(attrition) + Table S1(quarterly) + 우선순위 진단 3
  ------------------------------------------------------------------------------
  담당: 손지민 (262IPG01)   /   작성 목적: 분석관 방문용 1차 실행 스크립트
  실행 순서(계획서 그대로):
    1) RGST에서 NSCLC 코호트   : 45개 조직형 코드 양성 선택 (SCLC 자동 제외)
    2) T200을 코호트로 제한     : MID + RECU_FR_DD, PAT_AGE, CL_CD, INSUP_TP_CD
    3) T300에서 ICI 추출        : GNL_CD 앞 4자리 6384/6390/6577
    4) 환자별 최초 ICI          : index date / index drug
    5) index 기간 제한          : 2017-08-21 ~ 2021-12-31
    6) 정책 전후 분리           : 2019-07-23 기준 P1/P2
  산출물: out.cohort_nsclc, out.ici_initiator, Table S0/S1, 진단 리포트
  ============================================================================*/

options nofmterr mprint mlogic symbolgen ls=200 ps=max nocenter;
options msglevel=i;

/*------------------------------------------------------------------------------
  [CONFIG] 분석관 환경에 맞게 이 블록만 수정하세요
  ----------------------------------------------------------------------------*/
%let RAW = /userdata/kcure/raw;      /* 원시 테이블(RGST,T200,T300,DEATH,BFC ...) 경로 */
%let OUT = /userdata/kcure/work;     /* 산출물 저장 경로                               */

libname raw "&RAW" access=readonly;  /* 원시자료는 읽기 전용 권장 */
libname out "&OUT";

/* --- 변수명(테이블마다 실제 컬럼명이 다르면 여기서 교체) --- */
%let ID     = SNKEY;      /* 개인식별키 : RGST / DEATH / BFC / T200 공통          */
%let MIDV   = MID;        /* 명세서조인키 : T200 <-> T300/T400/T530               */
%let MCODEV = MCODE;      /* ★조직형(5자리 ICD-O-3) 컬럼. 아래 [주의1] 확인 필수 */
%let ICD10V = ICD10;      /* RGST 국제질병분류코드                                */
%let GNLV   = GNL_CD;     /* 일반명코드 (T300)                                    */

/* --- 기간/정책 상수 --- */
%let IDX_START = '21AUG2017'd;   /* nivo/pembro 급여 개시 = ICI index 시작 */
%let IDX_END   = '31DEC2021'd;   /* index 종료                             */
%let POLICY    = '23JUL2019'd;   /* atezo PD-L1 기준 삭제 → P1/P2 분리     */

/* --- 토글 --- */
%let EXCL_METHOD0 = 0;    /* 1이면 METHOD=0(DCO) 하드 제외. 이번 방문 S0는 미적용(0), 플래그만 생성 */

/*------------------------------------------------------------------------------
  [주의1] 조직형 변수: 계획은 45개 "5자리 MCODE" 코드로 선택.
    - K-CURE 맞춤 DB에서 '연구자 요청 그룹'을 신청했으므로 실제 제공 형태가
      (a) 원시 5자리 MCODE 컬럼      → &MCODEV = MCODE  로 두고 아래 45코드 사용
      (b) 요청그룹으로 재코딩된 MCODE_GRP → &MCODEV = MCODE_GRP 로 바꾸고
          nsclc_codes 대신 해당 그룹값(예: '01')으로 비교하도록 4번 주석 참고
    - 분석관에서 RGST 컬럼 목록(proc contents) 먼저 확인 후 확정.
  [주의2] 날짜 컬럼은 VARCHAR(8) 'YYYYMMDD' 가정 → input(var, yymmdd8.) 변환.
          숫자로 저장돼 있으면 input(put(var,z8.), yymmdd8.) 로 교체.
  ----------------------------------------------------------------------------*/


/*==============================================================================
  STEP 1. RGST → NSCLC 코호트 (45개 조직형 코드)
  ============================================================================*/

/* 1-a. NSCLC 포함 45코드 / SCLC 제외 5코드(참고·검증용) */
%let nsclc_codes =
  '80203' '80213' '80223'
  '80303' '80313' '80323' '80333' '80343' '80353'
  '80463'
  '80502' '80503' '80513' '80522' '80523'
  '80702' '80703' '80713' '80723' '80733' '80743' '80753' '80762' '80763' '80783'
  '80823' '80833' '80843'
  '81402' '81403' '81413' '81433' '81473'
  '82502' '82503' '82513' '82523' '82532' '82533' '82543' '82553'
  '85603' '85623'
  '89723' '89733';                                   /* = 45개 */
%let sclc_codes = '80413' '80423' '80433' '80443' '80453';  /* 목록에 없어 자동 제외(검증용) */

/* 1-b. RGST 정규화: 조직형 코드 문자열화(숫자/소수점/공백 모두 흡수), 날짜 파싱 */
data rgst_norm;
  set raw.RGST;
  length _mc $8;
  _mc = compress(cats(&MCODEV), '. ');               /* 80203.0/80203/'80203' → '80203' */
  fdx_dt = input(cats(FDX), yymmdd8.);               /* 최초진단일 */
  format fdx_dt yymmdd10.;
  is_c34   = (upcase(substr(cats(&ICD10V),1,3)) = 'C34');
  is_nsclc = (_mc in (&nsclc_codes));
  is_sclc  = (_mc in (&sclc_codes));
run;

/* 1-c. C34 & NSCLC 조직형 레코드만 → 개인별 index 등록 1건(최초 FDX) 선택 */
proc sort data=rgst_norm(where=(is_c34=1 and is_nsclc=1)) out=rgst_nsclc_all;
  by &ID fdx_dt;
run;

/* 다중원발/중복 레코드 진단용: 개인별 NSCLC C34 등록 건수 */
proc sql;
  create table _rgst_cnt as
  select &ID, count(*) as n_nsclc_reg
  from rgst_nsclc_all group by &ID;
quit;

data out.cohort_nsclc;                               /* 개인 1행 = index 암등록(최초 진단) */
  merge rgst_nsclc_all _rgst_cnt;
  by &ID;
  if first.&ID;                                      /* 최초 FDX 레코드 채택 */
  mult_primary_flag = (n_nsclc_reg > 1);             /* [우선순위2] 다중원발 = 제외 아님, 기록 */
  method0_flag      = (cats(METHOD) = '0');          /* DCO(사망진단서만) 플래그 */
run;

%if &EXCL_METHOD0 = 1 %then %do;
  data out.cohort_nsclc; set out.cohort_nsclc; if method0_flag=0; run;
%end;


/*==============================================================================
  STEP 2. T200을 코호트 SNKEY로 제한 → 명세서 키/날짜/특성 확보
  ============================================================================*/
proc sql;
  create table t200_coh as
  select a.&ID,
         a.&MIDV       as MID length=10,
         a.RECU_FR_DD,
         input(cats(a.RECU_FR_DD), yymmdd8.) as recu_dt format=yymmdd10.,
         a.PAT_AGE,
         a.CL_CD,
         a.INSUP_TP_CD
  from raw.T200 as a
  inner join out.cohort_nsclc as b
    on a.&ID = b.&ID;
quit;


/*==============================================================================
  STEP 3. T300에서 ICI 추출 (GNL_CD 앞 4자리)  →  3분할 없이 한 번에 매핑
    6384 = Nivolumab(옵디보) / 6390 = Pembrolizumab(키트루다) / 6577 = Atezolizumab(티쎈트릭)
  ============================================================================*/
data t300_ici;
  set raw.T300(keep=&MIDV &GNLV);
  length index_drug $12;
  _g4 = substr(cats(&GNLV),1,4);
  select (_g4);
    when ('6384') index_drug = 'Nivolumab';
    when ('6390') index_drug = 'Pembrolizumab';
    when ('6577') index_drug = 'Atezolizumab';
    otherwise delete;                                /* ICI 아님 */
  end;
  rename &MIDV = MID;
  keep &MIDV index_drug;
run;

/* ICI 라인 → 명세서(T200)로 붙여 개인/날짜 부여 (코호트 내 명세서에만 매칭) */
proc sql;
  create table ici_claims as
  select distinct
         t.&ID, t.MID, t.recu_dt, i.index_drug
  from t200_coh as t
  inner join t300_ici as i
    on t.MID = i.MID;
quit;


/*==============================================================================
  STEP 4. 환자별 최초 ICI = index date / index drug
  ============================================================================*/
proc sort data=ici_claims; by &ID recu_dt index_drug; run;

/* 같은 날 서로 다른 ICI 동시청구 진단(드묾) */
proc sql;
  create table _sameday as
  select &ID, recu_dt, count(distinct index_drug) as n_drug_day
  from ici_claims group by &ID, recu_dt
  having n_drug_day > 1;
quit;

data ici_first;
  set ici_claims;
  by &ID recu_dt index_drug;
  if first.&ID;                                      /* 최초 청구일의 (정렬상 첫) 약제 = index drug */
  index_dt = recu_dt;
  format index_dt yymmdd10.;
  keep &ID index_dt index_drug;
run;


/*==============================================================================
  STEP 5 & 6. index 기간 제한 + 정책 전후(P1/P2) 분리
  ============================================================================*/
data out.ici_initiator;
  merge ici_first(in=a) out.cohort_nsclc(in=b keep=&ID mult_primary_flag method0_flag);
  by &ID;
  if a;
  in_window = (&IDX_START <= index_dt <= &IDX_END);
  if in_window;                                      /* STEP 5 */

  length period $2;                                  /* STEP 6 */
  period = ifc(index_dt < &POLICY, 'P1', 'P2');

  index_year = year(index_dt);
  index_qtr  = catx(' ', put(year(index_dt),4.), cats('Q', ceil(month(index_dt)/3)));

  length ctrl_flag 3;
  ctrl_flag = (index_drug in ('Nivolumab','Pembrolizumab'));  /* Control pooled */
run;


/*==============================================================================
  TABLE S0. Cohort attrition
  ============================================================================*/
proc sql noprint;
  select count(distinct &ID) into :n1 trimmed from rgst_norm where is_c34=1;                 /* 전수 C34 */
  select count(distinct &ID) into :n2 trimmed from out.cohort_nsclc;                          /* NSCLC 45코드 */
  select count(distinct &ID) into :n3 trimmed from ici_claims;                                /* ICI 청구 있음 */
  select count(distinct &ID) into :n4 trimmed from out.ici_initiator;                         /* index 기간 내 */
  select count(distinct &ID) into :n_nivo  trimmed from out.ici_initiator where index_drug='Nivolumab';
  select count(distinct &ID) into :n_pemb  trimmed from out.ici_initiator where index_drug='Pembrolizumab';
  select count(distinct &ID) into :n_atez  trimmed from out.ici_initiator where index_drug='Atezolizumab';
quit;

data table_s0;
  length step 8 criterion $60 n 8 excluded $12;
  step=1; criterion='RGST 전체 (전수 C34)';              n=&n1; excluded='-';               output;
  step=2; criterion='NSCLC 45개 조직형 코드 해당';       n=&n2; excluded=cats(%eval(&n1-&n2)); output;
  step=3; criterion='ICI 청구 있음 (T300)';              n=&n3; excluded=cats(%eval(&n2-&n3)); output;
  step=4; criterion='index 기간 2017-08-21~2021-12-31';  n=&n4; excluded=cats(%eval(&n3-&n4)); output;
  step=9; criterion='최종 ICI initiator 코호트';         n=&n4; excluded='';                output;
  step=9; criterion='  └ Nivolumab';                     n=&n_nivo; excluded=''; output;
  step=9; criterion='  └ Pembrolizumab';                 n=&n_pemb; excluded=''; output;
  step=9; criterion='  └ Atezolizumab';                  n=&n_atez; excluded=''; output;
run;

title1 'Table S0. Cohort attrition';
title2 '*rate 분모 아님(ICI 2차 이상 급여). 다중원발=제외 아니라 기록.';
proc print data=table_s0 noobs label; var step criterion n excluded; run;
title;


/*==============================================================================
  TABLE S1. Quarterly distribution of index ICI initiators
  ============================================================================*/
title1 'Table S1. Quarterly distribution of index ICI initiators';
title2 'Control pooled = Nivolumab + Pembrolizumab';
proc tabulate data=out.ici_initiator format=8.0 missing;
  class index_qtr index_drug;
  table index_qtr=' ' all='Total',
        (index_drug=' ' all='Total ICI')*n=' '
  / box='Quarter';
run;

/* Control pooled 별도 열 */
proc sql;
  create table s1_ctrl as
  select index_qtr,
         sum(index_drug='Nivolumab')      as Nivolumab,
         sum(index_drug='Pembrolizumab')  as Pembrolizumab,
         sum(index_drug='Atezolizumab')   as Atezolizumab,
         sum(ctrl_flag=1)                 as Control_pooled,
         count(*)                         as Total
  from out.ici_initiator
  group by index_qtr
  order by index_qtr;
quit;
proc print data=s1_ctrl noobs; run;
title;


/*==============================================================================
  우선순위 진단 3개
  ============================================================================*/
title1 '진단 ① atezo Period 1 N  (＜30 이면 event-study 불가 → 설계 변경)';
proc freq data=out.ici_initiator;
  tables index_drug*period / norow nocol nopercent;
run;
title;

title1 '진단 ② 다중원발 / 중복 레코드';
title2 'mult_primary_flag=1: NSCLC C34 등록 2건 이상 / same-day: 같은 날 서로 다른 ICI';
proc freq data=out.cohort_nsclc; tables mult_primary_flag method0_flag / missing; run;
proc sql;
  select count(*) as same_day_multi_ICI_persons from _sameday;
quit;
title;

title1 '진단 ③ BFC 연도별 중복 (index 연도 1행 규칙 검증)';
title2 '아래 dup_in_index_year > 0 이면 사회경제 변수 중복집계 위험 → 연도 1행 규칙 필요';
proc sql;
  create table _bfc_idx as                            /* 코호트의 index 연도 BFC 행수 */
  select b.&ID, count(*) as n_bfc_rows_index_year
  from raw.BFC as b
  inner join out.ici_initiator as c
    on b.&ID = c.&ID and input(cats(b.STD_YYYY),4.) = c.index_year
  group by b.&ID;

  select sum(n_bfc_rows_index_year>1) as dup_in_index_year,
         count(*)                     as persons_with_index_year_bfc
  from _bfc_idx;
quit;
title;

/*==============================================================================
  다음 단계(방문 후/확정 후): 02_derive.sas
    - 파생변수: 취약군 7지표(뇌전이 C793·고령≥70·자가면역≥2회·스테로이드 pred-eq≥10mg),
      mCCI(Quan, index-1yr, 암·전이 제외), 초치료(TX), 이전 표적치료(EGFR/ALK TKI),
      사회경제(의료급여/보험료분위/가구원수/거주지/장애), index 기관종별
    - 분석용 마스터(1인 1행) export → R로 Table1 / DiD(feols) / OS(survival)
  ============================================================================*/
