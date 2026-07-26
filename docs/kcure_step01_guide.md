# STEP 0. 세션 준비 + 사전 확인

```sas
/*==================================================
  KC20260325001 ICI 코호트 STEP 01  (최종본)
  2026-07-27
==================================================*/
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

title1 "0-1. KCURE 테이블 목록";
proc sql;
  select memname, nobs, nvar
  from dictionary.tables
  where libname='KCURE'
  order by memname;
quit;

title1 "0-2. RGST 변수 목록";
proc contents data=kcure.kc20260325001_rgst varnum; run;

title1 "0-2b. ★ MCODE_GRP 실제 값 분포";
proc freq data=kcure.kc20260325001_rgst order=freq;
  tables MCODE_GRP / missing;
run;

title1 "0-2c. ★★ GATE - 45코드 매칭 레코드 수 (0이면 진행 금지)";
proc sql;
  select sum(upcase(strip(cats(MCODE_GRP))) in (
           '80203','80213','80223',
           '80303','80313','80323','80333','80343','80353',
           '80463',
           '80502','80503','80513','80522','80523','80702','80703','80713',
           '80723','80733','80743','80753','80762','80763','80783','80823',
           '80833','80843',
           '81402','81403','81413','81433','81473',
           '82502','82503','82513','82523','82532','82533','82543','82553',
           '85603','85623',
           '89723','89733')) as n_match_45
  from kcure.kc20260325001_rgst;
quit;
```

**⚠ `out.test` 에러 →** 경로를 `/home/sasuser/project/kc20260325001/out` 로 변경. 둘 다 안 되면 분석관 문의

**⚠ `ods excel` 에러 →** 그 줄만 삭제하고 rtf만 사용

## 표 0. 환경 기록

| 항목 | 기록 |
|---|---|
| 쓰기 가능 경로 | |
| 다음 방문까지 파일 유지? | |
| ods excel 작동? | |
| 반출 최소 셀 크기 제한 | |

## 표 0-1. 테이블 목록

T200 / T300 / T400 / T530 **파티션이 빠진 게 없는지** 확인

| 테이블명 | nobs | nvar |
|---|---|---|
| | | |
| | | |
| | | |
| | | |
| | | |
| | | |
| | | |
| | | |

## ★★ 표 0-2. 조직형 GATE — 여기서 멈추고 판정

**⚠ 이 판정을 건너뛰고 계속 돌리면 STEP 1부터 STEP 11까지 전부 0건이 나옵니다. 반드시 여기서 확인하세요**

| `n_match_45` (0-2c 결과) | 판정 | 조치 |
|---|---|---|
| 0 보다 큼 | 진행 | STEP 1로 |
| **0** | **진행 금지** | 0-2b 값 보고 요청그룹 코드로 STEP 1-2 교체 후 재실행 |
| `MCODE` 컬럼이 따로 있음 | 수정 후 진행 | `keep=` 과 `mcode=` 를 `MCODE` 로 변경 |

**기록:** MCODE_GRP 실제 값 = ________________

**기록:** `n_match_45` = ________________ / 진행 여부 = ________________

# STEP 1. NSCLC 코호트

## 1-1. 결측 판정 + 분리

```sas
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
```

## 표 A. 결측·제외

| 사유 | n |
|---|---|
| SNKEY 결측 | |
| 조직형(MCODE) 결측 | |
| **구조적 제외 소계** | |
| FDX 결측 (제외 안 함) | |

## 1-2. 45개 조직형 코드 양성 선택

```sas
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
```

## 1-3. 환자당 중복 레코드

```sas
proc sql;
  create table dup_chk as
  select SNKEY, count(*) as n_rec from nsclc_sel group by SNKEY;
quit;

title1 "B-2. 환자당 NSCLC 레코드 수 분포";
proc freq data=dup_chk; tables n_rec / out=out.b2_dup; run;
```

## 1-4. 환자별 최초진단 1건 (FDX 결측은 뒤로)

```sas
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
```

## 표 B. NSCLC 코호트

| 항목 | n |
|---|---|
| RGST 전체 레코드 | |
| 구조적 결측 제외 후 | |
| 45코드 해당 레코드 | |
| 45코드 해당 환자(SNKEY) | |
| **최초진단 1건 정리 후 (코호트)** | |
| 0건인 코드 (목록 적기) | |

**중복 분포:** 1건 ______ / 2건 ______ / 3건+ ______ → 2건 이상 ______ %

# STEP 2. T200 제한

```sas
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
```

## 표 C-1

| 항목 | n |
|---|---|
| T200 제한 후 청구 건수 | |
| `ymd` 결측 (0이어야 정상) | |

**⚠ 표 0-1에 T200 파티션이 더 있으면** 이 `from` 절에 union 추가 필요

# STEP 3. ICI 청구 추출

```sas
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
```

## 표 C-2. 연결

| 항목 | n |
|---|---|
| T300 ICI — atezo (6577) | |
| T300 ICI — nivo (6384) | |
| T300 ICI — pembro (6390) | |
| MID 조인 후 청구 건수 | |
| **ICI 환자 (distinct SNKEY)** | |

**⚠ 셋 중 0이 있으면** GNL_CD 4자리 가정이 틀린 것. 원본에서 `substr(GNL_CD,1,4)` 분포 확인

# STEP 4. 환자별 최초 ICI = index

**⚠ code4 정렬 순서는 6384(nivo) < 6390(pembro) < 6577(atezo). 동시 청구를 정렬 순으로 뽑으면 atezo가 체계적으로 밀립니다. 그래서 index date에 2종 이상이면 시작 약제 판정 불가로 보고 환자를 제외합니다**

## D-0. index date 동시 2종 판정

```sas
proc sql;
  create table first_dt as
  select SNKEY, min(ymd) as index_ymd
  from ici_claims group by SNKEY;

  create table idx_drug as
  select a.SNKEY, count(distinct b.code4) as n_drug_idx
  from first_dt as a
  inner join ici_claims as b
    on a.SNKEY = b.SNKEY and a.index_ymd = b.ymd
  group by a.SNKEY;
quit;

title1 "D-0a. index date에 2종 이상 동시 청구 (판정 불가 -> 제외)";
proc freq data=idx_drug; tables n_drug_idx / out=out.d0_sameday; run;

title1 "D-0b. (참고) 추적기간 중 아무 날이나 동시 2종";
proc sql;
  select count(*) as n_sameday_any from
    (select SNKEY from ici_claims group by SNKEY, ymd
     having count(distinct code4) > 1);
quit;
```

## D-1. 최초 ICI 행 채택 + 동시 2종 제외

```sas
proc sort data=ici_claims; by SNKEY ymd code4; run;

data ici_index;
  merge ici_claims(in=a) idx_drug(keep=SNKEY n_drug_idx);
  by SNKEY;
  if a;
  if first.SNKEY;
  if n_drug_idx > 1 then delete;      /* 시작 약제 판정 불가 -> 제외 */
  index_ymd = ymd;
  length index_drug $6;
  if      code4='6577' then index_drug='atezo';
  else if code4='6384' then index_drug='nivo';
  else if code4='6390' then index_drug='pembro';
  index_yr = int(index_ymd/10000);
run;

title1 "D-1. 약제별 환자 N (index 기준)";
proc freq data=ici_index; tables index_drug / out=out.d1_drug; run;
```

## 표 D

| 항목 | n |
|---|---|
| **index date 동시 2종 (제외됨)** | |
| 추적 중 아무 날 동시 2종 (참고) | |
| Nivolumab | |
| Pembrolizumab | |
| Atezolizumab | |
| 계 | |

**→ 제외 인원이 많으면** (예: 전체의 3% 초과) 논문 Limitation에 기술 필요. 인원 = ______ ( ______ %)

# STEP 5. 기간 제한 + 정책 전후

```sas
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
```

# STEP 6. Attrition + 약제 × 기간

```sas
title1 "E-1. 코호트 구축 단계별 인원 (Table S0)";
proc sql;
  create table out.e1_attr as
  select 'a. RGST 전체 레코드' as step, count(*) as n
         from kcure.kc20260325001_rgst
  union all select 'b. 구조적 결측 제외',    count(*) from nsclc_all
  union all select 'c. NSCLC 45코드 레코드', count(*) from nsclc_sel
  union all select 'd. NSCLC 환자(코호트)',  count(*) from nsclc_cohort
  union all select 'e. ICI 청구 있음', count(distinct SNKEY) from ici_claims
  union all select 'e2. 동시2종 제외 후',    count(*) from ici_index
  union all select 'f. index 기간 제한 후',  count(*) from cohort_final;
quit;
proc print data=out.e1_attr noobs; run;

title1 "E-2. ★ 약제 x 기간 교차 (최우선)";
proc freq data=cohort_final;
  tables index_drug*period / out=out.e2_drugperiod;
  tables ctrl*period       / out=out.e3_ctrlperiod;
run;
```

## 표 E-1. Attrition (Table S0)

| 단계 | n | 제외 n |
|---|---|---|
| a. RGST 전체 레코드 | | — |
| b. 구조적 결측 제외 | | |
| c. NSCLC 45코드 레코드 | | |
| d. NSCLC 환자 | | |
| e. ICI 청구 있음 | | |
| e2. 동시 2종 제외 후 | | |
| f. **최종 코호트** | | |

## ★ 결과 파일 한 번 끊기

**여기까지가 최우선 숫자입니다. 뒤에서 에러 나면 rtf가 안 열리므로 지금 한 번 닫고 새로 엽니다**

```sas
title;
ods excel close;
ods rtf close;

ods rtf   file="/home/sasuser/out/RESULT_step01b_0727.rtf" bodytitle;
ods excel file="/home/sasuser/out/RESULT_step01b_0727.xlsx"
          options(sheet_interval="proc" embedded_titles="yes");
```

**→ 이 시점에 `RESULT_step01_0727.rtf` 열어서 표 E-1 · E-2 숫자 확인하고 손으로 적기**

## ★ 표 E-2. 약제 × 기간 (최우선)

| | P1 (~19-07-22) | P2 (19-07-23~) | 계 |
|---|---|---|---|
| Nivolumab | | | |
| Pembrolizumab | | | |
| **Atezolizumab** | | | |
| Control pooled | | | |
| 계 | | | |

**★ 판정:** atezo P1 = ________ → 30 이상? ________ / event-study 가능? ________

# STEP 7. 분기별 추이 (Table S1)

```sas
title1 "F-1. 분기별 index ICI initiator";
proc freq data=cohort_final;
  tables yq*index_drug / out=out.f1_quarter;
run;

title1 "F-2. 분기별 교차표";
proc tabulate data=cohort_final;
  class yq index_drug;
  table yq, index_drug*n all*n / rts=14;
run;
```

## 표 F. Table S1

| Quarter | Nivo | Pembro | Atezo | 계 |
|---|---|---|---|---|
| 2017 Q3 | | | – | |
| 2017 Q4 | | | – | |
| 2018 Q1 | | | | |
| 2018 Q2 | | | | |
| 2018 Q3 | | | | |
| 2018 Q4 | | | | |
| 2019 Q1 | | | | |
| 2019 Q2 | | | | |
| **2019 Q3 ← 정책** | | | | |
| 2019 Q4 | | | | |
| 2020 Q1 | | | | |
| 2020 Q2 | | | | |
| 2020 Q3 | | | | |
| 2020 Q4 | | | | |
| 2021 Q1 | | | | |
| 2021 Q2 | | | | |
| 2021 Q3 | | | | |
| 2021 Q4 | | | | |

**메모:** atezo 최저 ______ → 최고 ______ ( ______ 배 증가)

# STEP 8. BFC 연도 매칭

```sas
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
```

## 표 G. BFC 매칭

| 항목 | 기록 | 판정 |
|---|---|---|
| BFC 환자당 레코드 최대 | | |
| `n_rows` | | |
| `n_pts` | | 같아야 정상 |

**⚠ 다르면 여기서 멈추고 원인 확인.** 진행하면 사회경제 변수 전부 뻥튀기됨

# STEP 9. 파생변수 + 결측 기록

```sas
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
```

## 표 H. 결측 (빼지 않고 기록)

| 변수 | atezo P1 | atezo P2 | ctrl P1 | ctrl P2 |
|---|---|---|---|---|
| GAIBJA_TYPE 결측 | | | | |
| SIDO_CD 결측 | | | | |
| 보험료 결측 | | | | |
| 가구원수 결측 | | | | |
| MAIDCL_CD 미지정 | | | | |
| PAT_AGE 결측 | | | | |
| FDX 결측 | | | | |
| STD_YYYY 미매칭 | | | | |
| **complete-case n** | | | | |
| 코호트 전체 n | | | | |

**⚠ atezo P1의 결측률이 유독 높으면** complete-case가 DiD를 왜곡. Unknown 유지 방침으로

# STEP 10. Table 1 — 사회경제·거주

```sas
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
```

## 표 I. Table 1 (4/4)

| 변수 | atezo P1 | atezo P2 | ctrl P1 | ctrl P2 |
|---|---|---|---|---|
| **의료급여** | | | | |
| 1종 | | | | |
| 2종 | | | | |
| 차상위 | | | | |
| 직장 | | | | |
| 지역 | | | | |
| 보험료 0 (의료급여) | | | | |
| 1–2분위 | | | | |
| 3–4분위 | | | | |
| 5–6분위 | | | | |
| 7–8분위 | | | | |
| 9–10분위 | | | | |
| 보험료 Unknown | | | | |
| 1인 가구 | | | | |
| **비수도권** | | | | |
| 서울 | | | | |
| 인천·경기 | | | | |
| 광역시 | | | | |
| 도·세종·제주 | | | | |
| **70세 이상** | | | | |
| 연령 중앙값 (IQR) | | | | |

# STEP 11. 반출 대비 — 5 미만 셀

**⚠ 데이터셋마다 변수 구조가 달라서 SET 병합은 에러 납니다. 따로 출력하세요**

```sas
title1 "Z-0. ODS OUTPUT 변수명 확인 (Frequency 맞는지)";
proc contents data=out.i1_ses varnum; run;

title1 "Z-1a. 약제 x 기간 - 5 미만";
proc print data=out.e2_drugperiod noobs;
  where 0 < count < 5;
run;

title1 "Z-1b. 분기별 - 5 미만";
proc print data=out.f1_quarter noobs;
  where 0 < count < 5;
run;

title1 "Z-1c. 사회경제 - 5 미만";
proc print data=out.i1_ses noobs;
  where 0 < Frequency < 5;
run;

title1 "Z-1d. 결측 - 5 미만";
proc print data=out.h1_missing noobs;
  where 0 < Frequency < 5;
run;
```

**⚠ Z-1c / Z-1d 가 에러 나면** Z-0 결과에서 빈도 변수의 실제 이름을 확인하고 `Frequency` 를 그 이름으로 교체

## 표 Z. 반출 걸릴 셀

| 출처 표 | 어떤 셀 | count |
|---|---|---|
| | | |
| | | |
| | | |
| | | |
| | | |

**→ 병합 전략 메모:** ______________________________________________

# STEP 12. 결과 파일 닫기 (필수)

```sas
title;
ods excel close;
ods rtf close;

proc datasets library=out; run;
```

**⚠ 이거 안 하면 rtf / xlsx 파일이 안 열립니다**

# 마무리 체크리스트

## 오늘 끝에 남아야 할 것

| 산출물 | 내용 | 확인 |
|---|---|---|
| `kcure_step01_cohort_0727.sas` | 코드 전체 (Ctrl+S 저장) | |
| `RESULT_step01_0727.rtf` | STEP 0~6 결과 (attrition·약제×기간) | |
| `RESULT_step01b_0727.rtf` | STEP 7~11 결과 | |
| `RESULT_step01_0727.xlsx` / `01b` | 같은 결과, proc별 시트 | |
| `out.nsclc_cohort` | NSCLC 코호트 | |
| `out.ici_claims` | ICI 청구 | |
| `out.cohort_final` | 최종 코호트 | |
| `out.cohort_flag` | 파생변수·결측 포함 (다음엔 이것만 사용) | |
| `out.e1_attr` 등 표 데이터셋 | e2_drugperiod, f1_quarter, h1_missing, i1_ses, z1_smallcell | |

## 손으로도 반드시 적을 것

| 표 | 내용 | 적었나 |
|---|---|---|
| 표 0-2 | **조직형 GATE** — `n_match_45` | |
| 표 D | 동시 2종 제외 인원 | |
| 표 E-1 | Attrition | |
| 표 E-2 | **약제 × 기간 — atezo P1** | |
| 표 F | 분기별 추이 | |
| 표 H | 결측 현황 | |
| 표 Z | 5 미만 셀 | |

## 막히면 볼 곳 4개

| 증상 | 원인 | 확인할 표 |
|---|---|---|
| STEP 1이 0건 | 조직형 변수가 그룹값 | 표 0-2 — GATE에서 이미 걸러짐 |
| STEP 2가 0건 | T200 파티션 누락 | 표 0-1 |
| `n_rows` ≠ `n_pts` | BFC 연도 중복 | 표 G — 멈추고 확인 |
| Z-1c / Z-1d 에러 | 빈도 변수명이 `Frequency` 아님 | Z-0 결과에서 실제 이름 확인 |

## 돌아와서 같이 정할 것

**atezo P1 N (표 E-2)** 이 핵심입니다.

| atezo P1 | 방향 |
|---|---|
| 30 이상 | event-study 포함 DiD 그대로 진행 |
| 30 미만 | pre / post 단순비교로 전환 검토 |

## 다음 방문 때 이어서

```sas
libname kcure "/home/sasuser/project/kc20260325001/src/data";
libname out "/home/sasuser/out";

proc datasets library=out; run;
proc print data=out.e1_attr noobs; run;
proc freq  data=out.cohort_flag; tables index_drug*period; run;
```
