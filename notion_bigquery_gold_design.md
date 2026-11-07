# KOIN Gold Mart 설계 및 BigQuery 검증 결과

최신 구현 상태: **2026-11-06, 5.0.13·6.18 참조**. 최신 44/20컬럼의 SQL 초안과 Superset 쿼리를 작성했고 Stage Gold 테이블 2개를 구조만 생성했다(각 0행). 새 로깅은 개발 미적용으로 실데이터 적재·공식 KPI 검증은 대기다. 아래의 이전 구현 상태·갱신일은 각 시점의 이력이다.

최신 대화 결정 반영: **2026-11-06, 5.0.12 및 6.16 우선**. 졸업계산기·동아리 종료 및 새/미래 주변상점 개발 중단을 반영한다. 최종 사용자 44컬럼은 기존 44개에서 졸업계산기 플래그를 제거하고 퍼널 배열을 추가한 새 구성이다. 집계 20컬럼은 유지하며 KPI용 metric_type 두 값을 채택한다. 아래의 과거 갱신일·실측은 이력이며 이번 문서 정리는 운영 재검증·배포를 뜻하지 않는다.

최초 작성 기준: `koin-stage-438512` 프로젝트, 2026-07-31 BigQuery 실측 데이터.
최종 문서 갱신: 2026-09-10 사용자 제공 2개 Gold(44/20컬럼) 계약과 KPI 4개·퍼널 보완안 반영. 마지막 실데이터 확인은 2026-09-09이며 이번에는 운영 조회·배포를 하지 않았다.
저장소 상태와 BigQuery 배포 상태를 분리해 기록한다. 코드 계약은 원격 `main` 병합 커밋을,
실데이터 상태는 BigQuery 읽기 전용 조회를 근거로 작성한다.

---

## 1. 확인된 사실

### 1.0 현재 Stage 기준 요약 (2026-09-09)

현재 검증 환경은 `koin-stage-438512`다. 아래 1.1 이하 최초 실측, 3장의 Placeholder 구조 검증, 4장의 Production 비교는 날짜가 붙은 이력이며 현재 상태와 혼용하지 않는다.

| 구분 | 현재 입력/상태 | 다음 작업 |
| --- | --- | --- |
| User | `silver.silver__users`, 4,707행, 4개 신규 컬럼 및 실제 값 확인 | 실제 값의 의미·매핑·Event 관계 검증; Placeholder 불필요 |
| Event 기본 사실 | `silver.silver_events`, 10,100행, 2026-07-19~08-27, 필수 분류 없음 | 기본 품질 참고; 분류 계약 충족 전 공식 Gold 입력으로 승인하지 않음 |
| Event 분류 참고 | `silver.silver_events_temp`, 14,453행, 2026-07-01~08-08 | 출처 제한을 명시한 읽기 전용 분석; V2 검증 결과로 대체하지 않음 |
| 목표 Event | `silver.silver_events_v2` 미존재 | Silver 담당 입력 제공 후 Stage 품질 검증 |
| 과거 User | `silver.silver__users_temp`, 네 컬럼 없음 | 과거 구조 검증 이력 유지; 현재 User 검증 입력과 구분 |
| Gold | 현 38컬럼 로컬 코드와 확장 설계 존재 | Stage 실제 KPI 실행·품질·비용 검증은 미완료; 이번 수정으로 배포하지 않음 |

Production은 후속 승격 대상이다. Stage User가 존재한다고 Production User 또는 BI가 준비됐다는 뜻은 아니다. 사용자 범위는 Gold이며 Silver 수정·추가 컬럼 생성·ID 로직 재구현을 하지 않는다.

최신 사용자 제공 계약은 **5.0.11의 물리 2개 Gold(사용자 44컬럼/집계 20컬럼)**이며 KPI 4개·퍼널 보완은 **6.14**를 따른다. 5.0.10의 단일 Gold 99컬럼과 6.13의 대응표는 이전 설계 이력이다. KPI용 metric_type 확장과 퍼널용 45번째 중첩 컬럼은 새 제안이며 구현·배포 완료가 아니다. Stage 컬럼 실측은 5.5.3을 따른다.


### 1.1 Stage 프로젝트/데이터셋

- 프로젝트: `koin-stage-438512`, 리전: `asia-northeast3`
- 데이터셋: `analytics_427218788`, `analytics_440323811`(GA4 raw export), `silver`, `gold`(현재 비어 있음)
- 현재 계정(`sm1118sm@gmail.com`)은 `koin-stage-438512`에 `roles/owner`, `kap-chat`에 `roles/owner` + `roles/resourcemanager.projectMover` 보유(2026-08-06 `gcloud projects get-iam-policy`로 재확인). 조회만 필요한 목적에는 과한 권한이다 — 축소 방안은 2장 3번 참고.

### 1.2 `silver.silver_events_temp` 스키마 및 검증

실측 스키마(주요 컬럼): `event_id`, `event_dt`(DATE, 파티션), `event_at`, `event_ts`, `event_name`, `user_pseudo_id`, `ga_session_id`, `custom_session_id`, `platform`, `device_category`, `device_os(_version)`, `event_label/category/value(_norm 포함)`, `page_title(_norm)`, `screen_class(_norm)`, `page_location`, `engagement_time_msec`, `service_name`, `funnel_stage`, `step_order`, `is_entry_event`(BOOLEAN), `is_core_action`(BOOLEAN), `stage_scope`.

검증 쿼리 결과:

| 지표 | 값 |
| --- | --- |
| 전체 행 수 | 14,241 |
| `event_id` Null 수 | 0 |
| 고유 `event_id` 수 | 14,241 (행 수와 일치 → PK 유일성 확인) |
| `event_dt` Null 수 | 0 |
| `user_pseudo_id` Null 수 | 0 |
| `service_name` Null 수 | 0 |
| `is_entry_event` Null 수 | 9,431 |
| `is_core_action` Null 수 | 9,431 |

`service_name`별 Null 분포를 확인한 결과, `is_entry_event`/`is_core_action` Null 9,431건은 **전부 `service_name = 'unmapped'`인 행에서만** 발생했고, 그 외 모든 `service_name`(main, shop, banner, account, timetable, board, cafeteria, bus, grad_calc, facility)에서는 Null이 0건이었다. 즉 Gold 집계에서 `coalesce(is_entry_event, false)`, `coalesce(is_core_action, false)` 처리는 데이터로 근거가 확인된 안전한 처리다.

### 1.3 `silver.silver__users_temp` 스키마 및 검증

실측 스키마: `user_pseudo_id`, `stream_id`, `user_id`, `user_id_source`, `top_user_id`, `property_user_id`, `param_user_id`, `gender`, `major`, `entry_year`, `first_seen_at`, `last_seen_at`, `user_id_support_count`, `source_event_count`, `property_user_id_set_ts`, `canonical_identity_state_id`.

**`user_type`, `signup_completed_at`, `is_deleted`, `is_mysql_mapped` 컬럼은 현재 Stage에 존재하지 않는다.** CLAUDE.md 계약상 이 컬럼들은 "Prod 이전 시 추가"로 명시된 컬럼이라, 아직 Stage 단계에서는 만들어지지 않은 것으로 확인된다.

검증 쿼리 결과:

| 지표 | 값 |
| --- | --- |
| 전체 행 수 | 117 |
| `user_pseudo_id` Null 수 | 0 |
| 고유 `user_pseudo_id` 수 | 117 (행 수와 일치 → `user_pseudo_id`당 한 행 확인) |
| `user_id` Null 수 | 98 (19건만 non-null) |
| `first_seen_at` Null 수 | 0 |
| `last_seen_at` Null 수 | 0 |

대표 ID 후보 비교(개인 식별자 원본값 미노출, 집계만):

| 지표 | 값 |
| --- | --- |
| `top_user_id` non-null | 19 |
| `property_user_id` non-null | 19 |
| `param_user_id` non-null | 0 |
| `top_user_id`·`property_user_id` 둘 다 non-null | 19 |
| 그중 값 일치 | 19 |
| 그중 값 불일치 | 0 |

`param_user_id`는 전 구간 Null이고, `top_user_id`/`property_user_id`는 둘 다 존재하는 19건에서 전부 일치했다(불일치 0건). `user_id` non-null 19건과 `top/property_user_id` non-null 19건이 동일 규모인 것으로 볼 때, `user_id`는 이미 `top_user_id`/`property_user_id` 우선순위 로직으로 확정된 값을 담고 있는 것으로 보인다(로직 자체를 재확인한 것은 아니며, 건수 일치로부터의 추정).

### 1.4 로컬 dbt 저장소와 BigQuery 실제 테이블의 차이 (중요)

`dbt/models/silver/silver_events.sql`(현재 저장소 코드)는 GA4 원본을 정제해 `silver_events` 테이블(중복 제거·KST 변환·화면명 표준화)을 만들지만, `service_name`/`funnel_stage`/`step_order`/`is_entry_event`/`is_core_action`/`stage_scope` 등 **서비스 분류 컬럼은 생성하지 않는다.** 반면 `silver_events_temp`에는 이 컬럼들이 존재한다.

또한 저장소에는 `silver__users`류 dbt 모델이 전혀 없다. 즉 `silver_events_temp`, `silver__users_temp`는 **현재 dbt 코드가 만드는 산출물이 아니라, 별도 경로로 이미 BigQuery에 존재하는 임시 테이블**이다. Gold 설계는 이 실제 데이터를 근거로 진행했고, dbt 코드에서는 이 두 테이블을 `source()`로 선언해 참조했다(아래 4장 참고).

---

## 2. 남은 확인 사항

1. **Stage User 컬럼 추가 완료, 의미·관계·KPI 검증 필요** — 2026-09-09 `koin-stage-438512.silver.silver__users`의 4개 컬럼과 실제 값 적재를 직접 확인했다(5.5.3절). 컬럼 존재와 기본 NULL 분포 점검은 완료다. 가입일 의미·매핑 정확성·Event/User 관계·가입 원천 freshness·KPI 정합성은 별도 검증 대상으로 남는다. Production `silver__users`는 아직 없다. Stage User가 PR #29 실행 산출물인지도 이번 메타데이터/COUNT만으로 확정하지 않는다.
2. **Stage Event 입력 계약 미충족** — Stage `silver_events_v2`는 아직 없고 legacy `silver_events`에는 필수 서비스/Entry/Core 분류 컬럼이 없다. `_temp`에는 분류 컬럼이 있지만 목표 모델 산출물이라는 출처 검증이 안 되어 있다. 현재 로컬 Gold는 임시 분류 Intermediate를 읽고 spine은 legacy `silver_events`를 읽는 상태이며, 목표 `ref('silver_events_v2')` 경로와 다르다. 현재 코드·목표 계약·물리 배포 상태를 구분한다.
3. **IAM 최소권한화 — 방안 확정, 실행은 보류(2026-08-06)** — `gcloud projects get-iam-policy`로 재확인한 결과 `sm1118sm@gmail.com`은 `koin-stage-438512`에 `roles/owner`, `kap-chat`에 `roles/owner` + `roles/resourcemanager.projectMover`를 보유하고 있다(둘 다 조회 목적에는 과함). 목표 역할은 두 프로젝트 모두 `roles/owner` 제거 후 `roles/bigquery.jobUser` + `roles/bigquery.dataViewer`로 축소하는 것으로 확정한다. **사용자가 실행 보류를 선택**했다 — Production(`kap-chat`) 자신의 owner 권한을 스스로 낮추는 건 되돌리기 번거로운 작업이라, 실제 `gcloud projects remove-iam-policy-binding` / `add-iam-policy-binding` 실행은 별도로 명시적 요청이 있을 때만 진행한다. 실행 시 필요한 명령:
   ```bash
   gcloud projects remove-iam-policy-binding <PROJECT_ID> --member="user:sm1118sm@gmail.com" --role="roles/owner"
   gcloud projects add-iam-policy-binding <PROJECT_ID> --member="user:sm1118sm@gmail.com" --role="roles/bigquery.jobUser"
   gcloud projects add-iam-policy-binding <PROJECT_ID> --member="user:sm1118sm@gmail.com" --role="roles/bigquery.dataViewer"
   ```
4. **`user_id` 확정 로직 자체의 재검증 여부 — 질문 1은 해결, 질문 2·3은 리스크 수용으로 종결** — 이번 검증은 `top_user_id`/`property_user_id`/`user_id`의 건수·일치 여부만 확인했고, `user_id`를 만드는 우선순위 SQL 자체를 직접 읽어 검증하지는 않았다. BCSDLab Slack에서 확인 결과, 처음에는 다음 두 가지가 팀 내부에서도 아직 명시적으로 답이 나오지 않은 상태였다.
   - 동일 이벤트에 anonymous 값을 가진 `top_user_id`와 학번형 값을 가진 `property_user_id`/`param_user_id`가 함께 존재하면 현재 COALESCE 순서상 anonymous가 선택된다.
   - `gender`, `major`가 대표 `user_id` 기준이 아니라 `user_pseudo_id`의 최신 관측값에서 선택될 수 있어, Prod에서 대표 user_id 기준 `koin_users` 속성을 우선할지 확인이 필요했다.

   `kap-chat.core.vw_user_id_canonical`(Prod) 뷰의 실제 SQL을 읽어 두 질문 모두에 대한 설계 의도 근거를 먼저 확보했고(4.4절), 이후 **김창윤님의 실제 확인 답변(4.4.1절)으로 질문 1은 해결됐다**: `property_user_id`는 `top_user_id`와 동일 컬럼이고 `param_user_id`는 로깅 실수이며, 작년 7~10월 실측에서 anonymous/학번형 충돌은 없었다. 이후 실제 `silver__users` 이관 dbt 코드를 읽고 **"동일 관측 ID 충돌"이라는 질문 3**까지 발견했다(행 레벨 `COALESCE(top, property, param)`가 cross-row 비-익명 우선 로직보다 먼저 일어나 학번형 후보를 조기에 버릴 수 있는 문제). **질문 2·3 모두 구조적으로 고치지 않고, warn(비차단) 모니터링 테스트로 감시하는 리스크 수용으로 최종 종결했다**(5.5.4절 참고, 2026-08-01).
5. **Stage vs 기존 Prod(`kap-chat`) KPI 비교 — 확인 완료, "비교 불가/무의미" 사유로 종결(2026-08-06)** — 실측 결과 Stage는 `analytics_427218788` + `analytics_440323811`, Prod는 `analytics_432041405`로 **서로 다른 GA4 속성**을 원본으로 쓴다. 또한 Prod `silver.silver_events`는 실제 스키마 확인 결과 `service_name`/`is_entry_event`/`is_core_action`/`funnel_stage` 등 Gold가 의존하는 분류 컬럼을 아직 갖고 있지 않다(해당 로직은 `core.vw_event_service_map`/`vw_core_event_service_name_map` 등 별도 뷰에만 존재). 따라서 "같은 날짜에 Stage와 Prod의 KPI 숫자가 일치하는지" 비교는 **애초에 성립하지 않는 질문**이다 — 같은 사용자·이벤트 모집단이 아니다. 의미 있는 검증은 운영 Silver 이관 후 "Gold 공식을 Stage/Prod 각각에 적용했을 때 각자 내부적으로 값이 타당한지"이며, 이는 이미 5.14.3(운영 Gold 구현)의 배포 검증 절차에 흡수돼 있어 별도 신규 작업으로 두지 않는다. 자세한 실측 근거는 4.10절 참고.
6. **`entry_year` 타입 통일 — 확정, 실측 완료(2026-08-06)** — Stage `silver__users_temp.entry_year`는 INT64, Prod `mart.dim_users.entry_year`는 STRING임을 `INFORMATION_SCHEMA.COLUMNS`로 재확인했다. Prod 값 전수 조사(NULL 23,170건 제외) 결과 2000~2026 사이 4자리 연도 문자열만 존재했고 `SAFE_CAST(... AS INT64)` 캐스팅 실패 0건. Gold 계약은 INTEGER로 유지하고 `is_deleted`와 동일하게 Gold 출력 단에서 `SAFE_CAST(entry_year AS INT64)`로 정규화한다(5.8.1절, warn 테스트는 5.12.3절).

---

## 3. 구현 범위

### 3.1 이번에 작성한 것

- `dbt_project.yml` — `intermediate` 폴더를 별도 내부 데이터셋의 table 기본값으로 등록
- `dbt/models/intermediate/int__user__retention_spine.sql` — Event USER×DAY와 first-seen/signup D0~D365 평가 행을 합치는 Gold-owned Intermediate
- `dbt/models/intermediate/_intermediate__models.yml` — Intermediate 4개 컬럼 계약
- `dbt/models/gold/mart_kpi_user_daily.sql` — 선택형 리텐션 Gold Mart. 2026-09-09 로컬은 임시 분류 Intermediate 및 `silver__users`를 참조하며, 목표 V2 입력과의 차이는 5.0·6.12절 참고
- `dbt/models/gold/_gold__models.yml` — 최종 38개 컬럼과 Null/flag 계약
- `dbt/tests/assert_int_user_retention_spine_*.sql` — Intermediate Grain·컬럼·경과일·Event 보존 차단 테스트
- `dbt/tests/assert_mart_kpi_user_daily_*.sql` — Gold Grain·38컬럼·리텐션 불변식·전일 Entry·Silver 일치·dense 행 0 처리 차단 테스트
- 구버전 `silver_stage_temp` source와 고정 D1/D7/D14/D30 테스트는 제거
- `AGENTS.md`의 dbt 경로 표기를 실제 경로(`dbt`)에 맞게 수정 (기존 `dbt/koin`은 Airflow DAG의 실제 마운트 경로 `/opt/airflow/dbt`와 불일치했음)

2026-08-25 현재 위 변경은 로컬 코드 작성 상태다. YAML 파싱과 `git diff --check`는 통과했지만
Docker Desktop daemon이 실행 중이 아니어서 `dbt parse/ls/compile`은 아직 완료되지 않았다.
Stage/Production `dbt run`, test, BigQuery DDL/DML 및 BI 연결은 수행하지 않았다.

#### 최초 프로토타입 검증 (2026-08-01 이전, 구버전 — 아래 재작성 전)

| 확인 항목 | 결과 |
| --- | --- |
| 전체 행 수 | 260 |
| distinct(`event_dt`, `user_pseudo_id`) | 260 (일치 → Grain 유일성 확인) |
| `is_multi_session_user = true` 행 수 | 83 |
| `had_entry_prev_day = true` 행 수 | 20 |
| `user_id` non-null 행 수 | 72 |

#### 구 5장 고정 리텐션 38개 컬럼 계약 검증 이력 (2026-08-06, 현재 구현 아님)

아래 내용은 당시 계약(38개 컬럼, 고정 D1/D7/D14/D30)을 검증한 역사 기록이다. 현재 로컬
`mart_kpi_user_daily.sql`은 2026-08-25에 선택형 D0~D365 계약으로 교체됐으며, 아래 수치를
새 구현의 검증 결과로 재사용하지 않는다. 당시 재작성 과정에서 대표값 랭킹의 BigQuery 분석
함수 중첩 오류는 2단계 집계로 수정했다.

2026-08-06 당시 Stage 임시 User에는 Silver User 4개 컬럼이 없어 별도 스텁 쿼리로 구조만
검증했다. PR #29의 `silver__users` SQL에는 네 컬럼이 포함됐지만 Stage 물리 모델과 실값은
2026-09-09 컬럼 존재·실제 값 적재는 확인했고 의미·관계·KPI 정합성은 별도 검증 대상이다. 현재 Gold는 Placeholder 없이 `ref('silver__users')`를 참조한다.

`bq query --dry_run`으로 전체 문법을 검증했고(에러 없음, 스텁 없이 실행하면 `user_type`만 "Unrecognized name" — 예상된 결과), 실제 테이블 생성 없이 스텁 버전을 `SELECT`로 직접 실행해 결과를 확인했다(BigQuery에 어떤 쓰기도 하지 않음):

| 확인 항목 | 결과 | 비고 |
| --- | --- | --- |
| 전체 행 수 | 260 | 최초 프로토타입과 동일(같은 Stage 데이터) |
| distinct(`event_dt`, `user_pseudo_id`) | 260 | 일치 → Grain 유일성 확인 |
| `is_new_user = 1` 행 수 | 117 | 전체 사용자 수와 일치 |
| `is_new_signup = 1` 행 수 | 0 | `signup_completed_at`이 스텁이라 예상된 값(Null) |
| `is_multi_session_user = 1` 행 수 | 83 | **최초 프로토타입과 정확히 일치** — 로직 보존 확인 |
| `had_entry_prev_day = 1` 행 수 | 20 | **최초 프로토타입과 정확히 일치** — 로직 보존 확인 |
| `is_active_entry = 1` 행 수 | 46 | 신규 지표(최초 프로토타입엔 없었음) |
| `used_shop_flg = 1` 행 수 | 30 | 신규 지표 |
| `used_account_flg = 1` 행 수 | 32 | 신규 지표 |
| `platform_dominant = 'unknown'` 행 수 | 0 | 대표값 fallback 정상 동작 |

`is_multi_session_user`/`had_entry_prev_day` 두 지표가 최초 프로토타입과 정확히 같은 값으로 나온 것은, 이번 재작성이 기존 로직을 깨지 않고 38개 컬럼으로 확장했다는 근거다. 아직 `dbt run`은 실행하지 않았다(BigQuery 쓰기 금지 원칙, 3.2절).

### 3.2 의도적으로 하지 않은 것

- IAM 역할 축소 — 사용자 결정 필요 (2.3 참고)
- `dbt run` 실행 — 실제 BigQuery에 테이블을 생성/치환하는 쓰기 작업이라 명시적 요청 없이 실행하지 않음. 로직은 동등한 `SELECT`로만 검증함
- Stage/Prod(`kap-chat`) KPI 비교 — 종결(서로 다른 GA4 Property·입력 구조라 비교 자체가 성립하지 않음, 4.10절/2장 5번 참고)
- `silver_events`/`silver__users` 자체의 재작성 — 서비스 분류 로직·대표 ID 로직을 만드는 것은 이번 범위가 아니며, 별도 설계 검토가 필요

---

## 4. Prod(`kap-chat` / KOIN-PRODUCTION) 실측 비교

Stage 설계를 확정하기 전에 `kap-chat`(표시 이름 "KOIN-PRODUCTION")의 실제 데이터셋/테이블/뷰를 직접 조회해 비교했다. **BigQuery 실측 기준이며, 이 문서의 이전 버전이나 Slack 대화 내용이 아니라 실제 스키마·뷰 정의를 읽고 확인한 내용이다.**

### 4.1 Prod 데이터셋 구조 — 이번에 설계 중인 3계층과 다름

```
raw → stg → core → mart → dash
```

`kap-chat`에는 `analytics_432041405`(GA4 raw), `raw`, `stg`, `core`, `silver`, `mart`, `dash`, `dataform_assertions`, `gcp_billing` 데이터셋이 있다. 지금 KOIN_DATA에서 설계 중인 "Bronze → Silver → Gold" 3계층보다 실제 레거시 구조는 계층이 더 세분화되어 있다(`core`가 사실상 서비스/퍼널 분류 계층, `mart`/`dash`가 BI 직전 단계). 3계층으로 단순화하는 것은 의도된 리팩터링 방향이며, 레거시 구조와 다르다는 것 자체가 문제는 아니다 — 다만 레거시의 어떤 로직이 어느 신규 계층으로 옮겨가는지는 계속 추적해야 한다.

### 4.2 Prod `silver.silver_events` / `silver_events_temp` — 분류 컬럼 없음

Prod의 Silver Event 테이블은 `event_id`, `event_dt`, `event_at`, `event_ts`, `event_name`, `user_pseudo_id`, `ga_session_id`, `custom_session_id`, `platform`, `device_category`, `device_os(_version)`, `event_label/category/value`, `page_title`, `screen_class`, `engagement_time_msec`, `page_location`, `raw_event_id`만 가지고 있다(**2026-07-31 실측 433,065행** — 이후 계속 적재돼 2026-08-06 재실측 시 494,975행으로 늘어남, 4.11절 참고). Stage `silver_events_temp`에 있는 `service_name`/`funnel_stage`/`step_order`/`is_entry_event`/`is_core_action`/`stage_scope`/`*_norm` 컬럼이 **Prod Silver에는 없다.** 이 분류 로직은 Prod에서는 `core` 데이터셋(`core.incremental_core_events_final`, `core.vw_core_event_service_name_map`, `core.vw_core_event_funnel_map`)에 별도로 존재한다.

Prod `silver.silver_events_temp`는 19,170,395행으로, **Stage의 `silver_events_temp`(14,241행)와 이름만 같을 뿐 스키마·역할이 다르다** — 환경 간 동명 테이블을 같은 계약으로 착각하면 안 된다.

Prod `silver__users`는 아직 존재하지 않는다(신규 생성 예정).

### 4.3 기존 Gold 동급 테이블 — `kap-chat.dash.table_dash_kpi_user_daily`

지금 설계 중인 `gold.mart_kpi_user_daily`와 사실상 동일한 목적의 테이블이 Prod에 이미 있다(파티션 `event_dt`, 클러스터 `user_pseudo_id, user_id`). 컬럼: `event_dt`, `user_pseudo_id`, `user_id`, `platform_dominant`, `device_category_dominant`, `device_os`, `is_logged_in`, `session_cnt_day`, `engagement_msec_day`, `is_repeat_user`, `first_seen_dt`, `first_signup_dt`, `is_new_user`, `is_new_signup`, `is_returning_d1`, `used_shop_flg`, `used_real_estate_flg`, `used_cafeteria_flg`, `used_bus_flg`, `used_board_flg`, `used_club_flg`, `used_facility_flg`, `used_timetable_flg`, `used_grad_calc_flg`, `used_account_flg`, `is_active_entry`, `is_active_any_event`.

비교 결과:

- **`used_real_estate_flg`, `used_club_flg`는 레거시 Prod 테이블엔 실제로 존재하는 컬럼이다.** 다만 5장 최종본에서는 둘 다 새 Gold 출력에서 제외한다 — `real_estate`는 Silver 분류 규칙 자체가 없어서(4.7절 이후 신규 확인), `club`은 동아리 기능이 별도 앱으로 분리돼 이 앱에서는 더 이상 발생하지 않는 기능이라는 사용자 확인에 따라(2026-08-06, 5.4절 참고) 제외했다.
- `used_main_flg`/`used_banner_flg`는 Prod에도 없다 — 새 설계와 일치하며 의도된 설계로 보인다.
- Prod의 `is_repeat_user`, `is_returning_d1`은 2026-08-06 고정 리텐션 설계의 `is_multi_session_user`, `is_signup_retained_d1`에 대응하던 레거시 이름이다. 2026-08-18 최종 계약은 고정 D1 컬럼을 선택형 `days_since_signup`/`is_signup_retained`로 교체했다.
- `event_cnt_day`, `entry_event_cnt_day`, `core_action_cnt_day`, `had_entry_prev_day`는 Prod 레거시 테이블에 없다 — 이번 설계에서 새로 추가되는 지표다.

### 4.4 `user_id` 대표값 선정 로직 발견 — `kap-chat.core.vw_user_id_canonical`

Prod `core` 데이터셋에 대표 `user_id` 선정 로직과, 이를 검사하기 위한 뷰(`core.vw_core_user_id_inspection_candidates`)가 이미 존재한다. 후자는 `is_anon_flg`(anonymous 패턴), `is_student_like`(학번형 패턴, `^\d{6}_\d+$`), `is_nil_like`/`is_null_literal`/`is_placeholder_exact`/`is_placeholder_pat`(더미·플레이스홀더 필터), `completeness_score`(가입연도 패턴+gender+major 존재 여부 합산 점수)를 계산한다.

`core.vw_user_id_canonical`의 대표값 선정 순서:

```sql
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY user_pseudo_id
    ORDER BY
      is_anon_flg ASC,           -- 비-익명(학번형) 먼저
      support_count DESC,        -- 지지수(등장 횟수) 높은 값 우선
      completeness_score DESC,   -- 보조정보(가입연도/성별/전공) 풍부한 값 우선
      latest_event_at DESC       -- 최신 관측
) = 1
```

이 로직은 2장 4번 항목의 질문들에 대한 명시적 답을 코드로 제공한다.

1. **anonymous vs 학번형 우선순위**: `is_anon_flg ASC`는 비-익명(학번형)을 anonymous보다 먼저 선택한다는 뜻이다. 즉 **anonymous가 학번형보다 우선되면 안 된다**가 Prod의 의도된 설계다. 이상민님이 Slack에서 가졌던 의심("anonymous보단 학번형이 나을 것 같다")과 일치한다.
2. **gender/major 대표성**: 뷰의 `primary_pick_with_attrs` 단계에서, 선정된 대표 `user_id`와 같은 `(user_pseudo_id, user_id)` 조합의 레코드 중 **최신 이벤트 시점의 gender/major**를 가져온다. 즉 대표 `user_id`와 무관하게 `user_pseudo_id`의 최신 관측값을 그냥 쓰는 게 아니라, 대표 ID가 확정된 다음 그 ID에 속하는 레코드 중에서 최신값을 골라 붙인다.

**주의**: 이는 Prod `core` 계층의 코드를 직접 읽어 확인한 강한 근거이지, 김창윤님의 명시적 확인 답변을 대체하는 것은 아니다.

#### 4.4.1 김창윤 확인 답변 도착 (2026-07-31 오후 10:28, Slack)

> "확인해봤는데 일단 property는 top과 동일한 컬럼이였고 params는 로깅 실수에서 온거라 작년 7월에서 10월까지 체크했는데 top과 params 둘다 학번형이여서 문제는 없을 것 같아요"

**질문 1(anonymous vs 학번형 우선순위)은 이 답변으로 사실상 종결됐다.**
- `property_user_id`는 `top_user_id`와 **동일한 컬럼**이었다(별도 소스가 아니라 하나의 값을 두 이름으로 노출한 것) — 1.3절에서 19건 전부 일치했던 이유가 설명된다.
- `param_user_id`는 **로깅 실수로 생긴 컬럼**이라 신뢰할 독립 소스가 아니다.
- 작년 7~10월 데이터를 직접 체크한 결과 `top`/`param` 둘 다 학번형이었고, anonymous와 학번형이 충돌한 실제 사례는 없었다.
- **다만 이는 특정 기간에 대한 경험적 확인이지, 앞으로도 절대 충돌이 없다는 설계 보장은 아니다.**

**질문 2(gender/major 대표성) — 리스크 수용으로 종결(2026-08-01)**: 김창윤님이 이 질문 자체를 이해하지 못했고, 이후 스레드에서 다시 답하지 않았다. 사용자가 "지금은 문제없다고 간주하고 종결"하기로 결정했고, 이후 실제 코드의 `latest_attributes`가 이 리스크를 그대로 구현하고 있음을 재확인했지만, 최종적으로 구조적 수정 없이 warn 테스트로 감시하는 쪽으로 확정했다(5.5.4절).

**질문 3(동일 관측 ID 충돌) — 리스크 수용으로 종결(2026-08-01)**: 실제 `silver__users` 이관 dbt 코드를 읽은 결과, `resolved_user_id = COALESCE(top_user_id, property_user_id, param_user_id)`가 행(관측) 레벨에서 먼저 계산된 뒤에야 cross-row "비-익명 우선" 정렬이 적용됨을 확인했다. 만약 어떤 사용자의 모든 관측에서 `top_user_id`가 항상 채워져 있고 항상 anonymous라면, 학번형인 `property_user_id`는 매 행 COALESCE 단계에서 이미 버려져 cross-row 우선순위 로직이 비교할 대상 자체가 없다. Silver User 로직을 고치는 방안까지 설계했으나, **최종적으로 Silver는 현재 코드 그대로 가고 이 문제도 warn 테스트로만 감시하기로 확정했다**(5.5.4절).

### 4.5 `mart.dim_users` — `is_deleted`/`is_mysql_mapped`는 Prod에도 아직 없음

Prod `mart.dim_users` 컬럼: `user_pseudo_id`, `user_id`, `platform`, `device_category`, `gender`, `major`, `entry_year`(STRING), `user_type`, `signup_completed_at`. CLAUDE.md는 `user_type`/`signup_completed_at`/`is_deleted`/`is_mysql_mapped` 4개가 "Prod 이전 시 추가된다"고 명시했는데, 실측 결과 **`user_type`, `signup_completed_at` 2개만 이미 Prod에 있고, `is_deleted`, `is_mysql_mapped`는 Prod에도 아직 없다.** 이 두 컬럼이 실제로 어디에 있는지(다른 테이블/아직 미구현인지) 추가 확인이 필요하다.

### 4.6 타입 불일치 — 확정(2026-08-06)

`entry_year`가 Stage `silver__users_temp`에서는 INTEGER(INT64), Prod `mart.dim_users`에서는 STRING이다(`INFORMATION_SCHEMA.COLUMNS`로 재확인). Prod 값을 `GROUP BY entry_year`로 전수 조사한 결과 NULL 23,170건을 제외하면 전부 2000~2026 사이 4자리 연도 문자열이었고, `SAFE_CAST(entry_year AS INT64)`로 캐스팅 실패한 값은 0건이었다. **Gold 계약은 INTEGER로 유지하고, Gold 출력 단에서 `SAFE_CAST(entry_year AS INT64)`로 정규화한다**(Silver 로직 변경 아님, `is_deleted`와 동일 패턴 — 5.8.1절 참고, 2장 6번 종결).

### 4.7 `is_logged_in`의 실제 Prod 계산식 확인 — 레거시가 이미 알려진 결함

`kap-chat.dash.vw_kpi_user_daily`의 실제 뷰 SQL을 확인한 결과, Prod의 `is_logged_in`은 다음과 같이 계산되고 있다.

```sql
CASE WHEN e.user_id IS NOT NULL THEN 1 ELSE 0 END AS is_logged_in
```

즉 **Prod 레거시가 이미 `user_id IS NOT NULL` 방식을 쓰고 있다.** 이건 CLAUDE.md가 명시적으로 금지한 바로 그 계산식이다 — "Prod는 이미 올바른 방식을 쓰고 있으니 그대로 따르면 된다"가 아니라, **Prod의 이 부분 자체가 새 설계에서 고치려는 대상(알려진 결함)**이라는 뜻이다. 5장(최종본)은 `is_logged_in`을 NULL로 미루는 데서 그치지 않고 **컬럼 자체를 아예 제거**했다(5.8.3절).

### 4.8 `used_account_flg` 실측 검증 (2026-08-01)

Stage `silver_events_temp`에서 `service_name = 'account'`인 68건을 `funnel_stage`/`is_entry_event`로 쪼개 확인한 결과:

| funnel_stage | 건수 | is_entry_event | is_core_action |
| --- | --- | --- | --- |
| login_entry | 60 | false | false |
| signup_start | 7 | false | false |
| terms_agreement | 1 | false | false |

**68건 전부 `is_entry_event = false`.** Account 퍼널에 literal `'entry'` 단계가 없어서, `service_name='account' AND is_entry_event` 조건으로는 `used_account_flg`가 항상 0이 된다는 주장이 실측으로 confirmed됐다. 그래서 5장은 `used_account_flg`를 Entry 조건 없이 "Account 서비스 이벤트 존재"로 재정의했다(5.8.5절).

### 4.9 BCSDLab Slack 사전 확인 및 설계 승인 (2026-08-01 오후 3:46~4:08)

이상민-김창윤 Slack 대화에서, 4.4.1절의 10:28pm 답변보다 **앞서** 있었던 부분이다.

- **오후 3:46, 김창윤**: "그 signup 컬럼이 koin_users에서 오는 컬럼인데 stage엔 없고 prod에만 있어서 이전할 때 추가할 예정이에요" — `user_type`/`signup_completed_at`/`is_deleted`/`is_mysql_mapped` 4개가 Prod 이전 시 추가된다는 내용을 김창윤님이 Slack으로 명시적으로 재확인했다(내용 자체는 CLAUDE.md 계약과 동일하지만, 이 출처가 이번에 처음 문서화됨).
- **오후 3:59, 이상민**: Gold 계층 설계 Notion 문서를 공유하며 "이런식으로 설계하면 될까요??"라고 확인 요청.
- **오후 4:05, 김창윤**: **"좋은데요?"** — Gold 설계에 대한 실제 승인. 다만 이건 배포 게이트인 "멘토 승인"과는 별개다 — 김창윤님은 Silver 쪽 동료 데이터 분석가이지, Production 배포를 게이트하는 멘토가 아니다.
- **오후 4:05~4:06, 김창윤**: "silver_users에서 user_id 컬럼이 대표 user_id로 선정한거라 그것만 아시면 좋을 것 같아요... 선정 로직은 기존 dataform과 거의 동일한데" — `silver__users.user_id`가 이미 대표 ID 선정이 끝난 컬럼이라는 것과, 그 선정 로직이 Prod의 기존 Dataform(=`core.vw_user_id_canonical`, 4.4절에서 코드로 확인한 바로 그 로직) 기준과 거의 동일하다는 걸 김창윤님이 직접 확인해줬다 — 내가 코드를 읽고 추정했던 부분이 원 개발자 확인으로 뒷받침됨.

이후 이상민이 4:17에 질문 1·2를 던졌고, 그 결과가 4.4.1절에 이어진다.

### 4.10 Stage vs Prod KPI 비교가 성립하지 않는 이유 (2026-08-06 실측)

`bq ls`/`INFORMATION_SCHEMA`로 재확인한 결과는 다음과 같다.

- **GA4 원본 속성 자체가 다르다.** Stage는 `analytics_427218788` + `analytics_440323811`, Prod는 `analytics_432041405`를 쓴다. 서로 다른 GA4 Property이므로 같은 날짜의 이벤트 수·세션 수가 같을 이유가 없다.
- **Prod `silver.silver_events`는 아직 Gold가 의존하는 분류 컬럼이 없다.** 실제 스키마 확인 결과 `raw_event_id`~`page_location`까지 20개 컬럼만 있고, `service_name`/`is_entry_event`/`is_core_action`/`funnel_stage`/`step_order`/`stage_scope`는 없다. 이 분류 로직은 Prod에서 `core.vw_event_service_map`, `core.vw_core_event_service_name_map`, `core.vw_event_funnel_map`, `core.vw_core_event_funnel_map` 등 **별도 View**로만 존재한다(Silver Event 테이블 자체에 아직 흡수되지 않음).
- **Prod `silver`/`core` 데이터셋에는 이미 여러 파이프라인 산출물이 있다**: `silver.silver_events`(TABLE, 분류 컬럼 없음), `core.table_core_user_id_canonical`, `core.incremental_core_events_final`, `core.vw_user_id_canonical` 등. Stage의 `silver_events_temp`/`silver__users_temp`와 Prod의 이 테이블들은 구조도 성숙도도 달라 1:1 비교 대상이 아니다.

**결론**: "같은 기간 Stage와 Prod의 KPI 숫자가 일치하는가"는 애초에 성립하지 않는 질문이다(모집단이 다름). 이번 검증으로 2장 5번을 "비교 불가/무의미"로 종결한다. 의미 있는 다음 단계는 운영 Silver 이관 후 Gold 공식을 Stage/Prod 각각에 적용했을 때 **각자 내부적으로** 값이 타당한지 확인하는 것이며, 이는 5.14.3절의 기존 배포 검증 절차에 이미 포함돼 있다.

### 4.11 Prod 현재 배포 준비 상태 실측 — As-Is (2026-08-06)

운영 Gold 배포 조건(5.14.3절) 대비 Prod의 현재 상태를 실측했다.

| 대상 | 현재 상태 |
| --- | --- |
| `kap-chat.silver.silver_events` | 존재. **2026-08-25 재실측 658,997행, `event_id` 고유 658,997, pseudo ID Null 0, 2026-06-27~2026-08-23 연속 58일** — Event 이력은 계속 증가 중이므로 인용 전 재조회한다 |
| Prod `silver_events` 분류 컬럼 | `service_name`/`is_entry_event`/`is_core_action` 없음(4.10절과 동일 확인) |
| `kap-chat.silver.silver__users` | **존재하지 않음** |
| `kap-chat.mart.dim_users` | `user_type`, `signup_completed_at`(TIMESTAMP) 존재. `is_deleted`, `is_mysql_mapped` 없음 |
| `kap-chat.mart.dim_users` 규모 | 전체 25,630행, 고유 `user_pseudo_id` 25,423, 고유 `user_id` 2,223 |
| `signup_completed_at` | Null 23,336건, non-null 2,294건, 가입일(KST) 범위 2018-08-26~2025-11-10, 미래 가입 0건 |
| `entry_year` | STRING, `SAFE_CAST(... AS INT64)` 실패 0건(5.8.1절과 일치) |
| `user_id`당 복수 `user_pseudo_id` | 522개 계정(고유 `user_id` 2,223개 중), 최대 43개 연결(5.13절 참고) |

`mart.dim_users`는 Gold의 직접 입력이 아니라 운영 Silver 승격 전 현재 상태를 확인하기 위한 비교 대상일 뿐이다. PR #29 기준 To-Be 운영 Gold는 배포된 `silver_events_v2`, `silver__users`만 참조한다.

**중요한 시사점**: Prod Event는 2026-06-27부터만 존재하는데 확인된 가입일은 2025-11-10 이전까지다. 즉 기존 가입자 대부분은 가입 시점 기준 D1/D7/D14/D30 평가 대상 날짜가 Event 데이터 시작일보다 훨씬 이르다 — 이 코호트를 "활동 없음(0)"으로 계산하면 안 되고 Null(측정 불가)로 처리해야 한다(5.8.4절 `event_complete_start_dt` 참고, 이번 실측이 그 필요성의 근거가 됐다).

**결론**: 2026-08-06 기준 Prod는 5.14.3절의 운영 배포 조건(분류 컬럼 존재, `silver__users` 존재, `is_deleted`/`is_mysql_mapped` 제공)을 만족하지 못한다. Silver 담당자의 운영 이관이 완료되기 전까지 Production 배포는 시작할 수 없다. **이 표는 As-Is(배포 준비 현황)이며, 5장의 38개 컬럼 To-Be 계약을 축소하는 근거로 쓰지 않는다** — Silver 이관 전에는 Stage에서 구조 검증(5.6절 Typed Placeholder)만 수행하고, 이관 완료 후 실제 값으로 가입·리텐션 지표를 재검증한다.

### 4.12 PR #29 병합 및 운영 Silver V2 코드 계약 확인 (2026-08-25)

GitHub PR #29는 2026-08-24 17:30 KST에 원격 `main`으로 병합됐다. 병합 커밋은
`3886d4f51af3a212b767871be81ae918b73aa984`이며 PR head의 최종 커밋은 `34bc5d0`이다.
실제 6개 변경 파일을 확인했으며, 기존 운영 `silver_events`를 수정하지 않고
`silver_events_v2`와 `silver__users` dbt 모델을 새로 추가한다.

| 항목 | PR #29 상태 | Gold 영향 |
| --- | --- | --- |
| Event 운영 후보 | `silver_events_v2` 추가 | 운영 Gold는 `ref('silver_events_v2')` 사용 |
| Event 분류 | SQL 출력에 `service_name`, `is_entry_event`, `is_core_action` 존재 | Gold 필수 입력 충족 후보 |
| Event pseudo ID | 동의 거부 Event의 Null을 정상 허용 | Gold 대상은 `user_pseudo_id IS NOT NULL`로 한정 |
| User 운영 후보 | `silver__users` 추가 | 운영 Gold는 `ref('silver__users')` 사용 |
| User 추가 4개 컬럼 | `user_type`, `signup_completed_at`, `is_deleted`, `is_mysql_mapped` 출력 | Placeholder 의존 제거 후보 |
| `is_deleted` | INT64 호환 출력 | Gold에서 BOOLEAN으로 출력 타입 정규화 |
| 저장소 상태 | 원격 `main` 병합 완료 | Gold가 참조할 코드 계약 확정 |
| BigQuery 배포 상태 | Stage·Production `silver_events_v2` 없음, Production `silver__users` 없음 | 병합만으로 실행·실데이터 검증이 완료된 것은 아님 |

`silver_events_v2.user_pseudo_id` Null은 Silver 오류로 간주하지 않는다. USER×DAY Grain에 넣을 수 없는 Event이므로 Gold `event_base`에서 제외하고, 제외 Event 수와 비율을 warn으로 감시한다. Event/User relationship 차단 테스트도 pseudo ID가 있는 Gold 대상 Event에만 적용한다.

PR의 `_silver_events_v2.yml`은 현재 `service_name`과 `stage_scope`를 문서화하지만 Gold 필수 컬럼인 `is_entry_event`, `is_core_action`은 컬럼 목록에 명시하지 않았다. SQL 출력에는 두 컬럼이 존재한다. Gold 배포 전 실제 테이블에 세 분류 컬럼이 모두 존재하는지와 타입을 확인한다. YAML 보완은 Silver 담당자 후속 사항이며 Gold에서 Silver YAML이나 분류 로직을 수정하지 않는다.

PR SQL에는 `club` 분류가 남아 있지만 현재 Gold 제품 범위에서는 `used_club_flg`를 계속 제외한다. Silver 분류가 존재한다는 이유만으로 Gold 계약을 자동 확장하지 않는다.

```text
As-Is deployed: legacy silver_events에는 분류 컬럼이 없고 Production silver__users는 없음
Merged code: 원격 main에 silver_events_v2 / silver__users 구현 존재
To-Be deployed: Stage 실행·검증, Production 승격·실행까지 완료된 상태
```

---

## 5. Gold Mart 설계 — 현행 계약과 대시보드 10개 구성요소 확장 설계 (2026-09-09)

이 장이 유일한 최종 기준이다. 지금까지 여러 차례 검토·수정을 거쳤고, 이 5장이 그 모든 논의의 최종 결과다. 앞으로 새 버전이 나오면 이 장을 계속 갱신하고, 별도 파일이나 다른 문서를 기준으로 삼지 않는다.

> **최신 설계 구분**: 5.0절은 KPI 4개·그래프 6개를 지원하기 위한 확장 설계다. 뒤의 기존 38컬럼·단일 USER×DAY·정확한 DN 계약은 현재 로컬 구현의 기준이며 전체 대시보드 지원 완료를 뜻하지 않는다. 확장 설계는 문서 수정 단계이고 SQL·테이블·BI 배포는 수행하지 않았다. 물리 테이블 수의 최종 선택에 앞서 논리 집계 단위와 필요한 사실을 먼저 확정한다.


### 5.0 대시보드 10개 구성요소를 위한 Gold 확장 설계

> **최신 사용자 제공 계약(2026-09-10)**: 사용자 Gold 44컬럼 + 집계 Gold 20컬럼의 물리 2개 구조는 5.0.11을 따른다. 아래 2026-09-09 단일 Gold 직접 참조안 및 이전 3개안은 이력이다. 두 모델은 Silver 직접 참조·Gold→Gold 금지를 유지한다. 로컬 SQL을 새 계약으로 변경하거나 배포한 것은 아니다.

#### 5.0.1 목적·범위·구현 상태

KPI는 MAU·신규 유저 수·D1~D7 범위 리텐션·주간 미복귀율의 4개, 그래프는 퍼널·서비스별 코호트 리텐션·주간 리텐션 커브·서비스별 이용 사용자 수·서비스별 DAU·서비스별 이탈률의 6개다. 이는 대시보드 화면 10개를 반드시 따로 만들거나 Mart를 10개 만든다는 뜻이 아니다. 퍼널 전환율 시계열은 앞선 논의의 추가 후보이며 같은 퍼널 사실로 지원하되 이번 확정 10개 개수에는 중복 포함하지 않는다.

Silver 모델·컬럼·중복 제거·사용자 ID·속성·MERGE는 수정하지 않는다. Gold 소유 Intermediate는 제공된 Silver 입력을 집계하며 Gold→Gold 참조는 만들지 않는다. 필요한 입력이 없다면 담당자에게 입력 계약 의존성으로 전달한다. 임시 분류 복제로 운영 입력 결손을 우회하지 않는다.

**구조적 결론**: 범위 리텐션·서비스 코호트·주간 리텐션 커브는 하나의 통합 리텐션 테이블에서 지원 가능하다. 대시보드 전체는 일별 활동·리텐션 평가·세션 퍼널이라는 서로 다른 논리 grain이 필요하다. 권장 물리화는 아래 3개이며, 하나의 물리 테이블을 유지하는 대안은 5.0.8에 명시한다. 이번 요청으로 3개 테이블의 생성이나 기존 모델 변경을 실행한 것은 아니다.

| 논리 출력 / 권장 모델명 | Grain | 역할 |
| --- | --- | --- |
| `mart_kpi_user_daily` 확장 | 날짜 × 사용자 | 기존 일간 KPI·서비스 활동 사실과 서비스 최초 이용일 제공 |
| `mart_user_retention` 신규 설계 | 계약버전 × 코호트종류 × 서비스 × 기준일 × 사용자 × 평가종류 × 평가시작경과일 × 평가종료경과일 | 일간·범위·주간 리텐션 및 주간 미복귀의 평가 사실을 통합 |
| `mart_user_funnel_session` 신규 설계 | 퍼널버전 × 퍼널 × 검증된 세션키 × 사용자 × 단계번호 | 동일 세션의 순차 도달 사실, 시작일, 관측완료 여부 제공 |

위 명칭 중 기존 마트 이외는 제안 모델명이며 아직 저장소에 구현되지 않았다. 기존 38컬럼에 아래 신규 사실을 추가하는 시점에는 YAML·고정 컬럼 테스트·참조 문서의 버전을 함께 변경한다.

#### 5.0.2 As-Is 재확인 및 과거 문안 정정

2026-09-09 BigQuery 직접 읽기 전용 확인 결과:

| 대상 | 이번 확인 |
| --- | --- |
| Stage `silver__users` | 필수 4개 컬럼 존재. 실제 COUNT 4,707행, 고유 pseudo 4,707, pseudo/first_seen_at NULL 0. 최초 관측일 2026-07-01~07-31. |
| Stage `silver_events` | 실제 COUNT 10,100행, 고유 event_id 10,100, pseudo NULL 0, 날짜 2026-07-19~08-27. 스키마에 service_name/is_entry_event/is_core_action 없음. |
| Stage `silver_events_temp` | 실제 COUNT 14,453행, 고유 event_id 14,453, pseudo NULL 0, 날짜 2026-07-01~08-08. 서비스·Entry·퍼널 분류 컬럼 존재. |
| Stage/Production `silver_events_v2` | 양쪽 Silver 목록에서 없음. |
| Production `silver__users` | Production Silver 목록에서 없음. |

이는 컬럼 존재·기본 집계 확인이다. User의 실제 가입 정보 정확성, Event/User 결합, 날짜별 누락, 최신 수집 완료, 서비스 분류와 퍼널 경로 정합성을 검증 완료한 것은 아니다. Event 최소~최대 날짜만으로 완전 가용 구간을 설정하지 않는다. Stage Event/User의 날짜 범위가 서로 다르므로 결합과 모집단을 별도 검증해야 한다.

사용자가 붙여넣은 “현재 Stage User에 4개 컬럼 없음”, Event 14,241행/User 117행, Placeholder 구조 검증 결과는 **2026-08-06 당시 `_temp` 이력**이다. 현재 Stage `silver__users` 상태로 인용하지 않는다. 고정 D1/D7/D14/D30은 과거 계약이고 현재 로컬 구현은 정확한 D0~D365 사실, 확정 KPI 요구는 D1~D7 범위 리텐션이다. 세 상태를 혼용하지 않는다.

운영 목표 입력은 필수 분류가 제공되는 Silver Event 계약과 `silver__users`다. 현재 코드상 후보명은 `silver_events_v2`다. 컬럼 없는 legacy `silver_events`를 이름만 같다는 이유로 목표 입력으로 인정하지 않는다. 현재 로컬 Gold가 임시 `int__event__service_classification`을 참조하는 사실은 6.12에 기록했으며, 운영 경로가 검증된 것으로 취급하지 않는다.

#### 5.0.3 공통 Intermediate·활동 기준·완전성

권장 흐름은 **Silver → Gold 소유 공통 일별 활동/최초 서비스 이용/코호트 평가/퍼널 경로 Intermediate → 각 Gold 출력 → Superset**이다. 두 Gold가 같은 Intermediate를 읽을 수 있지만 다른 Gold를 입력으로 읽지 않는다. Gold 소유 Intermediate를 허용한다는 것이 Silver 분류·ID 로직 재구현을 허용한다는 의미는 아니다.

필요한 내부 사실:

- `사용자 × 서비스 × 날짜`의 Any Event 여부, Entry 여부, 이벤트 수. 전체 범위는 `__all__`, 실제 메인 화면은 `main`으로 구분한다. `__all__`은 서비스 사용자 합계가 아니라 전체 이벤트에서 사용자를 중복 제거한 범위다.
- 서비스별 `first_service_seen_dt`: 제공된 충분한 Silver 과거 이력에서 해당 서비스 활동이 최초 관측된 날짜. `first_seen_dt`와 구분한다. 이력이 불충분한 경우 “최초 관측 기준”으로 명시하고 신규/기존 판정을 미확인 상태로 처리할 계약이 필요하다. 날짜 필터 내부의 MIN으로 최초 이용일을 만들지 않는다.
- `event_complete_start_dt`, `event_complete_dt`, 빌드 기준일·계약 버전. 구간 내부 누락이 없음을 보증하는 완전성 계약이 필요하며, 누락이 있으면 해당 구간을 미평가로 만든다. 향후 날짜를 활동 0으로 확정하지 않는다.

활동 기준 제안: 전체 MAU/주간 미복귀는 Any Event, 전체 최초방문 범위 리텐션 복귀는 Entry로 기존 확정 정의를 유지한다. 서비스 이용량·서비스 리텐션의 기준은 거버넌스와 맞춰 **서비스별 동일한 기준**으로 anchor·복귀에 적용한다. 아직 제공 문구의 “활성 사용자(거버넌스에 따름)”만으로 확정할 수 없으므로 후보 기본값은 Entry로 명시하되 기존 cafeteria/account Any Event 플래그를 Entry로 재명명하지 않는다. 서비스 기준이 승인·검증되기 전에는 해당 차트를 검증 대기로 둔다.

실제 main과 __all__은 같은 범위가 아니다. `board`는 공지사항이며 팀원모집으로 해석하지 않는다. club·별도 동아리 앱은 기존 제외 범위를 유지한다. 가입 퍼널은 account를 사용하지만 서비스 이용량 차트에는 account/main을 제외한다. “모든 서비스”라는 UI 문구 대신 제공·검증된 서비스 목록을 공개한다.

#### 5.0.4 기존 일별 KPI 마트에 추가할 것

기존 USER×DAY grain과 38개 컬럼 의미를 보존한다. 서비스 첫 이용/활동의 추가 컬럼은 최종 서비스 목록에 대해 아래 이름 패턴으로 명시하며, 기존 `used_*_flg`의 의미를 덮어쓰지 않는다.

| 추가 필드 | 타입 | 용도 |
| --- | --- | --- |
| `service_<s>_any_event_flg` | INT64, 0/1 | 해당 서비스 Any Event 이용 여부; 직접 상세 진입 등 Entry 없는 이용도 표현 |
| `service_<s>_entry_flg` | INT64, 0/1 | 해당 서비스 Entry 활동 여부; 서비스 거버넌스 기준과 대조 |
| `first_<s>_seen_dt` | DATE, nullable | 서비스별 최초 활동일; 신규/기존 분류 |
| `first_<s>_seen_is_known` | BOOL | 서비스 최초 관측일을 신규/기존 판정에 사용할 수 있는지 구분 |
| `event_complete_start_dt`, `event_complete_dt` | DATE | BI의 부분 관측 제외 기준 |
| `data_as_of_at` | TIMESTAMP | 빌드/데이터 기준시각 |
| `contract_version` | STRING | 컬럼·서비스 활동 정의 버전 |

`s`의 현재 설계 대상은 shop, bus, cafeteria, timetable, board, grad_calc, facility, main이며 account는 가입 퍼널 입력으로 별도 유지한다. `first_<s>_seen_dt`가 Any Event/Entry 중 무엇의 최초 날짜인지 계약에 고정하고 해당 서비스 활동 기준과 맞춘다. 둘 다 필요한 경우 날짜를 별도 명명한다. 8개 서비스 × 4개 신규 필드와 공통 4개 필드를 그대로 채택하면 기존 38개에서 74개가 되는 확장 후보이며, 확정 전 기존 컬럼 계약을 74개로 간주하지 않는다.

서비스별 기간 이용자는 각 서비스 플래그가 1인 고유 pseudo 수다. 신규는 기간 안에 최초 서비스 활동이 있는 이용자, 기존은 기간 전 최초 서비스 활동이 있는 이용자다. 최초일을 판정할 수 없는 이용자는 별도 “미확인”으로 표시하거나 신규/기존 분해를 제공하지 않는다. 하나의 사용자를 신규와 기존 양쪽에 넣지 않는다. 일별 DAU 신규/기존은 날짜별 정의를 사용하며 기간 전체 분류와 구분한다.

Superset은 wide 서비스별 Metric을 차트에서 series로 표시할 수 있도록 구성한다. 서비스명 열을 요구하는 필터/차트가 필요하면 저장된 데이터셋 변환 또는 정규화 출력이 필요하다. 기존 “Virtual Dataset 없음” 제약을 유지하는 경우 여러 Metric을 지원하는 실제 차트 설정으로 검증하고, 서비스 범례만 보고 네이티브 service_name 행 필터가 있다고 가정하지 않는다.

#### 5.0.5 통합 리텐션 테이블 — 세 리텐션과 주간 미복귀 공유

**하나의 리텐션 테이블을 공유하되 일별 사실과 기간 사실을 행 종류로 명확히 구분한다.** 사용자별 Range/Week OR 집계를 Gold에서 끝내므로 Superset은 선택한 평가 종류의 분모·분자를 단순 집계한다. 과거 설명의 사용자×경과일 테이블만 만들고 BI에 2단계 집계를 떠넘기지 않는다.

| 필드 | 타입 | 계약 |
| --- | --- | --- |
| `contract_version` | STRING | 코호트/활동/평가 정의 버전 |
| `cohort_type` | STRING | `first_seen`, `service_active_day`, `weekly_active` |
| `service_name` | STRING | `__all__` 또는 검증된 서비스 코드, main은 별도 |
| `anchor_dt` | DATE | 최초 관측일, 서비스 활동일 또는 기준 주 월요일 |
| `user_pseudo_id` | STRING | 코호트 사용자; 분모 보존 단위 |
| `evaluation_type` | STRING | `exact_day`, `range_d1_d7`, `relative_week`, `next_calendar_week` |
| `window_start_day`, `window_end_day` | INT64 | anchor 기준 관측 구간; 포함 범위 |
| `evaluation_start_dt`, `evaluation_end_dt` | DATE | 실제 평가 날짜 |
| `cohort_activity_basis`, `return_activity_basis` | STRING | Any Event/Entry를 구분 |
| `segment_at_anchor` | STRING | 기준일 당시 신규/기존/미확인; 평가일마다 바꾸지 않음 |
| `is_evaluable` | BOOL | anchor 모집단과 평가 구간 전체의 수집 완전성 충족 |
| `is_returned` | INT64, nullable | 완전 관측 시 구간 내 복귀 1/미복귀 0, 미평가 NULL |
| `eligible_user_flg` | INT64 | 평가 가능 1, 그 외 0 |
| `returned_user_flg` | INT64 | 평가 가능하고 복귀한 경우만 1, 그 외 0 |
| `not_returned_user_flg` | INT64 | 평가 가능하고 미복귀한 경우만 1, 그 외 0 |
| `event_complete_start_dt`, `event_complete_dt`, `data_as_of_at` | DATE/DATE/TIMESTAMP | 관측 기준 메타데이터 |

필터에 필요한 사용자 속성은 코호트 anchor 시점 기준으로 고정한다. Silver가 현재 스냅샷만 제공하는 gender/major 등을 과거 당시 속성으로 부르지 않는다. anchor의 플랫폼도 원천에서 정한 기준으로 고정하여 미복귀 평가행의 unknown 때문에 분모가 사라지지 않게 한다.

허용 행 조합:

| 용도 | cohort / 범위 | evaluation / 경과일 | 계산 |
| --- | --- | --- | --- |
| KPI D1~D7 Range | first_seen / __all__ | range_d1_d7 / 1~7 | anchor 월 필터 후 `100*SAFE_DIVIDE(SUM(returned_user_flg),SUM(eligible_user_flg))` |
| 일별 코호트 | service_active_day / 서비스 또는 main·__all__ | exact_day / N~N | anchor별·N별 동일 비율. D0는 정의상 anchor 활동이라 평가 가능 분모의 100% |
| 주간 커브 | service_active_day / 서비스 또는 main·__all__ | relative_week / 1~7, 8~14, ... | 같은 anchor의 경과 주차별 구간 복귀 비율. 주간 전체 관측 후 평가 |
| 앱/서비스 주간 미복귀 | weekly_active / __all__ 또는 서비스 | next_calendar_week / 7~13 | 기준 주 월요일 anchor의 사용자 중 다음 월~일 복귀 없음. `100*SAFE_DIVIDE(SUM(not_returned_user_flg),SUM(eligible_user_flg))` |

weekly_active의 기준 모집단은 anchor+0~6일 전체에 해당 활동이 있는 사용자다. 다음 주는 +7~13일이다. 상대 주차 +1~7과 달력 다음 주를 혼용하지 않는다. 앱 주간 미복귀는 Any Event로 확정되어 있고 서비스 주간 미복귀는 동일 서비스 미복귀라는 기본 제안이며 최종 정의 확정이 필요하다.

미평가 행은 is_returned=NULL, 집계 플래그 세 개는 0이다. 미복귀도 사용자 평가행이 반드시 남는다. `returned + not_returned = eligible`을 모든 행에서 보장한다. 관측이 끝나기 전에 복귀했더라도 미평가이면 분모·분자 모두 0이다. 분모 0은 N/A, 리텐션 분모 30명 미만은 비율을 숨기고 분모는 표시한다.

**코호트 기준일 계약**: 서비스 일간 코호트에는 그날 활동한 신규·기존 사용자가 모두 포함되며 같은 사용자가 여러 날짜의 코호트에 속할 수 있다. 월 전체 최초 방문 코호트에는 사용자당 anchor가 하나뿐이다. `first_seen_dt`를 서비스 활동일 anchor로 대체하지 않는다.

**주간 커브의 선택 기간 처리**: 사용자 제공 문구는 기간 내 기존·신규 유입을 언급하지만 여러 anchor의 동일 사용자 처리 기준은 아직 없다. 기본 화면은 anchor 한 날짜를 선택한 주간 커브로 제공하는 설계다. 여러 anchor를 통합하면 “사용자-코호트 참여 건수 가중 리텐션”이며 전체 고유 사용자 비율로 부르지 않는다. 기간 내 사용자당 최초 활동일을 anchor로 하는 고유 사용자 커브를 원하면 기간 선택에 따라 달라지는 사용자 집합 계산 또는 고정 cohort_period 계약이 추가로 필요하다. 같은 사람을 단순 SUM으로 중복 집계한 커브를 확정 요구 충족으로 표시하지 않는다.

파티션 후보는 anchor_dt, 클러스터 후보는 service_name/cohort_type/evaluation_type/user_pseudo_id다. 가능한 모든 과거 날짜×모든 사용자×D365를 생성하지 않는다. 실제 코호트 참여 사용자만 확장하고, 보존할 anchor 기간·최대 경과일·주간 평가 수를 명시한 뒤 비용을 측정한다. 기존 first_seen D365의 123만 행 근사는 서비스 활동일 코호트 비용으로 재사용할 수 없다.

#### 5.0.6 퍼널 테이블과 추가 Silver 입력 계약

일별 Gold의 일간 세션 수·서비스 플래그만으로 순서 기반 퍼널을 복원하지 않는다. Gold 소유 퍼널 Intermediate에서 Silver의 이벤트 상세를 읽어 유효한 세션 경로를 판정하고 결과만 공개한다.

필수 입력은 event_id, user_pseudo_id, ga_session_id, event_dt, event_at/event_ts, service_name, funnel_stage, step_order 및 검증 가능한 순서·세션 구분 정보다. 같은 pseudo/session 값이 서로 다른 스트림에서 충돌하는지 검증할 식별 정보가 필요하다. 현재 스키마로 증명하지 못하는 부분은 Silver 담당자에게 입력 의존성으로 전달한다. Gold에서 임의 식별자나 동률 순서를 만들어 정상 경로라고 선언하지 않는다.

출력 필드: `funnel_version`, `funnel_name`, `user_pseudo_id`, `session_key`, `anchor_dt`, `first_step_at`, `step_no`, `step_name`, `is_session_complete`, `is_step_reached`, `is_next_step_reached`, `is_final_step_reached`, `data_as_of_at`. 사용자×세션×퍼널마다 모든 정의 단계 행을 만들며 도달하지 않은 단계는 false로 보존한다. 단계의 의미·번호는 퍼널 버전에 종속된다.

`is_step_reached`는 해당 세션에서 1~현재 단계를 순서대로 충족했다는 뜻이다. `is_next_step_reached`는 그 세션의 다음 단계까지, `is_final_step_reached`는 마지막 단계까지 순차 도달을 의미한다. 완전 관측 세션만 공식 집계에 포함한다. 첫 단계에 도달하지 않은 세션은 대상이 아니다. 선택 기간은 첫 단계 진입일 anchor_dt에 적용하며 종료일 세션의 후속 이벤트도 관측한다.

동일 사용자의 여러 세션은 단계별 COUNT DISTINCT로 합친다. 단계 k 도달자 수를 U_k라 하면 직전 대비 전환율=U_k/U_(k-1), 다음 단계 이탈률=1-U_(k+1)/U_k, 전체 전환율=U_last/U_1이다. 같은 단계 행의 next/final 플래그를 조건부 COUNT DISTINCT하면 다음 단계·전체 완료 사용자 수를 얻을 수 있다. 이전 단계 대비율은 인접 단계 도달 수를 이용하는 차트 계산/검증된 Metric으로 구성하며 단순 행수 SUM을 쓰지 않는다. 첫 단계 도달률 100%, 마지막 다음 단계 이탈률 N/A, 분모 0 N/A다.

대상은 이번 확정 표의 7개: 회원가입 5단계, 주변상점·버스·식단·시간표·게시판 4단계, 졸업계산기 3단계다. 졸업계산기의 마지막은 탐색이며 임의로 핵심 전환/완료라고 바꾸지 않는다. 과거 시설 퍼널은 이력/확장 후보로 보존하되 이번 7개 목록에 자동 추가하지 않는다. main은 서비스 필터로 제거하지 않도록 상점 등의 첫 단계에 별도 결합한다. 버스는 출발 **또는** 도착지 확인이다. 가입은 로그인 진입을 가입 시작 대신 사용하지 않는다.

#### 5.0.7 주간 미복귀·필터와 남은 정의

사용자 문안의 “4달 동안 이벤트 없음”은 정의·계산식과 충돌하므로 **기준 주 활성 사용자 중 바로 다음 주에 이벤트가 한 번도 발생하지 않은 사용자 수**로 정정한다. 4개월 이탈 KPI를 새로 도입하지 않는다. 서비스별 이탈은 “같은 서비스의 다음 주 미복귀”를 제안 기준으로 적고 최종 확정 전 구현 대기로 표시한다.

MAU·신규 KPI의 기준 월, Range의 최초 방문 월, 주간 미복귀의 완료된 연속 두 주, 퍼널의 시작 세션 기간, 코호트의 anchor 기간은 서로 다른 필터다. 월 카드 종료일은 월말과 완전 가용 종료일 중 이른 날이다. 주간 미복귀는 해당 종료일까지 두 주 모두 관측된 가장 최근 쌍을 사용한다. Range의 D7은 다음 달로 이어질 수 있다. 과거 월말 시점 재현과 현재 기준의 성숙 코호트 평가는 구분한다.

서비스 신규 여부, 서비스 활동 거버넌스, 주간 커브의 여러 anchor 사용자 중복 기준은 제공 문안만으로 완전히 확정되지 않았다. 위 기본 제안과 제한을 표시하고, 문서가 이미 전체 10개 차트의 검증된 최종 실행 계약이라고 선언하지 않는다. UI/UX 문제·아하 모먼트·실험 효과는 해당 지표만으로 인과적으로 확정하지 않는다.

#### 5.0.8 물리 Gold를 하나로 유지해야 할 경우

물리 테이블 하나도 가능하지만 현 USER×DAY 38컬럼 계약을 유지한 채 추가 컬럼 몇 개만 붙이는 형태는 아니다. 하나의 공개 테이블에 아래 논리 사실을 **UNION ALL**하고 `record_type`으로 분리하는 대안이다. 서로 다른 사실을 JOIN해서 일간 활동을 평가일/퍼널 단계 수만큼 복제하지 않는다.

- `daily_activity`: 사용자×날짜의 일별 KPI 행.
- `retention_evaluation`: 5.0.5의 사용자×코호트×평가구간 행.
- `funnel_step`: 5.0.6의 사용자×세션×단계 행.

공통 필드는 `record_type`, `record_key`, `record_dt`, `user_pseudo_id`, `contract_version`, `data_as_of_at`이며 종류별 필드는 nullable한 superset 스키마로 둔다. record_key는 각 종류의 전체 grain에서 충돌 없이 생성하고 `(record_type, record_key)`를 검증한다. record_dt는 daily의 event_dt, retention/funnel의 anchor_dt로 정의한다. 타입별 날짜 역할을 명시하고 단일 공통 날짜 필터로 모든 카드 기간을 결정하지 않는다.

각 Superset 차트는 필수 record_type 조건을 고정해야 한다. 활동 컬럼을 retention/funnel 행에 복사하지 않고 NULL로 유지하며 타입별 필수값·배타성 검증을 추가한다. 월간 DISTINCT와 신규 SUM은 daily_activity만 읽는다. 리텐션은 해당 evaluation_type/cohort_type/service를 고정한다. 테이블명 `mart_kpi_user_daily`를 유지한다면 더 이상 USER×DAY만의 마트가 아니라는 파괴적 계약 변경을 명시하고 모든 기존 차트를 이관해야 한다.

이 방식은 **물리 1개 / 논리 3개**다. 타입별 NULL 컬럼, 잘못된 필터·집계 위험과 운영 복잡성이 늘므로 권장안은 논리 grain에 맞춘 물리 3개다. 사용자의 “가능한 한 하나” 선호에 대한 대안으로 제시하며, 물리 수 선택 전에 실제 SQL/비용·Superset 필터 안전성을 검증한다. 이번 문서 수정에서는 어느 테이블도 생성하지 않는다.

#### 5.0.9 검증 및 이행 순서

1. Silver 실제 입력과 Event/User 관계, 전체/서비스별 완전 가용 구간, 서비스 활동 정의, 신규/기존 기준을 검증한다. 2026-09-09 기본 COUNT만으로 이 단계를 통과했다고 하지 않는다.
2. 일별 활동·서비스 최초 이용의 공통 Intermediate를 설계하고 현재 38컬럼과의 동등 지표 대조를 수행한다. 기존 사용자의 local 변경은 보존한다.
3. 통합 리텐션에서 Range D0 제외·다중 복귀 1명·미성숙 양쪽 제외·0/NULL·월경계·주경계·서비스 이동·신규/기존·중복 anchor 사례를 검증한다. 세 평가 집계 플래그의 합 관계와 grain 고유성을 확인한다.
4. 퍼널의 순서 역전·단계 생략·반복·세션 분리·자정 통과·타임스탬프 동률·미완료 세션을 확인하고 단계 집합 포함관계와 같은 기간 사용자 DISTINCT를 검증한다.
5. 선택한 물리 구조에 따라 컬럼 계약·dbt tests·BI Dataset/Metric을 이관한다. Full Refresh로 Stage 실제 KPI를 검증한 뒤 운영 규모 행수·bytes·시간·Superset 차트 결과를 확인한다. 기존 DN 비용 추정은 서비스 코호트에 재사용하지 않는다.
6. 코드 작성/compile 통과/Stage 실행·품질 검증/운영 배포/BI 확인을 별도 상태로 관리한다. 이번 변경은 **설계 문서 수정 완료**, 구현·배포는 미수행이다.

---

### 5.0.10 Stage 기준 단일 Gold 직접 참조 계약 — 사용자 1~14장 형식 (2026-09-09)

#### 1. 목적

Bronze 이후부터 BI 대시보드까지 사용하는 데이터 계층의 역할을 정의하고, Superset이 직접 조회할 Gold Mart의 차기 테이블 계약을 설계한다.

현재 작업 범위는 Gold 계층으로 한정한다. Silver Event와 Silver User는 Silver 담당자가 제공하는 계약을 입력으로 사용하며, Gold 담당자는 다음 작업을 수행하지 않는다.

- Silver 테이블 및 모델 수정
- Silver 컬럼 직접 추가
- Event 중복 제거 로직 수정
- 사용자 ID 후보 선정 및 정규화 수정
- 사용자 속성 선정 수정
- Silver MERGE 및 지연 Event 처리 수정

Gold 물리 테이블은 하나로 구성하는 설계안을 사용한다. 현재 모델명을 유지할 경우 대상은 다음과 같다.

```text
gold.mart_kpi_user_daily
```

기존 모델은 USER×DAY 38개 컬럼의 일별 데이터 마트다. 확정 KPI 4개와 그래프 6개를 같은 물리 테이블에서 지원하려면 일별 활동, 리텐션 평가, 세션별 퍼널을 구분하여 저장하는 차기 계약으로 변경해야 한다.

```text
기존 계약: USER×DAY 38개 컬럼
차기 설계: record_type으로 구분한 일별 활동 / 리텐션 평가 / 퍼널 단계
```

물리 테이블 하나를 사용하더라도 모든 행의 Grain이 같은 것은 아니다. 차트별로 필요한 행 종류만 조회하며, 서로 다른 종류의 사실을 JOIN하여 활동 수나 사용자 수를 중복시키지 않는다.

현재 검증 기준은 Stage `koin-stage-438512`다. 2026-09-09 직접 확인 결과, Stage `silver__users`에는 가입 관련 4개 컬럼과 실제 값이 존재한다. Stage `silver__users_temp`에는 네 컬럼이 없고, Production `silver__users`는 아직 존재하지 않는다.

이 문서는 다음 두 상태를 함께 관리한다.

```text
As-Is: 현재 Stage 테이블·컬럼·기본 데이터 확인 및 로컬 38컬럼 구현
To-Be: Stage 입력 검증 후 단일 Gold 확장 계약 구현·검증
```

현재 구현 및 검증 상태는 다음과 같다.

| 구분 | 상태 |
| --- | --- |
| 기존 Gold SQL 및 38개 컬럼 계약 작성 | 로컬 코드 존재 |
| 2026-08-06 Typed Placeholder 구조 검증 | 과거 계약의 검증 이력 |
| Stage User 실제 4개 컬럼·타입·기본 값 적재 확인 | 완료 |
| 실제 User 값의 의미·매핑·Event 관계·Stage KPI 검증 | 별도 검증 필요 |
| Stage Event V2 및 필수 분류 입력 제공 | 대기 |
| 단일 Gold로 KPI 4개·그래프 6개를 수용하는 구조 | 이 문서에서 설계; SQL·테스트 구현 미수행 |
| Production·BI 연결 | Stage 검증 및 운영 입력 승격 후 진행 |

현재 Stage User 검증에서는 네 실제 컬럼을 직접 사용한다. Placeholder 결과를 실제 가입·리텐션·탈퇴·매핑 KPI 검증으로 간주하지 않는다. 단일 테이블 설계 가능성과 현재 Stage 입력으로 즉시 실행 가능한지는 별도다.

1차 Gold는 전체 결과의 정확성을 우선 검증하기 위해 Full Refresh 방식으로 구현한다. 증분 최적화는 2차 작업으로 분리하되, 실제 코호트 행 수·처리 비용이 허용 범위를 넘으면 BI 연결 전에 재설계한다.

---

#### 2. 전체 구조와 참조 원칙

```text
bronze_ga4_events
  ↓
Stage Silver Event / silver__users
  ↓
Stage gold.mart_kpi_user_daily
  └─ 하나의 SQL 내부 CTE에서 활동·리텐션·퍼널 계산
  ↓
Superset KPI 4개 + 그래프 6개
```

##### 모델 간 참조 원칙

```text
Gold → Silver 참조: 허용
별도 Intermediate 모델: 사용하지 않음
Gold → Gold 참조: 허용하지 않음
BI → Gold 참조: 허용
운영 Gold → Stage *_temp 참조: 허용하지 않음
```

여러 차트와 대시보드가 동일한 Gold Dataset을 조회할 수 있다. 대시보드 수와 Mart 수를 일대일로 맞추지 않는다. 활동·리텐션·퍼널 계산은 모두 mart_kpi_user_daily.sql 내부 CTE로 작성한다. CTE는 별도 테이블이나 dbt 모델이 아니며 Gold가 다른 Gold 테이블을 참조하지 않는다.

단일 테이블의 행 종류와 Grain은 다음과 같다.

| record_type | Grain | 제공 지표 |
| --- | --- | --- |
| `daily_activity` | 날짜 × 사용자 | MAU, 신규 유저 수, 서비스별 이용 사용자 수, 서비스별 DAU |
| `retention_evaluation` | 계약버전 × 코호트종류 × 서비스 × 기준일 × 사용자 × 평가종류 × 평가시작경과일 × 평가종료경과일 | 범위 리텐션, 일별 코호트, 주간 리텐션 커브, 앱·서비스 주간 미복귀 |
| `funnel_step` | 퍼널버전 × 퍼널 × 사용자 × 검증된 세션키 × 단계번호 | 동일 세션의 순서 기반 퍼널 |

전체 테이블의 고유 키는 `(record_type, record_key)`다. `record_key`는 각 행 종류의 전체 Grain으로부터 충돌 없이 생성하고 검증한다. 기존 `(event_dt, user_pseudo_id)` 유일성은 daily_activity 행에만 적용한다.

| 공통 추가 컬럼 | 타입 | 목적 |
| --- | --- | --- |
| `record_type` | STRING | 일별 활동·리텐션·퍼널 구분 |
| `record_key` | STRING | 종류별 Grain 고유 식별 |
| `record_dt` | DATE | 일별 활동은 event_dt, 리텐션·퍼널은 anchor_dt; 파티션 후보 |
| `contract_version` | STRING | 집계 계약 버전 |
| `event_complete_start_dt` | DATE | 연속 완전 가용 구간 시작 |
| `event_complete_dt` | DATE | 연속 완전 가용 구간 종료 |
| `data_as_of_at` | TIMESTAMP | 데이터·빌드 기준시각 |

공통 의미가 같은 컬럼만 공유하고 의미가 다르면 별도 이름을 사용한다. 각 내부 CTE 결과는 명시적 컬럼·타입으로 투영한 뒤 UNION ALL한다. 해당 행 종류에서 사용하지 않는 컬럼은 타입이 지정된 NULL로 둔다. 이는 서로 다른 사실의 스키마를 합치는 NULL이며, 누락된 Silver 필수 입력을 가짜 값으로 대체하는 Placeholder가 아니다.

---

#### 3. Silver 입력 계약

##### 3.1 Stage 검증 입력

| 구분 | 현재 테이블 | 사용 범위 |
| --- | --- | --- |
| User | `koin-stage-438512.silver.silver__users` | 네 실제 컬럼을 사용하는 현재 User 검증 입력 |
| Event 기본 사실 | `koin-stage-438512.silver.silver_events` | 기본 이벤트 점검; 필수 서비스 분류 없음 |
| Event 분류 참고 | `koin-stage-438512.silver.silver_events_temp` | 분류 컬럼과 표본 참고; 출처·생성 경로 제한 있음 |
| 과거 User | `koin-stage-438512.silver.silver__users_temp` | 과거 구조 검증 이력; 네 컬럼 없음 |
| 목표 Event | `koin-stage-438512.silver.silver_events_v2` | 현재 미존재; 제공 및 품질 검증 대기 |

현재 Stage Event 기본 사실과 분류 참고 테이블을 같은 데이터의 검증 완료 버전처럼 혼용하지 않는다. `_temp`를 목표 V2의 검증된 산출물로 간주하지 않으며, 운영 Gold가 Stage `_temp`를 직접 조회하지 않는다.

##### 3.2 Event Silver 필수 컬럼

| 컬럼 | 타입 | Gold 사용 목적 |
| --- | --- | --- |
| `event_id` | STRING | Event 고유성·보존 검증 |
| `event_dt` | DATE | 일별 집계 및 활동일 |
| `event_at` | DATETIME | 일간 대표값 및 이벤트 순서 검토 |
| `event_ts` | INT64 | 퍼널 이벤트 순서 검토; 동률 해소 보장과는 별도 |
| `user_pseudo_id` | STRING | 사용자 결합·코호트·퍼널 사용자 |
| `ga_session_id` | STRING | 사용자와 결합한 퍼널 세션 식별 |
| `custom_session_id` | STRING | 기존 일별 세션 계산; 퍼널 기본 키로 사용하지 않음 |
| `platform` | STRING | 플랫폼 분석 |
| `device_category` | STRING | 디바이스 분석 |
| `device_os` | STRING | OS 분석 |
| `engagement_time_msec` | INT64 | engagement 시간 합계 |
| `service_name` | STRING | 서비스 활동·코호트 |
| `is_entry_event` | BOOLEAN | Entry 활동·복귀 판정 |
| `is_core_action` | BOOLEAN | Core Action 지표 |
| `funnel_stage` | STRING | 퍼널 단계 의미 |
| `step_order` | INT64 | 서비스별 단계 순서 정의 |

세션의 스트림 간 충돌이나 이벤트 시각 동률을 현 필드로 판정할 수 없으면 추가 입력 의존성을 Silver 담당자에게 전달한다. Gold가 임의 순서·세션 식별자를 만들어 정확한 경로로 간주하지 않는다.

2026-09-09 Stage 실측 결과는 다음과 같다.

| 검증 항목 | silver_events | silver_events_temp |
| --- | ---: | ---: |
| 전체 Event 행 | 10,100 | 14,453 |
| 고유 event_id | 10,100 | 14,453 |
| user_pseudo_id Null | 0 | 0 |
| Event 날짜 범위 | 2026-07-19~08-27 | 2026-07-01~08-08 |
| 서비스·Entry·Core 분류 컬럼 | 없음 | 있음 |

이번 집계에서 event_id 고유 수와 전체 행 수가 같음을 확인했지만, Event/User 관계·날짜별 수집 완전성·분류 정확성·퍼널 순서는 별도 검증 대상이다. 최소~최대 날짜를 그대로 완전 가용 구간으로 선언하지 않는다.

분류 계약이 제공된 Event의 nullable 플래그는 기존 계약에 따라 처리한다.

```sql
COALESCE(is_entry_event, FALSE)
COALESCE(is_core_action, FALSE)
```

단, 컬럼 자체가 없는 입력을 이 식으로 우회할 수는 없다. 과거 14,241행과 서비스별 Entry 건수는 2026-08-06 표본 이력이며 현재 Stage 수치로 사용하지 않는다.

##### 3.3 User Silver 필수 컬럼

| 컬럼 | 타입 | Gold 사용 목적 |
| --- | --- | --- |
| `user_pseudo_id` | STRING | 사용자 결합 및 Grain |
| `user_id` | STRING | Silver 최종 사용자 ID |
| `gender` | STRING | 현재 스냅샷 사용자 필터 |
| `major` | STRING | 현재 스냅샷 사용자 필터 |
| `entry_year` | INT64 | 사용자 필터 |
| `first_seen_at` | DATETIME | 코인 전체 최초 관측일 |
| `user_type` | STRING | 사용자 유형 |
| `signup_completed_at` | TIMESTAMP | 가입일; 최초 관측일과 구분 |
| `is_deleted` | INT64, BOOLEAN 변환 호환 | 현재 탈퇴 상태 |
| `is_mysql_mapped` | BOOL | MySQL 사용자 매핑 여부 |

2026-09-09 Stage `silver__users` 실측 결과는 다음과 같다.

| 검증 항목 | 결과 |
| --- | --- |
| 전체 User 행 | 4,707 |
| 고유 user_pseudo_id | 4,707 |
| user_pseudo_id Null | 0 |
| first_seen_at Null | 0 |
| 최초 관측일 범위 | 2026-07-01~07-31 |
| user_type non-null | 488 |
| signup_completed_at non-null | 488 |
| is_deleted non-null | 488 |
| is_mysql_mapped non-null | 4,707 |
| is_mysql_mapped = TRUE | 488 |

위 개수가 같다고 동일 행 집합이나 매핑 정확성을 증명한 것은 아니다. 사용자 수는 계정 수가 아닌 user_pseudo_id 기준이다. 과거 117명 표본의 계정 중복 분포를 현재 4,707행의 결과로 사용하지 않는다.

##### 3.4 Stage에 추가된 User 입력

네 컬럼은 **Stage `silver__users`에 존재하며 실제 값도 적재되어 있다.** `_temp`의 미존재 상태와 구분한다.

| Silver User 컬럼 | 설계상 원천 | 실제 Stage 타입 | Gold 사용 목적 |
| --- | --- | --- | --- |
| `user_type` | koin_users.user_type | STRING | 사용자 유형 |
| `signup_completed_at` | koin_users.created_at | TIMESTAMP | 가입일 |
| `is_deleted` | koin_users.is_deleted | INT64 | 현재 탈퇴 상태 |
| `is_mysql_mapped` | koin_users.id IS NOT NULL | BOOL | MySQL 매핑 여부 |

원천 컬럼의 의미와 생성·결합 로직은 Silver 담당 범위다. 이번 확인은 실제 출력 컬럼과 값 적재 확인이며 원천 Join의 정확성을 증명한 것은 아니다. Gold는 koin_users를 직접 참조하거나 Silver 내부 Join을 재현하지 않는다.

현재 Stage User 검증에는 Typed Placeholder를 사용하지 않는다. 과거 Placeholder SQL은 이력으로만 보존한다. 최초 관측일을 실제 가입일로 대체하지 않는다.

```sql
DATE(signup_completed_at, 'Asia/Seoul')
```

가입일이 실제 최초 가입 완료 시각인지, 마이그레이션·레코드 재생성 시각인지, 재가입 의미가 무엇인지 추가 확인한다. 확정 리텐션 KPI는 가입 기준이 아닌 최초 방문 기준 D1~D7이다.

##### 3.5 Stage 실행 및 운영 배포 조건

Stage Gold 실행은 필수 컬럼 존재뿐 아니라 입력 고유성·Event/User 관계·분류·완전 가용 구간을 검증한 뒤 진행한다. 현재는 Stage User 컬럼 확인이 완료됐으나 목표 Event V2가 제공되지 않아 정식 KPI 검증 입력이 완성되지 않았다.

로컬에 존재하는 임시 분류 Intermediate는 현재 코드 상태로 기록하되, Silver 분류 결손을 우회하는 승인된 운영 입력으로 간주하지 않는다. Silver 수정과 새 분류 로직 작성은 이번 범위에 포함하지 않는다.

운영 배포는 같은 입력 계약을 Production에서도 충족한 뒤 진행한다. Stage Source 환경변수와 dbt target을 명시하고 컴파일된 입력 프로젝트가 Production 기본값으로 해석되지 않는지 확인한다.

##### 3.6 As-Is Stage와 To-Be 계약

| 대상 | As-Is Stage | To-Be |
| --- | --- | --- |
| User | 네 실제 컬럼·기본 값 적재 확인 | 의미·매핑·관계·실제 KPI 검증 통과 |
| Event | legacy에 분류 없음, V2 없음 | 필수 분류·세션·순서 입력 제공 및 검증 |
| Gold | 로컬 38컬럼 구현 | record_type 기반 단일 공개 테이블 구현·검증 |
| BI | 전체 10개 구성의 실행 검증 미완료 | 차트별 타입·기간·평가 필터와 수치 검증 |
| Production | silver__users 및 silver_events_v2 없음 | Stage 검증 후 동일 계약 승격 |

목표 입력은 환경별 dbt ref로 참조한다.

```sql
{{ ref('silver_events_v2') }}
{{ ref('silver__users') }}
```

현재 Stage에 위 Event 모델이 존재한다는 뜻은 아니다. Production 승격을 기다리며 Stage User 확인까지 미완료로 되돌리지 않고, 완료한 항목과 남은 항목을 각각 관리한다.

---

#### 4. 계층별 역할

##### 4.1 Bronze

원천 이벤트를 가능한 한 그대로 적재한다.

- 원천 데이터 보존
- 적재 시각과 원천 식별 메타데이터 추가
- 분석 및 BI에서 직접 조회하지 않음

##### 4.2 Silver Event

중복이 제거된 논리 Event 한 행을 제공한다.

- Grain: 논리 Event 한 행
- PK: event_id
- Event 날짜 및 시각 표준화
- Session 식별 정보 제공
- 플랫폼 및 디바이스 표준화
- 서비스·Entry·Core·퍼널 단계 분류 제공

Gold는 Silver Event를 다시 Dedup하거나 Event 분류를 재계산하지 않는다.

##### 4.3 Silver User

user_pseudo_id당 한 행의 최종 사용자 정보를 제공한다.

- 최종 user_id
- gender, major, entry_year
- first_seen_at
- user_type, signup_completed_at
- is_deleted, is_mysql_mapped

Gold는 ID 후보를 다시 조합하지 않고 Silver 최종 ID와 속성을 사용한다.

##### 4.4 Gold Mart

mart_kpi_user_daily는 Silver Event와 Silver User를 직접 참조하는 단일 dbt 모델이다. 별도 Intermediate 모델 또는 다른 Gold 테이블을 참조하지 않는다.

하나의 SQL 내부 CTE에서 다음을 계산한다.

- 일별 사용자·서비스 활동과 대표 디바이스
- 서비스별 최초 관측일과 신규·기존 구분
- 전체 최초 방문 및 서비스 활동일 코호트
- 일간·범위·주간 재방문과 주간 미복귀
- 동일 세션 내 순차 퍼널

계산 결과는 record_type별 행으로 UNION ALL하여 하나의 물리 테이블에 저장한다. “행 종류 3개”는 “Gold 테이블 3개”를 뜻하지 않는다.

---

#### 5. Gold Mart 테이블 계약

| 항목 | 내용 |
| --- | --- |
| dbt 모델명 | mart_kpi_user_daily |
| 논리 계층 | Gold |
| BI 연결 대상 | gold.mart_kpi_user_daily |
| 입력 | 검증된 Silver Event, silver__users |
| 전체 Grain | record_type별로 정의된 논리 사실 한 행 |
| Unique key | record_type + record_key |
| Partition 후보 | record_dt |
| Cluster 후보 | record_type, service_name, user_pseudo_id |
| 1차 Materialization | Full Refresh Table |
| Gold 물리 테이블 수 | 1개 |
| 별도 Intermediate 모델 | 없음 — 내부 CTE로 계산 |

##### 사용자 결합 기준

```text
Event.user_pseudo_id = User.user_pseudo_id
```

- Silver Event는 event_id당 한 행이다.
- Silver User는 user_pseudo_id당 한 행이다.
- user_pseudo_id가 NULL인 Event는 사용자 Mart에서 제외하고 비율을 모니터링한다.
- Gold 대상 Event의 사용자는 Silver User에 존재해야 한다.
- Gold 대상 User의 first_seen_at은 NULL이 아니어야 한다.

입력 고유성·관계가 실패하면 Gold에서 Dedup 또는 대표 User 선정을 수행하지 않는다.

##### USER×DAY Spine

일별 활동 분기에는 Event 날짜, 완전 가용 구간의 최초 관측일 및 가입일을 합쳐 사용자×날짜 한 행을 만든다. 활동 없는 행은 활동값을 0으로 둔다.

리텐션 분기는 코호트 사용자×평가구간을 따로 생성하고 활동을 LEFT JOIN한다. 돌아오지 않은 사용자가 사라지지 않도록 활동이 있는 사용자만으로 평가행을 만들지 않는다. 최초 방문 D0~D365 spine만으로 기존 사용자의 임의 서비스 활동일 코호트를 대체하지 않는다.

---

#### 6. 사용자 및 코호트 기준

##### 6.1 사용자 기준

모든 기본 사용자 집계는 user_pseudo_id 기준이다. user_id는 보조 식별자이며 계정 통합용 Gold PK로 사용하지 않는다. 기기 변경·재설치·식별자 초기화에 따라 실제 사람 수와 차이가 날 수 있다.

##### 6.2 최초 방문일과 코호트 기준일

```sql
DATE(first_seen_at) AS first_seen_dt,
DATE(signup_completed_at, 'Asia/Seoul') AS first_signup_dt
```

first_seen_at은 프로젝트 표준 시각으로 정규화된 DATETIME 계약을 사용한다. 가입일을 최초 관측일로 대체하지 않는다.

| cohort_type | anchor_dt | 대상 |
| --- | --- | --- |
| first_seen | 코인 전체 최초 관측일 | 회원·비회원 전체 최초 방문 사용자 |
| service_active_day | 해당 서비스 활동일 | 그날 활동한 신규·기존 사용자 |
| weekly_active | 기준 주 월요일 | 해당 주에 활동한 사용자 |

서비스별 최초 관측일은 제공된 전체 이력에서 계산한다. 조회 기간 내부의 MIN 날짜를 서비스 최초 이용일로 사용하지 않는다. 신규·기존 구분이 불확실하면 unknown으로 분리한다.

서비스 코호트에서 동일 사용자는 여러 날짜의 코호트에 포함될 수 있다. 여러 날짜를 합친 사용자-코호트 참여 수를 고유 사용자 수로 해석하지 않는다.

##### 6.3 범위·일간·주간 리텐션과 미복귀

| evaluation_type | 관측 구간 | 의미 |
| --- | --- | --- |
| range_d1_d7 | 최초 방문 D1~D7 | 구간 안 한 번 이상 Entry 복귀 |
| exact_day | anchor+N 당일 | 해당 날짜 같은 서비스 복귀 |
| relative_week | D1~D7, D8~D14, … | 상대 주간 구간 내 한 번 이상 복귀 |
| next_calendar_week | 기준 주 월요일+7~13일 | 다음 월~일의 복귀 여부 |

KPI 범위 리텐션은 first_seen + __all__ + range_d1_d7 조합이다. D0를 제외한다. 동일 사용자가 여러 날 복귀해도 구간 복귀자는 1명이다.

일간 코호트는 service_active_day + exact_day 조합이며 D0는 기준 활동 사용자라 평가 가능한 경우 100%다. 주간 커브는 같은 코호트의 relative_week 평가다. 기본 커브는 고정 anchor를 사용한다. 선택 기간의 여러 anchor를 고유 사용자로 합치는 커브는 사용자당 anchor 선택 규칙을 추가 확정해야 한다.

앱 주간 미복귀는 기준 주 Any Event 사용자 중 다음 주 Any Event가 없는 비율이다. “4개월 미방문” 문구는 사용하지 않는다. 서비스별 미복귀는 같은 서비스 다음 주 미복귀를 제안 기준으로 두되 확정 전 검증 대기로 관리한다.

```text
평가 가능 + 구간 내 복귀: is_returned = 1
평가 가능 + 구간 내 미복귀: is_returned = 0
구간 전체 관측 미완료 또는 불완전: is_returned = NULL
```

is_returned=1은 지정 구간의 활동 여부이며 매일 사용·영구 정착·UI/UX 개선 효과를 의미하지 않는다. 30일 이후 복귀도 설계된 평가 구간에 포함되면 측정할 수 있고, 구간 밖이면 이 지표의 평가 대상이 아닐 뿐 의미 없는 사용자로 판단하지 않는다.

두 완전성 변수는 필수다.

```sql
DATE('{{ var("event_complete_start_dt") }}') AS event_complete_start_dt,
DATE('{{ var("event_complete_dt") }}') AS event_complete_dt
```

MIN/MAX 이벤트 날짜로 대체하지 않는다. 구간 내부 누락이 없는지, anchor의 모집단을 정의할 데이터도 완전한지 확인한다. 이미 복귀했더라도 구간이 끝나지 않았으면 분모·분자 양쪽에서 제외한다.

---

#### 7. Gold 출력 컬럼 정의

NULL 규칙은 행 종류별로 적용한다. 모든 행에 38컬럼의 기존 NOT NULL 조건을 적용하지 않는다.

##### 7.1 기준일 및 사용자 속성

| 컬럼 | 타입 | 적용/정의 |
| --- | --- | --- |
| record_type, record_key, contract_version | STRING | 모든 행 필수; 종류·고유 키·계약버전 |
| record_dt | DATE | 모든 행 필수; daily는 event_dt, 나머지는 anchor_dt |
| user_pseudo_id | STRING | 모든 행 필수 |
| data_as_of_at | TIMESTAMP | 모든 행 필수; 빌드/데이터 기준시각 |
| event_complete_start_dt, event_complete_dt | DATE | 모든 행 필수; 완전성 계약 |
| event_dt | DATE | daily 행의 날짜; 다른 종류에서는 NULL |
| user_id, gender, major, user_type | STRING | Silver 현재 속성; 허용된 필터용으로 복사 가능 |
| entry_year | INT64 | SAFE_CAST로 출력 타입 통일 |
| is_deleted | BOOL | Silver 0/1을 출력 타입만 변환; 미확인 NULL |
| is_mysql_mapped | BOOL | Silver 최종 값; 필수 입력 NULL을 임의 FALSE로 보정하지 않음 |

사용자 속성은 현재 스냅샷이며 과거 당시 상태를 보장하지 않는다.

```sql
CASE
  WHEN LOWER(CAST(is_deleted AS STRING)) IN ('true', '1') THEN TRUE
  WHEN LOWER(CAST(is_deleted AS STRING)) IN ('false', '0') THEN FALSE
  ELSE NULL
END AS is_deleted
```

##### 7.2 플랫폼 및 디바이스

platform_dominant, device_category_dominant, device_os_dominant는 STRING이며 daily 행에서 기존 선정 기준을 유지한다.

1. 해당 값의 Event 수 내림차순
2. 가장 최근 event_at 내림차순
3. 값 오름차순
4. 유효값이 없으면 unknown

리텐션 행에서는 평가일의 unknown 값으로 미복귀자를 걸러내지 않는다. anchor 플랫폼 필터가 필요하면 별도 anchor 속성 계약을 추가해야 하며 현재 출력의 일간 대표값을 과거 anchor 속성으로 해석하지 않는다.

##### 7.3 사용자 활동 지표

| 컬럼 | 타입 | daily 행 정의 |
| --- | --- | --- |
| event_cnt_day | INT64 | COUNT(*) |
| entry_event_cnt_day | INT64 | Entry Event 수 |
| core_action_cnt_day | INT64 | Core Event 수 |
| session_cnt_day | INT64 | 기존 일별 세션 수 |
| engagement_msec_day | INT64 | engagement_time_msec 합계 |
| is_multi_session_user | INT64 | 세션 2개 이상이면 1 |

```sql
COUNT(*) AS event_cnt_day,
COUNTIF(COALESCE(is_entry_event, FALSE)) AS entry_event_cnt_day,
COUNTIF(COALESCE(is_core_action, FALSE)) AS core_action_cnt_day,
COUNT(DISTINCT COALESCE(custom_session_id, ga_session_id)) AS session_cnt_day,
SUM(COALESCE(engagement_time_msec, 0)) AS engagement_msec_day
```

위 세션 집계는 기존 daily 계약이다. 퍼널의 세션 식별은 검증된 ga_session_id 기반 키로 별도 판정하며 혼용하지 않는다. 활동값은 다른 record_type 행에서는 NULL이다.

##### 7.4 신규 사용자·전일 활동 및 리텐션

first_seen_dt, first_signup_dt는 DATE이며 is_new_user, is_new_signup, had_entry_prev_day는 daily 행의 0/1 플래그다. had_entry_prev_day는 달력상 전일 Self Join으로 계산하고 LAG로 대체하지 않는다.

| 리텐션 컬럼 | 타입 | 정의 |
| --- | --- | --- |
| cohort_type, service_name | STRING | 코호트 종류 및 범위; __all__과 실제 main 구분 |
| anchor_dt | DATE | 코호트 기준일 |
| evaluation_type | STRING | exact_day / range_d1_d7 / relative_week / next_calendar_week |
| window_start_day, window_end_day | INT64 | anchor 대비 구간 시작·종료; 양끝 포함 |
| evaluation_start_dt, evaluation_end_dt | DATE | 실제 관측 구간 |
| segment_at_anchor | STRING | new / existing / unknown, anchor 당시 고정 |
| cohort_activity_basis, return_activity_basis | STRING | any_event / entry |
| is_evaluable | BOOL | 전체 구간 및 모집단 평가 가능 여부 |
| is_returned | INT64 | 평가 가능 0/1, 미평가 NULL |
| eligible_user_flg | INT64 | 평가 가능 1, 그 외 0 |
| returned_user_flg | INT64 | 평가 가능하고 복귀 1, 그 외 0 |
| not_returned_user_flg | INT64 | 평가 가능하고 미복귀 1, 그 외 0 |

```text
returned_user_flg + not_returned_user_flg = eligible_user_flg
```

가입 기준 고정 D1/D7/D14/D30 네 컬럼을 범위 지표로 재해석하지 않는다. 차기 계약에서는 위 통합 평가 구조를 사용한다.

##### 7.5 서비스 이용 플래그

기존 used_shop_flg, used_bus_flg, used_board_flg, used_facility_flg, used_timetable_flg, used_grad_calc_flg는 Entry, used_cafeteria_flg와 used_account_flg는 Any Event라는 의미를 daily 행에서 유지한다.

서비스 활동 기준을 명확히 분리하기 위해 다음 필드 패턴을 추가한다.

| 필드 패턴 | 타입 | 정의 |
| --- | --- | --- |
| service_<s>_any_event_flg | INT64 | 해당 서비스 Any Event 존재 |
| service_<s>_entry_flg | INT64 | 해당 서비스 Entry 존재 |
| first_<s>_seen_dt | DATE | 해당 서비스의 거버넌스상 활동 기준 최초 관측일 |
| first_<s>_seen_is_known | BOOL | 그 날짜를 신규/기존 판정에 사용할 수 있는지 |

s는 shop, bus, cafeteria, timetable, board, grad_calc, facility, main이다. 서비스별 최초일과 복귀의 활동 기준은 거버넌스 확정 후 동일하게 적용한다. 이력이 불충분하면 신규/기존 미확인으로 분류한다. 기간 사용자 분해는 기간 내 최초일=신규, 기간 전 최초일=기존으로 배타적으로 집계한다.

board는 공지사항이며 팀원모집으로 바꾸지 않는다. main은 실제 메인 화면, __all__은 서비스 합계가 아닌 코인 전체 활동 범위다. club·별도 동아리 앱·미분류 real_estate는 추가하지 않는다.

##### 7.6 활성 사용자 플래그

is_active_entry, is_active_any_event, has_core_action은 daily 행의 0/1 플래그이며 나머지 행에서는 NULL이다. 리텐션 평가행을 활성 사용자로 세지 않는다.

##### 7.7 퍼널 단계

| 컬럼 | 타입 | 정의 |
| --- | --- | --- |
| funnel_version, funnel_name | STRING | 버전과 퍼널 구분 |
| session_key | STRING | 충돌 검증된 사용자 세션 키 |
| anchor_dt | DATE | 첫 단계 진입일; retention과 필드 공유 |
| first_step_at | DATETIME | 첫 단계 진입 시각 |
| step_no | INT64 | 버전별 단계번호 |
| step_name | STRING | 단계 의미 |
| is_session_complete | BOOL | 세션 수집·관측 완료 |
| is_step_reached | BOOL | 1~현재 단계를 같은 세션에서 순차 충족 |
| is_next_step_reached | BOOL | 다음 단계까지 순차 충족; 마지막 단계 NULL |
| is_final_step_reached | BOOL | 마지막 단계까지 순차 충족 |

첫 단계에 진입한 세션마다 정의된 모든 단계 행을 만들고 미도달은 FALSE로 보존한다. 타 세션의 단계를 연결하지 않으며 공식 집계는 완료 세션만 사용한다. 전체 기간의 사용자 DISTINCT를 위해 최종 Gold에 사용자 키를 유지한다.

---

#### 8. Gold 최종 컬럼 목록

아래는 차기 단일 테이블 설계의 명시적 컬럼 목록이다. 총 99개이며 현재 로컬 SQL의 38개 컬럼과 다르다. 서비스 거버넌스·세션키 검증에 추가 입력이나 출력이 필요하면 계약버전과 컬럼 목록을 함께 갱신한다. SQL 구현 완료를 의미하지 않는다.

```text
record_type
record_key
record_dt
contract_version
data_as_of_at
event_complete_start_dt
event_complete_dt
user_pseudo_id
event_dt
user_id
gender
major
entry_year
user_type
is_deleted
is_mysql_mapped
platform_dominant
device_category_dominant
device_os_dominant
event_cnt_day
entry_event_cnt_day
core_action_cnt_day
session_cnt_day
engagement_msec_day
is_multi_session_user
first_seen_dt
first_signup_dt
is_new_user
is_new_signup
had_entry_prev_day
used_shop_flg
used_cafeteria_flg
used_bus_flg
used_board_flg
used_facility_flg
used_timetable_flg
used_grad_calc_flg
used_account_flg
is_active_entry
is_active_any_event
has_core_action
service_shop_any_event_flg
service_shop_entry_flg
first_shop_seen_dt
first_shop_seen_is_known
service_bus_any_event_flg
service_bus_entry_flg
first_bus_seen_dt
first_bus_seen_is_known
service_cafeteria_any_event_flg
service_cafeteria_entry_flg
first_cafeteria_seen_dt
first_cafeteria_seen_is_known
service_timetable_any_event_flg
service_timetable_entry_flg
first_timetable_seen_dt
first_timetable_seen_is_known
service_board_any_event_flg
service_board_entry_flg
first_board_seen_dt
first_board_seen_is_known
service_grad_calc_any_event_flg
service_grad_calc_entry_flg
first_grad_calc_seen_dt
first_grad_calc_seen_is_known
service_facility_any_event_flg
service_facility_entry_flg
first_facility_seen_dt
first_facility_seen_is_known
service_main_any_event_flg
service_main_entry_flg
first_main_seen_dt
first_main_seen_is_known
cohort_type
service_name
anchor_dt
evaluation_type
window_start_day
window_end_day
evaluation_start_dt
evaluation_end_dt
segment_at_anchor
cohort_activity_basis
return_activity_basis
is_evaluable
is_returned
eligible_user_flg
returned_user_flg
not_returned_user_flg
funnel_version
funnel_name
session_key
first_step_at
step_no
step_name
is_session_complete
is_step_reached
is_next_step_reached
is_final_step_reached
```

is_logged_in, used_real_estate_flg, used_club_flg는 포함하지 않는다. 기존 가입 고정 리텐션 컬럼과 현재 로컬 DN용 days_since_first_seen/is_first_seen_retained/days_since_signup/is_signup_retained 네 컬럼을 이 버전에 혼합하지 않는다. 계약 전환 시 기존 소비자를 이관하고 과거 검증 결과를 새 계약의 검증 완료로 사용하지 않는다.

---

#### 9. Gold Mart 내부 CTE 구성

다음은 계산 순서를 설명하는 구조 예시이며 그대로 실행하는 완성 SQL은 아니다.

```sql
WITH event_base AS (
    -- ref('silver_events_v2'): 제공·검증된 Silver Event
),
user_base AS (
    -- ref('silver__users'): 실제 네 컬럼과 최종 ID·속성
),
parameters AS (
    -- 완전 가용 구간·계약버전·빌드 기준시각
),
user_day_activity AS (
    -- 사용자×날짜 활동 집계
),
service_user_day AS (
    -- 사용자×서비스×날짜 Any Event/Entry
),
service_first_seen AS (
    -- 전체 제공 이력에서 서비스별 최초 활동일
),
dominant_device AS (
    -- 일별 대표값
),
user_day_spine AS (
    -- 이벤트 날짜와 완전 가용 구간의 최초관측·가입일
),
previous_day_entry AS (
    -- 정확한 전일 Self Join
),
cohort_members AS (
    -- 전체 최초방문 / 서비스 활동일 / 기준 주 활동 집합
),
evaluation_windows AS (
    -- 일간·범위·상대주간·달력다음주 평가구간
),
retention_evaluations AS (
    -- 미복귀 분모 보존, 구간 OR, 완전성, 0/1/NULL
),
funnel_session_paths AS (
    -- 동일 세션의 순차 경로·완료 여부
),
funnel_steps AS (
    -- 모든 정의 단계의 도달 사실
),
daily_rows AS (
    -- 공통 최종 컬럼·타입으로 명시적 투영
),
retention_rows AS (
    -- 같은 최종 컬럼·타입으로 투영, 무관한 활동값은 NULL
),
funnel_rows AS (
    -- 같은 최종 컬럼·타입으로 투영
)
SELECT * FROM daily_rows
UNION ALL
SELECT * FROM retention_rows
UNION ALL
SELECT * FROM funnel_rows
```

마지막 SELECT *는 세 분기의 명시적 투영이 동일한 컬럼 순서·타입임을 검증한 전제다. Silver 원본 SELECT *를 그대로 UNION하지 않는다. 모든 CTE는 하나의 mart_kpi_user_daily.sql 내부에 있으며 ref는 두 Silver 모델만 사용한다. deduplicated_events, user_canonical, 별도 Intermediate 모델을 추가하지 않는다.

---

#### 10. Superset 대시보드 연결 및 계산 원칙

Gold에서 사용자별 기간 판정을 끝내고 Superset은 조건부 DISTINCT·합계·비율로 집계한다. 타입/평가 필터를 차트에 고정하며 사용자의 공통 필터가 이를 제거하지 못하도록 검증한다.

| 구성요소 | 필수 조건 | 집계 |
| --- | --- | --- |
| MAU | daily_activity, 기준 월 | Any Event 사용자 DISTINCT |
| 신규 유저 수 | daily_activity, 기준 월 | SUM(is_new_user) |
| 범위 리텐션 | retention_evaluation / first_seen / __all__ / range_d1_d7 | SUM(returned)/SUM(eligible) |
| 앱 주간 미복귀 | retention_evaluation / weekly_active / __all__ / next_calendar_week | SUM(not_returned)/SUM(eligible) |
| 퍼널 | funnel_step / 퍼널·버전 / 완료 세션 | 단계별 순차 도달 사용자 DISTINCT |
| 코호트 리텐션 | retention_evaluation / service_active_day / exact_day | 서비스·anchor·경과일별 복귀 비율 |
| 리텐션 커브 | retention_evaluation / service_active_day / relative_week | 고정 anchor의 경과 주차별 복귀 비율 |
| 서비스별 이용자 수 | daily_activity / 기간 | 선택 서비스 활동 사용자 DISTINCT 및 최초일 신규/기존 분해 |
| 서비스별 DAU | daily_activity / 날짜 | 일별 서비스 이용자와 동일 요일 WoW |
| 서비스별 이탈률 | retention_evaluation / weekly_active / 서비스 / next_calendar_week | 같은 서비스 다음 주 미복귀; 정의 확정 후 제공 |

```sql
-- MAU: record_type='daily_activity' + 기준 월
COUNT(DISTINCT CASE WHEN is_active_any_event = 1 THEN user_pseudo_id END)

-- 리텐션: 표의 해당 cohort/service/evaluation 조건 필수
100 * SAFE_DIVIDE(SUM(returned_user_flg), SUM(eligible_user_flg))

-- 주간 미복귀: 같은 주간 조건과 하나의 anchor 주 필수
100 * SAFE_DIVIDE(SUM(not_returned_user_flg), SUM(eligible_user_flg))
```

퍼널 단계 k의 사용자 집합 U_k는 동일 세션에서 1~k를 순차 충족한 사용자다. 직전 단계 대비 전환율=U_k/U_(k-1), 다음 단계 이탈률=1-U_(k+1)/U_k, 전체 전환율=U_last/U_1이다. 세션 판정 후 사용자 DISTINCT를 적용한다. 첫 단계 100%, 마지막 다음 단계 이탈률 N/A다. 차트의 인접 단계 비율 계산도 실제 결과로 검증한다.

MAU·신규는 월 활동일, Range는 최초 방문 월, 미복귀는 완료된 기준 주·다음 주, 퍼널은 첫 단계 진입일, 코호트는 anchor 날짜에 필터를 적용한다. 공통 event_dt 필터를 모든 타입에 적용하지 않는다. Range의 다음 달 평가일과 종료일에 시작한 퍼널 세션의 후속 이벤트를 잘라내지 않는다.

기간 서비스 이용자 수는 SUM 일별 플래그가 아닌 DISTINCT다. wide 서비스 컬럼은 Metric별 series로 구성하며 service_name 행 필터가 daily 행에도 있다고 가정하지 않는다. 특정 차트가 정규화 service_name을 요구하면 지원 설정을 검증해야 하며 Virtual Dataset 허용을 자동 전제하지 않는다.

분모 0은 N/A, 리텐션 분모 30명 미만은 비율을 숨기고 분모를 표시한다. YoY는 동등한 전년 관측 구간을 사용하고 데이터가 없으면 N/A다. 여러 anchor의 합계를 고유 사용자 커브로 표시하지 않는다.

---

#### 11. Null 및 기본값 처리

| 유형 | 처리 |
| --- | --- |
| 공통 키·버전·기준일·완전성 메타데이터 | 모든 행 필수 |
| Silver 사용자 속성 | 원천 미확인 NULL; 스냅샷 의미 유지 |
| daily 행의 활동 | 활동 없으면 0 |
| daily 행의 대표 디바이스 | 유효값 없으면 unknown |
| 다른 종류 행의 활동·서비스 플래그 | NULL; 0으로 일괄 채우지 않음 |
| 서비스 최초일 | 이력/판정 불충분 NULL 또는 known=FALSE, 신규·기존 미확인 |
| 리텐션 평가 가능·복귀 | 가능 0/1, 미평가 is_returned=NULL |
| 리텐션 집계 플래그 | 미평가이면 모두 0 |
| 퍼널 미도달 단계 | FALSE, 완료 세션만 공식 집계 |
| 마지막 단계 next 플래그 | NULL |
| 행 종류와 무관한 컬럼 | 타입 지정 NULL |

user_id 존재를 로그인·MySQL 매핑으로, first_seen_at을 가입으로, 서비스별 코호트 차이를 배너 노출의 인과 효과로 해석하지 않는다.

---

#### 12. dbt 테스트

##### 12.1 Silver Event 입력 차단 테스트

- event_id not_null/unique, event_dt not_null
- Gold 적격 Event만 user_pseudo_id not_null 관계 검사; 전체 NULL 비율은 모니터링
- 필수 서비스·Entry·Core·퍼널 컬럼 존재와 허용값
- 완전성 변수의 날짜 형식·순서 및 실제 구간 수집 완전성
- 공식 퍼널의 세션키 충돌·결측·동률 처리·관측완료 검증

##### 12.2 Silver User 입력 차단 테스트

- user_pseudo_id not_null/unique
- Gold 대상 first_seen_at not_null
- 네 실제 컬럼 존재, is_mysql_mapped not_null
- Gold 적격 Event/User 관계 누락 0
- 제공되는 경우 first_seen_at <= last_seen_at

##### 12.3 Silver 입력 warn 테스트

- unmapped·Entry/Core NULL 비율
- 현재 속성·대표 ID 관계, 복수 pseudo/계정 연결
- 미래 최초관측/가입일, 가입 원천 freshness
- is_deleted 허용값 및 entry_year 변환 실패
- anonymous 매핑 의심

품질 추적 전용 컬럼은 입력에 실제 존재할 때만 사용한다. Silver SQL을 수정하지 않고 품질 영향과 입력 의존성을 기록한다.

##### 12.4 Gold Mart 차단 테스트

- 전체 (record_type, record_key) 유일성 및 종류별 grain 고유성
- 이 계약의 99개 컬럼·타입·조건부 Null 규칙
- daily 분기와 Silver의 양방향 USER×DAY 보존 및 집계 일치
- 신규 D0행 유일성, 정확한 전일 활동, 무활동 0
- 미복귀 평가행 보존, returned+not_returned=eligible
- 미성숙 사용자의 분모·분자 제외, 월·주 경계
- 일간/범위/주간 평가 종류 비혼합
- 서비스 신규/기존 배타성 및 미확인 처리
- 퍼널 순서 역전·반복·단계 생략·타 세션 결합·자정 통과·미완료 세션
- U_last ⊆ ... ⊆ U_1 및 기간 사용자 DISTINCT
- 각 Superset 차트의 필수 타입·시간·평가 필터

기존 assert_mart_kpi_user_daily_column_contract.sql의 38개 고정 테스트는 구현 전환 시 새 목록과 함께 수정한다. 과거 테스트 통과를 새 구조의 통과로 간주하지 않는다.

---

#### 13. 구현 및 배포 단계

##### 13.1 Stage 구현

#### 13.1.1 현재 Stage 확인

- [완료] 2026-09-09 User 네 컬럼·타입·기본 적재값 확인
- [완료] User 4,707행·키 고유성·first_seen_at NULL 0 확인
- [완료] Event 기본/임시 테이블 건수·기간과 필수 분류 존재 여부 확인
- [대기] Event V2 입력 제공, Event/User 관계, 분류·완전성 검증
- [대기] 가입일·매핑 의미 및 실제 KPI 검증
- 2026-08-06 Placeholder 검증은 당시 이력으로 보존

#### 13.1.2 단일 Gold 구현 및 Stage 실제 검증

- 서비스 활동 기준·서비스 신규 정의·서비스 미복귀·주간 커브 중복 기준 확정
- 모델 내부 CTE만으로 활동·평가·퍼널 계산 작성
- 두 Silver ref 외 다른 dbt 모델 의존 없음 검증
- 명시적 99컬럼 출력 및 record_type별 조건부 계약 구현
- 전체 Stage 테스트와 KPI·차트 검증
- 실제 코호트 행수·스캔·Full Refresh 시간 측정
- 기존 38컬럼 소비자 이관 계획 확인

코드 작성·compile 통과·데이터 실행·수치 검증은 별도 상태다. 현재 문서 수정은 SQL 구현 또는 테이블 생성 완료를 뜻하지 않는다.

##### 13.2 Production 승격 및 배포

- Silver 담당자가 운영 입력 제공
- 운영 입력의 필수 컬럼·품질·완전성 재검증
- Stage/_temp 참조 없음 확인
- Stage 결과 검증 및 배포 승인 절차 후 운영 생성
- 타입 필터 없는 기존 차트 이관 및 운영 BI 수치 확인

##### 13.3 2차 최적화

- record_dt 파티션과 쿼리 패턴의 적합성 검증
- 이벤트 변경이 영향을 주는 과거 anchor 파티션 재계산
- 미성숙→성숙 평가 상태 전환 반영
- 늦게 도착한 복귀·퍼널 이벤트와 User 현재 속성 변경 영향 검토
- 서비스 코호트 보존 기간·최대 경과일 제한 및 실제 비용 측정
- Full Refresh와 증분 결과 동등성 검증

최초 방문 D365 비용 추정치를 서비스 활동일 코호트 비용으로 재사용하지 않는다. 원천을 여러 CTE에서 읽는다는 이유만으로 단일 스캔이나 저비용이 보장되지 않는다.

---

#### 14. 최종 운영 원칙

Gold 물리 테이블은 gold.mart_kpi_user_daily 하나다. Silver Event와 Silver User 다음에 직접 생성하고 별도 Intermediate 또는 다른 Gold 테이블을 참조하지 않는다.

활동·코호트·리텐션·퍼널 계산은 하나의 Gold SQL 내부 CTE에서 수행한다. 결과를 record_type으로 구분해 UNION ALL하며 전체 grain은 기존 USER×DAY가 아니다.

Stage User 네 컬럼과 실제 값은 확인됐다. Production User 및 Stage Event V2는 미존재이며, User 값의 의미·관계·KPI와 Event 입력 완전성은 별도 검증한다.

범위 리텐션·일별 코호트·주간 커브는 같은 리텐션 평가 구조를 공유한다. 가입 고정 D1/D7/D14/D30을 전체 KPI 정의로 유지하거나 범위 리텐션으로 재해석하지 않는다.

현재 설계는 총 99개 출력 컬럼을 명시한다. 추가 입력 필요나 남은 서비스·커브 정의 변경은 계약버전과 함께 관리하며 구현 전에 확정한다. 모델명 유지가 기존 38컬럼 소비자와의 호환성을 의미하지 않는다.

Silver 중복 제거·ID·속성·서비스 분류·MERGE는 재계산하지 않는다. 입력 결손과 품질 문제를 Gold에서 우회하지 않는다.

Superset은 차트별 record_type·코호트·평가·날짜 조건을 고정한다. 미관측을 미복귀 0으로 바꾸거나 종류가 다른 사용자 행을 합산하지 않는다.

1차는 Full Refresh로 검증하고 Stage 품질·실제 비용·차트 검증 및 승인 절차 후 Production에 연결한다.

> **아래는 기존 38컬럼 구현 기준 및 2026-08-25 배포 상태 이력이다. 최신 확장 설계와 실측은 5.0절을 우선한다.**

> **문서 상태: Silver 코드 병합 완료, BigQuery 배포 전 Gold 계약**
>
> PR #29는 원격 `main` 병합 커밋 `3886d4f`로 반영됐다. 따라서 `silver_events_v2`와
> `silver__users`의 SQL·YAML은 더 이상 Draft 후보가 아니라 저장소의 현재 코드 계약이다.
> 다만 2026-08-25 읽기 전용 BigQuery 점검에서 Stage·Production `silver_events_v2`,
> Production `silver__users`, Production `gold` 데이터셋은 아직 존재하지 않았다.
> 코드 병합과 dbt 실행·BigQuery 배포·품질 통과를 같은 상태로 취급하지 않는다.
>
> Silver 스키마 계약은 병합 코드로 확정됐지만 행 수, Null·Unique, Event/User relationship,
> 날짜 완전성 및 KPI 정확성은 실제 Stage 실행과 테스트 결과가 있어야 검증 완료로 바뀐다.

**현재 작업 범위는 Gold 계층으로 한정한다.** Silver Event와 Silver User의 내부 SQL, 사용자 ID 선정 로직, 사용자 속성 선정 로직 및 MERGE 방식은 수정하지 않는다. Silver 내부의 알려진 제한은 Gold 입력 계약과 품질 테스트(warn 포함)로 관리한다.

**1차 Gold는 Full Refresh로 구현한다.** 증분 `insert_overwrite`와 영향 파티션 최적화는 2차 작업으로 분리한다(5.14.4절). **Silver User 자체는 기존 incremental MERGE 방식 그대로 유지된다** — Full Refresh는 Gold 자신의 1차 materialization 방식일 뿐, Silver의 파이프라인 방식을 바꾸는 것이 아니다. 그래서 5.5.4절에 "최근 범위 MERGE에서 지연 Event가 제외될 수 있다"는 Silver 고유의 리스크가 여전히 남아 있다.

D365는 사용자가 임의의 N을 선택할 수 있도록 하는 **스키마 지원 상한**이다. 29일 Stage 표본은 2026-08-06 이력이다. 최신 Stage 테이블별 기간은 5.0.2절을 따른다. 현재 표본은 완전 가용 구간이 확정되지 않았으므로 D365 정확성·운영 비용이 검증됐다고 하지 않는다.

**행 수 추정 (2026-08-25 재계산, 이전 "약 930만 행" 추정을 대체한다)**

이전 추정 `25,423 × 366 ≈ 930만 행`은 모든 사용자가 완전한 366일 구간을 갖는다는 단순 곱셈이었다. 실제로는 `first_seen_dt + N < event_complete_start_dt`인 사용자의 Spine 행이 0개이므로 과대 추정이었다. GA4 원천(`kap-chat.analytics_432041405.events_*`, 2024-07-11~2026-08-23, 근사 pseudo 사용자 45,761명) 기준 재계산 결과는 다음과 같다.

| 최대 경과일 | Spine 행 0개인 사용자 | 예상 행 수 | 저장량 근사 |
| --- | ---: | ---: | ---: |
| D90 | 37,080 | 342,316 | 약 112 MB |
| D180 | 30,855 | 727,846 | 약 239 MB |
| **D365** | 21,615 | **약 123만** | **약 403 MB** |

D365 현재 기댓값은 약 123만 행 / 403MB다. 이 수치만으로 Horizon 축소가 필요하다고
단정할 규모는 아니지만 실제 Full Refresh 실행 시간과 Superset 스캔량은 아직 검증되지
않았다. 사용자가 모두 366일 구간을 갖는 장기 상한은 약 1,675만 행이므로,
**현재 기댓값과 장기 상한을 별도로 관리**한다.

위 수치는 `silver__users`가 아직 없어 GA4 원천으로 근사한 값이다. 실제 Gold 모집단은 승격된 `silver__users`가 결정하므로, Production BI 연결 전 실제 모델로 행 수·저장량·Full Refresh 처리 시간·스캔 비용을 재평가하고 승인한다. 허용 기준을 넘으면 최대값을 D180 또는 D90으로 줄이거나 증분 구현을 먼저 완료한다.

**스키마 상한과 운영 곡선 범위를 구분한다**

| 개념 | 값 | 성격 |
| --- | --- | --- |
| 스키마 지원 범위 | `days_since_* ∈ [0, 365]` | 고정 |
| 운영 곡선 지원 범위 | `min(현재 Event 연속일수 − 1, 365)` | 데이터 누적에 따라 자동 확대 |
| 특정 DN 한 점 | 해당 코호트가 완전 가용 구간 안에 있으면 계산 가능 | N과 무관 |

동일 코호트로 D0~DN 곡선 전체를 관측하려면 `first_seen_dt ∈ [event_complete_start_dt, event_complete_dt − N]`이어야 한다. **2026-08-25 실측 기준 `kap-chat.silver.silver_events`는 2026-06-27~2026-08-23 연속 58일(658,997행)이므로 단일 코호트 곡선의 현재 상한은 D57이고, N=365에서는 위 구간이 공집합이다.**

"정확한 DN 한 점을 계산할 수 있다"와 "동일 코호트의 D0~DN 곡선을 지원한다"는 서로 다른 주장이며 계약에서 섞어 쓰지 않는다. 대시보드에는 현재 관측 가능 상한을 함께 표시한다.

| 구분 | 실제 상태(2026-08-25) | 배포 완료 후 To-Be |
| --- | --- | --- |
| Gold 계층 및 Grain | 설계 확정 | 동일 |
| Gold 출력 계약 | 선택형 리텐션을 포함한 38개 컬럼 문서 계약 존재 | 동일 계약으로 구현 |
| 1차 실행 방식 | Gold 미배포 | Gold Full Refresh, Silver Event는 `insert_overwrite`, Silver User는 `merge` 유지 |
| Silver Event | 코드 병합 완료, Stage·Prod `silver_events_v2` 없음 | `ref('silver_events_v2')` 사용 가능 |
| Silver User | 당시 기록. 최신 Stage 컬럼·값 확인은 5.5.3절에서 완료로 갱신; Prod `silver__users` 없음 | Stage의 의미·관계·KPI 검증 후 운영 승격 |
| Gold SQL | 로컬에서 선택형 D0~D365 계약으로 재작성, dbt compile 대기 | Stage 입력·비용 게이트 검증 후 배포 후보 |
| Gold BigQuery | Stage `gold`는 비어 있고 Prod `gold` 데이터셋은 없음 | Stage에서 먼저 `gold.mart_kpi_user_daily` 생성·검증하는 흐름 |
| 실데이터 품질 검증 | 미완료 | 가정하지 않음. 실제 Stage 테스트 필요 |
| BI 연결 | 미진행 | Stage·비용·승인 게이트 통과 후에만 진행 |

이번 병합 후 계약에서 이전 고정 리텐션 문서 대비 바뀐 핵심은 다음과 같다.

- 운영 Event 입력을 `silver_events`가 아니라 `ref('silver_events_v2')`로 고정한다.
- 운영 User 입력은 `ref('silver__users')`이며 가입·탈퇴·MySQL 관련 Typed Placeholder를 제거한다.
- Silver Event의 `user_pseudo_id` Null을 Silver 실패로 보지 않고 Gold 대상에서 제외한 뒤 비율을 warn으로 감시한다.
- 가입 D1/D7/D14/D30 고정 플래그를 제거하고 최초 방문·가입 기준 D0~D365 선택형 리텐션으로 일반화한다.
- Event 일자, 최초 방문 리텐션 일자, 가입 리텐션 일자를 하나의 USER×DAY Spine으로 합친다.
- Superset은 한 개의 Physical Dataset을 직접 조회하며 Silver Join이나 리텐션 SQL을 Virtual Dataset에서 반복하지 않는다.
- PR 적용 여부와 데이터 품질 통과 여부를 분리한다. 모델이 존재해도 Stage 차단 테스트 전에는 Gold 입력 검증 완료가 아니다.

### 5.0.11 사용자 제공 2개 Gold 계약 및 KPI·퍼널 보완안 (2026-09-10)

#### 적용 범위와 우선순위

사용자가 제공한 사용자 Gold 44개 컬럼 + 집계 Gold 20개 컬럼의 두 물리 테이블 계약을 최신 기준으로 삼는다. 기존 38컬럼 구현, 5.0.10의 단일 99컬럼 설계, 6.11~6.13의 과거 물리 구조 설명을 대체한다. 과거 실측·논의는 삭제하지 않는다. 이번 작업은 문서 정의이며 dbt SQL/YAML·Silver·운영 BigQuery·Superset은 변경하지 않는다.

- 두 Gold는 검증된 운영 Silver Event/User를 직접 참조한다. 별도 Intermediate·Gold→Gold 참조는 없다. 공통 판정은 dbt 매크로/내부 CTE로 재사용한다.
- 제공 문안의 `silver_events`는 역할명으로 해석한다. 이전 실측의 레거시 테이블에 필수 분류가 없었으므로 이름만 보고 `ref('silver_events')`로 바꾸지 않는다. 필수 계약을 충족한 실제 운영 모델명(기존 목표 `silver_events_v2`)은 입력 담당 확인 후 고정한다.
- 사용자 기준은 `user_pseudo_id`. 현재 User Snapshot의 gender/major/entry_year/user_type을 두 모델에 동일하게 적용한다. 과거 당시 속성으로 부르지 않는다. NULL 조합도 보존한다.
- 사용자 테이블은 날짜×pseudo이며 Event 날짜 UNION 가입 날짜만 생성한다. 과거 dense D0~D365 spine 계약은 이 안에서 사용하지 않는다.
- 집계 테이블은 metric_type×metric_dt×service_name×period_n×gender×major×entry_year×user_type×cohort_user_segment의 실제 대상 조합만 저장한다. ROLLUP/CUBE 합계 행은 없다.
- 사용자 속성 조합끼리만 인원을 합산할 수 있다. 일자·서비스·경과 구간별 DISTINCT 수를 기간 전체 고유 사용자 수로 더하지 않는다.
- 전체 서비스 코드는 반드시 `__all__`이다. `main`은 실제 메인 화면이며 전체가 아니다. Markdown의 굵은 글씨 `all`과 코드를 혼용하지 않는다.
- first_seen_at이 TIMESTAMP이면 KST 날짜는 `DATE(first_seen_at, 'Asia/Seoul')`다. 이미 KST DATE/DATETIME으로 제공된다면 타입과 시간대 계약에 맞춰 추출한다. 무조건 `DATE(TIMESTAMP)`를 써 UTC 날짜로 바꾸지 않는다.
- build_id/user_snapshot_at/event_complete_start_dt/event_complete_dt는 같은 공개 배치에서 일치해야 한다. 단순히 같은 시각 문자열을 붙이는 것이 아니라 동일하게 고정된 Silver User 입력을 두 모델에서 사용해야 한다. 두 배치가 모두 검증되기 전 BI 공개를 전환하지 않는다.

#### 사용자 44컬럼 기준 목록

다음은 사용자 제공 부모 계약의 순서다. 기존 문서의 38컬럼(D0~D365 경과일 필드)과 다른 버전임을 명시한다.

```text
event_dt, user_pseudo_id, user_id, gender, major, entry_year, user_type,
is_deleted, is_mysql_mapped, platform_dominant, device_category_dominant,
device_os_dominant, event_cnt_day, entry_event_cnt_day, core_action_cnt_day,
session_cnt_day, engagement_msec_day, is_multi_session_user, first_seen_dt,
first_signup_dt, is_new_user, is_new_signup, had_entry_prev_day,
is_signup_retained_d1, is_signup_retained_d7, is_signup_retained_d14,
is_signup_retained_d30, used_shop_flg, used_cafeteria_flg, used_bus_flg,
used_board_flg, used_facility_flg, used_timetable_flg, used_grad_calc_flg,
used_account_flg, is_active_entry, is_active_any_event, has_core_action,
used_main_flg, event_complete_start_dt, event_complete_dt, user_snapshot_at,
build_id, computed_at
```

가입 리텐션 네 필드는 가입일 행에서만 정확한 DN Entry 여부를 저장하며 평가 불가는 NULL이다. 최초 방문 Range KPI와 혼용하지 않는다. 서비스 활동은 shop/bus/board/facility/timetable/grad_calc=Entry, cafeteria/main/account=각 서비스 Any Event, `__all__`=전체 Any Event다. 클럽·부동산은 제외한다. 서비스 전체 최초 이용일을 추가로 만든다는 뜻은 아니며 그래프 4의 신규는 선택 기간의 전체 GA4 최초 관측 사용자다.

#### 집계 20컬럼 기준 목록

```text
metric_row_id, metric_type, metric_dt, service_name, period_n,
window_start_dt, window_end_dt, gender, major, entry_year, user_type,
cohort_user_segment, denominator_users, numerator_users, is_complete,
event_complete_start_dt, event_complete_dt, user_snapshot_at, build_id,
computed_at
```

metric_row_id는 위 자연 키를 고정 순서·타입의 JSON STRUCT로 직렬화한 SHA256이다. NULL을 빈 문자열이나 '전체'로 대체하지 않는다. 분모는 저장행에서 양수, 완료 시 0≤분자≤분모, 미완료 시 분자 NULL이다. 필수 날짜·is_complete의 NOT NULL을 별도 검사한다.

| 기존 metric_type | 기준일·구간 | 유지할 의미 |
| --- | --- | --- |
| retention_daily | 서비스 활동일 c, D0~D56 | c일 코호트의 동일 서비스 당일 복귀 |
| retention_weekly | 서비스 활동일 c, W0~W8 | W0=c, Wn=c+7n−6~c+7n의 동일 서비스 구간 복귀 |
| churn_56d | 스냅샷 T, period_n=56, T−55~T | T까지 관측된 서비스 이용자 중 56일 미이용자 |

각 retention 코호트·서비스·속성·신규/기존 조합은 모든 D0~D56 및 W0~W8 행을 생성한다. 미성숙도 행을 남긴다. 그래프 3의 합산 단위는 사용자×코호트 기준일이며 실제 고유 사용자 수가 아니다. 서비스 이탈은 7개 서비스만, main/전체/account는 제외한다.

#### KPI 보완 제안 — 20컬럼 유지, metric_type 두 값 추가

현재 세 metric_type만으로 KPI 3·4를 지원한다고 표시하지 않는다. 아래 두 값을 **새 설계 제안**으로 추가한다. 6.14의 계산식은 이 값들이 구현·검증된 뒤에만 사용할 수 있다.

| 추가 metric_type | metric_dt | service_name / segment | period_n / 관측 구간 | 분모·분자 |
| --- | --- | --- | --- | --- |
| first_seen_range_entry_d1_d7 | 최초 관측일 c | `__all__` / new | 7 / c+1~c+7 | c일 전체 최초 관측 사용자 / 그중 구간 내 전체 Entry 재방문자 |
| app_weekly_nonreturn | 기준 주 월요일 w | `__all__` / not_applicable | 1 / w+7~w+13 | w~w+6 전체 Any Event 사용자 / 그중 w+7~w+13 Any Event가 없는 사용자 |

- Range 행은 최초 관측 사용자 조합별 1행이다. 기간 내 아무 활동일 코호트로 대체하지 않는다. 한 사용자는 최초 관측일 하나에만 속한다.
- app_weekly_nonreturn은 달력상 연속 두 주이며 기준 주 사용자 전체를 중복 제거한 다음 다음 주 미복귀를 판정한다. 일별 코호트 미복귀 인원을 더해서 주간 고유 수로 만들지 않는다.
- Range 완료는 c 및 c+1~c+7, 주간 미복귀 완료는 w~w+13 전체가 공통 완전 구간 안에 있어야 한다. 내부 수집 공백이 없어야 한다. 미완료 행은 분자 NULL이다.
- **표시 정책은 지표별로 다르다.** 그래프 2·3은 선택 코호트 중 미완료가 있으면 점/셀 전체 NULL을 유지한다. Range KPI는 사용자가 확정한 정의대로 미성숙 코호트를 분자·분모 양쪽에서 제외하고 제외 인원을 공개한다. 따라서 공통 all-complete `rate` Metric을 Range 카드에 그대로 쓰지 않는다.
- `retention_weekly / __all__ / new / W1`은 재방문이 Any Event라 Entry Range와 다르다. 또한 W1 코호트는 일별 고정 코호트다. 범위·활동 기준을 확인하지 않고 기존 행을 재사용하지 않는다.
- 기존 `churn_56d`는 56일 서비스 미이용이다. KPI의 다음 주 앱 미복귀와 같은 지표가 아니다. 기존 도메인·날짜 검증을 두 metric_type에 맞게 확장한다.

#### 퍼널 보완 제안 — 물리 2개 유지 시 사용자 45컬럼으로 확장 필요

**사용자 44컬럼+집계 20컬럼을 엄격히 유지하면서 임의 기간 고유 사용자 순서 퍼널까지 제공하는 것은 이 계약으로 불가능하다.** USER×DAY 활동 카운트에는 세션 내 순서가 없고, 날짜별 단계 인원에는 기간 중복 제거용 사용자 ID가 없다. session_cnt_day의 COALESCE 세션 수를 퍼널 세션 키로 재사용하지 않는다.

물리 2개를 유지할 때의 구체적 대안은 사용자 Gold에 아래 **45번째 중첩 컬럼**을 추가하는 것이다. 이는 승인된 44컬럼에 이미 있다는 뜻이 아니라 검토·구현할 확장안이다. 집계 Gold는 20컬럼을 유지한다. 확장하지 않으면 퍼널은 정의 문서만 제공하고 BI는 구현 대기로 둔다.

```text
funnel_session_facts ARRAY<STRUCT<
  funnel_id STRING,
  funnel_version STRING,
  session_key STRING,
  anchor_dt DATE,
  is_complete BOOL,
  max_step_reached INT64,
  total_steps INT64,
  step_reached_at ARRAY<TIMESTAMP>
>>
```

- 원소는 pseudo×검증된 session_key×funnel_id×funnel_version당 하나다. anchor_dt는 그 세션의 해당 퍼널 첫 단계 최초 진입일(KST)이며 부모 event_dt와 일치하는 행에만 적재한다. 다른 일자의 부모 행에 복제하지 않는다. 퍼널 없는 부모는 빈 배열이다.
- 세션이 자정을 넘어도 후속 이벤트를 읽되 저장은 첫 단계 진입일 한 행이다. 선택 기간은 이 anchor에 적용한다. 반복 첫 단계는 같은 세션의 최초 첫 단계로 고정하며 여러 경로가 있으면 실제 순차 경로 하나의 최대 도달 접두사를 계산한다.
- 동일 세션에서 t1<t2<…<tk인 유효 경로가 존재해야 max_step_reached≥k다. 무관한 이벤트는 허용, 필수 단계 생략은 금지다. 시간 동률을 순서로 인정할 근거가 없으면 해당 전환은 임의 인정하지 않고 제외/미확정 건수를 별도 검증한다.
- step_reached_at은 증거 경로의 1~max_step_reached 시각이다. 길이=max_step_reached이며 엄격히 증가한다. ARRAY 내부 NULL 시각을 사용하지 않는다.
- 유효 세션 키는 pseudo와 함께 식별 가능해야 한다. ga_session_id의 스트림 충돌·결측·완료 기준을 Silver 입력 계약으로 검증한다. discriminator가 없다면 불명확한 키를 합쳐 성공으로 만들지 않는다. Gold가 Silver 식별자를 새로 복원하거나 원천 분류를 수정하지 않는다.
- is_complete는 세션 종료/후속 이벤트 및 지연 수집의 완료 판정이다. 단순히 anchor_dt≤event_complete_dt라는 이유만으로 TRUE로 하지 않는다. 공통 미완료 세션 집합은 모든 단계의 공식 분모·분자에서 제외한다.
- 모든 파싱·순서·성숙 판정은 Gold 내부 CTE에서 끝낸다. BI의 UNNEST는 결과를 펼칠 뿐 이벤트 이력 Join·순서 재판정을 수행하지 않는다. 이 배열 확장은 플랫폼 필터나 사용자별 일간 카운트를 UNNEST 결과에서 SUM해도 된다는 뜻이 아니다.
- 비용 검증에는 사용자당 세션 수, 배열 최대 크기, 일별 재계산 범위, 자정 통과·늦은 완료에 따른 과거 anchor 파티션 갱신을 포함한다. 물리 테이블 수를 맞추기 위해 무제한 배열을 허용하지 않는다.

### 5.0.12 현행 서비스 범위 및 퍼널 확장 채택 — 사용자 대화 결정 (2026-11-06)

이 절은 이번 대화에서 사용자가 확인한 종료·개발 중단 상태와 최종 설계 진행 동의를 기록한다. 충돌 시 5.0.11의 서비스 범위·사용자 컬럼 목록·확장안 승인 대기 표기보다 이 절을 우선한다. 과거 실측과 설계 이력은 보존한다.

- 사용자 확인: 졸업계산기·동아리는 기능 종료, 새 주변상점·미래의 주변상점은 개발 중단이다. 현행 주변상점은 유지한다. 종료일의 실제 날짜와 구버전 이벤트 적용 기간은 미확인이다. 과거 데이터·명세 삭제를 승인한 것은 아니다.
- 사용자 Gold에서 `used_grad_calc_flg`를 제거한다. 기존 44개에서 43개가 되고, 5.0.11의 `funnel_session_facts` 배열 확장을 채택하여 최종 44컬럼으로 설계한다. 기존 44컬럼과 개수는 같지만 필드 구성이 다른 새 계약이다. 동아리는 이미 제외돼 있고 중단된 상점 두 버전은 별도 컬럼이 없으므로 추가 차감하지 않는다.
- 집계 Gold는 20컬럼을 유지하고 `first_seen_range_entry_d1_d7`, `app_weekly_nonreturn` 두 metric_type을 채택한다. 기존 3종을 포함한 총 5종이다. 지표 정의·성숙 정책은 5.0.11 및 6.14를 유지한다.
- 물리 Gold는 2개이며 두 모델 모두 검증된 Silver Event/User를 직접 참조한다. 별도 Intermediate·Gold→Gold 참조는 없다.
- 현행 퍼널은 signup/shop/bus/cafeteria/timetable/board의 6개다. grad_calc를 제외하며 facility를 자동 추가하지 않는다. 6.14의 나머지 6개 경로 및 순서·세션·기간 DISTINCT 불변식을 유지한다.
- 서비스 활동은 shop/bus/board/facility/timetable=Entry, cafeteria/main/account=해당 서비스 Any Event, `__all__`=앱 전체 Any Event다. 서비스 리텐션은 이 대상들을, 서비스 56일 이탈은 shop/bus/cafeteria/board/timetable/facility 6개를 대상으로 한다.
- 최종 설계 방향은 사용자와의 “이거로 골드 테이블 설계 하면 되는거지” 확인에서 합의했다. 세션 키·단계 매핑·동률·종료·지연 수집·배열 크기·Snapshot 고정·공동 공개·실패 복구의 세부 실행 계약과 실제 입력 검증까지 완료한 것은 아니다.
- 사용자 제공 event_label 네이밍 규칙 완료는 입력 의미를 명확히 하지만 실제 수집·Silver 반영·퍼널 순차 경로 검증을 증명하지 않는다. Gold에서 Silver 분류·ID 로직을 재구현하지 않는다.
- 문서 편집 및 대화 정리는 SQL/YAML·BigQuery·Airflow·Superset 배포가 아니다. 이번 대화에서는 운영 실데이터를 재조회하지 않았다. 상세 대화 요약과 후속 작업은 6.16을 참조한다.

### 5.0.13 새 로깅 기준 SQL 초안 및 Stage 구조 생성 상태 (2026-11-06)

5.0.12의 44/20컬럼 계약은 유지한다. 사용자는 이번 대화에서 Stage 작업을 요청한 뒤 **새 로깅은 개발자가 아직 적용하지 않았고 명세만 작성한 상태**라고 확인했다. 이에 따라 새 명세를 입력 계약으로 삼는 SQL 초안과 빈 Stage 테이블 구조까지 작성·생성하고, 실데이터 적재 및 공식 KPI 검증은 후속 단계로 둔다.

- Stage `koin-stage-438512.gold.mart_kpi_user_daily`: 44컬럼, 0행. `event_dt` 파티션, `user_pseudo_id/user_id` 클러스터.
- Stage `koin-stage-438512.gold.mart_service_metrics_daily`: 20컬럼, 0행. `metric_dt` 파티션, `metric_type/service_name/major/entry_year` 클러스터.
- 구조 생성은 성공했으며 로깅 수집·실데이터 계산·Superset UI 검증 완료를 의미하지 않는다. DDL은 `CREATE TABLE IF NOT EXISTS`만 수행했다.
- 기존 38컬럼 사용자 모델을 최신 구성의 초안으로 교체하고 집계 모델을 추가했다. 두 모델의 직접 의존성은 `silver_events_v2`, `silver__users`뿐이다. 졸업계산기 플래그·dense spine 참조를 제거했다. 기존 Intermediate 파일은 이력으로 남기며 새 Gold에서 참조하지 않는다.
- Gold는 새 라벨의 원시 접두어를 Silver의 분석용 서비스 분류로 대신 쓰지 않는다. 예를 들어 `main__main__shop_entry__main_entry__click`의 첫 구간과 상점 진입의 분석 대상은 다를 수 있다. `screen_view`/label 두 번째 구간이 논리 화면이라는 사실만으로 실제 메인 방문 이벤트를 만들지 않는다.
- 순서 판정은 검증된 Silver의 `funnel_stage/service_step_order` 의미를 전제로 한다. 새 SDK 라벨 → Silver 의미 분류의 전체 6경로 매핑은 아직 검증 완료가 아니다. 확인된 새 명세 5건의 대응 검사는 예시이며 전체 매핑표를 대체하지 않는다.
- `gold_build` 실행 계약의 로깅 배포·관측 완전성·가입 원천·단계 매핑·세션 검증은 기본 FALSE다. 실배포일·완전 구간·세션 종료/지연 정책은 임의 기본값으로 확정하지 않는다. 컴파일용 날짜와 인공 사례의 30분 세션 값은 실제 배포·운영 정책이 아니다.
- 개별 `dbt run/build`로 한 테이블만 교체하는 경로는 차단한다. 검증 후 공동 공개할 Stage 전용 SQL 생성 초안은 임시 후보 2개와 단일 DML 트랜잭션을 사용한다. 현재는 이 공개 스크립트를 실행하지 않았다. Superset의 여러 요청·캐시가 같은 배치를 보는지는 별도 통합 검증이 필요하다.
- 새 명세 전환일 이후의 Silver Event를 입력하는 초안이다. 이전 라벨의 이력을 임의 변환하지 않으며, 구·신 로그 통합과 56일 이력 충족 여부는 별도 입력 계약으로 확인한다.
- 구현 파일·검증 근거·남은 조건은 6.18에 기록한다.

### 5.1 목적

Bronze 이후부터 BI 대시보드까지 사용하는 dbt 모델의 계층과 역할을 정의하고, 대시보드가 직접 조회할 Gold Mart의 테이블 계약을 확정한다.

현재 프로젝트에서는 같은 Gold 계층의 모델 간 참조를 허용하지 않는다.

Gold에 `fct_*`, `agg_*`, `mart_*`를 모두 만들더라도 `mart_*`가 다른 Gold 모델을 참조할 수 없으면 Mart 내부에서 동일한 Fact 변환과 집계를 다시 계산해야 한다. 이 경우 `fct_*`와 `agg_*`는 명확한 사용처 없이 유지될 가능성이 있다.

따라서 현재 구현 범위에서는 `fct_*`와 `agg_*`를 별도 Gold 모델로 만들지 않는다.
다만 2026-08-25 멘토 피드백에 따라 코호트·리텐션처럼 Superset에서 윈도우 함수와
동적 Spine 계산을 수행하기 어려운 로직은 **Gold 담당 범위의 Intermediate 모델**에서
미리 계산한다. Intermediate는 BI 공개 Mart가 아니며 Gold→Gold 참조 금지 원칙을
우회하는 모델도 아니다. BI에 공개하는 Gold 물리 테이블은 계속 하나다.

### 5.2 전체 구조

```text
bronze_ga4_events
  ↓
silver_events_v2 / silver__users
  ↓
intermediate.int__user__retention_spine
  ↓
gold.mart_kpi_user_daily
  ↓
BI 대시보드
```

본 프로젝트의 외부 데이터 계약은 Bronze, Silver, Gold의 3계층을 유지한다.
Intermediate는 Silver와 Gold 사이에서 복잡한 Gold 계산을 분리하는 내부 dbt 계층이며,
새로운 원천 정제 계층이나 BI 공개 계층으로 취급하지 않는다.

#### 모델 간 참조 원칙

```text
Intermediate → Silver 참조: 허용
Gold → Intermediate 참조: 허용
Gold → Silver 참조: 필요한 일간 활동 집계에 허용
Gold → Gold 참조: 허용하지 않음
BI → Gold 참조: 허용
BI → Intermediate 참조: 허용하지 않음
운영 Gold → *_temp 참조: 허용하지 않음
```

Bronze와 Silver 사이의 별도 Staging 계층은 이번 작업에 추가하지 않는다. 여러 국가·지사·
주문/클레임처럼 원천별 스키마 차이를 먼저 흡수해야 하는 구조라면 Staging의 가치가 크지만,
현재 핵심 Event 원천은 GA4이고 PR #29의 Silver가 canonicalization·중복 제거·분류를 이미
담당한다. Staging 추가는 코호트 계산 문제를 해결하지 못하고 사용자의 Gold 범위를 넘어선다.

2026-08-06 이력 검증용 입력은 다음과 같다.

- Event Silver 후보: `koin-stage-438512.silver.silver_events_temp`
- User Silver 후보: `koin-stage-438512.silver.silver__users_temp`

`_temp`는 과거 구조 검증 및 출처 제한이 있는 참고 조회용이다. 현재 Stage User 검증 입력은 실제 4개 컬럼이 존재하는 `koin-stage-438512.silver.silver__users`다. Stage Event는 목표 V2가 없어 정식 KPI 검증 입력이 아직 완성되지 않았다. 두 입력 계약 충족 후 목표 Gold 계열 SQL은 환경별 물리 테이블명을 하드코딩하지 않고 `ref('silver_events_v2')`, `ref('silver__users')`,
`ref('int__user__retention_spine')`을 사용한다. Stage 검증도 `_temp` 대신 Stage target의
동일 모델명을 사용한다.

### 5.3 계층별 역할

#### Bronze

원천 이벤트를 가능한 한 그대로 적재한다.

- 원천 데이터 보존
- 적재 시각 추가
- 원천 식별을 위한 최소 메타데이터 추가

Bronze는 분석과 BI에서 직접 조회하지 않는다.

#### Silver Event

중복을 제거한 논리 이벤트 한 행을 나타내는 최종 Event Fact다.

- Grain: 논리 이벤트 한 행
- PK: `event_id`
- 원천 Event 중복 제거
- Event 시간과 날짜 타입 변환
- Session ID 보정
- 플랫폼 및 디바이스 표준화
- Event 문자열 정규화
- 서비스 및 퍼널 단계 분류
- `event_dt` 기준 증분 `insert_overwrite`
- 사용자 Dimension 및 일별 집계 제외

#### Silver User

`user_pseudo_id`를 기준으로 최종 사용자 식별자와 사용자 속성을 제공한다.

- Grain·PK: `user_pseudo_id`
- 최종 `user_id`
- 사용자 ID 원천 및 품질 정보
- 성별, 학과, 입학 연도
- 최초 및 최종 관측 시각
- 사용자 유형, 가입 완료 시각
- 현재 탈퇴 및 MySQL 매핑 상태

최종 `user_id`의 후보 선정과 정규화는 Silver User의 책임이다. Gold에서는 `top_user_id`, `property_user_id`, `param_user_id`를 다시 조합하거나 대표 ID를 재선정하지 않는다.

#### Intermediate — Retention Spine

`int__user__retention_spine`은 Superset에서 직접 계산하기 어려운 코호트 평가 행을 미리
생성하는 Gold-owned 내부 모델이다.

- Grain: `event_dt × user_pseudo_id`당 한 행
- 전체 non-null `user_pseudo_id`의 `first_seen_dt` 기준 D0~D365 Spine 생성
- 가입한 pseudo 사용자의 `first_signup_dt` 기준 D0~D365 Spine 생성
- Event 발생 USER×DAY와 두 Spine을 `UNION DISTINCT`
- `days_since_first_seen`, `days_since_signup` 계산
- `event_complete_start_dt`~`event_complete_dt` 평가 가능 범위 적용
- Entry 활동과 `is_*_retained`는 계산하지 않음
- BI에서 직접 조회하지 않음

1차 검증에서는 `table`로 물리화하고 `event_dt` 파티션, `user_pseudo_id` 클러스터를 적용한다.
이렇게 하면 Intermediate Grain·날짜 범위·경과일 계약을 Gold와 분리해 테스트할 수 있다. 비용 게이트
통과 후 필요하면 증분 `insert_overwrite`로 전환한다. 물리 Intermediate가 하나 생기지만
BI에 공개되는 Gold Mart는 `gold.mart_kpi_user_daily` 하나로 유지된다.

#### Gold Mart

`mart_kpi_user_daily`는 BI가 직접 조회하는 USER×DAY 모델이다.

Silver Event의 일간 활동 집계, Silver User 속성, Intermediate의 코호트·리텐션 Spine을
결합하여 사용자별 일간 활동량, 신규 방문·가입, 사용자가 선택한 D0~D365 리텐션,
서비스 이용 여부와 사용자 속성을 하나의 BI 테이블로 제공한다.

Entry 활동은 Gold의 `user_day_activity.entry_event_cnt_day`에서 한 번만 계산한다.
`is_active_entry`, `is_first_seen_retained`, `is_signup_retained`는 모두 이 동일한 집계값에서
파생한다. Intermediate가 Silver Event를 다시 집계해 리텐션 플래그를 만들지 않는다.

리텐션은 다음 두 기준을 분리해 제공한다.

- 전체 사용자 최초 방문 리텐션: `first_seen_dt` 기준, 로그인·비로그인을 모두 포함한 전체 `user_pseudo_id`
- 가입 사용자 리텐션: `first_signup_dt` 기준, `signup_completed_at`이 있는 `user_pseudo_id`

Gold 테이블은 사용자의 대시보드 선택값에 따라 다시 실행되지 않는다. Gold가 D0~D365의 평가 가능한 USER×DAY 사실을 미리 생성하고, Superset은 `days_since_first_seen` 또는 `days_since_signup`을 필터링한다.

Gold는 다음 작업을 수행하지 않는다.

- Event 중복 제거
- 대표 User 행 재선정
- 사용자 ID 후보 재조합
- 대표 사용자 속성 재선정
- Silver MERGE 또는 지연 Event 처리 보정

### 5.4 현재 Silver Event 컬럼

#### 이벤트 기본 컬럼

| 컬럼명 | 타입 | Gold 사용 목적 |
| --- | --- | --- |
| `event_id` | STRING | Event PK 및 Event 수 계산 |
| `event_dt` | DATE | 일간 집계 및 파티션 |
| `event_at` | DATETIME | Event 순서 및 대표값 선정 |
| `event_ts` | INT64 | Event 발생 시각 보조값 |
| `event_name` | STRING | Event 종류 판별 |
| `user_pseudo_id` | STRING | 사용자 식별 및 User 결합 |
| `ga_session_id` | STRING | GA Session 식별 |
| `custom_session_id` | STRING | 보정 Session 식별 |

#### 플랫폼 및 디바이스 컬럼

| 컬럼명 | 타입 | Gold 사용 목적 |
| --- | --- | --- |
| `platform` | STRING | 대표 플랫폼 계산 |
| `device_category` | STRING | 대표 디바이스 계산 |
| `device_os` | STRING | 대표 OS 계산 |
| `device_os_version` | STRING | OS 버전 분석 |

#### 이벤트 상세 컬럼

| 컬럼명 | 타입 | Gold 사용 목적 |
| --- | --- | --- |
| `event_label` | STRING | Event 상세 분류 |
| `event_category` | STRING | Event 카테고리 |
| `event_value` | STRING | Event 값 |
| `page_title` | STRING | 웹 화면 식별 |
| `screen_class` | STRING | 앱 화면 식별 |
| `page_location` | STRING | 웹 URL 및 분류 보조 |
| `engagement_time_msec` | INT64 | 일간 체류 시간 계산 |

#### 정규화 및 분석 분류 컬럼

| 컬럼명 | 타입 | Gold 사용 목적 |
| --- | --- | --- |
| `event_label_norm` | STRING | 정규화된 Event 상세값 |
| `event_value_norm` | STRING | 정규화된 Event 값 |
| `page_title_norm` | STRING | 정규화된 웹 화면명 |
| `screen_class_norm` | STRING | 정규화된 앱 화면명 |
| `service_name` | STRING | 서비스 플래그 계산 |
| `funnel_stage` | STRING | 향후 퍼널 Mart |
| `step_order` | INT64 | 향후 퍼널 정렬 |
| `is_entry_event` | BOOLEAN | Entry 지표 계산 |
| `is_core_action` | BOOLEAN | Core Action 지표 계산 |
| `stage_scope` | STRING | 향후 퍼널 범위 구분 |

Gold KPI에 필요한 최소 분류 컬럼은 다음과 같다.

```text
service_name
is_entry_event
is_core_action
```

Stage 검증 결과 `is_entry_event`, `is_core_action`은 전체 14,241행 중 각각 9,431행이 Null이며 `service_name = 'unmapped'`와 일치했다.

Gold에서는 다음처럼 처리한다.

```sql
COALESCE(is_entry_event, FALSE)
COALESCE(is_core_action, FALSE)
```

`funnel_stage`, `step_order`, `stage_scope`는 현재 USER×DAY 출력에 포함하지 않는다. 퍼널 BI가 필요하면 별도 Grain의 Mart를 설계한다.

#### 서비스 분류 제약

- 현재 Silver 분류에는 `real_estate` 규칙이 없다.
- 현재 Account Event는 모두 `is_entry_event = FALSE`다(4.8절 실측).
- Cafeteria Event도 13건 전부 `is_entry_event = FALSE`다(Account와 동일 유형, 5.8.5절).
- **Club 최종 제외 확정(2026-08-06)**: 2026-08-06 Stage 실측 표본(14,241건)에는 `service_name = 'club'` Event가 **0건**이었다. 사용자 확인 결과, 동아리(Club) 기능이 **별도 전용 앱으로 분리**되어 현재 이 앱(KOIN 본체)에서는 더 이상 제공되지 않는 기능이라는 것이 확인됐다. 즉 표본이 작아서 우연히 안 잡힌 게 아니라, 이 앱에는 애초에 club 관련 이벤트가 발생할 수 없는 구조다 — `used_real_estate_flg`(Silver 분류 규칙 자체가 없음)와 동일한 유형의 사유로, **`used_club_flg`를 최종 Gold 출력에서 제외한다**(39→38컬럼). Gold에서 Club 분류를 새로 만들지 않으며, 별도 동아리 앱의 데이터를 이 Gold Mart로 끌어오지도 않는다.

따라서 다음과 같이 처리한다.

- `used_real_estate_flg`: Gold 출력에서 제거(Silver 분류 규칙 자체가 없음)
- `used_account_flg`, `used_cafeteria_flg`: 서비스 Event 존재 여부로 계산(Entry 조건 없음)
- `used_club_flg`: Gold 출력에서 제거(동아리 기능이 별도 앱으로 분리됨, 위 확정 사유 참고)

### 5.5 현재 Silver User 컬럼

| 컬럼명 | 타입 | Gold 사용 | 용도 |
| --- | --- | --- | --- |
| `user_pseudo_id` | STRING | 사용 | Event 결합 및 사용자 PK |
| `stream_id` | STRING | 미사용 | GA4 Stream 식별 |
| `user_id` | STRING | 사용 | Silver에서 선정한 최종 ID |
| `user_id_source` | STRING | 품질 검증 | 최종 ID 원천 |
| `top_user_id` | STRING | 품질 검증 | ID 후보 |
| `property_user_id` | STRING | 품질 검증 | top ID 동일성 검증용 |
| `param_user_id` | STRING | 품질 검증 | 과거 Event parameter ID |
| `gender` | STRING | 사용 | 성별 BI 필터 |
| `major` | STRING | 사용 | 학과 BI 필터 |
| `entry_year` | INTEGER | 사용 | 입학 연도 BI 필터 |
| `first_seen_at` | DATETIME | 사용 | 전체 이력 최초 관측 시각 |
| `last_seen_at` | DATETIME | 품질 검증 | 최종 관측 시각 |
| `user_id_support_count` | INTEGER | 품질 검증 | 최종 ID 지지 관측 수 |
| `source_event_count` | INTEGER | 품질 검증 | 상태 계산 근거 Event 수 |
| `property_user_id_set_ts` | INTEGER | 품질 검증 | 속성 ID 설정 시각 |
| `canonical_identity_state_id` | STRING | 미사용 | Stage 내부 검증용, Prod 출력 제거 예정 |

`user_event_id`는 실제 스키마에 없으므로 계약에서 제외한다.

ID 원천 및 품질 컬럼은 BI Gold에 노출하지 않는다. Silver 품질 검증과 사용자 식별 문제 추적에만 사용한다.

#### 5.5.1 사용자 ID 사용 원칙

`silver__users.user_id`는 Silver가 선정한 최종 대표 ID다. Gold는 이를 신뢰하고 그대로 사용한다.

현재 확인된 내용은 다음과 같다.

- `property_user_id`는 `top_user_id`와 동일 원천이다.
- `param_user_id`는 과거 로깅 실수에서 발생했다.
- 확인한 작년 7~10월에는 top/param 충돌이 발견되지 않았다.

특정 기간의 검증 결과를 영구 계약으로 간주하지 않는다. 원천별 ID 불일치는 warn 테스트로 모니터링한다.

#### 5.5.2 사용자 속성 사용 원칙

Gold는 Silver User가 출력한 `gender`, `major`, `entry_year`를 그대로 사용한다. Gold에서 대표 ID 기준으로 속성을 다시 선정하지 않는다.

#### 5.5.3 PR #29 병합 코드가 제공하는 운영 추가 컬럼

| 컬럼 | 원천 | 타입 | Gold 사용 목적 |
| --- | --- | --- | --- |
| `user_type` | `koin_users.user_type` | STRING | 사용자 유형 분석 |
| `signup_completed_at` | `koin_users.created_at` | TIMESTAMP | 가입 코호트 및 선택형 D0~D365 리텐션 |
| `is_deleted` | `koin_users.is_deleted` | BOOLEAN 호환 | 현재 탈퇴 상태 |
| `is_mysql_mapped` | `koin_users.id IS NOT NULL` | BOOLEAN | MySQL 매핑 여부 |

**2026-09-09 재확인: 네 컬럼이 추가되어 있는 위치는 Stage `koin-stage-438512.silver.silver__users`다. Production `kap-chat.silver.silver__users`는 아직 존재하지 않는다.** Stage `_temp`와 Stage 정식 이름의 테이블을 구분한다. Stage에서 테이블 이름에 `_temp`가 없다고 Production 승격 완료인 것은 아니다.

두 프로젝트의 `silver.INFORMATION_SCHEMA.COLUMNS`와 Silver 테이블 목록을 읽기 전용으로 조회했다.

| 위치 | 네 컬럼 존재 여부 | 현재 판정 |
| --- | --- | --- |
| `koin-stage-438512.silver.silver__users` | 4개 모두 존재 | Stage 컬럼 추가 및 아래 실제 값 적재 확인 |
| `koin-stage-438512.silver.silver__users_temp` | 4개 모두 없음 | 과거 Placeholder 구조 검증용 입력 |
| `kap-chat.silver.silver__users` | 테이블 없음 | Production User 승격 미완료 |

Stage `silver__users` 실제 SELECT 집계(전체 4,707행):

| 컬럼 | BigQuery 실제 타입 | non-null 행 수 |
| --- | --- | ---: |
| `user_type` | STRING | 488 |
| `signup_completed_at` | TIMESTAMP | 488 |
| `is_deleted` | INT64 | 488 |
| `is_mysql_mapped` | BOOL | 4,707 |

`is_mysql_mapped=TRUE`는 488행이다. 위 개수가 같다는 사실만으로 동일한 488행이거나 매핑이 정확하다고 단정하지 않는다. `is_deleted`는 실제로 BOOL이 아닌 INT64이므로 Gold의 0/1→BOOLEAN 정규화 계약을 유지하고 허용값을 추가 검증한다.

2026-08-06 `_temp`의 컬럼 미존재와 Typed Placeholder 검증은 과거 이력으로 보존한다. **현재 Stage `silver__users`를 사용하는 검증에는 네 실제 컬럼을 직접 사용하며 Placeholder를 넣지 않는다.** 실제 값이 존재한다는 것과 가입일 의미·사용자 매핑·Event/User 관계·KPI가 올바르다는 것은 별도다. 이번 확인으로 “실제 4개 컬럼 기반 Stage KPI 검증 완료” 또는 “Production 연결 가능”으로 바꾸지 않는다. 누가 언제 어떤 코드로 추가했는지는 이번 조회만으로 확인하지 않았다.

| 검증/배포 항목 | 현재 상태 |
| --- | --- |
| Stage User 4개 컬럼 추가 | 확인 완료 |
| Stage 실제 값 적재 및 기본 NULL 개수 확인 | 확인 완료 |
| 실제 가입일·매핑 정확성·Event/User 관계·Stage KPI 검증 | 별도 검증 필요 |
| Production `silver__users` 승격 | 미완료 — 테이블 없음 |
| Production Gold·BI 연결 | 운영 입력 제공 및 Stage 검증 후 진행 |

#### 5.5.4 Silver User 알려진 제한

현재 Silver User에는 다음과 같은 알려진 제한이 있다.

1. **(질문 3)** 동일 관측에서 `top_user_id`가 존재하면 `param_user_id`가 대표 ID 후보에서 제외될 수 있다(행 레벨 COALESCE가 cross-row 비-익명 우선 로직보다 먼저 일어남).
2. **(질문 2)** `gender`, `major`가 대표 `user_id`를 지지하는 관측으로 제한되지 않을 수 있다(`user_pseudo_id` 전체 이력에서 선택될 수 있음).
3. 최근 범위 MERGE에서 기존 `last_seen_at`보다 과거인 지연 Event가 제외될 수 있다.
4. **anonymous ID의 숫자 suffix가 MySQL 사용자 ID로 해석될 가능성이 있다.** 실제 Prod SQL은 `regexp_extract(resolved_user_id, r'_(\d+)\s*$')`로 숫자 suffix를 추출해 `koin_users.id`와 결합하는데, anonymous ID 패턴이 `anonymous_숫자`(`^anonymous(?:_\d+)?$`) 형태라서 이 suffix가 학번이 아니라 anonymous ID의 일련번호일 수도 있다. 잘못 매핑되면 엉뚱한 MySQL 계정에 연결될 위험이 있다.
5. `is_deleted`의 실제 출력 타입이 Gold BOOLEAN 계약과 다를 수 있다. 실제 Prod SQL은 `safe_cast(is_deleted as int64)`로 정수 캐스팅한다.

위 항목은 Silver 담당 범위다. **Gold에서 ID 또는 사용자 속성을 다시 계산해 교정하지 않는다.** Gold 배포 전 영향 여부를 입력 품질 테스트(5.12.3절 warn 테스트)로 확인한다. 4번은 특히 `koin_users` 결합이 실제로 이뤄지는 Prod 이후에만 발현되는 리스크다.

### 5.6 Silver 컬럼 최종 확인

Gold가 직접 사용하는 최소 Silver 컬럼은 다음과 같다.

| 모델 | 최소 컬럼 |
| --- | --- |
| Event Silver | `event_id`, `event_dt`, `event_at`, `user_pseudo_id`, `ga_session_id`, `custom_session_id`, `platform`, `device_category`, `device_os`, `engagement_time_msec`, `service_name`, `is_entry_event`, `is_core_action` |
| User Silver | `user_pseudo_id`, `user_id`, `gender`, `major`, `entry_year`, `first_seen_at`, `user_type`, `signup_completed_at`, `is_deleted`, `is_mysql_mapped` |

아래는 2026-08-25 기록의 배포 상태 이력이다. User 4개 컬럼의 최신 2026-09-09 실측 및 값 적재 상태는 5.5.3절을 우선한다. 아래 Gold 데이터셋 존재 여부는 이번 User 점검에서 재조회하지 않았다.

```text
Stage silver_events_temp: Gold 필수 Event 분류 컬럼 존재, 이력 검증용
Stage silver__users_temp: 운영 추가 4개 컬럼 없음, 이력 검증용
Stage silver_events: 20개 기본 컬럼, Gold 필수 분류 컬럼 없음
Stage silver__users: 19개 컬럼과 운영 추가 4개 컬럼 존재
  - 4,707행 / 고유 user_pseudo_id 4,707 / first_seen_at Null 0
  - 생성·최종 수정 2026-08-10이므로 PR 병합 후 실행 결과가 아님
Stage silver_events_v2: 없음
Stage gold: 데이터셋은 있으나 테이블 0개

Production silver_events: 20개 기본 컬럼, Gold 필수 분류 컬럼 없음
Production silver_events_v2: 없음
Production silver__users: 없음
Production gold: 데이터셋 없음
```

PR #29 병합 코드가 배포 후 제공해야 하는 입력 상태는 다음과 같다.

```text
Stage/Production silver_events_v2:
  event_id·event_dt·event_at 및 서비스 분류 3개 컬럼을 포함한 Event Silver 계약 제공

Stage/Production silver__users:
  user_pseudo_id당 1행과 user_type·signup_completed_at·is_deleted·is_mysql_mapped 제공

Gold:
  두 Silver 모델을 ref()로 읽는 mart_kpi_user_daily를 Stage에 먼저 생성할 수 있는 상태
```

#### 과거 Stage 데이터 검증 결과

| 검증 항목 | 결과 |
| --- | --- |
| Event 전체 행 | 14,241 |
| Event `event_id` Null | 0 |
| Event 고유 `event_id` | 14,241 |
| Event `user_pseudo_id` Null | 0 |
| User 전체 행 | 117 |
| User 고유 `user_pseudo_id` | 117 |
| User `user_pseudo_id` Null | 0 |
| User `first_seen_at` Null | 0 |

#### 과거 Stage 임시 처리

Stage에서 38개 Gold 스키마 형태가 필요하면 `user_base`에서 다음 임시값을 사용할 수 있다.

```sql
CAST(NULL AS STRING) AS user_type,
CAST(NULL AS TIMESTAMP) AS signup_completed_at,
CAST(NULL AS BOOL) AS is_deleted,
FALSE AS is_mysql_mapped
```

이 값은 과거 구조 검증용이다. PR #29 병합 후 새 Stage 검증에서는 Typed Placeholder를
사용하지 않고 배포된 `silver__users`의 실제 네 컬럼을 직접 참조한다. 실제 값이 없거나
타입이 다르면 Gold를 우회 생성하지 않고 입력 계약 실패로 처리한다.

#### `signup_completed_at` 사용 조건

```text
signup_completed_at ← koin_users.created_at
```

다음 조건을 확인한 후 사용한다.

- 실제 최초 가입 완료 시각인가?
- 마이그레이션 또는 레코드 재생성 시각이 아닌가?
- 기존 사용자에게도 유효한 값이 존재하는가?
- 탈퇴 후 재가입의 의미가 정의됐는가?

Gold 가입일은 KST 기준으로 계산한다.

```sql
DATE(signup_completed_at, 'Asia/Seoul')
```

#### 5.6.1 Stage 실행 Source 환경변수 차단 계약 (2026-08-25 추가)

PR #29 병합 코드의 source 기본값은 운영을 가리킨다.

```yaml
KOIN_DATA_GA4_PROJECT 기본값: kap-chat
KOIN_DATA_GA4_DATASET 기본값: analytics_432041405
KOIN_DATA_APP_DB_PROJECT 기본값: kap-chat
KOIN_DATA_APP_DB_DATASET 기본값: analytics_432041405
```

따라서 환경변수 없이 Stage에서 `dbt run`을 실행하면 Stage 결과 테이블을 만들면서 입력은
운영 GA4와 운영 `koin_users`에서 읽을 수 있다. 이는 코드가 정상 컴파일되더라도 환경 격리
검증을 무효화한다. 과거 `1cf654b`에서는 GA4 기본값을 Stage로 되돌린 이력이 있지만 PR #29
병합 결과는 다시 운영 기본값이다.

Silver source YAML 수정은 Silver 담당 범위다. Gold 작업에서는 다음 실행 전 차단 절차를
적용한다.

- Stage 실행 전에 `KOIN_DATA_GA4_PROJECT`, `KOIN_DATA_GA4_DATASET`,
  `KOIN_DATA_APP_DB_PROJECT`, `KOIN_DATA_APP_DB_DATASET` 네 값을 모두 명시한다.
- `target.name = 'stage'`에서 source가 `kap-chat.analytics_432041405`로 해석되면 기본적으로
  실행을 중단한다. 운영 원천을 읽는 의도적 교차 환경 검증은 별도 승인과 읽기 전용 권한이
  있을 때만 예외로 허용한다.
- `dbt compile` 또는 `manifest.json`에서 `source('ga4','events')`와
  `source('app_db','koin_users')`의 최종 project/dataset을 출력해 실행 로그에 남긴다.
- Stage `silver_events_v2`·`silver__users` 실행 전에 이 preflight를 통과해야 하며,
  Intermediate와 Gold는 검증되지 않은 Stage Silver 결과를 입력으로 사용하지 않는다.
- Airflow/Cosmos 배포에서는 네 환경변수를 연결 설정에 명시하고 기본값 의존을 금지한다.

이 항목은 데이터 값 테스트가 아니라 **실행 환경 차단 게이트**다. PR 병합 여부나 dbt parse
성공만으로 통과 처리하지 않는다.

### 5.7 Gold Mart 테이블 계약

#### 모델 기본 정보

| 항목 | 내용 |
| --- | --- |
| dbt 모델명 | `mart_kpi_user_daily` |
| 논리 계층 | Gold |
| 운영 Event 입력 | `silver_events_v2` |
| 운영 User 입력 | `silver__users` |
| 운영 Spine 입력 | `int__user__retention_spine` |
| 현재 Stage User 검증 입력 | `koin-stage-438512.silver.silver__users` — 네 실제 컬럼 사용 |
| 현재 Stage Event 점검 입력 | `silver_events` 기본 이벤트 / `silver_events_temp` 분류 참고, 어느 쪽도 완성된 V2 입력으로 간주하지 않음 |
| 목표 Stage KPI 검증 입력 | Stage target의 `silver_events_v2`, `silver__users` — Event V2 제공·검증 대기 |
| 이력 검증 입력 | `silver_events_temp`, `silver__users_temp` |
| BI 연결 대상 | `gold.mart_kpi_user_daily` |
| Grain | `event_dt × user_pseudo_id`당 1행 |
| Unique key | `event_dt + user_pseudo_id` |
| Partition | `event_dt` |
| Cluster 후보 | `user_pseudo_id`, `user_id` |
| 1차 실행 방식 | Full Refresh |

#### 사용자 결합 기준

```text
Event.user_pseudo_id = User.user_pseudo_id
```

Silver Event는 `event_id`당 한 행, Silver User는 `user_pseudo_id`당 한 행을 보장해야 한다. PR #29 계약상 Silver Event의 `user_pseudo_id` Null은 허용한다.

Gold에서는 Event를 다시 Dedup하거나 대표 User 행을 선정하지 않는다. Silver 고유성 테스트가 실패하면 Gold 실행과 배포를 중단한다.

Gold는 `silver_events_v2`에서 `user_pseudo_id IS NOT NULL`인 Event만 USER×DAY 대상으로 사용한다. 이 Gold 대상 Event의 모든 `user_pseudo_id`는 Silver User에 존재해야 한다.

```text
silver_events_v2.user_pseudo_id IS NOT NULL
  → silver__users.user_pseudo_id
```

Event 사용자가 User에 없거나 결합된 `first_seen_at`이 Null이면 Gold에서 임의 보정하지 않는다. pseudo ID가 Null인 제외 Event는 사용자 KPI에 포함하지 않으며 제외 비율을 warn으로 공개한다.

#### USER×DAY Spine

운영 Gold는 다음 세 집합을 `UNION DISTINCT`로 결합한다.

```sql
select event_dt, user_pseudo_id
from event_user_day

union distinct

select retention_dt as event_dt, user_pseudo_id
from first_seen_retention_spine

union distinct

select retention_dt as event_dt, user_pseudo_id
from signup_retention_spine
```

`first_seen_retention_spine`은 모든 `user_pseudo_id`에 대해 `first_seen_dt`부터 D365까지, `signup_retention_spine`은 가입 사용자에 대해 `first_signup_dt`부터 D365까지 생성한다. 단, 실제 생성 범위는 각 기준일+365일과 `event_complete_dt` 중 이른 날짜까지이며, `event_complete_start_dt`보다 이른 평가일은 생성하지 않는다.

```sql
generate_array(0, 365)
```

두 Spine과 Event 날짜를 합쳐도 `(event_dt, user_pseudo_id)`는 한 행으로 유지된다. Event가 없는 날짜에는 활동·서비스 지표를 0으로 채운다. 이 촘촘한 Spine은 사용자가 선택한 N일에 활동이 없었던 사용자의 `0`을 분모에 포함하기 위해 필요하다.

과거 `_temp` User에 `signup_completed_at`이 없을 때는 `first_seen_at` 기반 전체 사용자
리텐션만 검증할 수 있었다. PR #29 병합 모델은 실제 `silver__users.signup_completed_at`을
출력하므로 배포 후 최초 방문과 가입 리텐션을 모두 검증 대상으로 둔다. 단, 가입 시각 의미와
값의 품질은 실제 Stage 테스트와 원천 freshness 조건을 통과해야 한다.

### 5.8 Gold 출력 컬럼

#### 5.8.1 기준일 및 사용자 속성

| 컬럼 | 타입 | Null | 정의 |
| --- | --- | --- | --- |
| `event_dt` | DATE | 불가 | Event 발생일 또는 리텐션 Spine의 평가일 |
| `user_pseudo_id` | STRING | 불가 | Event 또는 User 식별자 |
| `user_id` | STRING | 허용 | Silver User 최종 ID |
| `gender` | STRING | 허용 | Silver User `gender` |
| `major` | STRING | 허용 | Silver User `major` |
| `entry_year` | INTEGER | 허용 | Silver User `entry_year` |
| `user_type` | STRING | 허용 | Silver User `user_type` |
| `is_deleted` | BOOLEAN | 허용 | 현재 탈퇴 상태, 미매핑은 Null |
| `is_mysql_mapped` | BOOLEAN | 불가 | MySQL 매핑 여부 |

`is_mysql_mapped = FALSE`여도 GA4 기반 `user_id`는 존재할 수 있다. Gold에서 `user_id`를 임의로 Null로 변경하지 않는다.

Silver의 `is_deleted`가 0/1 정수이면 Gold 출력 타입만 다음처럼 BOOLEAN으로 통일할 수 있다(이건 Silver 로직을 바꾸는 게 아니라 출력 타입 표현만 정규화하는 것이다 — 5.5.4절 5번 참고).

```sql
CASE
  WHEN LOWER(CAST(is_deleted AS STRING)) IN ('true', '1') THEN TRUE
  WHEN LOWER(CAST(is_deleted AS STRING)) IN ('false', '0') THEN FALSE
  ELSE NULL
END AS is_deleted
```

**`entry_year` 타입 통일 (2026-08-06 확정, 실측 완료)**: Stage `silver__users_temp.entry_year`는 INT64, Prod `mart.dim_users.entry_year`는 STRING이다(둘 다 BigQuery `INFORMATION_SCHEMA.COLUMNS`로 실측 확인). Prod 값을 전수 조사한 결과(`GROUP BY entry_year`, NULL 23,170건 제외 전부), 2000~2026 사이의 4자리 연도 문자열만 존재했고 `SAFE_CAST(entry_year AS INT64)`로 캐스팅 불가능한 값은 0건이었다. Gold 계약은 INTEGER로 유지하고, `is_deleted`와 동일한 패턴으로 출력 타입만 정규화한다(Silver 로직 변경 아님).

```sql
SAFE_CAST(entry_year AS INT64) AS entry_year
```

Stage는 이미 INT64라 이 표현식이 그대로도 안전하다(no-op). 향후 Prod 실측에서 4자리 연도가 아닌 값(빈 문자열, 텍스트 등)이 발견되면 `SAFE_CAST`가 NULL로 흡수하므로 Gold 배포가 깨지지는 않되, warn 테스트(5.12.3절)로 비율을 감시한다.

#### 5.8.2 플랫폼 및 디바이스

| 컬럼 | 타입 | Null | 정의 |
| --- | --- | --- | --- |
| `platform_dominant` | STRING | 불가 | 일간 대표 플랫폼 |
| `device_category_dominant` | STRING | 불가 | 일간 대표 디바이스 |
| `device_os_dominant` | STRING | 불가 | 일간 대표 OS |

각 컬럼은 독립적으로 다음 순서로 선정한다.

1. Event 수 내림차순
2. 가장 최근 `event_at` 내림차순
3. 해당 값 오름차순
4. 값이 없으면 `unknown`

#### 5.8.3 사용자 활동 지표

| 컬럼 | 타입 | Null | 정의 |
| --- | --- | --- | --- |
| `event_cnt_day` | INTEGER | 불가 | 일간 Event 수 |
| `entry_event_cnt_day` | INTEGER | 불가 | Entry Event 수 |
| `core_action_cnt_day` | INTEGER | 불가 | Core Action Event 수 |
| `session_cnt_day` | INTEGER | 불가 | 고유 Session 수 |
| `engagement_msec_day` | INTEGER | 불가 | 체류 시간 합계 |
| `is_multi_session_user` | INTEGER | 불가 | Session 수가 2개 이상이면 1 |

```sql
COUNT(*) AS event_cnt_day,
COUNTIF(COALESCE(is_entry_event, FALSE)) AS entry_event_cnt_day,
COUNTIF(COALESCE(is_core_action, FALSE)) AS core_action_cnt_day,
COUNT(DISTINCT COALESCE(custom_session_id, ga_session_id)) AS session_cnt_day,
SUM(COALESCE(engagement_time_msec, 0)) AS engagement_msec_day
```

Silver의 `event_id UNIQUE` 계약을 신뢰하므로 `COUNT(*)`를 사용한다. Event가 없는 리텐션 Spine 행은 활동 지표를 0으로 처리한다.

```sql
CASE WHEN session_cnt_day >= 2 THEN 1 ELSE 0 END
  AS is_multi_session_user
```

**`is_logged_in`은 실제 당일 로그인 여부가 아니므로 Gold에서 완전히 제거한다.**

#### 5.8.4 최초 방문·가입 및 선택형 리텐션(D0~D365)

**2026-08-18 변경**: 고정 D1/D7/D14/D30 플래그를 제거하고, 사용자가 Superset에서 원하는 N일을 선택할 수 있는 일반화된 리텐션 계약으로 교체한다. 물리 Gold 테이블은 `mart_kpi_user_daily` 하나를 유지한다.

| 컬럼 | 타입 | Null | 정의 |
| --- | --- | --- | --- |
| `first_seen_dt` | DATE | 불가 | 전체 GA4 이력 기준 최초 관측일 |
| `first_signup_dt` | DATE | 허용 | KST 기준 가입 완료일 |
| `is_new_user` | INTEGER | 불가 | `first_seen_dt = event_dt`이면 1 |
| `is_new_signup` | INTEGER | 불가 | `first_signup_dt = event_dt`이면 1 |
| `had_entry_prev_day` | INTEGER | 불가 | 달력상 전일 Entry 활동 여부 |
| `days_since_first_seen` | INTEGER | 허용 | `event_dt - first_seen_dt`, D0~D365 범위의 전체 사용자 리텐션 경과일 |
| `is_first_seen_retained` | INTEGER | 허용 | 해당 최초 방문 경과일에 Entry 활동이 있으면 1, 없으면 0 |
| `days_since_signup` | INTEGER | 허용 | `event_dt - first_signup_dt`, D0~D365 범위의 가입 리텐션 경과일 |
| `is_signup_retained` | INTEGER | 허용 | 해당 가입 경과일에 Entry 활동이 있으면 1, 없으면 0 |

```sql
DATE(first_seen_at) AS first_seen_dt,
DATE(signup_completed_at, 'Asia/Seoul') AS first_signup_dt
```

`had_entry_prev_day`는 달력상 전일을 Self Join한다.

```sql
previous.user_pseudo_id = current.user_pseudo_id
AND previous.event_dt = DATE_SUB(current.event_dt, INTERVAL 1 DAY)
```

단순 `LAG()`는 이전 활동일을 반환할 수 있으므로 사용하지 않는다.

전체 사용자 최초 방문 리텐션은 `first_seen_dt`, 가입 리텐션은 `first_signup_dt`를 시작점으로 한다. `first_seen_dt` 기준에는 로그인·비로그인을 모두 포함한 전체 `user_pseudo_id`가 들어가고, 가입 기준은 그중 `signup_completed_at`이 있는 부분집합이다. Event 당시 로그인 여부는 현재 Silver 계약으로 판정하지 않는다.

```sql
date_diff(event_dt, first_seen_dt, day) as days_since_first_seen,
date_diff(event_dt, first_signup_dt, day) as days_since_signup
```

두 경과일은 0~365일 범위이면서 평가일이 Event 완전 가용 범위 안일 때만 리텐션 분석에 사용한다. Event 때문에 존재하는 범위 밖 행에서는 경과일과 리텐션 플래그를 Null로 둔다.

```text
기준일+N일 Entry 활동 존재: 1
기준일+N일 Entry 활동 없음: 0
기준일 없음, N<0, N>365 또는 Event 완전 가용 범위 밖: NULL
```

**`event_complete_start_dt` 추가(2026-08-06, 실측으로 발견한 결함 수정)**: 완료 여부를 `event_complete_dt`(미래 방향 컷오프) 하나만으로 판단하면 왼쪽 절단(left-censoring) 문제가 생긴다. 실측 결과 Prod `silver.silver_events`는 2026-06-27부터만 존재하는데, `mart.dim_users.signup_completed_at`(KST)은 2018-08-26까지 거슬러 올라간다(23,336건 Null 제외, future 0건). 즉 2020년에 가입한 사용자의 "가입+7일" 시점은 `event_complete_dt`보다 훨씬 과거라 완료 조건(`<= event_complete_dt`)은 통과하지만, 그 시점의 Event 데이터 자체가 아예 없다 — 이걸 그대로 계산하면 활동이 없어서 리텐션 0으로 잘못 나온다(사실은 "측정 불가"). 그래서 완료 판정에는 시작일도 함께 확인해야 한다.

```sql
DATE('{{ var("event_complete_start_dt") }}') AS event_complete_start_dt,
DATE('{{ var("event_complete_dt") }}') AS event_complete_dt
```

각 리텐션 평가일은 다음 범위 안에 있을 때만 완료로 판단한다.

```sql
event_dt BETWEEN event_complete_start_dt AND event_complete_dt
```

전체 사용자 최초 방문 리텐션은 다음 패턴으로 계산한다. 가입 리텐션도 기준일만 `first_signup_dt`로 바꿔 동일하게 계산한다.

이 계산은 Intermediate가 아니라 최종 Gold에서 수행한다. Intermediate는 평가일과 경과일만
제공하고, Gold가 한 번 계산한 `entry_event_cnt_day`를 리텐션과 활성 플래그가 공유한다.

```sql
CASE
  WHEN first_seen_dt IS NULL THEN NULL
  WHEN DATE_DIFF(event_dt, first_seen_dt, DAY) NOT BETWEEN 0 AND 365 THEN NULL
  WHEN event_dt < event_complete_start_dt THEN NULL
  WHEN event_dt > event_complete_dt THEN NULL
  WHEN entry_event_cnt_day > 0 THEN 1
  ELSE 0
END AS is_first_seen_retained
```

```sql
CASE WHEN entry_event_cnt_day > 0 THEN 1 ELSE 0 END AS is_active_entry
```

따라서 경과일이 non-null인 평가 가능 행에서는 다음 불변식이 성립해야 한다.

```text
is_first_seen_retained = is_active_entry
is_signup_retained = is_active_entry
```

각 등식은 해당 기준의 `days_since_*`가 non-null인 행에만 적용한다.

두 리텐션 플래그는 다음 식으로 완전히 재계산할 수 있는 **파생 컬럼**이다.

```sql
IF(days_since_first_seen IS NOT NULL, is_active_entry, NULL)
  AS is_first_seen_retained,
IF(days_since_signup IS NOT NULL, is_active_entry, NULL)
  AS is_signup_retained
```

그럼에도 최종 Gold에 물리화한다. Superset이 `COUNT(is_*_retained)`만으로 해당 기준일과
경과일을 평가할 수 있는 pseudo 사용자 수를 분모로 계산하고, `SUM(is_*_retained)`로
잔존 pseudo 사용자 수를 계산하게 하기 위해서다. `is_active_entry`만 노출하면 활동 여부는
알 수 있지만 각 코호트 기준의 평가 가능 여부를 별도 조건 없이 셀 수 없다.

두 변수(`event_complete_start_dt`, `event_complete_dt`)는 KST 기준 DATE이며 Airflow/dbt `vars`로 필수 제공한다. 값이 없으면 기본값을 추정하지 않고 Gold 실행을 실패시킨다. `MIN(event_dt)`/`MAX(event_dt)`는 실제 데이터 완전성을 보장하지 않으므로(예: 특정 날짜 파티션 일부만 적재된 경우) 자동 대체값으로 쓰지 않는다.

예를 들어 사용자가 N=10을 선택하면 `days_since_first_seen = 10`을 필터링해 정확한 D10 전체 사용자 리텐션을 계산한다. D0~D10 곡선은 `days_since_first_seen BETWEEN 0 AND 10`으로 조회한다. 가입 리텐션은 같은 방식으로 `days_since_signup`과 `is_signup_retained`를 사용한다.

코호트 날짜 범위는 각 사용자의 기준일을 선택하는 필터다. 예를 들어 `first_seen_dt BETWEEN '2026-08-01' AND '2026-08-31'`은 8월 중 처음 관측된 전체 pseudo 사용자를 선택하고, `first_signup_dt`의 같은 범위는 8월 중 가입한 pseudo 사용자를 선택한다. 각 사용자의 D10 평가일은 자신의 기준일+10일이다. 모든 사용자의 공통 시작일을 8월 1일로 바꾸는 의미가 아니다.

가입일이나 최초 방문일과 무관하게 "사용자가 선택한 8월 1일에 활동한 사용자"를 새 코호트로 삼는 임의 활동일 기준 리텐션은 현재 계약에 포함하지 않는다. 이를 지원하려면 `anchor_dt × days_since_anchor × user_pseudo_id`라는 다른 Grain을 펼쳐야 하므로 한 개 USER×DAY Mart와 일반 Superset 필터만으로 계산하지 않는다.

두 리텐션의 경과일과 플래그는 반드시 다음 짝으로만 사용한다.

| 리텐션 | 코호트 기준일 | 경과일 필터 | 집계 플래그 |
| --- | --- | --- | --- |
| 전체 사용자 최초 방문 | `first_seen_dt` | `days_since_first_seen` | `is_first_seen_retained` |
| 가입 사용자 | `first_signup_dt` | `days_since_signup` | `is_signup_retained` |

`days_since_first_seen`으로 필터한 결과에 `is_signup_retained`를 집계하거나, `days_since_signup`으로 필터한 결과에 `is_first_seen_retained`를 집계하지 않는다. 두 경과일이 같은 행에 존재하더라도 서로 다른 기준일의 값이다.

기준일에서 N일이 지나기 전에는 해당 USER×DAY 평가 행이 없거나 플래그가 Null이므로 분모에서 제외한다. N일이 지나고 그 날짜가 `event_complete_dt`에 포함되면 Full Refresh가 해당 평가 행을 생성해 0 또는 1로 확정한다. 한번 확정된 DN은 과거 Event가 보존되는 한 N일 이후에도 계속 조회할 수 있다.

현재 계약은 정확한 DN 리텐션과 D0~DN 일별 곡선을 제공한다. "N일 이내 한 번이라도 재방문"은 최근 코호트의 N일 관측 완료 여부를 별도로 통제하는 누적 플래그가 필요하므로 38개 컬럼 계약에 포함하지 않는다. 필요 시 정확한 DN과 혼용하지 않고 별도 컬럼 계약으로 검토한다.

#### 5.8.5 서비스 이용 플래그

| 컬럼 | 타입 | Null | 정의 |
| --- | --- | --- | --- |
| `used_shop_flg` | INTEGER | 불가 | Shop Entry 존재 |
| `used_cafeteria_flg` | INTEGER | 불가 | Cafeteria 서비스 Event 존재 |
| `used_bus_flg` | INTEGER | 불가 | Bus Entry 존재 |
| `used_board_flg` | INTEGER | 불가 | Board Entry 존재 |
| `used_facility_flg` | INTEGER | 불가 | Facility Entry 존재 |
| `used_timetable_flg` | INTEGER | 불가 | Timetable Entry 존재 |
| `used_grad_calc_flg` | INTEGER | 불가 | Grad Calc Entry 존재 |
| `used_account_flg` | INTEGER | 불가 | Account 서비스 Event 존재 |

일반 서비스 플래그는 다음처럼 계산한다.

```sql
MAX(CASE
  WHEN service_name = '<service>'
   AND COALESCE(is_entry_event, FALSE)
  THEN 1 ELSE 0
END)
```

Account와 Cafeteria는 Entry 조건 없이 서비스 Event 존재 여부로 계산한다. **2026-08-06 서비스별 Entry 실측 전수 확인 결과** `service_name`별 (전체건수/Entry건수)는 shop 294/288, account 68/0, timetable 22/14, board 17/17, cafeteria 13/0, bus 10/2, grad_calc 8/2, facility 7/7이었다. **Cafeteria도 Account와 마찬가지로 13건 전부 `is_entry_event = FALSE`**라, Entry 조건을 걸면 `used_cafeteria_flg`가 항상 0이 되는 동일한 결함이 있었다(4.8절 `used_account_flg`와 같은 유형). 그래서 Cafeteria도 Account와 같은 예외로 처리한다.

```sql
MAX(CASE WHEN service_name = 'account' THEN 1 ELSE 0 END)
  AS used_account_flg,
MAX(CASE WHEN service_name = 'cafeteria' THEN 1 ELSE 0 END)
  AS used_cafeteria_flg
```

나머지 서비스(shop/timetable/board/bus/grad_calc/facility)는 전부 Entry 건수가 0보다 커서 Entry 조건을 그대로 적용해도 안전하다.

`used_real_estate_flg`는 현재 Silver 분류 규칙이 없으므로 포함하지 않는다.

#### 5.8.6 활성 사용자 플래그

| 컬럼 | 타입 | Null | 정의 |
| --- | --- | --- | --- |
| `is_active_entry` | INTEGER | 불가 | Entry Event가 하나 이상이면 1 |
| `is_active_any_event` | INTEGER | 불가 | Event가 하나 이상이면 1 |
| `has_core_action` | INTEGER | 불가 | Core Action이 하나 이상이면 1 |

```sql
CASE WHEN entry_event_cnt_day > 0 THEN 1 ELSE 0 END AS is_active_entry,
CASE WHEN event_cnt_day > 0 THEN 1 ELSE 0 END AS is_active_any_event,
CASE WHEN core_action_cnt_day > 0 THEN 1 ELSE 0 END AS has_core_action
```

#### 5.8.7 BI(Superset) 계산 및 대시보드 연결 원칙

5.14.6절의 Slack 결론(별도 코호트 마트 대신 사전 계산 플래그)을 실제 BI 연결 방식으로 구체화한 것이다.

현재 사용하는 Superset의 계산된 컬럼과 SQL Metric은 행 단위 표현식 또는 집계식은 제공하지만, Tableau의 FIXED LOD와 같은 계산을 전제로 설계하지 않는다.

따라서 코호트 기준일, 전일 활동, 리텐션 판정처럼 USER×DAY보다 다른 상세 수준을 고정해야 하는 값은 BI에서 다시 만들지 않고 Gold SQL에서 계산한다. BI는 Gold가 제공한 컬럼을 합계, 개수, 비율로 표현하는 역할만 담당한다.

선택형 리텐션은 별도 코호트 Gold Mart와 Virtual Dataset 없이 `mart_kpi_user_daily` 하나로 제공한다. Gold-owned Intermediate가 D0~D365의 평가 가능한 USER×DAY Spine을 생성하고, 최종 Gold가 이를 결합하며 Superset은 사용자가 선택한 N으로 경과일 컬럼을 필터링한다.

```sql
-- 전체 사용자 정확한 DN 리텐션: days_since_first_seen = N 필터
SAFE_DIVIDE(SUM(is_first_seen_retained), COUNT(is_first_seen_retained))

-- 가입 사용자 정확한 DN 리텐션: days_since_signup = N 필터
SAFE_DIVIDE(SUM(is_signup_retained), COUNT(is_signup_retained))
```

전체 사용자 리텐션 차트는 `first_seen_dt`를 코호트 시작일로, 가입 리텐션 차트는 `first_signup_dt`를 코호트 시작일로 그룹화한다. `COUNT(is_*_retained)`는 선택한 N일을 평가할 수 있는 pseudo 사용자 수다. 아직 N일이 지나지 않았거나 Event 완전 가용 범위 밖인 사용자는 분모에 포함하지 않는다.

리텐션율은 평가 가능 분모가 30명 이상일 때만 기본 표시한다. 30명 미만이면 비율은 Null 또는 숨김 처리하되 분모 자체는 Tooltip이나 별도 KPI로 표시한다. 이 기준은 BI 표시 정책이며 Gold 행이나 플래그를 제거하지 않는다. 운영 승인으로 임계값을 바꿀 수 있다.

```sql
-- 전체 사용자 리텐션율 예시: days_since_first_seen = N 필터와 함께 사용
CASE
  WHEN COUNT(is_first_seen_retained) >= 30
  THEN SAFE_DIVIDE(
    SUM(is_first_seen_retained),
    COUNT(is_first_seen_retained)
  )
  ELSE NULL
END
```

대시보드별 기본 사용 방식은 다음과 같다.

| 대시보드 영역 | 시간·그룹 기준 | 주요 BI 집계 |
| --- | --- | --- |
| 일간 활동 | `event_dt` | `SUM(is_active_entry)`, `SUM(is_active_any_event)`, 활동량 합계 |
| 신규 방문·가입 | `event_dt` | `SUM(is_new_user)`, `SUM(is_new_signup)` |
| 전체 사용자 최초 방문 코호트 | `first_seen_dt`, `days_since_first_seen` | 사용자가 선택한 정확한 DN 및 D0~DN 리텐션 곡선 |
| 가입 코호트 | `first_signup_dt`, `days_since_signup` | 사용자가 선택한 정확한 DN 및 D0~DN 리텐션 곡선 |
| 서비스 이용 | `event_dt` | 각 `used_*_flg`의 합계 |

여러 대시보드가 동일한 Gold Dataset을 조회할 수 있으므로 대시보드 수와 마트 수를 일대일로 맞추지 않는다. 마트 분리 여부는 대시보드 수가 아니라 Grain과 계산 계약이 달라지는지를 기준으로 판단한다. 물리 테이블 수가 적다는 사실만으로 성능이 보장되는 것은 아니며, 실제 성능은 Chart 수, 동시 Query 수, Scan 범위, Partition Filter와 집계 복잡도의 영향을 받는다.

D0~D365 선택형 리텐션은 Intermediate의 촘촘한 USER×DAY Spine을 최종 Gold에 결합해 제공하므로 별도 BI 공개 Mart가 필요하지 않다. 사용자가 N=10을 선택하면 D0~D10, N=23을 선택하면 D0~D23을 같은 Gold Dataset에서 조회한다. 최대 지원 범위는 365일이며, 이를 넘는 요구는 행 수와 비용을 다시 검토한다.

**Rolling WAU/MAU 한계 (2026-08-06, 6장 대시보드 카탈로그 검토 중 발견)**: 달력 기준 주간/월간 순 사용자 수(WAU/MAU)는 시간 Grain을 주·월로 바꾸고 `COUNT(DISTINCT CASE WHEN is_active_any_event = 1 THEN user_pseudo_id END)`를 쓰면 된다(가입만 하고 활동이 없는 Spine 행이 섞이지 않도록 `is_active_any_event = 1` 조건이 반드시 필요하다). 하지만 "매일 기준으로 직전 7일/30일" 같은 **이동(rolling) 구간 순 사용자 수**는 일반 Superset SQL Metric(단순 집계식) 하나로는 계산할 수 없다 — 시간 구간이 매 행(day)마다 달라지는 이동 윈도우 중복 제거는 표준 GROUP BY 집계로 표현이 안 되고, Gold SQL에서 미리 윈도우를 펼쳐두거나 Superset Virtual Dataset에 명시적 SQL을 써야 한다. 이건 5.14.6절의 LOD 한계와 같은 종류의 제약이라 별도 원칙으로 남긴다: **Rolling 지표가 실제로 필요해지면 지금 수치를 근사치로 대체하지 않고 별도 요구사항으로 검토한다.** 상세 Metric 정의와 대시보드 구성은 6장 참고.

### 5.9 Gold 최종 컬럼 목록

운영 Gold의 최종 계약은 총 38개 컬럼이다. 2026-08-18에 고정 가입 D1/D7/D14/D30 네 컬럼을 선택형 리텐션 네 컬럼으로 교체하여 컬럼 수는 유지한다.

```text
event_dt
user_pseudo_id
user_id
gender
major
entry_year
user_type
is_deleted
is_mysql_mapped
platform_dominant
device_category_dominant
device_os_dominant
event_cnt_day
entry_event_cnt_day
core_action_cnt_day
session_cnt_day
engagement_msec_day
is_multi_session_user
first_seen_dt
first_signup_dt
is_new_user
is_new_signup
had_entry_prev_day
days_since_first_seen
is_first_seen_retained
days_since_signup
is_signup_retained
used_shop_flg
used_cafeteria_flg
used_bus_flg
used_board_flg
used_facility_flg
used_timetable_flg
used_grad_calc_flg
used_account_flg
is_active_entry
is_active_any_event
has_core_action
```

제외된 기존 컬럼은 다음과 같다.

- `is_logged_in`
- `used_real_estate_flg`
- `used_club_flg`(2026-08-06 추가 제외 — 동아리 기능이 별도 앱으로 분리됨, 5.4절 참고)

### 5.10 Intermediate와 Gold 구현 구성

#### Intermediate dbt 경로·스키마 계약

Intermediate 모델은 `dbt/models/intermediate/` 아래에 두고, 폴더의 기본 물리화와 데이터셋
경계는 `dbt_project.yml`에서 다음처럼 선언한다.

현재 설정처럼 `intermediate` 블록 없이 디렉터리만 추가하면 프로젝트 기본 materialization인
`view`와 profile의 기본 dataset `silver`를 사용하므로, 의도한 내부 물리 테이블 경계가
생기지 않는다.

```yaml
models:
  koin_data:
    silver:
      +materialized: view
      +schema: silver
    intermediate:
      +materialized: table
      +schema: intermediate
    gold:
      +materialized: table
      +schema: gold
```

현재 `generate_schema_name(custom_schema_name, node)` 매크로는 `+schema`가 있으면 target의
기본 dataset과 결합하지 않고 해당 값을 그대로 반환한다. 따라서 target project가 각각
정확히 설정됐다는 전제에서 실제 relation은 다음처럼 생성된다.

| 실행 target | Intermediate relation |
| --- | --- |
| Stage/dev | `koin-stage-438512.intermediate.int__user__retention_spine` |
| Production/prod | `kap-chat.intermediate.int__user__retention_spine` |

별도 `intermediate` 데이터셋을 사용하는 이유는 내부 계산 모델을 BI 공개 `gold` 데이터셋과
권한·탐색 경계에서 분리하기 위해서다. Superset에는 `intermediate` 조회 권한을 부여하지
않는다. `gold` 데이터셋 안에 `int__` 모델을 함께 두는 방식은 BI 공개 모델과 내부 모델의
경계가 약해지므로 현재 계약에서는 채택하지 않는다.

`event_dt` 파티션과 `user_pseudo_id` 클러스터처럼 모델 고유의 물리 설정은
`int__user__retention_spine.sql`의 `config()`에 둔다. 폴더 기본값은 계층 전체의
materialization/schema를, 모델 `config()`는 해당 테이블의 파티션·클러스터 계약을 담당한다.

```sql
{{
    config(
        partition_by={
            'field': 'event_dt',
            'data_type': 'date',
            'granularity': 'day'
        },
        cluster_by=['user_pseudo_id']
    )
}}
```

1차 `table` 물리화에서는 `on_schema_change`에 의존하지 않고 YAML·singular test로 컬럼 계약을
차단한다. `on_schema_change` 정책은 2차 `incremental` 전환 시 함께 확정한다.

이 설정의 문서화는 실제 데이터셋 생성이나 권한 부여를 승인하지 않는다. Stage 실행 전에
대상 project·dataset과 실행 계정의 dataset 생성/쓰기 권한을 별도 preflight로 확인한다.

#### `int__user__retention_spine`

```sql
with event_base as (
    -- ref('silver_events_v2'), non-null user_pseudo_id만 사용
),
user_base as (
    -- ref('silver__users'), first_seen/signup 기준일
),
event_user_day as (
    -- Event 발생 USER×DAY
),
first_seen_retention_spine as (
    -- 전체 사용자 first_seen_dt 기준 D0~D365, 완전 가용 완료일까지
),
signup_retention_spine as (
    -- 가입 사용자 first_signup_dt 기준 D0~D365, 완전 가용 완료일까지
),
user_day_spine as (
    -- 위 세 USER×DAY 집합 UNION DISTINCT
),
retention_offsets as (
    -- 최초 방문·가입 경과일만 계산; Entry·리텐션 플래그는 계산하지 않음
)
select * from retention_offsets
```

#### `mart_kpi_user_daily`

```sql
with event_base as (
    -- ref('silver_events_v2')
),
user_base as (
    -- ref('silver__users'), Gold 출력 타입 정규화
),
retention_spine as (
    -- ref('int__user__retention_spine')
),
user_day_activity as (
    -- Event, Entry, Core, Session, 체류 지표
),
dominant_device as (
    -- 대표 플랫폼·디바이스·OS
),
service_flags as (
    -- 서비스 이용 플래그
),
previous_day_entry as (
    -- 달력상 전일 Entry Self Join
),
final as (
    -- Intermediate Spine + 활동 + 사용자 속성 결합
    -- entry_event_cnt_day 하나로 is_active_entry와 두 is_*_retained 계산
)
select * from final
```

Intermediate와 Gold 모두 `deduplicated_events`, `user_canonical` CTE를 두지 않는다. Event
중복 제거와 대표 사용자 선정은 계속 Silver 계약을 신뢰한다. Intermediate 분리는 계산
책임과 테스트 경계를 나누는 것이며 최종 38개 Gold 컬럼이나 USER×DAY Grain을 바꾸지 않는다.

### 5.11 Null 처리 규칙

| 컬럼 유형 | 처리 방식 |
| --- | --- |
| `user_id` | 미식별 사용자는 Null |
| `gender`, `major`, `entry_year`, `user_type` | 정보가 없으면 Null |
| `is_deleted` | MySQL 미매핑이면 Null |
| `is_mysql_mapped` | 미매핑이면 `FALSE` |
| `first_seen_dt` | Gold 대상 사용자는 Not Null |
| `first_signup_dt` | 미가입 또는 미매핑이면 Null |
| `days_since_first_seen`, `is_first_seen_retained` | D0~D365 및 Event 완전 가용 범위 안에서만 값, 그 밖은 Null |
| `days_since_signup`, `is_signup_retained` | 미가입이거나 D0~D365·Event 완전 가용 범위 밖이면 Null |
| 플랫폼·디바이스 | 값이 없으면 `unknown` |
| 활동 지표 | Event가 없으면 0 |
| 서비스 플래그 | 조건 미충족이면 0 |
| 신규·활성·전일 활동 플래그 | 조건 미충족이면 0 |

Gold는 Silver에 없는 값을 다음 방식으로 보정하지 않는다.

- `user_id IS NOT NULL`을 로그인 또는 MySQL 매핑으로 해석
- `first_seen_at`을 가입 완료 시각으로 해석
- 사용자 ID 형식으로 가입 또는 계정 상태 추정
- 없는 서비스 분류를 Gold에서 임의 생성

### 5.12 dbt 테스트

#### 5.12.1 Silver Event 입력 차단 테스트

- `event_id`: `not_null`, `unique`
- `event_dt`: `not_null`
- `service_name`: `not_null`, 허용값
- Gold 필수 Event 컬럼 존재 및 타입 확인(`service_name`, `is_entry_event`, `is_core_action` 포함)
- `event_complete_start_dt <= event_complete_dt`(2026-08-06 추가 — 5.8.4절 왼쪽 절단 방지용 변수)
- `event_complete_start_dt`, `event_complete_dt`가 KST DATE로 필수 제공됨(값 없으면 실행 실패, 기본값 추정 안 함)

`silver_events_v2.user_pseudo_id` Null은 동의 거부로 발생할 수 있으므로 Silver 전체 `not_null` 차단 테스트를 두지 않는다. Gold `event_base`는 non-null 행만 선택한다.

#### 5.12.2 Silver User 입력 차단 테스트

- `user_pseudo_id`: `not_null`, `unique`
- Gold 대상 User의 `first_seen_at`: `not_null`
- `first_seen_at <= last_seen_at`(`last_seen_at`이 입력에 존재하는 경우 — 5.5절 최소 계약엔 없음)
- 운영 `is_mysql_mapped`: `not_null`
- Gold 필수 User 컬럼 존재
- `silver_events_v2.user_pseudo_id IS NOT NULL`인 Gold 대상 Event의 Event/User relationship 누락 건수 0

차단 테스트가 실패하면 Gold에서 Dedup이나 대표값 선정을 통해 우회하지 않고 실행과 배포를 중단한다.

`is_mysql_mapped`는 Silver 계약상 `not_null`이므로 **Gold에서 `coalesce(is_mysql_mapped, false)`로 덮지 않는다.** coalesce하면 upstream 계약 위반이 조용히 FALSE로 흡수돼 차단 테스트가 무력화된다.

#### 5.12.2.1 가입 원천 freshness 차단 테스트 (2026-08-25 재확인)

**2026-08-24 실측**: `kap-chat.analytics_432041405.koin_users`의 `lastModifiedTime`은 2025-11-10 11:48 UTC(6,218행), `kap-chat.mart.dim_users.signup_completed_at` 최대값은 2025-11-09 18:19다. **가입 원천이 약 9.5개월째 갱신되지 않았다.** 같은 기간 `dim_users` 행 수는 25,630→25,636으로 증가했으므로, 가입이 없었던 것이 아니라 **가입 원천 적재가 멈춘 것**으로 추정한다(Silver 담당자 확인 필요).

2026-08-25 재계산에서 D90·D180 가입 Spine은 0행이었지만 D365 가입 Spine은 10,045행이
생성됐다. 이는 오래된 가입 중 일부의 D365 평가일이 현재 Event 구간과 겹친 결과일 뿐,
2026년 신규 가입 원천이 최신이라는 뜻이 아니다. 따라서 가입 코호트 KPI는 Horizon별
행 존재 여부와 무관하게 freshness 복구 전까지 검증 완료로 간주하지 않는다.

영향 컬럼은 다음 7개다.

```text
first_signup_dt
is_new_signup
days_since_signup
is_signup_retained
is_mysql_mapped
is_deleted
user_type
```

**이 freshness 실패는 가입 관련 컬럼에만 적용하는 부분 차단이며, Gold Mart 전체를 차단하지 않는다.** Event·활동·서비스 플래그·활성 플래그와 `first_seen_dt` 기준 전체 사용자 코호트는 non-null `user_pseudo_id` 전체를 대상으로 정상 배포한다. 가입 원천이 오래됐다는 이유로 전체 사용자 KPI의 모집단을 로그인·가입 사용자로 좁히지 않는다.

차단 조건:

- 가입 원천 테이블의 최종 적재 시각이 기준일로부터 허용 지연(예: 7일)을 넘으면 **가입 관련 7개 컬럼을 사용하는 BI 차트와 검증을 차단**한다.
- `MAX(first_signup_dt)`가 장기간 전진하지 않으면 Horizon에 따라 Spine 행이 남아 있더라도 **정상 결과가 아니라 원천 이상**으로 보고한다.
- dbt `source` freshness(`warn_after`/`error_after`)를 가입 원천에 설정하고, Gold 단에서는 `MAX(first_signup_dt)`와 기준일 간격을 확인하는 테스트를 둔다.

원천이 복구되기 전까지 가입 관련 컬럼은 계약에 유지하되 **검증 완료로 간주하지 않으며**, BI에서는 해당 차트를 숨기고 원천 최종 적재일을 함께 표시한다.

#### 5.12.3 Silver 입력 warn 테스트

- `unmapped` 비율
- Silver Event `user_pseudo_id` Null 건수·비율과 Gold 제외 Event 비율
- Entry/Core Null 분포
- top/property 불일치
- top/param 불일치
- top=anonymous, param=학생형 사례
- 동일 `user_pseudo_id`의 복수 정규화 ID
- 대표 ID 기준 속성과 현재 속성의 차이
- **anonymous 사용자 중 `is_mysql_mapped = TRUE`** (5.5.4절 4번 — 숫자 suffix 오매핑 감지)
- **`is_deleted` 값과 타입 분포** (5.5.4절 5번 — 타입 불일치 감지)
- **`entry_year` `SAFE_CAST(... AS INT64) IS NULL` 비율**(원본이 non-null인데 캐스팅 실패한 경우만, 5.8.1절 — 2026-08-06 Prod 전수 실측에서는 0건이었으나 향후 값 추가 시 감시)
- 미래 `first_seen_at`
- `signup_completed_at` 미래 시각
- **하나의 `user_id`에 연결된 복수 `user_pseudo_id` 분포**(5.13절 — 계정 기준과 `user_pseudo_id` 기준 리텐션·사용자 수가 달라질 수 있는 규모 파악용)

warn 발생만으로 자동 배포를 차단하지 않는다. 다만 영향이 BI 결과를 유의미하게 변경하거나 잘못된 사용자 매핑을 만들면 Silver 담당자 확인 또는 명시적 승인 전에는 운영 배포하지 않는다.

**조건부 실행(2026-08-06 추가)**: `top_user_id`, `property_user_id`, `param_user_id` 및 대표 ID 기준 속성처럼 Gold 필수 입력 계약(5.6절)에 포함되지 않은 품질 추적 전용 컬럼을 쓰는 warn 테스트는 해당 컬럼이 운영 Silver 또는 별도 품질 검증 입력에 실제로 제공될 때만 실행한다. 이 품질 컬럼이 없다는 이유만으로 Gold 모델 실행 자체를 실패시키지 않는다 — warn 테스트는 어디까지나 진단용이지 배포 게이트가 아니다.

#### 5.12.3.1 Intermediate 차단 테스트

- `(event_dt, user_pseudo_id)`: `unique`, `not_null`
- non-null `days_since_first_seen`, `days_since_signup`: 0~365
- `days_since_first_seen`이 non-null이면 `DATE_DIFF(event_dt, first_seen_dt, DAY)`와 일치
- `days_since_signup`이 non-null이면 `DATE_DIFF(event_dt, first_signup_dt, DAY)`와 일치
- Event 완전 가용 범위 밖의 평가 행을 생성하지 않음
- 미가입 사용자의 `days_since_signup`은 Null
- Intermediate 출력에 `entry_event_cnt_day`, `is_active_entry`, `is_first_seen_retained`,
  `is_signup_retained`가 존재하지 않음

Intermediate 테스트가 실패하면 Gold를 생성하지 않는다. Gold 테스트는 최종 결합, Entry
단일 계산과 38개 컬럼 계약을 검증하고 Intermediate의 Spine 계산을 중복 구현하지 않는다.

#### 5.12.4 Gold Mart 차단 테스트

- `(event_dt, user_pseudo_id)`: `unique`, `not_null`
- 최종 출력 컬럼 수: 38개(5.9절 — 스키마 회귀 방지)
- `first_seen_dt`: `not_null`
- 활동 지표가 0 이상
- Not Null INTEGER 플래그가 0 또는 1
- `is_first_seen_retained`, `is_signup_retained`는 각각 Null, 0, 1 중 하나
- non-null `days_since_first_seen`, `days_since_signup`은 0~365
- `is_new_user = 1`이면 `first_seen_dt = event_dt`
- `is_new_signup = 1`이면 `first_signup_dt = event_dt`
- `had_entry_prev_day = 1`이면 달력상 전일 Entry 존재
- `days_since_first_seen`이 non-null인 행에 한해 `DATE_DIFF(event_dt, first_seen_dt, DAY)`와 일치
- `days_since_signup`이 non-null인 행에 한해 `DATE_DIFF(event_dt, first_signup_dt, DAY)`와 일치
- 리텐션 플래그가 1이면 해당 `event_dt`에 Entry 활동 존재
- 평가 가능한 Spine 행에서 Entry가 없으면 해당 리텐션 플래그가 0
- `days_since_first_seen`이 non-null이면 `is_first_seen_retained = is_active_entry`
- `days_since_signup`이 non-null이면 `is_signup_retained = is_active_entry`
- `event_dt`가 `event_complete_start_dt`~`event_complete_dt` 밖이면 리텐션 경과일과 플래그가 Null
- 미가입 사용자의 `days_since_signup`, `is_signup_retained`는 Null
- Event가 없는 리텐션 Spine 행의 활동·서비스 지표는 0
- 서비스 플래그와 Silver 기준 Event 비교
- `used_account_flg`와 Account Event 존재 여부 비교
- `used_cafeteria_flg`와 Cafeteria Event 존재 여부 비교(2026-08-06 추가 — 5.8.5절 예외 처리 검증용)
- Gold `user_id`와 Silver 최종 `user_id` 일치
- Event 없는 가입일 행의 활동 지표가 0

### 5.13 사용자 식별 설계

Gold Mart의 Grain과 유일성 기준은 `user_pseudo_id`를 사용한다.

`user_id`는 사용자 식별 및 속성 분석을 위한 보조 식별자이며 Gold 기본키로 사용하지 않는다. 하나의 `user_id`(계정)에 여러 `user_pseudo_id`가 연결되면 계정 기준과 Gold 기준 사용자 수·리텐션이 서로 다를 수 있다. **최초 방문·가입 선택형 리텐션은 모두 `user_pseudo_id` 기준이며 계정 기준이 아니다.** 이 차이가 BI 해석에 영향을 줄 수 있으므로 5.12.3절 warn 테스트로 분포를 감시한다.

**2026-08-06 실측**: Stage `silver__users_temp`에서 복수 `user_pseudo_id`가 연결된 `user_id`는 3개(최대 6개 연결), Prod `mart.dim_users`에서는 522개(최대 43개 연결, 고유 `user_id` 2,223개 중). Prod 쪽은 규모가 훨씬 커서 계정 기준과 `user_pseudo_id` 기준의 차이가 실제 BI 해석에 영향을 줄 수 있는 수준이다 — 운영 배포 후 이 분포를 반드시 모니터링한다.

Silver User가 사용자 ID의 후보 선택과 정규화를 담당하고 Gold는 Silver의 최종 `user_id`를 그대로 사용한다.

Gold에서는 다음 작업을 수행하지 않는다.

- 원천별 ID 재조합
- ID 형식 기반 임의 교정
- anonymous 또는 학생형 여부에 따른 재선정
- Silver와 별개의 사용자 식별 우선순위 적용
- 대표 ID 기준 사용자 속성 재계산

Silver의 ID 및 속성 관련 알려진 제한은 5.5.4절과 5.12.3절의 warn 테스트로 관리한다.

향후 다음 구조가 필요하면 별도 모델로 설계한다.

- 내부 사용자 PK `user_key`
- 하나의 `user_id`와 여러 `user_pseudo_id` 관계
- 식별자 관계 유효 시작·종료 시각
- 사용자 속성 변경 이력
- 탈퇴 사용자 이력

### 5.14 현재 구현 범위

#### 구현 대상

- `intermediate.int__user__retention_spine`(Gold 내부용, BI 접근 금지)
- `gold.mart_kpi_user_daily`
- Intermediate/Gold schema 및 singular data test
- PR #29의 `silver_events_v2`, `silver__users`를 `ref()`로 사용하는 입력 계약

#### 현재 범위에서 제외

- Bronze 및 Silver 모델 수정
- Silver User ID 후보 선정 수정
- Silver User 속성 선정 수정
- Silver User MERGE 수정
- 별도 Gold `fct_*`
- `agg_*`
- 별도 D0~N 코호트 리텐션 Mart 및 Superset Virtual Dataset
- 퍼널 전용 Gold Mart
- 사용자 속성·상태 SCD
- 여러 `user_pseudo_id`를 통합하는 `user_key`
- 실제 Event 시점 로그인 KPI
- `is_logged_in`
- `used_real_estate_flg`
- `used_club_flg`
- Gold 증분 최적화

퍼널 BI가 필요하면 `funnel_stage`, `step_order`, `stage_scope`를 사용하는 별도 Grain의 Gold Mart를 설계한다. 해당 Mart도 Silver를 직접 참조한다.

선택형 D0~D365 코호트 리텐션은 제외 대상이 아니다. 별도 Mart 없이 `mart_kpi_user_daily`의 경과일·리텐션 컬럼을 Superset이 필터 및 집계하며, BI에서 LOD나 Virtual Dataset을 사용하지 않는다(5.8.7절).

#### 5.14.1 Stage Gold 구현 — 2026-08-06 이력 검증 (As-Is)

- Stage Silver 스키마 확인
- Event/User Grain 및 relationship 검증
- Event 기반 USER×DAY 생성
- 활동·대표 디바이스·서비스 플래그 검증
- 누락된 User 4개 컬럼은 구조 검증용 임시값(Typed Placeholder, 5.6절) 사용
- 가입 및 MySQL 지표는 운영 입력 전까지 검증 완료로 간주하지 않음
- Stage Gold를 운영 BI에 연결하지 않음

#### 5.14.2 PR #29 병합 후 Stage 배포·검증

PR #29 코드는 원격 `main`에 병합됐지만 Stage `silver_events_v2`는 아직 없다. 아래는
Silver 담당자가 Stage target에 병합 모델을 실행한 뒤 Gold가 수행해야 할 검증 순서다.
문서 작성은 dbt 실행을 뜻하지 않는다. 다만 2026-09-09 직접 조회한 Stage User 4개 컬럼·타입·기본 값 적재 확인은 완료로 표시하며, 남은 데이터 품질·모델 실행 검증과 구분한다.

Gold 구현은 Stage Silver 물리 테이블 생성을 기다리지 않고 **코드 작성과 정적 컴파일 검증까지만**
먼저 진행할 수 있다. 단, dbt는 원격 저장소가 아니라 현재 로컬 checkout의 모델 그래프를
읽으므로 로컬 작업 트리에 `silver_events_v2`와 `silver__users` 정의가 실제로 있어야 한다.

2026-08-25 로컬 `main`은 사용자 확인 후 PR #29 병합 커밋 `3886d4f`로 fast-forward했다.
두 Silver 모델과 `_app_db__sources.yml`이 로컬에 존재하며 Gold/Intermediate 참조도 해당
node로 전환했다. 기존 Gold·test·문서 및 환경 파일은 보존했고 GitHub PR 병합이나 BigQuery
배포는 수행하지 않았다. 다음 정적 검증 조건을 적용한다.

- `git status --short`와 `git diff --name-status HEAD..origin/main`으로 로컬 변경과 원격 변경의
  경로 충돌 여부 확인
- `rg --files dbt/models/silver`와 `dbt ls`로 두 Silver node가 로컬 manifest 대상에 포함됐는지 확인
- `dbt_project.yml`의 `intermediate` 블록과 `generate_schema_name` 결과 확인

로컬 파일 및 YAML 정적 확인은 완료했다. Docker Desktop daemon이 꺼져 있어 기존
`dbt-bigquery:1.9.latest` 컨테이너를 이용한 `parse/ls/compile`은 대기 상태다. 이 검증은
이미지를 pull/build하거나 Airflow/Superset 서비스를 재시작하지 않고, bind mount된 현재
`dbt/` 코드를 대상으로 수행한다.

로컬 최신화는 다음 확인 순서로 완료했다. 이는 이미 병합된 원격 `main`을 로컬이 따라간
fast-forward이며 새로운 GitHub PR 병합이 아니다.

```bash
git fetch origin
git status --short
git diff --name-status HEAD..origin/main
git merge --ff-only origin/main
git rev-parse --short HEAD
```

원격 변경은 Silver 경로 6개 파일에 한정돼 Gold·test·문서 경로와 겹치지 않았고,
`AGENTS.md` 수정과 untracked 환경·Gold·test·문서를 유지한 채 완료됐다. 별도 stash나
commit은 만들지 않았다.

위 선행 조건을 만족하면 다음 작업은 허용한다.

- `int__user__retention_spine.sql` 작성
- `mart_kpi_user_daily.sql`과 schema/test 계약 재작성
- 네 Source 환경변수를 명시한 `dbt parse`, `dbt ls`, `dbt compile`
- 컴파일 SQL과 `manifest.json`의 참조 관계·최종 Source project/dataset 검증

이 단계의 성공은 Jinja, `ref()`, 컬럼 계약과 의존 그래프에 대한 **정적 검증**일 뿐 실제
데이터 품질 검증이 아니다. Stage `silver_events_v2`와 PR #29 기준 `silver__users`가 실제로
생성되고 5.12절 입력 테스트를 통과하기 전에는 Intermediate·Gold의 `dbt run`, `dbt build`,
데이터 테스트 및 결과 테이블 검증을 수행하지 않는다. 기존 레거시 테이블이나 Typed
Placeholder로 실행 단계를 우회하지 않는다.

- 네 Source 환경변수 명시 및 컴파일된 project/dataset preflight 통과(5.6.1절)
- Stage `silver_events_v2`의 세 분류 컬럼과 pseudo ID Null 분포 확인
- [완료: 2026-09-09 직접 조회] Stage `silver__users` 4개 컬럼·타입·기본 값 적재 확인(5.5.3절). [대기] 의미·허용값·매핑·관계 검증
- Gold 입력은 처음부터 `ref('silver_events_v2')`, `ref('silver__users')`를 사용하고 Typed Placeholder를 두지 않음
- non-null pseudo Event/User relationship 누락 0 확인
- `int__user__retention_spine`을 Stage에 생성하고 Intermediate 차단 테스트 통과
- 최초 방문 D0~D365 Spine 및 실제 가입 D0~D365 Spine 생성
- 사용자가 선택한 N에 대한 정확한 DN 및 D0~DN 결과 검증
- `event_complete_start_dt`, `event_complete_dt` 기준 경과일·플래그 Null/0/1 검증
- Full Refresh로 38개 컬럼과 실제 지표 생성
- Stage Gold 전체 테스트(5.12절) 통과
- Stage의 짧은 Event 기간으로는 D365 비용을 승인하지 않고 계산 정확성만 검증
- Stage 결과를 운영 BI에 연결하지 않음

#### 5.14.3 운영 Gold 구현

실제 운영 절차에서는 Stage(`koin-stage-438512`) Silver·Intermediate·Gold 검증을 먼저
통과해야 한다. 멘토 또는 배포 승인권자의 승인 없이는 Production(`kap-chat`)에
Intermediate·Gold를 배포하거나 Superset을 연결하지 않는다.

- 운영 Silver 승격 및 필수 컬럼 확인
- `_temp` 참조 제거
- `ref('silver_events_v2')`, `ref('silver__users')` 사용
- Gold-owned `ref('int__user__retention_spine')` 사용
- 최초 방문·가입 D0~D365 USER×DAY Spine 활성화
- `event_complete_start_dt`~`event_complete_dt` 평가 가능 범위 적용
- Full Refresh로 최종 38개 컬럼 생성
- 운영 사용자 수 기준 D365 예상 행 수·저장량·실행 시간·스캔 비용 산정
- Full Refresh 운영 기준 통과 또는 증분 전환 완료를 BI 연결 차단 조건으로 확인
- Silver 입력 차단 테스트 통과
- Gold 테스트 통과
- Stage 배포 및 결과 검증
- 멘토 승인 후 Production 배포와 BI 연결

#### 5.14.4 2차 최적화

1차 Full Refresh를 정확성 기준 결과로 검증한 후 다음을 별도 작업으로 진행한다. 다만 운영 규모 평가에서 Full Refresh가 승인된 실행 시간·비용 기준을 넘으면 증분 전환은 BI 연결 전 필수 항목으로 승격한다.

- 1차 구조에서는 Intermediate가 Event 발생 USER×DAY를 만들기 위해 `silver_events_v2`를
  읽고, Gold도 활동·대표 디바이스·서비스 지표를 계산하기 위해 같은 Silver Event를 다시
  읽는다. 현재 약 65.9만 행 규모에서는 책임 분리와 계산 정확성을 우선해 이 중복 스캔을
  허용하되, dry run 예상 bytes·실제 처리 bytes·실행 시간을 두 모델별로 기록한다.
- 중복 스캔이 승인 비용·시간 기준을 넘을 때만 공통 `int__user__daily_activity` 도입 또는
  Intermediate 출력 확장을 검토한다. 이 경우에도 Entry 정의와 `entry_event_cnt_day` 계산은
  한 곳에만 두며, Intermediate와 Gold에 리텐션 판정 로직을 다시 이중화하지 않는다.
- Intermediate와 Gold의 `event_dt` 증분 `insert_overwrite`
- 실행 날짜 파라미터
- 전일 Entry Lookback
- D0~D365 Spine과 Event 완전 가용 완료일 전진에 따른 영향 파티션 재계산
- Silver User 현재 속성 변경 영향 처리
- Full Refresh와 증분 실행 결과 동등성 테스트

#### 5.14.5 최종 운영 원칙 — To-Be

현재 작업 범위는 Gold 계층으로 한정한다.

Gold는 운영 Silver Event와 Silver User를 직접 참조해 USER×DAY Mart를 생성하고, Silver의 Event 중복 제거·대표 사용자 선정·사용자 속성 결정을 다시 수행하지 않는다.

최종 Gold 계약은 38개 컬럼이며 다음 세 컬럼은 완전히 제거한다.

```text
is_logged_in
used_real_estate_flg
used_club_flg
```

1차 Intermediate와 Gold는 Full Refresh로 구현한다. 실제 운영 단계에서는 PR #29 모델을
Stage target에 실행한 뒤 Event 분류, pseudo ID Null 제외, User 추가 4개 컬럼과 선택형
리텐션을 검증한다. 이 문서는 해당 실행을 대신하지 않는다.

Silver 입력 계약 또는 Event/User relationship이 깨지면 Gold에서 임의 보정하지 않고 배포를 중단한다. Silver 내부의 알려진 제한(5.5.4절, 5개 항목)은 Gold 입력 warn 테스트로 감시하고 Silver 담당자에게 전달한다.

Stage 검증과 멘토 승인 후에만 Production 및 BI에 연결한다. Gold 증분 최적화는 1차 정확성 검증 이후 별도 작업으로 진행한다.

**실제 배포 상태(2026-08-25 읽기 전용 재확인)**: PR #29는 원격 `main`에 병합됐다.
Stage에는 2026-08-10 생성된 기존 `silver__users`와 추가 4개 컬럼이 있지만
`silver_events_v2`는 없다. 이 Stage User는 PR 병합 후 실행 결과가 아니다. Production에는
`silver_events_v2`와 `silver__users`가 모두 없고 `gold` 데이터셋도 없다. Stage `gold`
데이터셋에도 테이블이 없다. 따라서 **코드 병합 완료, BigQuery 배포·품질 검증 미완료**다.

**잔여 항목 3개 전부 종결(2026-08-06, 실제 BigQuery 재검증 완료)**:
- `entry_year` 타입 통일 — Stage INT64, Prod STRING 확정, Gold 출력 단 `SAFE_CAST` 정규화로 종결(4.6절, 5.8.1절)
- Stage vs 기존 Prod(`kap-chat`) KPI 비교 — 서로 다른 GA4 속성이라 비교 자체가 성립하지 않는다는 결론으로 종결(4.10절, 2장 5번)
- IAM 최소권한화 — 목표 역할 확정, 실행은 사용자 선택으로 보류(2장 3번)

#### 5.14.6 BI(Superset) 제약과 코호트/리텐션 설계 원칙 (2026-08-01, BCSDLab Slack)

이상민-김창윤 Slack에서 코호트 리텐션 계산 방식을 논의한 결과, 다음이 확정됐다.

**2026-08-25 멘토 피드백 반영**: 코호트와 리텐션은 중요한 지표이므로 Gold 범위에서
제외하지 않는다. Superset에서 `LAG` 등 윈도우 계산을 안정적으로 수행하기 어렵기 때문에
Silver와 Gold 사이에 Gold-owned Intermediate를 두고 미리 계산한다. Bronze와 Silver 사이의
Staging은 다양한 원천 스키마를 먼저 표준화해야 할 때 유효하지만, 현재 GA4 중심 구조에는
추가하지 않는다. 이 결정은 BI 공개 Gold 테이블 하나 원칙과 양립한다. Intermediate는
내부 계산·테스트 모델이고 Superset은 최종 Gold만 조회한다.

- **Superset은 LOD(Level of Detail) 계산을 지원하지 않는다.** (이상민이 직접 확인: "슈퍼셋에서 lod 지원안한다고 하네요") 레거시 대시보드는 LOD를 최대 4개까지 써서 코호트 리텐션을 만들었는데, 김창윤님도 "이게 많으쓰면 성능도 구려지고" 문제가 있었다고 인정함.
- 대안은 두 가지였다: (1) 값을 미리 계산해서 가져오거나, (2) LOD를 안 쓰는 방법을 찾거나. **(1)로 결정.**
- 이상민이 "코호트 전용 마트를 하나 더 만드는 건 어떤가요?"를 제안했으나, **기각됨.** 근거:
  - 레거시에서 코호트 리텐션 하나에 LOD가 4개 필요했던 걸 그대로 마트로 옮기면 마트가 3~4개 더 늘어나고, BI 연결 마트가 총 5개까지 늘어날 수 있음.
  - 김창윤: "마트는 적을수록 좋아요, bi가 뜨는 게 빨라져서." 이상민: "일단 최대한 적게 만들어볼게요." 김창윤: "성묵님은 1개를 좋아하시긴 할걸요."
- **2026-08-25 수정 결론: 코호트/리텐션 관련 계산은 별도 BI 공개 Mart나 Virtual Dataset을 만들지 않는다. Gold-owned Intermediate에서 미리 계산한 뒤 `mart_kpi_user_daily`에 포함해 제공한다.**
- **2026-08-18 변경**: D1/D7/D14/D30 컬럼을 계속 추가하는 방식 대신, D0~D365 USER×DAY Spine과 `days_since_*`, `is_*_retained` 컬럼으로 일반화했다. Superset은 사용자가 선택한 N으로 경과일을 필터링한다.
- 물리 Gold 테이블은 계속 1개다. 행 수 증가는 Stage에서 실측하고, 1차 Full Refresh의 실행 시간·스캔량이 허용 범위를 넘으면 최대 리텐션 기간을 조정한다.

---

## 6. BI 대시보드 카탈로그 — 현재 지원 범위와 확장 요구 (2026-09-09)

5장이 Gold의 데이터 계약이라면 이 장은 Superset의 집계·표현 계약이다. 6.1~6.10은 기존 38컬럼 기준의 지원 카탈로그이며, 확정 KPI 정의는 6.11, 전체 점검은 6.12, 최신 10개 구성요소와 확장 구조의 연결은 6.13을 따른다. 전체 요구를 기존 38컬럼만으로 지원한다는 의미가 아니다.

이 장의 모든 Metric·차트는 5.8.7절의 BI 연결 원칙(Superset은 LOD에 의존하지 않고, Gold가 사전 계산한 값을 합계·개수·비율로만 다룬다)을 따른다.

작성 기준: `gold.mart_kpi_user_daily` 최종 38개 컬럼 계약

> **배포 전제**: PR #29의 두 Silver 모델이 정상 배포되고, Intermediate·Gold 테스트와
> 운영 규모 비용 게이트를 통과한 뒤 `gold.mart_kpi_user_daily`가 생성된 상태를 대상으로
> 한다. 현재 BigQuery에 Intermediate나 Gold 테이블이 존재한다는 뜻은 아니다.

---

### 6.1 목적

`gold.mart_kpi_user_daily` 하나를 Superset Dataset으로 연결했을 때 만들 수 있는 KPI, 차트, 필터와 대시보드 구성을 정의한다.

Superset 연결은 BigQuery의 `gold.mart_kpi_user_daily`를 직접 가리키는 **Physical Dataset**을
기본으로 한다. Event/User Join과 리텐션 Spine 계산은 dbt Gold SQL에서 끝내며, Superset
Virtual Dataset이나 BI 계층의 임의 Join으로 재구현하지 않는다. Dataset 접근 권한은
일반 대시보드 소비자와 개별 식별자 조회가 필요한 제한된 운영 사용자를 분리한다.

대시보드마다 별도의 Gold Mart를 만들지 않는다. 아래 구성요소는 모두 동일한 `gold.mart_kpi_user_daily`를 사용한다.

```text
gold.mart_kpi_user_daily
  ├─ 종합 KPI 대시보드
  ├─ 사용자 활동 대시보드
  ├─ 신규 방문·가입 대시보드
  ├─ 전체 사용자·가입 코호트 리텐션 대시보드
  ├─ 서비스 이용 대시보드
  ├─ 플랫폼·디바이스 대시보드
  └─ 사용자 구성·계정 상태 대시보드
```

대시보드 수와 Mart 수는 일대일 관계가 아니다. 여러 대시보드가 하나의 Gold Dataset을 공유한다.

---

### 6.2 데이터 해석의 기본 원칙

#### 6.2.1 Grain

Gold Mart의 Grain은 다음과 같다.

```text
event_dt × user_pseudo_id당 1행
```

따라서 일간 사용자 수는 `COUNT(*)`로 계산하지 않고 목적에 맞는 플래그를 합산한다.

```sql
-- Entry 기준 일간 활성 사용자
SUM(is_active_entry)

-- Event 1건 이상 기준 일간 활성 사용자
SUM(is_active_any_event)
```

`COUNT(*)`에는 Event가 없는 리텐션 Spine 행도 포함되므로 DAU로 사용하지 않는다.

#### 6.2.2 사용자 기준

모든 기본 사용자 수와 리텐션은 `user_pseudo_id` 기준이다.

- `user_pseudo_id`: Gold Grain과 KPI의 기본 사용자 식별자
- `user_id`: Silver가 선정한 보조 식별자
- 하나의 `user_id`에 여러 `user_pseudo_id`가 연결될 수 있음
- 계정 기준 사용자 수와 Gold의 사용자 수는 서로 다를 수 있음

`COUNT(DISTINCT user_id)`는 정확한 계정 수가 아니라 **non-null 대표 ID 수**다 — `user_id`가 anonymous 형식일 수도 있어(5.5.1절) 전부 실제 MySQL 계정이라는 보장이 없다. 참고용 보조 지표로만 사용하고, 기본 사용자 KPI와 혼용하지 않는다. 실제 MySQL 매핑 계정 수가 필요하면 `COUNT(DISTINCT CASE WHEN is_mysql_mapped THEN user_id END)`처럼 `is_mysql_mapped` 조건을 명시해야 한다.

#### 6.2.3 사용자 속성의 시점

다음 컬럼은 Silver User의 현재 Snapshot이다.

```text
gender
major
entry_year
user_type
is_deleted
is_mysql_mapped
```

과거 Event 행에도 현재 속성이 붙는다. 따라서 이를 이용한 과거 추이는 "당시의 사용자 속성"이 아니라 "현재 속성으로 다시 구분한 과거 활동"이다.

#### 6.2.4 리텐션 Spine 행

최초 방문일 또는 가입일로부터 D365까지 Event가 없는 날짜에도 사용자 행이 생성될 수 있다. 이 행은 다음 특징을 가진다.

```text
event_cnt_day = 0
is_active_any_event = 0
is_active_entry = 0
```

따라서 활성 사용자 수는 반드시 활성 플래그를 합산하거나 조건부 `COUNT(DISTINCT)`로 계산한다. 단순 `COUNT(*)` 또는 무조건적인 `COUNT(DISTINCT user_pseudo_id)`를 DAU·WAU·MAU로 사용하지 않는다.

#### 6.2.5 리텐션 기준

전체 사용자 리텐션은 `first_seen_dt`, 가입 사용자 리텐션은 `first_signup_dt`를 시작일로 한다. 사용자가 N을 선택하면 다음 두 형태를 구분해 제공한다.

- 정확한 DN 리텐션: 시작일+N일 당일 Entry 활동 비율
- D0~DN 리텐션 곡선: 각 경과일의 정확한 당일 Entry 활동 비율

N은 0~365 범위에서 선택한다. 평가일이 Event 완전 가용 범위 밖이면 분모에서 제외한다.

---

### 6.3 Superset 공통 Metric 정의

#### 6.3.1 활성 사용자 Metric

```sql
-- Entry DAU
SUM(is_active_entry)

-- Any Event DAU
SUM(is_active_any_event)

-- Core Action 사용자 수
SUM(has_core_action)

-- 다중 Session 사용자 수
SUM(is_multi_session_user)
```

#### 6.3.2 활동량 Metric

```sql
-- Event 수
SUM(event_cnt_day)

-- Entry Event 수
SUM(entry_event_cnt_day)

-- Core Action Event 수
SUM(core_action_cnt_day)

-- Session 수
SUM(session_cnt_day)

-- 총 Engagement 시간(분)
SAFE_DIVIDE(SUM(engagement_msec_day), 60000)

-- 총 Engagement 시간(시간)
SAFE_DIVIDE(SUM(engagement_msec_day), 3600000)
```

#### 6.3.3 사용자당 평균 Metric

```sql
-- Any Event 활성 사용자당 Event 수
SAFE_DIVIDE(
  SUM(event_cnt_day),
  SUM(is_active_any_event)
)

-- Any Event 활성 사용자당 Session 수
SAFE_DIVIDE(
  SUM(session_cnt_day),
  SUM(is_active_any_event)
)

-- Any Event 활성 사용자당 Engagement 시간(분)
SAFE_DIVIDE(
  SUM(engagement_msec_day),
  SUM(is_active_any_event) * 60000
)

-- Session당 Engagement 시간(분)
SAFE_DIVIDE(
  SUM(engagement_msec_day),
  SUM(session_cnt_day) * 60000
)

-- Session당 Event 수
SAFE_DIVIDE(
  SUM(event_cnt_day),
  SUM(session_cnt_day)
)
```

#### 6.3.4 활동 품질 비율 Metric

```sql
-- Entry 활성률: Any Event 사용자 중 Entry 사용자 비율
SAFE_DIVIDE(
  SUM(is_active_entry),
  SUM(is_active_any_event)
)

-- Core Action 사용자율
SAFE_DIVIDE(
  SUM(has_core_action),
  SUM(is_active_any_event)
)

-- 다중 Session 사용자율
SAFE_DIVIDE(
  SUM(is_multi_session_user),
  SUM(is_active_any_event)
)

-- 사용자당 Entry Event 수
SAFE_DIVIDE(
  SUM(entry_event_cnt_day),
  SUM(is_active_any_event)
)

-- 사용자당 Core Action 수
SAFE_DIVIDE(
  SUM(core_action_cnt_day),
  SUM(is_active_any_event)
)
```

#### 6.3.5 신규 방문·가입 Metric

```sql
-- 신규 GA4 사용자 수
SUM(is_new_user)

-- 신규 가입 pseudo 사용자 수(계정 수 아님 — 아래 pseudo vs 계정 기준 참고)
SUM(is_new_signup)

-- 신규 사용자 중 당일 활동 사용자 수
SUM(
  CASE
    WHEN is_new_user = 1 AND is_active_any_event = 1 THEN 1
    ELSE 0
  END
)

-- 신규 가입 pseudo 사용자 중 가입일 활동 사용자 수
SUM(
  CASE
    WHEN is_new_signup = 1 AND is_active_any_event = 1 THEN 1
    ELSE 0
  END
)

-- 가입일 활동률
SAFE_DIVIDE(
  SUM(CASE WHEN is_new_signup = 1 AND is_active_any_event = 1 THEN 1 ELSE 0 END),
  SUM(is_new_signup)
)

-- 가입일 Entry 활동률
SAFE_DIVIDE(
  SUM(CASE WHEN is_new_signup = 1 AND is_active_entry = 1 THEN 1 ELSE 0 END),
  SUM(is_new_signup)
)
```

`SUM(is_new_signup) / SUM(is_new_user)`는 동일한 모집단을 순서대로 통과한 전환율이 아니므로 공식 가입 전환율로 사용하지 않는다. 참고 비율로 표시하려면 "신규 GA4 사용자 대비 가입 발생 비율"처럼 제한된 의미를 제목에 명시한다.

**pseudo 기준 vs 계정 기준(2026-08-06 추가)**: `SUM(is_new_signup)`은 Gold Grain에 따른 신규 가입 `user_pseudo_id` 수이며 실제 KOIN 계정 수가 아니다(하나의 `user_id`에 여러 `user_pseudo_id`가 연결될 수 있음, 6.2.2절). MySQL 매핑 계정 기준 신규 가입자 수가 필요하면 다음 보조 Metric을 별도로 쓴다. 이건 "신규 가입 계정 수(MySQL 매핑 기준)"로 이름 붙이고 기본 가입 코호트/리텐션 Metric과 혼용하지 않는다.

```sql
COUNT(DISTINCT CASE
  WHEN is_new_signup = 1
   AND is_mysql_mapped
  THEN user_id
END)
```

#### 6.3.6 전일 Entry 동시 활동 Metric

```sql
-- 오늘 Entry 활동자 중 전일에도 Entry 활동한 사용자 수
SUM(
  CASE
    WHEN is_active_entry = 1 AND had_entry_prev_day = 1 THEN 1
    ELSE 0
  END
)

-- 오늘 Entry 활동자 중 전일 Entry 동시 활동 비율
SAFE_DIVIDE(
  SUM(CASE WHEN is_active_entry = 1 AND had_entry_prev_day = 1 THEN 1 ELSE 0 END),
  SUM(is_active_entry)
)
```

이 비율은 가입 코호트 D1 리텐션이 아니다. 또한 `had_entry_prev_day = 0`이라고 해서 이탈 또는 재활성 사용자라고 단정하지 않는다.

#### 6.3.7 기간 사용자 수 Metric

```sql
-- 선택 기간 활성 user_pseudo_id 수
COUNT(DISTINCT CASE
  WHEN is_active_any_event = 1 THEN user_pseudo_id
END)

-- 선택 기간 Entry 활성 user_pseudo_id 수
COUNT(DISTINCT CASE
  WHEN is_active_entry = 1 THEN user_pseudo_id
END)

-- 선택 기간 식별된 user_id 수(보조 지표)
COUNT(DISTINCT CASE
  WHEN is_active_any_event = 1 THEN user_id
END)
```

일별 시계열에서 `SUM(is_active_any_event)`는 DAU다. 주·월 단위 고유 사용자 수는 시간 Grain을 주·월로 바꾸고 다음처럼 `is_active_any_event = 1` 조건을 명시한 `COUNT(DISTINCT CASE ... END)`를 사용한다(가입만 하고 활동이 없는 Spine 행이 섞이면 안 되므로 단순 `COUNT(DISTINCT user_pseudo_id)`는 쓰지 않는다).

```sql
COUNT(DISTINCT CASE
  WHEN is_active_any_event = 1 THEN user_pseudo_id
END)
```

달력 주간 WAU와 달력 월간 MAU는 만들 수 있지만, 매일 직전 7일·30일을 보는 Rolling WAU/MAU는 일반 집계 Metric만으로 계산하지 않는다. Rolling 지표가 필요하면 Superset Virtual Dataset의 명시적 SQL이나 별도 요구사항 검토가 필요하다.

#### 6.3.8 선택형 리텐션 Metric

```sql
-- 전체 사용자: days_since_first_seen = N 필터 후 평가 가능 사용자 수
COUNT(is_first_seen_retained)

-- 전체 사용자 정확한 DN 리텐션율
SAFE_DIVIDE(
  SUM(is_first_seen_retained),
  COUNT(is_first_seen_retained)
)

-- 가입 사용자: days_since_signup = N 필터 후 정확한 DN 리텐션율
SAFE_DIVIDE(
  SUM(is_signup_retained),
  COUNT(is_signup_retained)
)

-- D0~DN 곡선: days_since_first_seen BETWEEN 0 AND N 필터 후
-- days_since_first_seen으로 그룹화하고 같은 정확한 DN Metric 사용
```

`days_since_first_seen`과 `days_since_signup`이 같은 USER×DAY 행에서 모두 non-null이면
`is_first_seen_retained`와 `is_signup_retained`의 값은 항상 같다. 두 플래그가 모두 그날의
`is_active_entry`에서 파생되기 때문이다. 이는 중복 계산 오류가 아니라 의도된 결과다.

두 리텐션 지표의 차이는 활동 판정값이 아니라 **기준일·경과일·평가 가능 모집단**이다.

- 전체 사용자 리텐션 분모: `COUNT(is_first_seen_retained)`
- 가입 사용자 리텐션 분모: `COUNT(is_signup_retained)`
- 미가입 pseudo 사용자는 가입 리텐션 분모에 포함되지 않음
- 같은 사용자라도 `first_seen_dt`와 `first_signup_dt`가 다르면 동일 `event_dt`의 경과일이 다름

따라서 두 플래그가 같은 행에서 같다는 이유로 하나를 제거하거나, 한 기준의 경과일 필터와
다른 기준의 플래그를 결합하지 않는다.

대시보드의 N 선택값은 0~365다. 전체 사용자 차트는 `days_since_first_seen`, 가입 사용자 차트는 `days_since_signup`에 적용한다. 코호트 그룹은 각각 `first_seen_dt`, `first_signup_dt`를 사용한다.

Heatmap은 반드시 코호트 기준일(`first_seen_dt` 또는 `first_signup_dt`)과 해당 경과일을 함께 그룹화한다. 반면 선택한 코호트 기간 전체의 리텐션 곡선과 단일 DN KPI는 코호트 기준일을 행·열에 표시하지 않고 경과일별로 통합 집계할 수 있다. 이 경우에도 해당 코호트 날짜 범위를 필터로 명시하고 `COUNT(is_*_retained)` 분모를 함께 표시한다. 코호트 날짜 필터 없이 전체 이력을 통합한다면 차트 제목에 `전체 평가 가능 코호트 통합`임을 명시한다. 경과일마다 평가 가능 분모가 달라질 수 있으므로 분모를 숨긴 채 서로 다른 DN 비율만 비교하지 않는다.

경과일과 플래그는 반드시 같은 기준끼리 사용한다. `days_since_first_seen`은 `is_first_seen_retained`하고만, `days_since_signup`은 `is_signup_retained`하고만 결합한다. 교차 조합은 오류 없이 무의미한 숫자를 만들 수 있으므로 금지한다.

기본 리텐션율은 평가 가능 분모가 30명 이상일 때만 표시한다. 30명 미만이면 비율은 Null 또는 숨김 처리하고 `COUNT(is_*_retained)` 분모는 함께 노출한다. 최소 분모는 Gold 컬럼 계약이 아니라 Superset 표시 정책이다.

#### 6.3.9 서비스 이용 Metric

```sql
SUM(used_shop_flg)
SUM(used_cafeteria_flg)
SUM(used_bus_flg)
SUM(used_board_flg)
SUM(used_facility_flg)
SUM(used_timetable_flg)
SUM(used_grad_calc_flg)
SUM(used_account_flg)
```

각 합계는 **해당 날짜(단일 `event_dt`)** 에 서비스를 이용한 `user_pseudo_id` 수다.

서비스 이용률을 동일한 기준으로 비교할 때는 Any Event 활성 사용자를 분모로 사용한다.

```sql
-- Shop 이용률 예시
SAFE_DIVIDE(
  SUM(used_shop_flg),
  SUM(is_active_any_event)
)
```

`used_account_flg`와 `used_cafeteria_flg`는 서비스 Event 존재 기준이고, 나머지 서비스 플래그는 Entry Event 기준이다. 차트 설명에 이 차이를 명시한다.

**⚠️ 여러 날짜를 합칠 때는 SUM이 아니라 COUNT(DISTINCT)를 쓴다(2026-08-06 추가)**: 위 `SUM(used_*_flg)`는 하루 단위에서만 "그날의 고유 이용 사용자 수"와 같다. 주/월처럼 여러 날짜를 하나로 합친 기간의 고유 이용 사용자 수를 구할 때 `SUM`을 그대로 쓰면 같은 사용자가 여러 날 이용한 걸 중복 카운트해 **고유 사용자 수가 아니라 서비스 이용 USER×DAY 수**가 나온다. 이 경우 다음처럼 계산한다.

```sql
-- 선택 기간(주/월) 내 Shop 고유 이용 사용자 수
COUNT(DISTINCT CASE WHEN used_shop_flg = 1 THEN user_pseudo_id END)
```

6.4.5절(서비스 이용 대시보드)의 주간/월간 고유 이용 사용자 차트는 이 방식을 따른다.

#### 6.3.10 계정·매핑 상태 Metric

```sql
-- 활성 사용자 중 MySQL 매핑 사용자 수
SUM(
  CASE
    WHEN is_active_any_event = 1 AND is_mysql_mapped THEN 1
    ELSE 0
  END
)

-- 활성 사용자 MySQL 매핑률
SAFE_DIVIDE(
  SUM(CASE WHEN is_active_any_event = 1 AND is_mysql_mapped THEN 1 ELSE 0 END),
  SUM(is_active_any_event)
)

-- 활성 사용자 중 현재 탈퇴 상태 사용자 수
SUM(
  CASE
    WHEN is_active_any_event = 1 AND is_deleted IS TRUE THEN 1
    ELSE 0
  END
)

-- 탈퇴 여부 파악 가능한 활성 사용자 중 현재 탈퇴 상태 비율
-- 분모를 is_mysql_mapped가 아니라 is_deleted IS NOT NULL로 직접 잡는다
-- (Null 처리 규칙상 두 조건이 대체로 같이 움직이지만, 분모를 실제 측정 대상 필드로 명시하는 게
--  더 안전하다 — 11절 Null 규칙이 깨지는 예외가 생겨도 이 비율은 항상 올바르게 계산된다)
SAFE_DIVIDE(
  SUM(CASE WHEN is_active_any_event = 1 AND is_deleted IS TRUE THEN 1 ELSE 0 END),
  SUM(CASE WHEN is_active_any_event = 1 AND is_deleted IS NOT NULL THEN 1 ELSE 0 END)
)
```

`is_mysql_mapped`와 `is_deleted`는 현재 Snapshot이므로 해당 날짜 당시의 매핑·탈퇴 상태 추이로 해석하지 않는다.

---

### 6.4 권장 대시보드 전체 구성

#### 6.4.1 종합 KPI 대시보드

서비스 상태를 한 화면에서 확인하는 경영·운영 요약 화면이다.

##### 상단 KPI 카드

| 구성요소 | Metric | 권장 비교 |
| --- | --- | --- |
| Entry DAU | `SUM(is_active_entry)` | 전일, 전주 동일 요일 |
| Any Event DAU | `SUM(is_active_any_event)` | 전일, 전주 동일 요일 |
| 신규 GA4 사용자 | `SUM(is_new_user)` | 전일, 전주 |
| 신규 가입 pseudo 사용자 | `SUM(is_new_signup)` | 전일, 전주 |
| Session 수 | `SUM(session_cnt_day)` | 전일, 전주 |
| Core Action 사용자 | `SUM(has_core_action)` | 전일, 전주 |
| 선택 DN 전체 사용자 리텐션율 | `SAFE_DIVIDE(SUM(is_first_seen_retained), COUNT(is_first_seen_retained))` | 선택 N, 최초 방문 코호트 |
| 선택 DN 가입 리텐션율 | `SAFE_DIVIDE(SUM(is_signup_retained), COUNT(is_signup_retained))` | 선택 N, 가입 코호트 |

최근 코호트는 선택한 N일까지 아직 성숙하지 않았을 수 있으므로 종합 카드에는 선택 N, 데이터 완료 기준일과 평가 가능 사용자 수를 함께 표시한다.

##### 주요 차트

1. 일별 Entry DAU와 Any Event DAU 추이 — 2개 Line
2. 일별 신규 사용자와 신규 가입 pseudo 사용자 추이 — 2개 Line 또는 Bar
3. 일별 Event·Session 추이 — Mixed Chart
4. 일별 Core Action 사용자율 — Line
5. 서비스별 일간 이용 사용자 — Stacked Bar 또는 Multi-line
6. 코호트별 선택 DN 리텐션 — Multi-line
7. 플랫폼별 활성 사용자 구성 — Stacked Area

#### 6.4.2 사용자 활동 대시보드

##### KPI 카드

- Entry DAU
- Any Event DAU
- 선택 기간 고유 활성 사용자
- Event 수
- Entry Event 수
- Core Action Event 수
- Session 수
- 총 Engagement 시간
- 활성 사용자당 Event 수
- 활성 사용자당 Session 수
- Session당 Engagement 시간

##### 시계열 차트

| 차트 | 시간 기준 | Metric |
| --- | --- | --- |
| 일별 활성 사용자 | `event_dt` | Entry DAU, Any Event DAU |
| 일별 활동량 | `event_dt` | Event, Entry Event, Core Action Event |
| 일별 Session | `event_dt` | Session 수, 다중 Session 사용자 수 |
| 일별 Engagement | `event_dt` | 총 시간, 사용자당 시간, Session당 시간 |
| 일별 활동 품질 | `event_dt` | Entry 활성률, Core Action 사용자율 |
| 전일 연속 Entry 활동 | `event_dt` | 전일 Entry 동시 활동 사용자 수와 비율 |

##### 분포 및 구성 차트

- 사용자별 일간 Event 수 분포: `event_cnt_day` Histogram
- 사용자별 일간 Session 수 분포: `session_cnt_day` Histogram
- 사용자별 일간 Engagement 분포: `engagement_msec_day` Histogram
- 단일 Session 대 다중 Session 사용자 비율: `is_multi_session_user`
- Core Action 보유/미보유 사용자 구성: `has_core_action`
- Entry 활동/기타 Event 활동 사용자 구성: `is_active_entry`, `is_active_any_event`

Histogram은 Event가 없는 리텐션 Spine 행을 제외하기 위해 `is_active_any_event = 1` 필터를 적용한다.

#### 6.4.3 신규 방문·가입 대시보드

##### KPI 카드

- 신규 GA4 사용자 수
- 신규 가입 pseudo 사용자 수
- 신규 가입 계정 수(MySQL 매핑 기준, 보조 지표)
- 가입일 활동 사용자 수
- 가입일 활동률
- 가입일 Entry 활동률
- 가입 사용자 중 MySQL 매핑 사용자 수

##### 차트

1. 일별 신규 GA4 사용자 추이
2. 일별 신규 가입 pseudo 사용자 추이
3. 신규 사용자와 가입 발생 추이 비교
4. 가입일 활동률 추이
5. 가입자 `user_type` 구성
6. 가입자 성별 구성
7. 가입자 학과 구성 Top N
8. 가입자 입학 연도 구성
9. 가입자 대표 플랫폼·디바이스·OS 구성
10. 최초 방문일과 가입일 차이 분포

최초 방문부터 가입까지 소요일은 가입일 행에 한해 다음처럼 계산할 수 있다.

```sql
DATE_DIFF(first_signup_dt, first_seen_dt, DAY)
```

권장 필터:

```text
is_new_signup = 1
first_signup_dt IS NOT NULL
```

음수 값은 가입 시각·최초 관측 범위 또는 원천 품질 문제일 수 있으므로 별도 품질 확인 대상으로 표시한다.

#### 6.4.4 전체 사용자·가입 코호트 리텐션 대시보드

##### KPI 카드

- 선택한 N
- 선택 DN 평가 가능 전체 pseudo 사용자 수
- 선택 DN 전체 사용자 잔존 수와 리텐션율
- 선택 DN 평가 가능 가입 pseudo 사용자 수
- 선택 DN 가입 잔존 수와 리텐션율
- D0~DN 일별 리텐션 곡선

##### 차트

1. 최초 방문 코호트 × D0~DN Retention Heatmap
2. 가입 코호트 × D0~DN Retention Heatmap
3. 최초 방문일·주차·월별 선택 DN 리텐션 추이
4. 가입일·주차·월별 선택 DN 리텐션 추이
5. 사용자 유형별 리텐션 비교
6. 성별 리텐션 비교
7. 학과별 리텐션 비교
8. 입학 연도별 리텐션 비교
9. 대표 플랫폼별 리텐션 비교
10. 대표 디바이스별 리텐션 비교
11. MySQL 매핑 여부별 리텐션 비교

##### 선택형 코호트 Pivot 예시

| 최초 방문 코호트 | D0 | D1 | D2 | ... | 선택 DN |
| --- | ---: | ---: | ---: | ---: | ---: |
| 2026-W27 | 비율 | 비율 | 비율 | ... | 비율 |
| 2026-W28 | 비율 | 비율 | 비율 | ... | 비율 |

각 경과일의 분모가 다를 수 있다. 최근 코호트는 선택한 N일까지 성숙하지 않았을 수 있으므로 각 리텐션율과 `COUNT(is_*_retained)`를 함께 표시한다.

##### 필수 필터

```text
days_since_first_seen BETWEEN 0 AND <선택 N>
```

가입 리텐션 화면은 `days_since_signup BETWEEN 0 AND <선택 N>`을 사용한다. 대용량 조회에는 평가일 `event_dt` 파티션 필터도 함께 적용한다.

##### 지원 범위

현재 Mart는 D0~D365에서 사용자가 선택한 N까지의 정확한 일별 리텐션 곡선과 Heatmap을 지원한다. 365일 초과, 사용자가 임의로 정한 별도 시작일, 계정 기준 리텐션은 현재 범위에 포함하지 않는다.

#### 6.4.5 서비스 이용 대시보드

##### KPI 카드

- Shop 이용 사용자 수
- Cafeteria 이용 사용자 수
- Bus 이용 사용자 수
- Board 이용 사용자 수
- Facility 이용 사용자 수
- Timetable 이용 사용자 수
- Grad Calc 이용 사용자 수
- Account 이용 사용자 수

##### 차트

1. 서비스별 일간 이용 사용자 수
2. 서비스별 주간 고유 이용 사용자 수
3. 서비스별 월간 고유 이용 사용자 수
4. 서비스별 활성 사용자 대비 이용률
5. 서비스 이용 구성비
6. 서비스별 신규 사용자 이용률
7. 서비스별 신규 가입 pseudo 사용자 가입일 이용률
8. 서비스별 Core Action 사용자 구성
9. 플랫폼별 서비스 이용 사용자
10. 디바이스별 서비스 이용 사용자
11. 사용자 유형별 서비스 이용 사용자
12. 학과·입학 연도별 서비스 이용 사용자

**⚠️ SUM vs COUNT(DISTINCT) 주의(2026-08-06 추가)**: `used_*_flg`는 사용자·일 단위 존재 여부다. 위 2·3번(주간/월간 고유 이용 사용자 수)처럼 **여러 날짜를 합친 기간**에 대해 물을 때 `SUM(used_shop_flg)`를 그대로 쓰면 **고유 사용자 수가 아니라 서비스 이용 USER×DAY 수**가 나온다(같은 사용자가 그 주에 3일 이용했으면 3으로 잡힘). 여러 날짜의 고유 이용 사용자 수가 필요하면 반드시 다음처럼 중복을 제거한다.

```sql
-- 선택 기간(주/월) 내 Shop 고유 이용 사용자 수
COUNT(DISTINCT CASE WHEN used_shop_flg = 1 THEN user_pseudo_id END)
```

일별(단일 `event_dt`) 차트에서는 `SUM(used_shop_flg)` = 그날의 고유 이용 사용자 수가 맞다(Grain이 이미 event_dt × user_pseudo_id라서 하루 안에서는 중복이 없음) — 혼동은 여러 날짜를 하나로 합칠 때만 발생한다.

##### 사용자별 일간 이용 서비스 수

Superset Calculated Column으로 다음 값을 만들 수 있다.

```sql
used_service_cnt_day =
    used_shop_flg
  + used_cafeteria_flg
  + used_bus_flg
  + used_board_flg
  + used_facility_flg
  + used_timetable_flg
  + used_grad_calc_flg
  + used_account_flg
```

이를 이용해 다음 차트를 만들 수 있다.

- 일간 이용 서비스 수 분포
- 2개 이상 서비스 이용 사용자 수
- 다서비스 이용률
- 평균 이용 서비스 수

```sql
-- 2개 이상 서비스 이용 사용자 수
SUM(CASE WHEN used_service_cnt_day >= 2 THEN 1 ELSE 0 END)

-- 다서비스 이용률
SAFE_DIVIDE(
  SUM(CASE WHEN used_service_cnt_day >= 2 THEN 1 ELSE 0 END),
  SUM(is_active_any_event)
)

-- 활성 사용자당 평균 이용 서비스 수
SAFE_DIVIDE(
  SUM(used_service_cnt_day),
  SUM(is_active_any_event)
)
```

서비스 간 동시 이용 조합도 일간 수준에서는 계산할 수 있다.

```sql
-- Shop과 Cafeteria를 같은 날 모두 이용한 사용자 수
SUM(CASE
  WHEN used_shop_flg = 1 AND used_cafeteria_flg = 1 THEN 1
  ELSE 0
END)
```

서비스 플래그는 Event 수가 아니라 사용자별 일간 존재 여부이므로, 서비스 내 클릭 수나 기능 사용 횟수로 해석하지 않는다.

#### 6.4.6 플랫폼·디바이스 대시보드

##### KPI 및 차트

1. 대표 플랫폼별 Entry DAU
2. 대표 플랫폼별 Any Event DAU
3. 대표 플랫폼별 Event·Session 수
4. 대표 플랫폼별 Core Action 사용자율
5. 대표 플랫폼별 신규 사용자·가입 pseudo 사용자 수
6. 대표 플랫폼별 선택 DN 리텐션
7. 대표 디바이스 카테고리별 활성 사용자 구성
8. 대표 OS별 활성 사용자 구성
9. 플랫폼 × 디바이스 Pivot Table
10. 플랫폼 × OS Pivot Table
11. 디바이스별 사용자당 Event·Session·Engagement
12. OS별 서비스 이용률
13. `unknown` 플랫폼·디바이스·OS 비율

`platform_dominant`, `device_category_dominant`, `device_os_dominant`는 사용자별 일간 대표값이다. 이 차트는 Event 전체의 플랫폼 분포가 아니라 USER×DAY 대표 플랫폼 분포다.

가입일에 Event가 없는 행은 대표값이 `unknown`일 수 있으므로, 활동 플랫폼 분석에는 `is_active_any_event = 1`을 적용한다.

#### 6.4.7 사용자 구성 대시보드

##### 분석 차원

```text
gender
major
entry_year
user_type
is_mysql_mapped
is_deleted
```

##### KPI 및 차트

1. 성별 활성 사용자 수와 구성비
2. 학과별 활성 사용자 Top N
3. 입학 연도별 활성 사용자 수
4. 사용자 유형별 활성 사용자 수
5. 성별 신규 사용자·가입 pseudo 사용자 수
6. 학과별 신규 사용자·가입 pseudo 사용자 수
7. 입학 연도별 신규 사용자·가입 pseudo 사용자 수
8. 사용자 유형별 신규 사용자·가입 pseudo 사용자 수
9. 성별·학과·입학 연도별 사용자당 활동량
10. 사용자 유형별 Core Action 사용자율
11. 사용자 유형별 다중 Session 사용자율
12. 사용자 유형별 서비스 이용률
13. 사용자 속성별 선택 DN 리텐션
14. Null·미상 속성 비율

현재 Snapshot 속성이므로 장기간 추이는 "현재 속성으로 재분류한 활동"임을 대시보드 설명에 표시한다.

학과처럼 값의 종류가 많은 차원은 Top N과 `Others`를 사용한다. 사용자 수가 적은 세그먼트의 리텐션은 분모를 함께 표시하고 최소 표본 기준을 적용한다.

#### 6.4.8 계정 매핑·현재 상태 대시보드

##### KPI 카드

- 활성 사용자 중 MySQL 매핑 사용자 수
- 활성 사용자 MySQL 매핑률
- 식별된 `user_id` 수(non-null 대표 ID 수, 계정 수 아님 — 6.2.2절)
- 현재 탈퇴 상태인 활성 사용자 수
- 탈퇴 여부 파악 가능한 활성 사용자 중 현재 탈퇴 상태 비율(분모: `is_deleted IS NOT NULL`)

##### 차트

1. 활동 사용자 MySQL 매핑/미매핑 구성
2. 신규 사용자 MySQL 매핑 구성
3. 가입 사용자 MySQL 매핑 구성
4. 사용자 유형별 매핑률
5. 플랫폼·디바이스별 매핑률
6. 매핑 여부별 활동량 비교
7. 매핑 여부별 리텐션 비교
8. 현재 탈퇴 상태 사용자 활동 구성
9. 하나의 `user_id`에 연결된 `user_pseudo_id` 상세 조회

`is_mysql_mapped`는 로그인 여부가 아니다. `is_deleted`는 현재 상태이며 과거 시점의 탈퇴 상태가 아니다. 따라서 "일별 로그인 사용자", "일별 탈퇴율", "탈퇴 시점 전후 분석"을 이 화면에서 제공하지 않는다.

#### 6.4.9 사용자 상세 조회 테이블

운영 확인과 지표 추적을 위한 상세 Table을 만들 수 있다.

##### 권장 컬럼

```text
event_dt
user_pseudo_id
user_id
gender
major
entry_year
user_type
is_deleted
is_mysql_mapped
platform_dominant
device_category_dominant
device_os_dominant
event_cnt_day
entry_event_cnt_day
core_action_cnt_day
session_cnt_day
engagement_msec_day
is_multi_session_user
first_seen_dt
first_signup_dt
is_new_user
is_new_signup
had_entry_prev_day
days_since_first_seen
is_first_seen_retained
days_since_signup
is_signup_retained
used_*_flg
is_active_entry
is_active_any_event
has_core_action
```

개별 식별자는 접근 권한이 있는 사용자에게만 노출한다. 일반 BI 화면에서는 `user_pseudo_id`, `user_id`를 기본 숨김 처리하고 드릴다운 또는 제한된 운영용 화면에서만 사용한다.

---

### 6.5 공통 필터 구성

#### 6.5.1 기본 필터

| 필터 | 컬럼 | 적용 대상 |
| --- | --- | --- |
| 조회 기간 | `event_dt` | 모든 대시보드 |
| 리텐션 기간 N | `days_since_first_seen` 또는 `days_since_signup` | 전체 사용자·가입 리텐션 |
| 최초 방문 코호트 기간 | `first_seen_dt` | 전체 사용자 리텐션 |
| 가입 코호트 기간 | `first_signup_dt` | 가입 리텐션 |
| 성별 | `gender` | 활동·가입·리텐션·서비스 |
| 학과 | `major` | 활동·가입·리텐션·서비스 |
| 입학 연도 | `entry_year` | 활동·가입·리텐션·서비스 |
| 사용자 유형 | `user_type` | 활동·가입·리텐션·서비스 |
| 플랫폼 | `platform_dominant` | 활동·서비스 |
| 디바이스 | `device_category_dominant` | 활동·서비스 |
| OS | `device_os_dominant` | 활동·서비스 |
| MySQL 매핑 여부 | `is_mysql_mapped` | 사용자 구성·계정 상태 |
| 현재 탈퇴 여부 | `is_deleted` | 사용자 구성·계정 상태 |

#### 6.5.2 분석용 보조 필터

```text
is_active_entry
is_active_any_event
has_core_action
is_multi_session_user
is_new_user
is_new_signup
had_entry_prev_day
first_seen_dt
first_signup_dt
days_since_first_seen
days_since_signup
각 used_*_flg
```

#### 6.5.3 필터 적용 주의사항

- 활동 분석에는 `is_active_any_event = 1` 또는 `is_active_entry = 1`을 목적에 맞게 사용한다.
- 가입 분석에는 `is_new_signup = 1`을 사용한다.
- 전체 사용자 리텐션은 `days_since_first_seen`, 가입 리텐션은 `days_since_signup`을 사용한다.
- 신규 GA4 사용자 분석에는 `is_new_user = 1`을 사용한다.
- 사용자 속성 Null을 자동 제외하지 말고 `unknown/null` 그룹으로 품질을 함께 확인한다.
- 리텐션 화면은 코호트 시작일과 평가일 `event_dt`를 구분하고, 선택 N과 평가 가능 사용자 수를 함께 표시한다.
- 모든 대용량 시계열 조회는 `event_dt` 필터를 적용하여 BigQuery 파티션을 사용한다.

---

### 6.6 추천 Superset 시각화 유형

| 분석 목적 | 권장 시각화 |
| --- | --- |
| 단일 핵심 수치 | Big Number |
| 전일·전주 대비 | Big Number with Trendline |
| 일별 추이 | Time-series Line Chart |
| 활동량과 사용자 수 비교 | Mixed Time-series |
| 서비스별 이용자 비교 | Bar Chart |
| 서비스별 시간 추이 | Multi-line 또는 Stacked Bar |
| 사용자 속성 구성 | Bar, Treemap, Pie는 소수 범주에 한정 |
| 플랫폼·디바이스 구성 | Stacked Area 또는 Stacked Bar |
| 선택형 D0~DN 리텐션 | Heatmap, Pivot Table, Multi-line |
| 사용자별 활동 분포 | Histogram 또는 Box Plot |
| 두 차원의 교차 분석 | Pivot Table 또는 Heatmap |
| 개별 사용자 확인 | Table |

Pie Chart는 범주가 많은 `major`, `entry_year`, `device_os_dominant`에는 사용하지 않는다.

---

### 6.7 대시보드에 반드시 표시할 정의

각 대시보드의 설명 영역에 다음을 명시한다.

```text
사용자 기준: user_pseudo_id
Entry DAU: 당일 Entry Event가 1건 이상인 user_pseudo_id 수
Any Event DAU: 당일 Event가 1건 이상인 user_pseudo_id 수
전체 사용자 리텐션: 최초 방문일로부터 선택한 N일째 Entry 활동한 비율
가입 리텐션: 가입일로부터 선택한 N일째 Entry 활동한 비율
D0~DN 리텐션 곡선: 각 경과일의 정확한 당일 Entry 활동 비율
리텐션 미완료 또는 Event 관측 범위 밖 코호트: 분모에서 제외
사용자 속성 및 탈퇴·매핑 상태: Silver User의 현재 Snapshot
Account/Cafeteria 이용: 서비스 Event 존재 기준
그 외 서비스 이용: Entry Event 존재 기준
```

리텐션 차트에는 선택 N과 평가 가능 pseudo 사용자 수(`COUNT(is_first_seen_retained)` 또는 `COUNT(is_signup_retained)`)를 같이 노출한다. 작은 표본에서 비율만 표시하지 않는다.

---

### 6.8 이 38개 컬럼으로 만들면 안 되는 지표

다음 지표는 현재 Mart의 Grain 또는 입력 계약으로 정확히 계산할 수 없다.

| 만들면 안 되는 지표 | 이유 |
| --- | --- |
| 일별 로그인 사용자 수 | `is_mysql_mapped`와 `user_id`는 로그인 Event가 아님 |
| 로그인 성공률 | 로그인 시도·성공 Event 계약이 없음 |
| 계정 기준 정확한 사용자 수·리텐션 | 여러 `user_pseudo_id`가 한 `user_id`에 연결될 수 있음 |
| 당시 성별·학과·사용자 유형별 과거 추이 | 사용자 속성이 현재 Snapshot임 |
| 일별 탈퇴자·탈퇴율 | `is_deleted`가 현재 상태이며 탈퇴 시각이 없음 |
| 재가입 분석 | 탈퇴·재가입 이력과 유효 기간이 없음 |
| 일반 이탈률·재활성률 | 리텐션 Spine은 있으나 이탈·재활성의 상태 및 연속 비활동 기간 계약이 없음 |
| 정확한 Funnel 전환율 | `funnel_stage`, `step_order`, Event 순서가 출력에 없음 |
| 화면·버튼별 행동 분석 | Event 이름·화면·라벨이 Gold 출력에 없음 |
| 서비스 내 기능 사용 횟수 | `used_*_flg`는 일간 존재 여부만 표현 |
| Real Estate 이용 지표 | Silver에 분류 규칙이 없어 출력에서 제외됨 |
| 365일 초과 리텐션 | 현재 선택형 Spine 최대 범위가 D365임 |
| 임의 달력일을 시작점으로 한 리텐션 | 시작점은 `first_seen_dt` 또는 `first_signup_dt`로 한정됨 |
| Event 플랫폼 전체 분포 | 플랫폼 컬럼은 사용자별 일간 대표값임 |
| OS 버전 분석 | `device_os_version`은 38개 Gold 출력에 없음 |
| Rolling 7일·30일 고유 사용자 | 단순 Metric만으로 날짜별 이동 구간 중복 제거 불가 |

이 요구가 필요해지면 현재 수치를 임의로 대체하지 않고 Grain과 원천 계약을 다시 검토한다.

---

### 6.9 우선 구현 순서

#### 1순위: 핵심 운영 화면

1. 종합 KPI 카드
2. 일별 Entry DAU·Any Event DAU
3. 신규 사용자·가입자 추이
4. Event·Session·Core Action 추이
5. 서비스별 이용 사용자 추이

#### 2순위: 전체 사용자·가입 리텐션

1. 사용자가 선택한 D0~DN 최초 방문 코호트 Heatmap
2. 사용자가 선택한 D0~DN 가입 코호트 Heatmap
3. 선택 DN별 평가 가능 pseudo 사용자 수
4. 사용자 유형·플랫폼별 리텐션
5. 가입일 활동률

#### 3순위: 세그먼트와 품질

1. 플랫폼·디바이스·OS 구성
2. 성별·학과·입학 연도·사용자 유형 구성
3. MySQL 매핑 현황
4. `unknown`·Null 비율
5. 제한된 사용자 상세 조회

---

### 6.10 최종 구성 결론

최종 38개 컬럼만으로 다음 영역을 하나의 Gold Mart에서 제공할 수 있다.

```text
일간·기간 활성 사용자
Event·Entry·Core Action 활동량
Session과 Engagement
신규 GA4 사용자와 신규 가입
가입일 활동
전체 사용자·가입 사용자 선택형 D0~D365 코호트 리텐션
전일 Entry 동시 활동
8개 서비스 이용 사용자와 이용률(Club 제외)
다서비스 이용
플랫폼·디바이스·OS 구성
성별·학과·입학 연도·사용자 유형 세그먼트
MySQL 매핑과 현재 탈퇴 상태
사용자별 일간 상세 조회
```

이 구성은 Superset의 LOD 계산에 의존하지 않는다. 코호트와 리텐션 판정은 Gold에서 완료하고 BI는 합계·고유 개수·비율·시각화만 담당한다.

모든 대시보드는 `gold.mart_kpi_user_daily` 하나를 공유하며, 별도 Gold Mart를 추가하지 않는다.

### 6.11 KPI·퍼널 최종 정의 (2026-09-07)

> 역사 절 안내(2026-09-18 추가): 이 절은 2026-09-07 당시 38컬럼·단일 Mart 기준의 요구사항과 검토 이력이다. 현재 물리 계약은 5.0.11의 사용자 44컬럼 + 집계 20컬럼을 따르고, KPI 4개·퍼널의 현재 Superset 실행 계약은 6.14가 우선한다. 이 절과 6.14가 충돌하면 6.14를 적용한다.

사용자가 2026-09-07에 아래 KPI 4개와 퍼널 문안을 최종 정의로 확정했다. 지표 정의는 이 절을 따른다. 정의 확정은 구현 완료를 뜻하지 않으며, 이탈률·퍼널 구현에 필요한 Gold 집계 구조는 후속 설계 대상이다. 5장의 38컬럼·단일 Mart 물리 계약과의 차이는 해결해야 할 구현 제약으로 유지한다.

#### 공통 기준

- 날짜는 한국 시간 기준이다. 날짜 필터 시작일이 속한 달을 KPI 기준 월로 사용한다. 과거 월 선택 시 제목은 해당 월을 표시하고 ‘이번 달’이라고 표시하지 않는다.
- 월 지표의 종료일은 월말과 파이프라인이 보장하는 데이터 완전 가용일 중 이른 날이다. 최신 이벤트 발생일만으로 데이터 완전성을 판단하지 않는다. 월 전체를 관측하지 못했다면 집계 범위를 표시한다.
- 사용자는 `user_pseudo_id` 기준이다. 회원·비회원을 포함하며 실제 사람 또는 계정 수와 다를 수 있다. 식별자가 없는 이벤트는 사용자 집계에서 제외한다.
- 현재 계약의 MAU는 Any Event 활동, 리텐션 재방문은 Entry 활동이다. 서로 다른 활동 기준을 카드 설명에 표시한다. 동일 기준으로 통일하려면 별도 합의가 필요하다.

- 완전 가용 시작일도 확인한다. 월초가 `event_complete_start_dt`보다 이르면 부분 관측으로 표시하고 월 전체 MAU·신규 유저 수로 해석하거나 증감 비교하지 않는다. **(2026-09-18 변경)** MAU·신규 카드는 선택 기간에 현재 적재된 행을 직접 집계하며 자동 완료 캡핑을 하지 않는다. 진행 월은 부분값일 수 있으므로 검증 완료 기준일을 항상 함께 표시한다. 미적재 미래 월과 실제 0명은 단순 Metric만으로 완전히 구분되지 않을 수 있으며, No data 상태와 기준일 각주를 함께 확인한다.
- 월 KPI는 날짜 필터의 시작일로 기준 월을 정하며 종료일은 월 집계 규칙으로 계산한다. 퍼널은 선택한 시작일~종료일을 그대로 사용한다. 이 필터 적용 차이를 화면에 표시한다.
- 비교 기준값이 0이면 증감률은 N/A로 표시한다. 진행 월의 동일 경과일 비교가 짧은 달 때문에 불가능하면 공통으로 존재하는 일수로 양쪽 비교 구간을 맞추고 날짜를 표시한다. 완료 월 전체 비교는 달력 월 전체로 유지한다.

#### KPI 1. MAU — 기준 월 활성 사용자 수

- 목적: 코인 전체의 월간 활성 사용자 규모를 확인해 서비스 성장·정체와 학사 일정, 홍보, 기능 출시 전후의 변화를 파악한다.
- 대상 서비스/사용자: 코인 전체, 회원·비회원 포함.
- 정의: 기준 월 집계 구간에 이벤트가 1회 이상 관측된 고유 사용자 수.
- 계산: `COUNT(DISTINCT CASE WHEN is_active_any_event = 1 THEN user_pseudo_id END)`.
- 기간: 기준 월 1일~집계 종료일.
- 차트 종류: KPI 카드.
- 단위: 명(`user_pseudo_id` 기준).
- 비교: 완료된 월은 전월 및 전년 동월과 비교한다. 진행 중인 월은 같은 경과 기간끼리 비교하고 실제 비교 날짜를 표시한다. 전년 동월 비교는 YoY, 직전 학기 비교는 별도 학기 비교다.
- 해석 주의: DAU를 합산하면 월간 중복 사용자가 포함되므로 MAU가 아니다. 증감만으로 UI/UX 개선 효과를 단정하지 않는다.
- 구현 상태: 현 Gold 계약으로 지원 가능. 운영 배포 및 입력 검증은 별도다.

#### KPI 2. 신규 유저 수 — 기준 월 최초 관측 사용자 수

- 목적: 새로 유입된 사용자의 규모를 파악하고 홍보 또는 신학기 유입 변화의 신호를 확인한다.
- 대상 서비스/사용자: 코인 전체, 가입 여부 무관.
- 정의: Silver가 제공하는 최초 관측일 `first_seen_dt`가 기준 월 집계 구간에 속하는 고유 사용자 수. 월 안에서 처음 방문한 기존 사용자를 신규로 재분류하지 않는다.
- 계산: 해당 기간 `SUM(is_new_user)`.
- 집계 검증 조건: 사용자당 `is_new_user = 1` 행은 정확히 한 번만 존재해야 한다(`first_seen_dt = event_dt`인 날은 사용자마다 하루뿐이므로). 0번(신규 판정 누락) 또는 2번 이상(중복) 나오면 입력 오류로 보고한다.
- 기간/단위/차트: MAU와 같은 월 집계 구간, 명(pseudo 기준), KPI 카드.
- 비교: 전월 및 전년 동월의 동등한 관측 구간과 비교한다. 전년 동월 비교는 YoY, 직전 학기 비교는 별도 학기 비교로 구분해 표기하며 두 명칭을 혼용하지 않는다(MAU와 동일 규칙). 홍보 효과를 해석할 때 캠페인 기간과 학사 일정을 함께 확인한다.
- 해석 주의: 실제 생애 최초 방문을 보장하는 값이 아닌 추적 데이터의 최초 관측이다. 재설치·식별자 초기화·기기 변경 또는 수집 이력 한계의 영향을 받을 수 있다. 가입자 수나 아하 모먼트 달성자 수로 해석하지 않는다.
- 구현 상태: 현 Gold 계약으로 지원 가능.

#### KPI 3. 리텐션 — 최초 방문 D1~D7 Range Entry 리텐션율

- 변경 결정(2026-09-07): 사용자 요청으로 KPI 리텐션을 정확한 D7에서 Range 리텐션으로 변경한다. 범위는 기존 7일 기준을 유지해 최초 관측 다음 날(D1)부터 D7까지로 설정한다. 이 절의 최신 KPI 정의가 과거 D7 KPI 검토 문구보다 우선한다. 5장의 정확한 DN 물리 계약은 현재 구현 지원 범위를 설명하며 Range 지원 완료를 뜻하지 않는다.
- 목적: 최초 유입 사용자가 이후 일주일 안에 다시 서비스에 진입하는지 확인하여 유입 이후 재방문 수준을 파악한다.
- 대상 서비스/사용자: 코인 전체 최초 관측 사용자, 회원·비회원 포함. 가입일이나 기존 사용자의 임의 방문일을 기준일로 사용하지 않는다.
- 정의: 기준 월 최초 관측 사용자 중 D1~D7 사이에 Entry 활동이 한 번 이상 발생한 사용자 비율. 최초 관측일 D0는 재방문 구간에서 제외한다. 날짜는 한국 시간의 달력일 기준이며 최초 이벤트 시각부터 168시간을 의미하지 않는다.
- 분모: 기준 월 최초 관측 사용자 중 D1~D7 전체가 완전 가용 구간에 포함되고 수집 완료된 고유 사용자 수. D1 >= event_complete_start_dt 및 D7 <= event_complete_dt를 만족하고 구간 내 누락이 없어야 한다.
- 분자: 분모 사용자 중 D1~D7 어느 날이든 is_active_entry=1인 고유 사용자 수. 여러 날 재방문해도 한 명으로 집계한다.
- 계산: `100 × SAFE_DIVIDE(D1~D7 내 1회 이상 재방문한 평가 가능 사용자 수, D1~D7 전체 평가 가능 사용자 수)`.
- 사용자별 판정: 평가 가능한 사용자에 한해 D1~D7의 Entry 활동 존재 여부를 1/0으로 판정한 후 사용자 단위로 집계한다. 아직 D7 관측이 끝나지 않은 사용자는 이미 재방문했더라도 분모와 분자에서 모두 제외한다. 미복귀 0과 평가 불가 NULL을 구분한다.
- 기간: 날짜 필터 시작일이 속한 달을 first_seen_dt 코호트 기간으로 사용한다. 재방문 관측은 다음 달로 이어질 수 있다. 과거 월 코호트도 현재 완전 가용일까지 평가하며 과거 월말 시점 수치 재현과 구분한다.
- 차트/단위: KPI 카드, %. 재방문자 수/평가 가능 사용자 수, 관측 구간 D1~D7, 데이터 기준일 및 평가 가능한 최초 방문일 범위를 함께 표시한다. 분모 30명 미만은 비율을 숨기고 분모를 표시한다. 분모 0은 N/A다.
- 기간 선정 이유: 기존 7일 관측 길이를 유지하면서 특정 하루가 아닌 일주일 내 재방문 여부를 확인한다. 도메인 표준이나 실측 최적 구간을 의미하지 않는다.
- 필터 안전 조건: 활성 사용자·신규 사용자·서비스 이용 플래그를 전체 행 필터로 적용해 미복귀 사용자를 제거하지 않는다. 사용자별 D1~D7 조건과 성숙 조건을 적용한다. 이벤트 파티션 범위는 코호트 시작일+1일부터 코호트 종료일+7일까지로 잡고, 공통 월 활동일 필터를 중첩하지 않는다.
- 계산 금지: 일별 DN 리텐션율을 더하거나 평균내지 않는다. `days_since_first_seen BETWEEN 1 AND 7`만 적용한 뒤 `SUM(is_first_seen_retained)/COUNT(is_first_seen_retained)`를 사용하면 사용자 재방문 비율이 아닌 사용자×일 활동 비율이 되므로 사용하지 않는다. D7 당일 플래그만으로도 이 지표를 계산할 수 없다.
- 해석 주의: 구간 내 한 번이라도 재방문했는지를 보여주며 재방문 횟수·지속 이용·D7 당일 활동을 보장하지 않는다. MAU는 Any Event, 재방문은 Entry 기준임을 표시한다. 주간 미복귀율과 기준일·모집단·활동 기준이 다르므로 두 지표는 서로의 여집합이 아니다.
- 구현 조건: 현 38컬럼 계약은 정확한 DN용 일별 사실을 제공하지만 사용자별 구간 복귀·구간 전체 관측 완료 판정 집계는 제공하지 않는다. Gold 범위에서 성숙 여부와 사용자별 Range 판정 및 BI 집계를 설계·검증한 후 제공한다. 기존 DN 플래그 의미를 바꾸거나 Silver를 수정하지 않는다. 이번 변경은 지표 정의 변경이며 물리 모델·SQL 구현 완료가 아니다.

#### Range 리텐션 기간 선정 — 외부 자료 검토 (2026-09-07)

결론: 현재 코인 전체 최초 방문→Entry 재방문 KPI는 D1~D7을 유지하는 것을 권장한다. 외부 자료가 뒷받침하는 것은 ‘사용 주기에 맞춘 구간 설정’과 ‘주간 주기의 제품에 7일 구간을 적용하는 타당성’이다. 배민의 공식 내부 기준이나 코인 실데이터 최적 구간이 검증됐다는 뜻은 아니다. 배민·우아한형제들 및 요기요 관련 공개 검색에서 소비자 Range 리텐션의 정확한 구간·분모·복귀 이벤트를 명시한 1차 자료는 이번 조사에서 확보하지 못했다.

| 자료 | 확인된 내용 | 코인 적용 시 한계 |
| --- | --- | --- |
| [Amplitude Retention Playbook](https://info.amplitude.com/rs/138-CDN-550/images/product-analytics-playbook-vol1-amplitude.pdf), 제품 사용 주기 설명 | 주 1회 주문을 가정한 음식 배달 앱 예시에서 D1~D7, D8~D14, D15~D21 구간을 설명한다. | 설명용 사례이며 특정 배달 앱의 실제 KPI 공개가 아니다. |
| [Amplitude 신규 사용자 리텐션](https://amplitude.com/books/mastering-retention/new-user-retention) | 사용 주기가 주간인 제품의 초기 가치 발견 구간은 D1~D7, 격주 제품은 D1~D14, 월간 제품은 D1~D30으로 구분한다. | 업종만으로 기간을 고정하지 않고 실제 사용 주기에 따라 선택한다. |
| [DoorDash 2026년 2분기 실적 공시](https://www.sec.gov/Archives/edgar/data/1792789/000179278926000048/proddashex991-pressrelease.htm) | 소비자 리텐션을 코호트 내 계정 중 최근 측정 월에 거래한 계정의 비율로 정의한다. | 실제 기업의 월간 거래 기준이며 최초 방문 후 D1~D30 Entry 리텐션과 다르다. 7일이 배달 업계의 통일 표준이라는 근거는 없다. |
| [Amplitude의 Rappi 사례 설명](https://amplitude.com/blog/measure-user-retention) | 초기 20일의 주문 횟수와 이후 리텐션의 관계를 분석했다. | 초기 행동 분석 구간이지 D1~D20 Range 리텐션을 공식 KPI로 사용한다는 증거는 아니다. |
| [Mixpanel의 Deliveroo 사례 설명](https://mixpanel.com/blog/churn-analytics/) | 1주·3주 리텐션 분석 사례를 소개한다. | 대상은 소비자가 아니라 입점 음식점 파트너다. 소비자 앱의 구간 선정 근거로 직접 전용하지 않는다. |

코인에 대한 판단(외부 실측 사실이 아닌 분석 제안):

- 현재 KPI의 목적은 신규 사용자의 초기 재방문이다. D1~D7은 첫날 이후 모든 요일을 한 번 포함하고 7일 관측 후 판단할 수 있어, D1~D3보다 요일 편향을 줄이고 D1~D14·D1~D30보다 결과 확인이 빠르다.
- 코인은 주문만 측정하는 배달 앱이 아니라 식단·버스·상점 등 여러 서비스를 포함하며 복귀 이벤트도 주문 완료가 아닌 Entry다. 배달 앱의 거래 기준이나 월간 리텐션 수치를 그대로 가져오지 않는다.
- D1~D7은 초기 복귀를 보여준다. 지속적 정착을 보려면 D8~D14, D15~D21, D22~D28처럼 서로 겹치지 않는 주간 구간을 보조 분석한다. 이는 후속 분석 제안이며 이번에 추가 KPI·차트 구현을 승인하거나 계약을 확장하는 것은 아니다.
- D1~D14 또는 D1~D30 누적 구간은 창이 넓어서 동일 모집단에서 비율이 높아질 수밖에 없다. 숫자가 더 높다는 이유로 더 적합한 기간이라고 판단하지 않는다.

실데이터로 구간을 검증하는 방법:

1. 출처·분류·완전성이 검증된 운영 데이터에서 D28까지 모두 관측 가능한 동일 최초 방문 코호트를 선정한다. 학기 중·방학·홍보 유입을 분리한다. Stage 임시 테이블만으로 최적 구간을 확정하지 않는다.
2. 동일 분모로 D1~D3, D1~D7, D1~D14, D1~D28의 최초 Entry 복귀 누적 비율과 최초 복귀일까지의 분포를 비교한다. 돌아오지 않은 사용자도 분모에 유지한다.
3. 별도로 반복 활동 사용자들의 Entry 활동일 간격을 확인한다. [Amplitude Usage interval 문서](https://www.amplitude.com/docs/analytics/charts/retention-analysis/retention-analysis-interpret-usage)는 사용자별 반복 이벤트 간격 중앙값의 분포를 활용한다. 이 분석은 반복 사용자가 대상이므로 신규 사용자 전체의 첫 복귀 분석을 대체하지 않는다.
4. D1~D7 복귀 여부별로 D8~D14·D22~D28 재방문을 비교해 초기 복귀가 이후 이용과 연결되는지 살핀다. 구간은 합산하지 않고 각 구간에서 사용자 중복 제거한다. 서비스별 첫 이용 리텐션은 별도 기준일 계약이 필요하므로 앱 전체 first_seen_dt를 몰래 대체하지 않는다.
5. 여러 코호트에서 첫 복귀가 8~14일에 집중된다면 14일로 변경을 검토한다. 7일 이내 복귀가 주된 패턴이고 이후 이용과도 연결된다면 7일을 유지한다. 표본 수와 불확실성을 함께 보고, 최소 30명 표시 정책만 충족했다고 통계적 충분성이 보장된다고 해석하지 않는다.

노션 ‘기간 선정 이유’용 문안:

> 최초 방문 다음 날부터 7일 동안 한 번 이상 재방문했는지를 측정한다. 주간 사용 주기의 제품에 D1~D7 구간을 적용하는 Amplitude의 분석 지침을 참고했으며, 모든 요일을 포함하면서 신규 유입의 초기 복귀를 빠르게 확인하기 위해 7일을 사용한다. 배민의 공식 기준을 채택한 것은 아니며, 코인의 실제 첫 복귀 간격과 이후 주간 재방문을 검증해 적합성을 확인한다.

#### KPI 4. 이탈률 — 주간 미복귀율

- 목적: 직전 주 이용자 중 다음 주에 돌아오지 않은 비율을 확인해 이용 지속성 저하의 신호를 찾는다.
- 대상 서비스/사용자: 코인 전체, 기준 주에 Any Event 활동이 있었던 회원·비회원.
- 정의: 기준 주 월~일에 활동한 사용자 중 바로 다음 주 월~일에 활동이 한 번도 없었던 사용자 비율.
- 계산: `기준 주 활성 사용자 중 다음 주 미활동 사용자 수 / 기준 주 활성 사용자 수 × 100`.
- 기간: 두 주가 모두 완전히 관측된 최신 연속 주차를 사용한다. 기준 월 KPI 화면에서는 해당 월말(또는 데이터 완전 가용일)까지 평가가 끝난 최신 주차 쌍을 표시하며, 카드에 두 주의 날짜를 명시한다. 평가 가능한 주차 쌍이 없으면 표시하지 않는다.
- 주차 경계: C를 `MIN(기준 월말, event_complete_dt)`로 두고, C 이하의 가장 최근 일요일을 E로 잡는다. 다음 주는 E-6일~E, 기준 주는 E-13일~E-7일이다. E-13일이 `event_complete_start_dt`보다 이르면 표시하지 않는다. 두 주 전체의 수집 완전성이 보장돼야 한다. 월초에는 이전 달 주차가 사용될 수 있으며 두 주의 날짜를 명시한다.
- 계산 안전 조건: 기준 주 사용자 집합 A와 다음 주 사용자 집합 B를 각각 중복 제거하고 `100 × |A \ B| / |A|`로 계산한다. 월 활동일 필터로 두 주를 잘라내지 않는다. 분모 0은 안전 나눗셈으로 N/A 처리한다.
- 단위/차트: %, KPI 카드. 미복귀자 수/기준 주 활성 사용자 수를 함께 표시한다. 분모가 0이면 N/A다.
- 해석 주의: 영구 이탈·회원 탈퇴가 아니라 일주일간의 미복귀다. 시험·방학·공휴일 등 이용 필요성의 변화도 영향을 줄 수 있으며 UI/UX 문제의 직접 증거가 아니다. `100% - D1~D7 Range 리텐션`으로 계산하지 않는다.
- 구현 상태: 현 Gold 설계에는 일별 활동 정보(`is_active_any_event`)가 포함돼 있으나, 사용자별 두 주 활동 집합을 비교하는 사전 집계 컬럼·로직은 현 38컬럼 단일 Mart에 없다. 6.3.7절 Rolling WAU/MAU 한계와 같은 유형의 제약으로, 일별 활동을 표현하는 설계는 있지만 두 주 집합 비교는 단순 Superset 집계 Metric 하나로 표현할 수 없는 것이며 Gold 쪽에 별도 Intermediate/집계 설계가 필요하다. 지표 정의는 확정이며 Gold 범위 집계 설계·검증을 마친 뒤 카드를 제공한다. Silver 변경을 사용자 작업으로 추가하지 않는다.

#### 그래프 1. 퍼널

- 목적: 정해진 이용 경로에서 단계별 전환·이탈을 확인해 추가 분석이 필요한 지점을 찾고, 개선 전후 같은 조건의 전환율을 비교한다. 단계 이탈만으로 UI/UX 문제를 확정하지 않는다.
- 근거 정정(2026-09-07 최초 작성, 2026-09-07 재정정): `silver_events_temp`를 생성하는 dbt 모델이 이 저장소에 없다는 것은 확인된 사실이다. 다만 이 한 가지 사실만으로 "수기 placeholder 픽스처"라고 단정한 것은 근거가 부족했다 — 재검토 결과 수정한다. KOIN_GOLD_HANDOFF.md의 placeholder 경고는 Silver User에 추가될 `user_type`/`signup_completed_at`/`is_deleted`/`is_mysql_mapped` 네 필드의 typed placeholder에 관한 것이며, Event 테이블(`silver_events_temp`) 전체가 합성 데이터라는 근거로 확대 적용할 수 없다. 생성 SQL·적재 이력·작성자 확인 같은 별도 근거가 없으므로, 정확한 표현은 "이 테이블이 `silver_events_v2`의 검증된 산출물이라는 근거가 없고, 생성 경로와 출처가 확인되지 않은 임시 테이블"이다 — 합성/가짜 데이터라거나 특정 방식으로 만들어졌다고 단정하지 않는다. 이 표본의 단계별 건수는 컬럼 존재 확인 이상의 근거로 쓸 수 없다는 제한은 유지한다. 아래 단계 정의는 이 표본이 아니라 `dbt/models/silver/silver_events_v2.sql`의 분류 CASE문을 직접 읽어 확정했다. 이 코드가 Stage/Production에 실제로 배포·실행됐다는 뜻은 아니다(코드 존재 ≠ 배포이며, 미배포 자체도 "예정 위치에 현재 산출물이 없다"는 뜻이지 "과거에 실행된 적이 없다"는 뜻은 아니다 — 아래 구현 상태 참고).
- 대상 퍼널(필터): 회원가입, 상점, 버스, 식단, 시간표, 졸업계산기, 게시판(공지사항), 시설 중 하나를 필터로 선택한다(2026-09-07 확정 — 회원가입·주변 상점 2종에서 전체 서비스로 확장). **"게시판" 항목은 이전 문서에서 "팀원모집"으로 잘못 표기됐다** — 코드상 트리거 이벤트(`main_notice`, `popular_notice`, `notice_tab`, `notice_search` 등)와 메뉴 값 "게시판"이 전부 공지사항 게시판을 가리키며, 팀원모집 관련 문자열은 코드에 없다. 메인과 배너는 이번 8개 선정 대상에서 제외한다 — 배너는 `click`이 코드에서 `is_core_action = true`로 분류돼 있어 "자체 핵심 액션이 없다"는 이전 서술은 틀렸다(정정), 제외 사유는 핵심 액션 부재가 아니라 분석 대상 범위 선정이다. 메인은 실제로 단일 이벤트(`funnel_stage='main'`, `step_order=0`)뿐이라 core_action 자체가 코드에 없고, 아래 회원가입 제외 7개 퍼널의 공통 1단계(메인 방문)로만 쓴다. 이 8개는 현재 선정한 분석 대상이며, 코인 앱의 모든 기능을 빠짐없이 포함한다는 뜻은 아니다(미포함 기능은 아래 "퍼널 확장 후보" 참고).
- 공통 1~2단계(회원가입 제외 7개 공통): 1단계 메인 방문 → 2단계 서비스 진입(entry, Silver `step_order=1`). 3단계 이후는 서비스마다 실제 단계 수·의미가 다르며(서비스별 최대 1~3단계), 코드에 없는 단계를 임의로 만들지 않는다. 회원가입은 메인을 포함하지 않고 가입 시작을 첫 단계로 하는 아래 별도 5단계를 쓴다.
- 서비스별 단계 매핑(`dbt/models/silver/silver_events_v2.sql` 코드 확인, 2026-09-07. Stage `silver_events_temp` 표본 건수는 위 근거 정정에 따라 참고용으로만 병기):

    | 서비스 | 단계(step_order) | 핵심 액션(core_action) | 진입 트리거 요약 | Stage 표본(참고용, 대표성 없음) |
    | --- | --- | --- | --- | --- |
    | 상점 | 1 entry → 2 shop_view(상세조회) → 3 call | call(전화 클릭) | 메뉴 '주변상점' 등 | entry 290, shop_view 3, call 3 |
    | 버스 | 1 entry → 2 set_od(출발 **또는** 도착 확인, 둘 다 필수 아님) → 3 search | search(경로 검색) | 메뉴 '버스 시간표' **또는** '교통편 조회하기'(둘 다 동일 entry 트리거 — 별도 기능 아님) | entry 2, set_od 7, search 1 |
    | 식단 | 1 entry → 2 explore(메뉴 시간 조회) → 3 share | share(메뉴 공유) | 메뉴 '식단' | entry 2, explore 13 |
    | 시간표 | 1 entry → 2 explore(검색·학기/교육과정 선택) → 3 save | save(이미지 저장) | 메뉴 '시간표' | entry 15, explore 9 |
    | 졸업계산기 | 1 entry → 2 explore(학과·학기·과목 편집/삭제/추가 등) | 없음 — 코드에 core 분기 자체가 없음(표본 부족이 아님) | event_label='graduation_calculator' | entry 2, explore 6 |
    | 게시판(공지사항) | 1 entry(공지 메인) → 2 explore(공지 탭/검색) → 3 read | read(인기공지 등 읽기) | 메뉴 '게시판' | entry 19(코드상 explore/read는 표본에 없음) |
    | 시설 | 1 entry만 | 없음 — 코드에 2·3·4단계 분류 규칙 자체가 없음 | 메뉴 '교내 시설물 정보' | entry 10 |
    | 회원가입(account) | 1 시작(signup_start) → 2 약관동의(terms_agreement) → 3 본인인증(identity_verification) → 4 정보입력(form_entry) → 5 가입완료(signup_complete) | signup_complete | event_value='회원가입 시작' 등 | 아래 회원가입 단계 참고 |

    로그인(`login_entry`)은 회원가입과 같은 `service_name=account`, `step_order=1`이지만 별도 경로(재방문 로그인)이며 그 자체로는 후속 단계가 없다. 클럽(club)은 코드에 4단계 분류가 남아 있으나 제품 결정(동아리 앱 분리)으로 이미 대상에서 제외돼 있다 — 이번 재검토로 다시 추가하지 않는다.

- 대상 사용자: 선택 기간에 첫 단계에 진입한 식별 가능한 사용자. 회원가입은 실제 가입 시작 이벤트를 대상으로 하며 로그인 화면 방문을 대체값으로 쓰지 않는다.
- 회원가입 단계(2026-09-07 코드 확인으로 정정): 기존 확정 문안 "시작→정보 입력→인증→완료"(4단계)는 로컬 `silver_events_v2.sql` 코드와 다르다. 코드가 분류하는 실제 순서는 **시작(signup_start, 1) → 약관 동의(terms_agreement, 2) → 본인 인증(identity_verification, 3) → 정보 입력(form_entry, 4) → 가입 완료(signup_complete, 5)로 5단계**다. 기존 문안에 없던 "약관 동의" 단계가 있고, "정보 입력"과 "인증"의 순서가 반대다. 확정 KPI·퍼널 대상(회원가입 1건)이라는 지표 선정 자체는 바꾸지 않되, 이 5단계 순서를 퍼널 상세의 새 기준으로 삼는다. 약관 동의 이벤트를 정보 입력 완료로 임의 치환하지 않는다. 이 코드가 Stage/Production에 실제 배포됐는지, 5단계 각각의 이벤트가 실제 UI 플로우와 일치하는지는 별도로 검증해야 하며, 검증 전에는 5단계 전체 수치 제공을 보류한다.
- 주변 상점 단계: 메인 방문 → 상점 진입 → 상점 상세 조회 → 전화 클릭. 메인부터 시작하는 경로의 전환율이며 메인을 거치지 않은 직접 진입 경로의 성과까지 대표하지 않는다. 전화 클릭은 통화 연결 또는 주문 완료가 아니다. 회원가입을 제외한 다른 서비스도 같은 방식(메인 방문 → 해당 서비스 진입 → 그 서비스에 정의된 마지막 단계까지)을 따르되, 단계 수는 위 매핑 표 기준으로 서비스마다 다르다(예: 졸업계산기는 진입→탐색까지 2단계, 시설은 진입 1단계뿐).
- 핵심 액션 해석 범위(2026-09-07 추가): `share`(식단 공유)·`save`(시간표 이미지 저장)·`search`(버스 경로 검색)·`call`(상점 전화 클릭)은 그 행동에 도달했다는 뜻이지 서비스 이용 목적 달성이나 완료를 보장하지 않는다 — 식단은 공유하지 않아도 메뉴 확인 목적을 달성할 수 있고, 시간표 저장이 수업 추가 완료를 보장하지 않으며, 버스 검색이 유용한 경로 제공을 보장하지 않고, 전화 클릭이 통화 연결·주문 완료를 보장하지 않는다(전화 클릭 건은 기존에도 명시돼 있었고 나머지 3개로 같은 원칙을 확장한다). 전체 8개 퍼널의 공통 지표명은 "전체 경로 전환율"이다. 마지막 단계가 핵심 액션으로 정의된 서비스는 "핵심 액션 도달률"로도 표시할 수 있다. 졸업계산기·시설은 마지막 관측 단계 도달률이며 서비스 이용 완료를 의미하지 않는다. 어느 경우에도 서비스 이용 성공률이나 만족도의 자동 증거로 쓰지 않는다. 각 이벤트가 시도(예: 저장 버튼 클릭)인지 완료(예: 저장 성공 콜백)인지는 실제 수집 시점을 Silver에 확인하기 전에는 단정하지 않는다.
- 1→2단계 연결(회원가입 제외 7개, 메인 방문 → 서비스 진입): 같은 `service_name` 안의 `step_order` 순서가 아니라, 같은 세션(`ga_session_id`) 안에서 main 이벤트 다음에 발생한 해당 서비스의 첫 entry(`is_entry_event = true`) 이벤트로 판정한다. 2단계 이후는 선택한 서비스에 정의된 마지막 단계까지 그 서비스의 `step_order` 순서를 그대로 사용한다(고정된 4단계가 아니라 서비스별 매핑 표를 따른다). main은 `stage_scope='global'`이라 서비스 필터만으로는 걸리지 않으므로 별도 조건으로 결합해야 한다.
- 집계 단위: 사용자×세션의 유효한 경로를 먼저 판정하고, 차트의 각 단계 도달자는 고유 `user_pseudo_id`로 집계한다. 동일 사용자의 서로 다른 세션에서 발생한 단계를 합쳐 전환으로 만들지 않는다.
- 순서 조건: 동일 세션에서 앞 단계 이후 다음 단계가 발생한 경우만 인정한다. 중간에 무관한 이벤트가 있어도 허용하며 필수 단계 생략은 허용하지 않는다. 반복 클릭은 단계 도달자 수에 중복 반영하지 않는다. 세션 식별자는 pseudo ID와 결합한다. `custom_session_id`는 shop 등 대부분 서비스에서 결측률이 90%를 넘고(shop 100%, main 99.9%, account 88%, 2026-07-01~2026-08-08 표본) 사용할 수 없으므로 `ga_session_id`를 세션 필드로 확정하며, 타임스탬프 동률 처리·결측 처리 규칙은 구현 전에 별도로 확정한다.
- 단계 번호 정의: 차트에 표시하는 "단계 k"는 메인 방문을 1로 포함한 번호다(예: 상점 차트 3단계 = Silver `step_order=2`인 `shop_view`). 회원가입은 예외로, 메인을 붙이지 않고 Silver `step_order` 1~5를 그대로 차트 단계 1~5로 쓴다. 아래 U_k 표기의 k는 이 차트 단계 번호를 따른다.
- 순차 도달 집합: 단계 k 도달자는 유효한 동일 세션에서 1~k 단계를 모두 순서대로 충족한 사용자의 집합 U_k다. m을 선택한 퍼널의 마지막 차트 단계 번호라 하면(회원가입 제외 7개는 서비스별 매핑 표에 따라 m=2~4, 회원가입은 m=5), 세션별 경로 판정 후 선택 기간 전체에서 사용자 중복을 제거하며 `U_m ⊆ ... ⊆ U_2 ⊆ U_1`을 검증한다. 상점 U_1은 해당 기간의 유효한 메인 진입 사용자 전체이며, 이후 상점에 간 사용자만으로 분모를 미리 제한하지 않는다.
- 단계 표시: 단계 k에는 직전 단계 대비 전환율 `|U_k|/|U_(k-1)|`과 다음 단계 이탈률 `1-|U_(k+1)|/|U_k|`을 구분해 표시한다. 첫 단계의 누적 도달률은 100%이며 마지막 단계의 다음 단계 이탈률은 N/A다. 모든 비율은 분모 0을 N/A로 처리한다.
- 구현 차단 조건: 세션 키는 `(user_pseudo_id, ga_session_id)`이며 원천의 스트림 간 충돌 가능성을 검증한다. `silver_events_temp`에는 스트림·GA4 속성 구분 컬럼이 없고 Stage는 서로 다른 GA4 속성 2개(`analytics_427218788`, `analytics_440323811`)를 병합한다(2026-09-07 스키마 재확인). 충돌 검증에 필요한 discriminator 컬럼 자체가 없다는 점을 먼저 확인한다. 키 결측이나 순서를 확정할 수 없는 동률 이벤트를 임의 연결하지 않는다. 동률 판정 정책, 세션 종료·지연 수집 완료 기준, 미완료 세션의 분모 처리와 제외 수 공개 규칙을 문서화하기 전에는 공식 퍼널을 제공하지 않는다. 세션별 관측 완료 여부를 먼저 판정하여 관측이 완료된 동일한 세션 집합을 모든 단계의 집계에 사용한다. 미완료 세션은 확정 전환율의 분모·분자 집계에서 제외하고 제외된 세션 수를 별도로 표시한다. 세션 제외 후 단계별 사용자 중복 제거를 수행한다.
- 전환 시간: 동일 세션 내 완료 기준. 세션을 넘어선 가입 완료는 이 퍼널의 전환에 포함하지 않는다. 인증 중 세션 분리로 실제 가입 완료와 차이가 발생하는지 검증해 제한사항으로 표시한다.
- 기간: 첫 단계 진입일이 날짜 필터 안에 들어오는 세션을 선택한다. 종료일에 시작한 세션의 후속 이벤트도 전환 관측 범위까지 조회한다. 관측이 끝나지 않은 세션은 확정 이탈로 처리하지 않는다.
- 계산: 단계별 전환율(단계 k) = 단계 k 도달자 수 / 직전 단계(k-1) 도달자 수 × 100(= 위 단계 표시의 `|U_k|/|U_(k-1)|`과 동일 정의, 도착 단계 기준). 단계별 이탈률(단계 k) = 100 × (1 - 다음 단계(k+1) 도달자 수/단계 k 도달자 수)(= 위 단계 표시의 `1-|U_(k+1)|/|U_k|`와 동일 정의, 출발 단계 기준). 두 비율은 서로 다른 전환 구간을 가리키므로 동일 단계에 표시할 때 혼동하지 않는다. 전체 경로 전환율 = 첫 단계부터 마지막 단계까지 순차 도달한 사용자 수(U_m, m=해당 퍼널의 마지막 차트 단계) / 첫 단계 진입 사용자 수(U_1) × 100. 분모 0이면 N/A.
- 차트: 퍼널 차트. 각 단계에 도달자 수·직전 단계 대비 전환율·이탈률을 표시한다. 첫 단계는 기준 100%로 표시한다. 단위는 명(pseudo 기준), %다.
- 비교: 개선 전후 같은 퍼널 버전·전환 시간·플랫폼·관측 기간 조건을 사용한다. 이벤트 수집이나 분류 변경도 함께 확인한다.
- 표본 유의사항(2026-09-07 재정정): `silver_events_temp`의 출처가 확인되지 않으므로 이 안의 표본 크기·독립 단계별 집계에서 뒤 단계 사용자 수가 앞 단계보다 많게 나오는 현상(버스 entry<set_od, 식단 entry<explore, 상점 call/shop_view 200% 등)을 실제 순서 위반·로깅 결함·가짜 데이터의 증거로 단정하지 않는다. 직접 진입, 일부 단계 생략(딥링크 등), 수집 시점 차이 같은 여러 원인이 가능하며 어느 쪽인지는 확인되지 않았다. 원인과 무관하게, 공식 전환율에는 독립 집계가 아니라 세션 기준 순차 판정(U_k)이 필요하다는 결론만 유지한다. `silver_events_v2`가 실제 배포되고 실데이터가 쌓인 뒤 표본 크기·정합성을 다시 확인한다.
- `service_step_order` 컬럼 확인 결과(2026-09-07, 코드 확인으로 해결): `silver_events_v2.sql`에는 `service_step_order = (service_name='main' ? NULL : step_order)`로 명시돼 있다 — `step_order`를 대체할 별도 컬럼이 아니라 main을 제외한 `step_order`의 단순 복사본이다. 다만 `silver_events_temp`에서는 이 값이 대부분 NULL로 나타나는데(shop 296건 중 2건만 population 등), 이는 컬럼 정의 문제는 아니다 — `silver_events_temp`의 생성 경로가 확인되지 않아 정확한 원인은 알 수 없으나(위 근거 정정 참고), 코드상 정의가 명확하므로 컬럼 자체를 다시 조사할 필요는 없다. 퍼널 순서 기준은 `step_order`(=`service_step_order`, main 제외)로 확정한다.
- 구현 상태(2026-09-07 코드 확인, 배포 상태 표현 재정정): 현 USER×DAY Gold에는 단계·세션별 순서 정보가 없어 정확한 퍼널을 만들 수 없다는 제약은 8개 퍼널 모두에 공통이다. 코드(`silver_events_v2.sql`) 기준으로 상점·버스·식단·시간표·게시판(공지사항)·회원가입은 핵심 액션까지의 분류 규칙이 코드에 이미 존재하고, 졸업계산기·시설은 핵심 액션 분류 규칙 자체가 코드에 없다(표본 부족이 아니라 규칙 부재). `silver_events_v2` 테이블은 2026-09-07 재확인 시점에 Stage(`koin-stage-438512.silver`)와 Production(`kap-chat.silver`) 어디에도 존재하지 않는다 — 이는 "예정 위치에 현재 산출물이 없다"는 뜻이며 "과거에 한 번도 실행되지 않았다"는 증거는 아니다. 같은 날 `INFORMATION_SCHEMA.JOBS_BY_PROJECT`를 180일 범위로 읽기 전용 조회한 결과, Stage·Production 모두 `silver_events_v2`를 생성·적재하는 job은 없었고, Production에서 찾은 유일한 관련 job(2026-08-28)은 `INFORMATION_SCHEMA.TABLES`에서 테이블 존재 여부만 확인하는 SELECT였다(생성 시도 아님). 180일 이전의 실행·삭제 이력은 job 이력 조회 범위 밖이라 미확인으로 남긴다. 별도 grain의 Gold 설계가 필요한 후속 요구사항이며 이번 문서화로 단일 Mart 제약을 변경하지 않는다. 검증 전 상태를 화면에 표시할 때는 0% 전환·100% 이탈처럼 확정값으로 보이는 수치를 쓰지 않고 "측정 불가"/"검증 대기" 같은 명시적 상태로 표시한다.

#### 퍼널 확장 후보 — 8개 대상 밖 (2026-09-07 조사, 미확정)

사용자가 언급한 실제 코인 앱 기능 중 아래는 `unmapped` 원시 화면(screen_class)으로 확인되지만, `silver_events_v2.sql` 코드에도 분류 규칙이 없어 현재 8개 확정 대상에는 포함하지 않는다. 대상 목록을 넓히려면 Silver에 새 CASE 분기 추가가 먼저 필요하다(Gold 범위 밖).

| 기능 | 실제 화면(screen_class) | 코드 분류 규칙 | 상태 |
| --- | --- | --- | --- |
| 콜벤팟 모집 | `callvanactivity` | 없음 | 미분류 확인 |
| 학교 부서정보 | `departmentactivity` | 없음 | 미분류 확인 |
| 분실물 | `lostandfoundactivity` | 없음(iOS `find_user_write`→`lost_item_write` 라벨 보정 코드는 있으나 이후 service_name 매핑 규칙 없음) | 미분류 확인 |
| 복덕방 | `landactivity` | 없음 | 미분류 확인(`used_real_estate_flg` 제외와 동일 사유) |
| 코인 for business | 전용 화면 없음, `event_name=BUSINESS` 태그만 확인 | 없음 | 미분류 확인 |
| 채팅 | `groupchatactivity` | 없음 | 미분류 확인, Stage 표본 1명뿐이라 있다/없다 단정 불가 |

**정정**: 이전 턴에 "교통편 조회하기"를 위 후보에 포함했었는데, 코드 확인 결과 이는 별도 기능이 아니라 기존 `bus` 서비스의 entry 트리거 문구 중 하나다(`event_value_norm in ('버스 시간표', '교통편 조회하기')`가 동일하게 `bus`/`entry`로 분류됨). 새 후보 목록에서 제외한다.

#### BigQuery MCP 확인 결과 및 이상 사항 (2026-09-07 조회)

- Production `kap-chat` 데이터셋 목록에는 `gold`가 없고, Production Silver 목록에는 `silver_events_v2`, `silver__users`가 없다. Stage Silver 목록에도 `silver_events_v2`는 없다. 이 문안은 운영 KPI 구현 완료를 뜻하지 않는다.
- Stage `silver__users`에는 `user_type`, `signup_completed_at`, `is_deleted`, `is_mysql_mapped`가 존재한다. 이는 현재 메타데이터 확인이며 과거 8월 검증 이력을 대체하거나 데이터 품질을 보증하지 않는다.
- Stage `silver_events_temp`의 2026-07-01~2026-08-08 표본 조회에서 account는 `login_entry` 61건/15명, `signup_start` 7건/5명, `terms_agreement` 1건/1명만 관측됐다. 정보 입력·인증·가입 완료가 이 표본에서 확인되지 않았으므로 그 시점(2026-09-07 초) 기준 확정 문안이었던 4단계 가입 퍼널은 검증되지 않았다. 표본 미관측을 운영 로깅 부재로 단정하지 않는다. **[이전 정의 검토 이력]** 이후 로컬 코드 확인으로 회원가입은 5단계(시작→약관동의→본인인증→정보입력→가입완료)로 정정됐다 — 이 문단의 "4단계"는 당시 기준이며 새 사실로 다시 쓰지 않는다. 최신 정의는 위 "회원가입 단계" 참고.
- 같은 표본에서 main은 4,300건/71명, shop `entry`는 290건/20명, `shop_view`는 3건/1명, `call`은 3건/2명이다. 이는 독립 단계별 집계이며 순서 검증된 퍼널 도달자 수가 아니다. 단순 `call 사용자 / shop_view 사용자`는 200%가 되므로 공식 전환율로 사용할 수 없다.
- 실제 `main` 단계는 `stage_scope='global'`, account/shop 단계는 `stage_scope='service'`다. 상점 퍼널을 `service_name='shop'`만으로 필터하면 메인 단계가 사라진다.
- ‘YOY로 지난 학기 대비’는 표현 수정이 필요하다. YoY는 전년 동기이며 직전 학기 비교와 다르다. 신규 방문자 수만으로 아하 모먼트 경험 여부도 판정할 수 없다.

#### Claude 검토 결과 반영 (2026-09-07, 읽기 전용 bq 재확인)

- Stage 프로젝트 `koin-stage-438512`에 `gold` 데이터셋 shell은 이미 존재하지만 내부에 테이블이 없다(`mart_kpi_user_daily` 미생성). 정의 확정이 구현 완료를 의미하지 않는다는 본문 원칙과 일치하는 추가 확인 사실이며, 이 사실만으로 운영 배포 일정을 앞당길 근거로 쓰지 않는다.
- 세션 필드 결측률(2026-07-01~2026-08-08 표본, `koin-stage-438512.silver.silver_events_temp`): `ga_session_id`는 main/account/shop 전 이벤트에서 결측 0건. `custom_session_id`는 shop 296건 전부 결측, main 4,300건 중 4,297건 결측, account 69건 중 61건 결측. 퍼널 순서 조건의 세션 필드는 `ga_session_id`로 확정한다(위 그래프 1 순서 조건 항목에 반영).
- 같은 표본에서 `account`의 `step_order`는 `signup_start`=1, `login_entry`=1(병렬), `terms_agreement`=2뿐이며 3·4에 해당하는 이벤트가 없다. 가입 관련 단계명 두 종류가 관측됐지만 당시 확정 4단계 중 두 단계가 검증된 것은 아니다. 특히 약관 동의는 정보 입력 또는 인증을 대체하지 않는다. **[이전 정의 검토 이력]** "확정 4단계"는 이후 로컬 코드 확인으로 5단계로 정정됐다(위 "회원가입 단계" 참고) — 이 문단을 새 사실처럼 인용하지 않는다.
- 핵심 계산식(`is_active_any_event`, `is_new_user`, `is_first_seen_retained`/`COUNT` 분모 처리)은 5장 Gold 계약과 문자 그대로 일치해 오류 없음. 수정한 것은 신규 유저 수의 YoY/학기 비교 표현 누락과 이탈률 "구현 상태"의 원인 서술(데이터 부재가 아니라 BI Metric 표현 한계)뿐이다.

#### 추가 문서 검토 결과 (2026-09-07)

- 이번 검토는 KPI 4개와 회원가입·주변 상점에 한정한다. 기존에 추가된 다른 서비스 퍼널 내용은 보존했으며 이번 검토로 검증 완료한 것으로 간주하지 않는다.
- Stage 동일 기간을 BigQuery MCP로 재조회해 main/account/shop의 기존 단계별 건수·사용자 수 및 GA/custom 세션 결측 수가 일치함을 확인했다. 이는 이벤트 순서·세션 관측 완료·운영 품질 검증을 뜻하지 않는다.
- 필수 수정: D7 분모를 보존하는 필터 조건 및 안전 나눗셈, 월·주간 지표의 완전 가용 시작일 확인, 주차 경계, 퍼널 단계 표시와 순차 도달 집합, 가입 2단계 대체 금지를 위 상세에 반영했다.
- 남은 구현 검증: Silver 입력 고유성·관계·필수 컬럼, 신규 사용자 D0행 완전성, D7 0/1/NULL과 사용자당 평가행 고유성, 두 주 수집 완전성, 가입 단계 매핑, 세션 키 충돌·동률·종료·지연 수집 처리, 퍼널 순차 집합 포함 관계. Silver 문제는 입력 의존성으로 보고하고 Gold에서 임의 보정하지 않는다.
- 주간 미복귀율은 일별 활동 정보가 존재하지만 현 단순 BI Metric 계약의 집합 비교 기능이 없다는 문제이고, 퍼널은 현재 USER×DAY 출력에서 이벤트 순서 정보 자체가 소실된 문제다. 두 구현 제약을 구분한다.

#### 전체 8개 퍼널 재평가 — 추가 확인 사실 및 Claude 검토 인계 (2026-09-07)

대상 8개는 유지한다. 이번 재평가는 이전의 회원가입·상점 한정 검토를 확장한 것으로, 모든 서비스의 4단계 또는 실제 전환이 검증됐다는 뜻이 아니다. 아래는 Stage 관측과 로컬 Silver V2 코드 확인을 구분한 결과다. 운영 배포 상태·원천 UI 동작을 추정하여 확정하지 않는다. 기존 표와 아래 사실이 충돌하면 기존 표를 검증 완료의 근거로 사용하지 않는다.

검증 근거:

- BigQuery MCP 읽기 전용 조회: `koin-stage-438512.silver.silver_events_temp`, `event_dt` 2026-07-01~2026-08-08. `service_name`, `funnel_stage`, `step_order`, `service_step_order`, `is_entry_event`, `is_core_action`, 원천 라벨·값과 세션 결측을 확인했다.
- 로컬 코드 읽기: `dbt/models/silver/silver_events_v2.sql`의 서비스 분류, 단계 분류, `step_order`, `is_core_action`. 코드 존재는 Stage/Production 배포나 실제 이벤트 수집 증거가 아니다.
- 아래 숫자는 단계별 독립 고유 사용자 수이며 순차 퍼널 도달자 수가 아니다. 회원가입은 시작 5명·약관 동의 1명, 공통 main은 71명이다. 8개 service의 표본 이벤트에서 `ga_session_id` 결측은 0건이지만 세션 키 충돌·관측 완료·순차 경로는 미검증이다.

| 퍼널 | Stage 관측: 단계별 사용자 수 | 로컬 V2 코드 확인 | 재평가 |
| --- | --- | --- | --- |
| 회원가입 | signup_start 5, terms_agreement 1 | 시작 1 → 약관 2 → 인증 3 → form_entry 4 → 완료 5 | 확정 문안은 정보 입력→인증인데 코드 순서는 인증→form_entry다. 실제 UI·이벤트 의미를 확인해야 하며 문안 또는 Silver 순서를 임의 변경하지 않는다. |
| 상점 | entry 20, shop_view 1, call 2 | call이 핵심 액션 | 단계 이벤트 존재만 확인. 실제 순차 전환은 미검증이다. |
| 버스 | entry 1, set_od 3, search 1 | set_od는 출발지 확인 또는 도착지 확인 중 하나만 있어도 분류 | ‘출발·도착 모두 설정 완료’로 표현하면 과장이다. 한쪽 설정 확인이라는 이벤트 의미와 실제 필수 경로를 검증한다. |
| 식단 | entry 1, explore 5 | explore는 menu_time, core는 menu_share→share | 4단계 규칙은 존재하지만 share는 표본 미관측. 메뉴 확인과 공유 완료는 다른 성과다. 공유를 서비스 이용 성공 전체로 해석하지 않는다. |
| 시간표 | entry 7, explore 4 | explore는 검색·학기/교육과정 선택, core는 이미지저장→save | 4단계 규칙은 존재하지만 save는 표본 미관측. 시간표 작성·수업 추가 완료로 임의 해석하지 않는다. |
| 졸업계산기 | entry 2, explore 1 | entry/explore만 존재, 해당 서비스 core 분기 없음 | 단순 표본 부족이 아니라 로컬 코드에서 4단계 분류 규칙 자체가 없다. 계산 완료 이벤트를 임의 가정하지 않는다. |
| 팀원모집으로 표기된 board | entry 6 | main_notice, notice_tab/search, popular_notice 등 게시판·공지 관련 규칙; core는 read | Stage entry 19건은 main_notice/main_notice_detail이며 값은 ‘공지사항’이다. board=팀원모집 매핑은 근거가 부족하고 다른 서비스를 집계할 위험이 있다. 실제 팀원모집 이벤트 대응을 검증해야 한다. |
| 시설 | entry 5 | 메뉴의 ‘교내 시설물 정보’ 진입만 분류, 탐색·core 분기 없음 | 로컬 코드에 3·4단계 규칙이 없다. 누락 단계의 이탈률을 100%나 완료율을 0%로 만들지 않는다. |

반드시 구분할 문제:

1. 대상은 전체 서비스지만 공통 4단계는 분석 요구 구조다. 서비스별 실제 경로와 이벤트 매핑이 검증됐다는 뜻이 아니다. 특히 졸업계산기·시설은 코드 규칙 부재, 식단·시간표는 규칙 존재/표본 미관측으로 상태가 다르다.
2. 기존 표의 ‘미계측’은 원천 미수집으로 오해될 수 있다. ‘표본 미관측’, ‘로컬 분류 규칙 없음’, ‘서비스 매핑 미검증’을 구분한다. ‘4단계 전부 확인’도 ‘단계 이벤트 존재 확인, 순차 전환 미검증’으로 표현해야 한다.
3. `step_order`는 분류상의 순서이고 실제 이벤트 시간 순서나 필수 행동을 보증하지 않는다. `service_step_order`는 표본에서 NULL이 많으므로 대체 순서 키로 바로 사용할 수 없다.
4. `is_core_action=true`는 분류 계약이다. 식단 공유·시간표 이미지 저장·게시판 읽기를 모든 서비스의 동일한 이용 성공으로 취급하거나 서비스 간 전환율 순위를 그대로 품질 순위로 해석하지 않는다.
5. 메인부터 시작하는 퍼널은 ‘메인 경유 경로’를 평가한다. 직접 진입·저장된 설정 등으로 특정 단계를 생략하는 이용은 제외될 수 있으므로 미전환을 모두 불편 또는 이용 실패로 단정하지 않는다.
6. 본 재평가로 확정 KPI·서비스 대상을 바꾸거나 Silver 수정을 사용자 작업으로 추가하지 않는다. 문제가 있는 서비스는 대상 목록을 유지하고 검증 전 수치 제공 상태를 구분한다. Gold 물리 계약 확장이나 별도 Mart 구현은 승인된 것으로 간주하지 않는다.

Claude에게 요청할 후속 검토:

- 위 8개 각각에 대해 ① 반드시 고칠 문서 오류 ② 구현 전 검증 조건 ③ 해당 서비스 퍼널 상세 최종 문안을 작성한다.
- board=팀원모집의 근거, 가입 단계 순서, 버스 set_od의 완료 의미, 식단/시간표 핵심 액션의 실제 의미, 졸업계산기/시설 분류 부재를 우선 검토한다.
- 서비스별 필수 경로·반복 시도·직접 진입·순차 도달 집합·세션 키·관측 완료·필터 범위를 검토한다. 실제 순차 전환을 재현하지 않았다면 ‘검증 완료’라고 쓰지 않는다.
- 확정 정의와 충돌이 발견되면 근거 및 최소 수정안을 제시하되 임의로 지표 정의를 교체하지 않는다. 제품 의미 판단에 필요한 자료가 없다면 정확히 무엇이 부족한지 적는다.

#### Claude 검토 요청문 — 복사해서 사용

아래 요청에 따라 이 문서의 6.11절에 작성된 KPI 4개(MAU, 신규 유저 수, 리텐션, 이탈률)와 퍼널 상세 문안을 검토해 주세요. 작업 범위는 문서 검토와 문구 수정 제안이며 코드 구현·배포가 아닙니다.

이 문서의 5장은 Gold 계약, 6장은 BI 카탈로그입니다. 6.11절은 사용자가 확정한 지표 요구사항입니다. 기존 물리 계약과 구분해 읽고 지표 선정·정의를 다시 미확정 상태로 돌리지 마세요. 특히 현재 Gold는 `event_dt × user_pseudo_id` grain의 38컬럼 단일 Mart이며, 정확한 DN 리텐션은 지원하지만 Range 리텐션·일반 이탈률·순서 기반 퍼널은 현 계약에서 지원하지 않습니다. 사용자의 구현 범위는 Gold뿐입니다. Silver 수정이나 별도 Mart 추가를 이미 승인된 작업으로 간주하지 마세요.

검토할 내용:

1. 각 지표의 목적과 정의·분모·분자·기간·필터·활동 기준이 서로 맞는지 확인해 주세요. 특히 MAU의 Any Event와 리텐션의 Entry 기준 차이가 혼동을 만들지 검토해 주세요.
2. 확정된 최초 방문 D7 리텐션의 설명과 계산이 일치하는지 확인해 주세요. 특정 날짜 재방문과 Range 리텐션을 구분하고, 도메인 관행을 주장한다면 확인 가능한 출처를 제시해 주세요. 현재 데이터만으로 최적의 N을 확정하지 마세요.
3. 이탈률의 확정 정의인 ‘기준 주 활성 사용자 중 다음 주 미복귀 비율’이 목적에 적합한지, ‘주간 미복귀율’이라는 명칭이 정확한지 검토해 주세요. D7의 여집합이나 회원 탈퇴율과 혼동하지 마세요.
4. 월 KPI와 주간 미복귀 지표의 날짜 필터가 일관적인지, 미완료 관측 기간과 소표본 처리가 적절한지 확인해 주세요.
5. 퍼널의 첫 단계 모집단, 동일 세션 내 순서, 중복 제거, 종료일 경계, 가입 인증 중 세션 분리, 직접 상점 진입 경로를 검토해 주세요. Stage의 독립 단계별 사용자 수를 실제 퍼널 전환율로 사용하지 마세요.
6. BigQuery 확인 사실, 기존 계약으로 지원 가능한 항목, 추가 구현 설계·검증이 필요한 항목이 명확히 구분됐는지 확인해 주세요. Stage 표본만으로 Production의 이벤트 누락이나 성과를 단정하지 마세요.

답변은 (1) 반드시 고칠 오류, (2) 확정 정의를 구현하기 위한 남은 조건, (3) 노션 ‘상세’에 붙여 넣을 최종 문안 순서로 작성해 주세요. 최종 문안은 KPI 4개와 퍼널만 포함하고 목적·대상·정의·계산·기간·단위/차트·해석 주의·구현 가능 여부를 유지해 주세요. 정의 확정과 구현 완료는 구분하고, 현 계약으로 지원하지 않는 지표를 구현 가능한 것처럼 쓰지 마세요.


### 6.12 대시보드 전체 요구사항 대비 Gold 점검 (2026-09-09)

#### 점검 범위와 결론

사용자가 전달한 확정 KPI 4개와 그래프 6개를 현재 로컬 SQL·YAML·테스트와 대조했다. 이는 정적 코드/문서 검토이며 이번 점검에서 BigQuery 테이블 조회, dbt 실행, 배포 또는 실제 수치 검증은 하지 않았다. 6.11의 과거 실측은 그 날짜의 이력으로 유지한다.

현재 `mart_kpi_user_daily`는 `event_dt × user_pseudo_id` 38컬럼이다. MAU·신규 유저 수 및 현재 서비스 활동 정의에 따른 이용자 집계에는 적합하지만, 이번 대시보드 전체를 현 단일 테이블의 단순 BI Metric만으로 구현할 수는 없다. 아래에서 “추가 계산”은 필요한 데이터는 일부/전부 남아 있으나 현재 제공 계약에 계산이 없다는 뜻이고, “정보 부족”은 Gold에서 집계하며 원천 정보를 잃었다는 뜻이다. 요구사항을 삭제하거나 기존 DN 지표로 대체하지 않는다.

#### 구성요소별 지원 판정

| 구성요소 | 현재 Gold 지원 | 필요한 조건/추가 설계 |
| --- | --- | --- |
| MAU | 컬럼으로 지원 가능 | 기준 월에 `COUNT(DISTINCT IF(is_active_any_event=1,user_pseudo_id,NULL))`. 무활동 spine 행을 세지 않는다. 월초~완전 가용일까지 및 YoY 동일 관측 구간을 적용한다. |
| 신규 유저 수 | 컬럼으로 지원 가능 | 기준 월 `SUM(is_new_user)`. 기준 월이 완전 가용 구간에 포함되고 해당 월 최초 관측 사용자의 D0행이 정확히 1개인지 확인한다. 가입자 수와 구분한다. |
| D1~D7 범위 리텐션 | 사용자별 추가 계산 필요 | `first_seen_dt` 코호트와 사용자별 D1~D7 Entry OR/MAX, 7일 전체 성숙 판정이 필요하다. 일별 사실은 있으나 단순 DN 비율 집계는 오답이다. |
| 주간 미복귀율 | 주간 사용자 집합 비교 필요 | 기준 주 Any Event 사용자 집합에서 다음 주 집합을 뺀다. 두 주 전체의 수집 완전성을 보장해야 하며 `had_entry_prev_day`로 대체할 수 없다. |
| 서비스별 퍼널 | 현 Gold 정보 부족 | 최종 Gold에 세션 키, 이벤트 시각·순서, 퍼널 단계가 없다. Gold 소유 계산에서 Silver 계열 이벤트를 입력받아 동일 세션의 순차 경로를 판정할 별도 grain 설계가 필요하다. |
| 서비스별 일간 코호트 리텐션 | 코호트 생성·미복귀 분모 보존 추가 필요 | 현재 anchor는 전체 최초 관측/가입뿐이다. 서비스와 임의 시작일의 활동 사용자 코호트는 별도 `service × anchor_dt × user × offset` 논리가 필요하다. 현재 서비스 플래그로 활동 기반 집합을 일부 재구성할 수 있지만 단순 차트 필터로는 불가하다. |
| 서비스별 주간 리텐션 커브 | 정의 확정 및 구간 집계 필요 | 기준일, Week 구간, 서비스 복귀 조건, 신규/기존 분류를 고정한다. 주간 1회 이상 복귀는 일별 비율 평균이 아니라 사용자별 주간 OR 집계다. |
| 서비스별 기간 이용 사용자 수 | 전체 사용자 수 조건부 가능 / 서비스 신규 분리 부족 | 서비스별 `COUNT(DISTINCT IF(used_*_flg=1,user_pseudo_id,NULL))`. 기간 전체에서 SUM하면 사용자일 수가 된다. 서비스 최초 이용일은 없으므로 서비스 신규/기존 분리는 추가 설계가 필요하다. |
| 서비스별 DAU·WoW | 현재 활동 정의로 조건부 가능 | 날짜별 서비스 이용자를 집계하고 7일 전 같은 요일과 비교한다. 신규/기존의 기준을 통일하고 비교 양쪽 수집이 끝난 날짜만 비교한다. |
| 서비스별 이탈률 | 정의 미완성 / 이후 추가 계산 | 분모 서비스 이용 기간과 미복귀 기간, 해당 서비스 미복귀인지 앱 전체 미복귀인지 정해야 한다. 이후 서비스별 사용자 집합 비교가 필요하다. |

#### 현재 SQL에서 확인한 주의사항

1. 서비스 활동 기준이 통일되어 있지 않다. shop/bus/board/facility/timetable/grad_calc는 Entry 발생, cafeteria/account는 해당 service의 Any Event 발생으로 `used_*_flg`를 만든다. 따라서 차트에서 모두 “이벤트가 발생한 서비스 이용자” 또는 모두 “Entry 활성 사용자”라고 부르면 안 된다. 거버넌스 정의와 비교한 뒤 Gold 서비스 사실을 설계한다. 기존 플래그 의미를 몰래 바꾸지 않는다.
2. `used_main_flg`가 없다. 실제 메인 화면 활동과 코인 전체 활성 사용자는 다르며 서비스 이용자 수의 합은 중복 때문에 전체 사용자 수도 아니다. 실제 메인이면 별도 main 활동 사실이 필요하고, 전체이면 이름을 “코인 전체”로 표시한다. 요구 문구의 “모든 서비스”도 현 8개 플래그로 모든 앱 기능을 포괄한다는 뜻이 아니다. board는 공지사항이며 팀원모집으로 재해석하지 않는다. club은 기존 제외 범위를 유지한다.
3. `first_seen_dt`는 코인 전체 최초 관측일이다. 사용자의 첫 이벤트가 bus라고 해서 이후 최초 이용한 shop의 서비스 신규 여부를 알 수는 없다. “전체 신규의 최초 유입 서비스”와 “서비스별 최초 이용 사용자”는 다른 분석이다. 후자를 원하면 충분한 과거 이력에서 서비스별 최초 활동일이 필요하다. 현재 day grain에서는 첫날 여러 서비스의 시간 순서도 복원할 수 없다.
4. 무활동 날짜는 0으로 채운 spine 행이 있다. MAU/DAU에 무조건 COUNT DISTINCT를 적용하면 무활동 사용자까지 센다. 반대로 리텐션 전체에 active/service=1 필터를 걸면 미복귀 분모가 사라진다.
5. `platform_dominant` 등은 일별 대표값이고 무활동 날은 unknown이다. 리텐션에 평가일 플랫폼 필터를 적용하면 분모가 왜곡될 수 있다. 코호트 기준일의 속성으로 사용자 집합을 먼저 고정할지 정해야 한다. gender/major/user_type 등도 현재 User 스냅샷이며 과거 당시 상태가 아니다.
6. 완전 가용 시작/종료일은 Intermediate 변수로 사용되지만 최종 38컬럼에 관측 기준일 메타데이터가 없다. 더구나 event_user_day는 구간 밖 이벤트 날짜도 보존한다. MAU/DAU가 자동으로 수집 완료일까지 잘린다고 가정하지 않는다. 빌드와 같은 완전성 기준을 BI에 전달하고 구간 안의 수집 누락도 확인해야 한다.
7. 로컬 구현이 5장 일부 서술과 다르다. 현재 Gold는 `int__event__service_classification`을, spine은 `silver_events`를 참조한다. 분류 Intermediate는 legacy `silver_events`에 분류를 재현하는 임시 모델이다. 문서의 `silver_events_v2` 직접 참조와 다르며 현재 경로 자체를 기록한다. 이 임시 모델의 코드 존재는 배포·승인 이력 또는 분류 정확성의 증거가 아니다. 서비스 분류 모델이 이벤트를 추가/누락/중복하지 않는지 별도 검증하고 최종 입력 경로를 정합화해야 한다. 이번 점검에서 Silver 또는 분류 규칙은 수정하지 않았다.
8. 현 활동 대조 테스트는 expected와 Gold를 inner join하므로 그 테스트 단독으로 누락 행을 잡지는 못한다. spine의 Event 보존 테스트는 존재하지만 최종 Gold는 User inner join을 하므로 최종 출력까지의 양방향 USER×DAY 보존 검증도 필요하다. 분류 단계에서 잘못 분류된 이벤트는 같은 분류 모델을 읽는 집계 대조만으로 검출되지 않는다.

#### 지표 문서에서 먼저 정할 내용

- 이탈률: 사용자 제공 문안의 정의·계산식은 “다음 주 미복귀”인데 분자만 “4달 동안 이벤트 없음”이다. 기존 6.11 계약과 나머지 정의에 맞춘 수정안은 **“기준 주 활성 사용자 중 바로 다음 주에 이벤트가 한 번도 발생하지 않은 고유 사용자 수”**다. 4개월 이탈을 의도했다면 별도의 지표·관측 기간 설계가 필요하며 이번에 임의 전환하지 않는다.
- 신규 사용자: 월 KPI는 코인 전체 최초 관측으로 유지한다. 서비스 차트는 서비스 첫 이용 기준인지 전체 신규 기준인지 범례에 적는다. 기간 이용자 막대에서는 서비스 신규 집합을 먼저 정한 뒤 기존=전체 이용자−신규로 만들어 기간 안의 중복 분류를 막는다. 일별 신규/기존은 날짜마다 재분류될 수 있으므로 기간 고정 분류와 구분한다.
- 서비스별 코호트: “시작일 활동한 모든 사용자”와 “그날 서비스 최초 이용자” 중 기준을 명시한다. 현재 목적 문구는 전자까지 포함하므로 `first_seen_dt` 코호트로 대체하면 안 된다. 전자에서는 같은 사용자가 여러 시작일 코호트에 들어갈 수 있다. D0는 같은 서비스의 기준 활동이며 이후 같은 서비스 복귀인지 앱 복귀인지 고정한다.
- 리텐션 커브: Day 0 기준 비율을 비교하는 커브의 X축은 기준일 이후 경과 주차가 적합하다. 실제 달력 주간 추이와 경과 주차 커브는 다르다. 주차를 기준일 상대 D1~D7/D8~D14로 할지 월~일 달력 주로 할지 명시한다. 신규/기존은 anchor 시점에 고정한다. 여러 일 코호트를 합치면 분모 가중 방식과 중복 사용자 처리 단위도 명시한다.
- 서비스별 이탈률: 우선 문서화할 후보는 “기준 주에 해당 서비스를 이용한 사용자 중 다음 주 해당 서비스 미이용 비율”이다. 이 경우 다른 서비스를 계속 이용해도 해당 서비스 미복귀자다. 확정된 앱 전체 이탈률과 같은 Any Event 정의를 쓰는지 현 서비스 플래그 정의를 쓰는지 명확히 한다. 아직 확정 정의로 간주하지 않는다.
- 일간 코호트는 그룹의 날짜별 복귀 패턴을 보여주며 개인별 반복 빈도나 같은 사람이 매일 복귀했는지를 직접 보여주지 않는다. 배너·UI 노출과 성과의 관계는 노출·실험군 정보가 필요하고, 현 Gold에는 없다. 단순 코호트 차이로 원인이나 선호를 확정하지 않는다.
- 필터: 월 카드, first_seen 월 코호트, 두 주 비교, 퍼널 시작 세션, 서비스 코호트는 날짜의 역할이 다르다. 모든 차트에 같은 event_dt 필터를 일괄 적용하지 않는다. YoY는 전년의 대응 구간이며 과거 데이터가 없으면 비교 N/A다.

#### Gold 범위 내 구현 설계 방향 — 검토안, 계약 변경 아님

1. 현 USER×DAY 마트는 전체 활동과 현재 정의에 따른 서비스 이용량의 기반으로 유지한다.
2. 범위 리텐션과 주간 미복귀는 현 일별 사실에 필요한 정보가 남아 있으므로 사용자별 구간 판정을 Gold 소유 Intermediate에서 계산하고 BI가 집계할 평가 사실을 제공하는 방안을 설계한다. 고정 D1~D7 플래그를 추가하는 안이라면 사용자당 한 평가행에만 적재해 중복 합산을 막고, 성숙 여부/기준일/0·NULL 계약을 함께 설계한다. 이는 38컬럼 계약 확장 후보이며 이미 구현한 내용이 아니다. Gold→Gold 참조를 추가하지 않는다.
3. 서비스 분석은 서비스별 활동·최초 활동일과 기준일 사용자 집합이 필요하다. wide 형식 확장 또는 USER×SERVICE×DAY 기반 후속 설계를 비교할 수 있으나, 새 물리 Mart를 자동 추가하지 않는다. 임의 anchor의 코호트는 활동 사실만 있어도 BI의 단순 집계로 즉시 만들 수 있는 것은 아니며 분모 집합·평가일 완전성 계산 계층이 필요하다.
4. 퍼널은 Event/Session 정보로 돌아가 순차 경로를 판정해야 한다. 후보 grain은 `funnel_version × funnel × user × session × anchor_dt`이며 완료된 세션의 순차 도달 단계와 사용자 식별자를 보존한다. 날짜별 사용자 수만 미리 합산하면 조회 기간 전체 DISTINCT를 복원할 수 없다. 첫 단계 진입 시점과 반복 시도 선택, 세션 키의 스트림 간 충돌, 시각 동률·지연 수집·세션 완료를 명시한다. 결과가 필요하면 별도 grain의 Gold 출력 계약 검토가 필요하다.
5. 따라서 **단일 38컬럼·직접 조회·단순 Metric 제약을 모두 그대로 유지하면 확정 대시보드 전체 구현은 불가능**하다. 지표 요구를 유지하려면 Gold 출력 또는 계산 계층의 확장 설계가 필요하다. 이번 점검은 이 차이를 구체화한 것이며 Silver 수정·새 Mart 생성·배포를 수행하거나 승인된 것으로 간주하지 않는다.

#### 구현 전 통과해야 할 검증

- 입력/출력: 원천 Event 고유성, 분류 전후 event_id 보존, Gold 적격 Event→User 관계, 최종 USER×DAY 유일성·양방향 보존, 서비스별 대표 경로의 라벨/Entry 의미를 확인한다.
- MAU/신규: 같은 사람이 여러 날짜·서비스에 방문해도 월 1명, 무활동 spine 제외, 대상 월 신규 D0행 1개, 수집 시작 전/미완료 월 표시를 확인한다. 대상 기간 밖의 오래된 사용자에게까지 신규 D0행을 요구하지 않는다.
- Range: D0만 활동=미복귀, D1만 복귀=복귀, D7만 복귀=복귀, 여러 날 복귀=1명, 완전 관측 미복귀=분모 포함, 이미 복귀했어도 미성숙=양쪽 제외, 월말 유입의 다음 달 관측을 확인한다. 분모 0 및 기존 30명 미만 표시 정책을 유지한다.
- 주간 미복귀: 기준 주만/양쪽/다음 주만 활동하는 사례와 월 경계, 불완전 주차 제외를 확인한다. 서비스 미복귀는 다른 서비스만 사용한 사례를 포함한다.
- 코호트/커브: 신규·기존 기준 고정, 서비스 간 분모 비혼합, 미복귀 0/미평가 NULL, D365 이후 기존 사용자의 임의 시작일 코호트까지 누락 없이 평가하는지 확인한다. 현 최초관측 D0~D365 spine이 모든 임의 시작일 평가행을 제공한다고 가정하지 않는다.
- 퍼널: 세션 간 단계 결합 금지, 순서 역전/반복/직접 진입/자정 통과/동률/미완료 세션 사례와 `U_last ⊆ ... ⊆ U_1`을 검증한다. 분모 0·검증 대기는 N/A/검증 대기로 표시한다.

현재 점검 결과는 코드/문서 대조이며 위 실행 검증을 통과했다는 의미가 아니다.


### 6.13 확정 10개 구성요소와 수정 Gold 설계 연결 (2026-09-09)

이 절은 2026-09-09 단일 Gold안의 대응 이력이다. 최신 사용자 제공 2개 Gold 계약은 5.0.11, KPI 4개·퍼널의 새 구현 계약은 6.14를 우선한다. 아래 daily/retention/funnel은 당시 단일 Gold의 논리 사실이다.

| 번호 | 구성요소 | 논리 데이터 | 필요한 필터·계산 | 상태 |
| --- | --- | --- | --- | --- |
| 1 | MAU | daily | 월 범위, Any Event 조건부 사용자 DISTINCT, YoY 동등 관측 | 현 컬럼 가능, 실행 검증 필요 |
| 2 | 신규 유저 수 | daily | 같은 월 범위 is_new_user SUM, D0 유일성 | 현 컬럼 가능, 실행 검증 필요 |
| 3 | D1~D7 범위 리텐션 | retention | first_seen/__all__/range_d1_d7, anchor 월, SUM(returned)/SUM(eligible) | 사용자 구간 사실 추가 |
| 4 | 이탈률(주간 미복귀) | retention | weekly_active/__all__/next_calendar_week, 가장 최근 완료 주차 쌍, SUM(not_returned)/SUM(eligible) | 주간 사실 추가; 4개월 문구 정정 |
| 5 | 퍼널 | funnel | 퍼널·버전·anchor 기간·완료 세션, 단계별 조건부 DISTINCT | 이벤트 순차 모델 추가 |
| 6 | 코호트 리텐션 | retention | service_active_day/exact_day, 서비스·anchor별 경과일 | 서비스 활동 코호트 추가 |
| 7 | 리텐션 커브 | retention | service_active_day/relative_week, 고정 anchor의 경과 주차 | 주간 사실 추가; 기간 통합 기준 미확정 |
| 8 | 서비스별 이용자 | daily | 기간 서비스 이용자 DISTINCT, 서비스 최초일로 신규/기존 분리 | 서비스 최초일·활동 정의 추가 |
| 9 | 서비스별 DAU | daily | 날짜별 서비스 이용자, 같은 요일 WoW, 신규/기존 배타성 | 기본 활동 가능; 서비스 신규 분리 확장 |
| 10 | 서비스별 이탈률 | retention | weekly_active/서비스/next_calendar_week | 동일 서비스 미복귀 정의 제안, 확정 후 구현 |

서비스 거버넌스와 신규 정의, 여러 anchor를 합친 고유 사용자 주간 커브 기준이 남아 있으므로 해당 항목은 “설계 조건 남음”으로 관리한다. 차트가 단순 수치로 보인다고 기존 컬럼만으로 지원 완료 표시하지 않는다. 미관측·미완료·입력 결손·검증 대기는 0이나 100% 이탈 대신 N/A/검증 대기로 표시한다.

### 6.14 Superset 불변식 및 계산 필드 — KPI 4개와 퍼널 (2026-09-10)

#### 적용 범위와 실제 지원 상태

사용자 제공 「Superset 불변식 및 계산 필드 — 확정 그래프 2~6」에 이어 붙일 보완 문안이다. KPI와 그래프 번호를 혼동하지 않는다. 5.0.11의 사용자 44/집계 20컬럼이 출발점이며, 아래 새 지표 종류 및 퍼널 중첩 컬럼은 구현 전 제안이다. 운영 SQL 실행·BigQuery 배포·Superset 등록을 수행한 결과가 아니다.

| 항목 | 조회 대상 | 추가 계약 | 상태 |
| --- | --- | --- | --- |
| KPI 1 MAU | 사용자 Gold | 월 필터·완료 범위 연결 | 44컬럼으로 표현 가능 |
| KPI 2 신규 유저 수 | 사용자 Gold | 최초 관측일 행 보존 검증 | 44컬럼으로 표현 가능 |
| KPI 3 D1~D7 Range Entry 리텐션 | 집계 Gold | first_seen_range_entry_d1_d7 추가 | 20컬럼 유지 가능, 기존 3종 metric_type만으로는 불가 |
| KPI 4 다음 주 앱 미복귀율 | 집계 Gold | app_weekly_nonreturn 추가 | 20컬럼 유지 가능, churn_56d 재사용 불가 |
| 그래프 1 순서 기반 퍼널 | 사용자 Gold 확장안 + 표시용 Dataset | funnel_session_facts 중첩 컬럼 추가 | 45/20컬럼 확장안. 엄격한 44/20 계약에서는 미지원 |

**필수 문구 정정**

- KPI 이탈률의 분자에 있던 “4달 동안 이벤트 없음”은 목적·정의·계산식과 충돌한다. 이 문서에서는 나머지 정의와 일치하는 **“기준 주 활성 사용자 중 바로 다음 주에 이벤트가 한 번도 없는 사용자”**로 정정한다. 4개월 미이용 KPI를 새로 도입하지 않는다.
- 전체 앱 코드는 `__all__`, 실제 메인 화면은 `main`이다. 서비스 이탈 그래프의 56일 판정과 앱 KPI의 다음 주 미복귀를 분리한다.
- 그래프 2·3의 고정 일별 코호트와 KPI 3의 최초 방문 코호트는 다르다. 기간/분모/활동 기준이 다른 지표를 공통 Metric 하나로 통일하지 않는다.

#### 공통 날짜·필터·입력 위치

- GoogleSQL 참조 SQL의 `@start_dt`, `@end_dt`는 포함 경계 KST DATE다. `@event_complete_start_dt`, `@event_complete_dt`는 해당 공개 build의 검증된 메타데이터다. SQL Lab/클라이언트에서 바인딩하며 Calculated Column에 붙이지 않는다.
- `M=DATE_TRUNC(@start_dt, MONTH)`, `E=LEAST(LAST_DAY(M), @event_complete_dt)`다. KPI 월은 시작일이 속한 달이다. 선택 종료일이 다음 달이어도 KPI 월을 늘리지 않는다. 퍼널은 선택 시작~종료일을 그대로 쓴다. **(2026-09-18 범위 한정)** M은 선택 월의 시작일이다. E는 YoY 등 검증 완료 범위를 사용하는 별도 비교 Metric의 비교 종료일로만 쓴다. **MAU·신규 카드 본값의 자동 상한이 아니며**, 카드 본값은 Superset이 선택한 event_dt 범위를 그대로 사용한다(캡핑 없음).
- **(2026-09-18 변경)** MAU/신규 카드는 물리 사용자 Gold(`mart_kpi_user_daily`)에 직접 연결하고, 자동 완료 캡핑(LEAST/NULL 처리)을 두지 않는다. 카드 값은 선택한 기간(Superset Time Range) 안에서 **조회 시점에 Gold에 존재하는 행의 부분 집계값**이다. `event_complete_dt`는 이 값을 자동으로 잘라내는 상한이 **아니라** 연속 수집 완전성이 검증된 마지막 날짜이며, 카드 값에는 `event_complete_dt` 이후에 들어온 부분 적재 행이 포함될 수 있으므로 이를 월 완료값으로 해석하지 않는다. 카드 옆에 `MAX(event_complete_dt)`를 "검증 완료 기준일" 각주로 항상 병기해 이후 날짜의 부분 적재 행이 카드에 포함될 수 있음을 안내한다. 이 정책은 미적재 미래 월과 실제 0명을 Metric만으로 완전히 구분하지 못할 수 있다는 운영상 한계를 동반하며, 이를 보장되는 불변식처럼 설명하지 않는다. 아래 KPI 1·2의 "완료 조건" 행도 이 변경을 반영한다.
  - 변경 이력(2026-09-18): 이전의 월 완료 여부 기반 자동 NULL 캡핑 정책은 폐기하고, 물리 사용자 Gold 직접 집계와 검증 완료 기준일 각주 방식으로 변경했다.
- `user_snapshot_at`, `build_id`, 완료 범위는 사용자 필터와 독립된 배치 제어값이다. 필터 결과가 0행이어도 관측 여부를 판단할 수 있어야 한다. NULL/누락/두 테이블 불일치 시 카드 계산을 차단한다.
- 성별·학과·입학연도·사용자 유형은 분자·분모에 동일한 현재 Snapshot 조건을 적용한다. 전체 앱 KPI에 서비스 필터를 연결하지 않는다. 회귀용 일간 활동 플래그 필터를 리텐션/이탈 Dataset 전체에 걸지 않는다.
- 기간 필터가 기본적으로 전달하는 임의 범위와 M~E가 다를 수 있다. **(2026-09-18 변경)** MAU/신규의 카드 값 자체는 물리 Dataset에 직접 연결한 Superset 기본 Time Range("이번 달" 등)만으로 계산하므로 별도의 KPI 전용 월 필터·날짜 변환 Dataset이 더 이상 필수는 아니다. 다만 아래 YoY 비교(같은 경과일수 비교)에는 M~E 계산이 여전히 필요하며, 그 경우에 한해 날짜 변환 Dataset이나 Calculated Column을 쓴다. Superset `get_time_filter(..., remove_filter=True)`를 쓴다면 외부 원래 시간 조건이 중복 적용되지 않는지도 검증한다.
- SUM/COUNT/COUNTIF는 Metrics → SQL expression, 행 단위 식은 Calculated Columns, 전체 SELECT는 Dataset SQL 또는 참조 SQL이다. 저장 Metric 이름을 다른 Metric의 SQL 컬럼처럼 참조하지 않는다.
- 비율 Metric은 0~1, 표시 형식 `.1%`. 인원은 정수. 집계 비율을 AVG하지 않는다. 분모 0은 N/A. 기존 소표본 규칙(리텐션 평가 가능 인원 30명 미만 비율 숨김)은 KPI 3에 유지하고 분모 자체는 표시한다.

#### KPI 1. MAU — 기준 월 활성 사용자 수

**목적·대상·정의**

코인 전체의 월간 활성 사용자 규모를 확인하여 서비스 성장·정체와 학사 일정·홍보·기능 출시 전후의 변화를 파악한다. 회원·비회원을 포함한 pseudo 기준이며, **(2026-09-18 변경)** Superset에서 선택한 **단일 달력 월**의 event_dt 범위 안에 Event가 한 번 이상 존재하는 고유 사용자 수다. 별도 E 캡핑은 하지 않는다. UI/UX 개선의 인과 효과를 이 수치만으로 단정하지 않는다.

**자연어 불변식 (2026-09-18 개정)**

1. 한 사용자가 여러 날·여러 서비스를 이용해도 선택 월에 한 명으로 센다.
2. `is_active_any_event=1`인 사용자만 센다. Event 없는 가입일 행은 제외한다.
3. 같은 기간과 사용자 필터에서 일별 이용자 수는 MAU보다 클 수 없다.
4. 같은 조건에서 신규 사용자 수는 MAU 이하여야 한다.
5. 진행 월은 조회 시점까지 적재된 누적 부분값을 표시하고 데이터 기준일을 함께 표시한다.
6. 미적재 기간과 실제 0명은 단순 Metric만으로 자동 구분되지 않을 수 있으며, `data_as_of_dt`(검증 완료 기준일)와 No data 상태를 함께 확인한다.

**실제 BI 입력**

Dataset: `kap-chat.gold.mart_kpi_user_daily`.

Metric `mau_users`:

```sql
COUNT(DISTINCT CASE WHEN is_active_any_event = 1 THEN user_pseudo_id END)
```

| 차트 항목 | 설정 |
| --- | --- |
| 차트 | KPI 카드 / Big Number |
| Metric | mau_users |
| 시간 조건 | **(2026-09-18 변경, 2026-09-18 단일월 제약 추가)** Superset이 선택한 **단일 달력 월**의 `event_dt` 범위를 그대로 사용(별도 E 캡핑 없음). 시간 범위는 선택 월 1일 이상, 다음 달 1일 미만으로 설정한다 |
| Group by | 없음 — 월 안의 날짜를 다시 분리하지 않음 |
| 속성 필터 | gender / major / entry_year / user_type |
| 제외할 전역 필터 | 서비스, cohort_user_segment, 신규/기존 분류 |
| 제목·보조 정보 | 기준 월 MAU, 실제 조회 기간, `data_as_of_dt`(검증 완료 기준일) 각주 |
| 완료 조건 | **(2026-09-18 변경)** 자동 캡핑·NULL 처리 없음. 조회 시점에 Gold에 존재하는 행을 그대로 집계한다. `event_complete_dt`는 자동 상한이 아니라 검증 완료 기준일이며 각주로만 안내한다(이후 날짜의 부분 적재 행이 카드에 포함될 수 있음) |

**(2026-09-18 설정 제약 추가) MAU·신규 월 카드는 한 번에 하나의 달력 월만 선택한다.** 시간 범위는 선택 월 1일 이상, 다음 달 1일 미만으로 설정한다. 여러 달을 한 카드에서 합쳐 `COUNT DISTINCT`한 값은 "기간 고유 활성 사용자"이며 MAU로 표시하지 않는다. 월별 추이 차트는 calendar month로 그룹화해 각 월을 독립 집계한다. 신규 사용자도 MAU와 동일한 단일 월 필터를 공유해야 한다. 이 제약은 E 캡핑을 다시 도입하는 것이 아니다 — 선택 월 전체 범위 안에서 현재 존재하는 행을 직접 집계하는 정책은 그대로 유지한다.

**MAU·신규 카드 Metric (2026-09-18 변경, 직접 연결)** — Virtual Dataset 없이 물리 Dataset `kap-chat.gold.mart_kpi_user_daily`에 바로 등록한다.

```sql
-- Metric: mau_users (위 mau_users와 동일 식, 참고로 재게시)
COUNT(DISTINCT CASE WHEN is_active_any_event = 1 THEN user_pseudo_id END)

-- Metric: new_users
COALESCE(SUM(is_new_user), 0)

-- Metric: new_users_distinct — 검증용
COUNT(DISTINCT CASE WHEN is_new_user = 1 THEN user_pseudo_id END)

-- Metric: data_as_of_dt — 카드 옆 각주용. 자동 상한이 아니라 검증 완료 기준일 표시 전용
MAX(event_complete_dt)
```

각주 표시 예: "검증 완료 기준일: {data_as_of_dt}까지 — 이후 날짜의 부분 적재 행이 카드에 포함될 수 있습니다." 미적재 미래 월이나 데이터 시작 이전 월을 선택하면 0명으로 보일 수 있다는 한계를 각주 설명에 함께 명시한다(자동 N/A 처리는 하지 않음).

선택적으로 카드에 실제 포함된 최신 활동일을 함께 보여주고 싶으면 아래 보조 Metric을 추가할 수 있다. 이 값은 "이벤트 완전성"을 증명하지 않으므로 `data_as_of_dt`(검증 완료 기준일)를 대체하지 않는다.

```sql
-- Metric: latest_active_event_dt — 선택 사항, 카드에 포함된 최신 활동일(완전성 증명 아님)
MAX(IF(is_active_any_event = 1, event_dt, NULL))
```

**(2026-09-18 명확화)** `data_as_of_dt`(검증 완료 기준일)는 모든 MAU·신규 카드 옆에 필수로 표시한다. `latest_active_event_dt`는 QA/운영 점검용 선택 보조 Metric으로만 두며 필수 신선도 지표로 격상하지 않는다 — 사용자 특성 필터가 적용되면 전체 파이프라인 최신일이 아니라 그 세그먼트만의 최신 활동일이 되고, 활동이 없는 정상 날짜와 수집 결손을 구분하지 못하기 때문이다. 실제 화면에 노출할 경우 "최신 활동 관측일, 완전성 기준 아님"이라고 라벨을 붙인다.

이전에 쓰던 완료 판정 기반 `bounds`/`counts` 참조 SQL과 월 단위 자동 NULL 처리는 위 변경 이력(2026-09-18)에 따라 폐기했으며 본문에는 남기지 않는다.

**YoY — MAU와 신규에 공통 적용**

- 완료 월은 전년 동월 전체와 비교한다. 진행 월은 같은 경과 일수로 비교한다. 전년 비교 기간도 수집 완전성이 확인돼야 한다.
- 전년 월 시작 P=DATE_SUB(M, INTERVAL 1 YEAR). 진행 월 비교 마지막 경과일 k는 `LEAST(DATE_DIFF(E,M,DAY), DATE_DIFF(LAST_DAY(P),P,DAY))`. 비교는 M~M+k와 P~P+k다. 윤년 등으로 YoY 비교용 M~E와 실제 비교에 쓴 M~M+k가 다르면 두 날짜 범위를 별도로 표시한다. 완료 월 전체는 이 부분 월 절단 규칙을 적용하지 않는다.
- `YoY=(현재 비교 인원−전년 비교 인원)/전년 비교 인원`. 전년 0이면 증감률 NULL, 절대 증감은 표시한다. 비교 데이터가 없으면 절대 증감도 N/A다.
- 단순 '1년 전 Time shift'가 자동으로 동등한 관측 기간을 만든다고 가정하지 않는다. 두 범위는 속성 필터·모집단 정의·Snapshot도 동일하게 적용한다. 작년 당시 속성 재현이 아니라 현재 Snapshot으로 양쪽을 재분류한 비교다.
- UI/UX·홍보의 효과 판정은 학사 일정, 수집/ID 체계 변경을 함께 살핀다. YoY를 전 학기 비교라고 부르지 않는다.
- **(2026-09-18 명시)** MAU·신규 카드 값 자체의 완료 캡핑을 없앴다고 해서 YoY까지 자동으로 완화되는 것은 아니다. 진행 월의 부분값을 전년 동월 **전체**와 비교하지 않는다. YoY를 제공하려면 위 규칙대로 동일 경과일 범위(M~M+k vs P~P+k)로 비교하거나, 그렇지 않으면 YoY 자체를 N/A로 두고 실제 비교에 사용한 기간을 카드에 명시한다. **YoY 수치는 카드에 보이는 무캡핑 부분값을 그대로 분자로 재사용하지 않고, M~E 또는 동일 경과일 비교 범위로 별도 재계산한 값이어야 한다.** 카드 본값의 조회 범위와 YoY 비교에 실제 사용한 기간이 다르면 두 기간을 화면에 각각 표시한다.

#### KPI 2. 신규 유저 수 — 기준 월 최초 관측 사용자 수

**목적·대상·정의**

기준 월에 처음 관측된 사용자 규모로 신학기·홍보 등의 유입 변화를 파악한다. **(2026-09-18 변경)** 가입 여부와 관계없이 first_seen_dt가 MAU 카드와 동일한 Superset 단일 달력 월 event_dt 선택 범위에 포함되는 pseudo가 대상이다. 별도 E 캡핑은 하지 않는다. 신규 가입자 수·로그인 사용자 수·서비스 최초 이용자 수와 다르다. 재설치·기기 변경·식별자 초기화와 추적 이력의 영향을 받는다.

**자연어 불변식 (2026-09-18 개정)**

1. 신규 사용자는 전체 관측 이력의 `first_seen_dt=event_dt`인 날에만 한 번 센다.
2. 회원가입일이 아니라 전체 GA4 최초 관측일을 기준으로 한다.
3. 과거 사용자가 선택 월에 다시 방문해도 신규가 아니다.
4. 같은 기간·특성 조건에서 신규 사용자는 MAU에 포함되어야 한다.
5. USER×DAY Grain과 최초 관측일 행 보존이 지켜지면 `SUM(is_new_user)`와 신규 사용자 DISTINCT 수가 같아야 한다.

**실제 BI 입력**

Dataset: 사용자 Gold(`kap-chat.gold.mart_kpi_user_daily`) 직접 연결. 완료 캡핑·YoY 설정은 KPI 1과 동일하게 자동 NULL 처리 없이 부분값+`data_as_of_dt`(검증 완료 기준일) 각주 방식을 공유한다. MAU와 신규 사용자는 반드시 같은 물리 Dataset·`event_dt` 범위·`gender/major/entry_year/user_type` 필터를 공유해야 한다.

Metric `new_users`:

```sql
COALESCE(SUM(is_new_user), 0)
```

검증용 Metric `new_users_distinct`:

```sql
COUNT(DISTINCT CASE WHEN is_new_user = 1 THEN user_pseudo_id END)
```

**불변식 검증 SQL** — 위반 행 0건. 최초 관측일 D0 보존 원천 대조는 별도로 수행한다.

```sql
SELECT event_dt, user_pseudo_id, first_seen_dt, is_new_user
FROM `kap-chat.gold.mart_kpi_user_daily`
WHERE event_dt BETWEEN DATE_TRUNC(@start_dt, MONTH)
                   AND LEAST(LAST_DAY(@start_dt), @event_complete_dt)
  AND (first_seen_dt IS NULL
       OR is_new_user IS DISTINCT FROM IF(first_seen_dt = event_dt, 1, 0)
       OR (is_active_any_event = 1 AND first_seen_dt > event_dt)
       OR (is_new_user = 1 AND is_active_any_event IS DISTINCT FROM 1));
```

#### KPI 3. 범위 리텐션 — 최초 방문 D1~D7 Entry 재방문율

**목적·대상·정의**

처음 유입된 사용자가 다음 일주일 안에 다시 서비스에 진입하는지 확인한다. 기준 월 최초 관측 사용자이며 회원·비회원 모두 포함한다. 기준일 c=first_seen_dt, 관측 구간은 KST 달력일 c+1~c+7이며 D0를 제외한다. 가입일이나 서비스 활동일을 기준일로 바꾸지 않는다.

- 분모: 해당 월 최초 관측 사용자 중 c와 D1~D7 전체 관측이 완료된 고유 사용자.
- 분자: 분모 안에서 D1~D7에 전체 Entry가 한 번 이상 있는 고유 사용자.
- 계산: 분자÷분모. 여러 날·서비스에서 재방문해도 1명. 다음 달의 복귀도 읽는다.
- 해석: 구간 내 1회 이상 재방문이며 매일 방문·정착·영구 잔존을 뜻하지 않는다. MAU의 Any Event와 다른 활동 기준이다.

**자연어 불변식**

1. 관측이 끝나지 않은 사용자는 이미 복귀했더라도 분모·분자 모두 제외한다. 관측이 완료된 미복귀는 분모에 포함하고 분자 0이다.
2. 평가 가능 인원+평가 대기 인원=코호트 인원. 모든 최초 관측 조합의 행을 남겨 대기 인원이 사라지지 않게 한다.
3. 분자≤평가 가능 분모. 분모 0은 N/A, 1~29명은 소표본으로 비율 숨김·인원 표시.
4. `SUM(일간 복귀 인원)`, `AVG(D1~D7 비율)`, `is_signup_retained_d7`은 대체 계산이 아니다.
5. **그래프 2·3과 성숙 정책이 다르므로 전용 Metric을 쓴다.** 그래프 2·3의 선택 전체 NULL 규칙을 이 카드에 적용하면 확정된 '성숙 사용자만 평가' 정의를 바꾸게 된다.

**실제 BI 입력** — 집계 Gold의 새 metric_type 구현 후 사용한다.

고정 필터: `metric_type='first_seen_range_entry_d1_d7'`, `service_name='__all__'`, `period_n=7`, `cohort_user_segment='new'`. 날짜는 metric_dt의 기준 월 범위다. window_start_dt/window_end_dt에 같은 월 필터를 걸지 않는다. is_complete 필터 대신 다음 조건부 합계로 대기 인원을 함께 남긴다.

Metric `range_cohort_users`:

```sql
COALESCE(SUM(denominator_users), 0)
```

Metric `range_eligible_users`:

```sql
COALESCE(SUM(IF(is_complete, denominator_users, 0)), 0)
```

Metric `range_returned_users`:

```sql
CASE WHEN COALESCE(SUM(IF(is_complete, denominator_users, 0)), 0) = 0 THEN NULL
     ELSE SUM(IF(is_complete, numerator_users, 0)) END
```

Metric `range_pending_users`:

```sql
COALESCE(SUM(IF(is_complete IS FALSE, denominator_users, 0)), 0)
```

Metric `range_retention_rate` — `.1%`, 소표본 정책 포함:

```sql
CASE WHEN COALESCE(SUM(IF(is_complete, denominator_users, 0)), 0) < 30 THEN NULL
     ELSE SAFE_DIVIDE(SUM(IF(is_complete, numerator_users, 0)),
                      SUM(IF(is_complete, denominator_users, 0))) END
```

카드에는 비율과 함께 재방문자/평가 가능 인원, 평가 대기 인원, 기준 월, D1~D7 Entry, 데이터 기준일을 표시한다. 선택 월 앞부분 자체가 수집되지 않은 경우 공식 월 KPI는 N/A이며 단순히 기록된 코호트만 공식 전체로 표시하지 않는다. 신규/기존 및 서비스 전역 필터는 연결하지 않는다. 공통 사용자 특성 필터만 적용한다.

**차트 집계 참조 SQL**

```sql
WITH stats AS (
  SELECT COALESCE(SUM(denominator_users), 0) AS cohort_users,
         COALESCE(SUM(IF(is_complete, denominator_users, 0)), 0) AS eligible_users,
         COALESCE(SUM(IF(is_complete IS FALSE, denominator_users, 0)), 0) AS pending_users,
         SUM(IF(is_complete, numerator_users, 0)) AS returned_users
  FROM `kap-chat.gold.mart_service_metrics_daily`
  WHERE metric_type = 'first_seen_range_entry_d1_d7'
    AND service_name = '__all__' AND period_n = 7 AND cohort_user_segment = 'new'
    AND metric_dt BETWEEN DATE_TRUNC(@start_dt, MONTH)
                      AND LEAST(LAST_DAY(@start_dt), @event_complete_dt)
  -- 필요한 사용자 특성 조건을 WHERE에 추가한다.
)
SELECT *,
       IF(eligible_users = 0, NULL, returned_users) AS displayed_returned_users,
       CASE
         WHEN DATE_TRUNC(@start_dt, MONTH) < @event_complete_start_dt
           OR DATE_TRUNC(@start_dt, MONTH) > @event_complete_dt THEN NULL
         WHEN eligible_users < 30 THEN NULL
         ELSE SAFE_DIVIDE(returned_users, eligible_users)
       END AS range_retention_rate
FROM stats;
```

인원이 0인 정상 빈 코호트와 미적재 배치를 이 SQL의 빈 결과만으로 구분할 수는 없다. 공개 배치 검증과 source 대조가 먼저 통과해야 한다. raw 인원은 부분 관측 진단용으로 남을 수 있지만 공식 비율은 위 완료 규칙을 따른다.

**불변식 검증 SQL**

```sql
SELECT *
FROM `kap-chat.gold.mart_service_metrics_daily`
WHERE metric_type = 'first_seen_range_entry_d1_d7'
  AND metric_dt BETWEEN @start_dt AND @end_dt
  AND (service_name IS DISTINCT FROM '__all__'
       OR period_n IS DISTINCT FROM 7
       OR cohort_user_segment IS DISTINCT FROM 'new'
       OR window_start_dt IS DISTINCT FROM DATE_ADD(metric_dt, INTERVAL 1 DAY)
       OR window_end_dt IS DISTINCT FROM DATE_ADD(metric_dt, INTERVAL 7 DAY)
       OR is_complete IS DISTINCT FROM (
         metric_dt >= event_complete_start_dt
         AND DATE_ADD(metric_dt, INTERVAL 7 DAY) <= event_complete_dt));
```

공통 20컬럼 NOT NULL·도메인·분자/분모 검사를 함께 수행한다. 1명이 D1·D3·D7 모두 방문해도 1명, D0만 방문하면 0명, D7 미관측이면 복귀 여부와 무관하게 평가 대기인 인공 사례를 사용자 판정 결과와 대조한다.

#### KPI 4. 이탈률 — 기준 주 활성 사용자의 다음 주 앱 미복귀율

**목적·대상·정의**

기존 활성 사용자의 다음 주 이용 지속성이 낮아지는 신호를 확인한다. 코인 전체이며 회원·비회원 포함이다. 기준 주 월~일 전체 Any Event 사용자 중 바로 다음 월~일에 전체 Any Event가 한 번도 없는 사용자 비율이다. 56일 서비스 이탈·4개월 미이용·탈퇴율과 구분하여 카드 이름을 '다음 주 앱 미복귀율'로 표시한다.

- 기준 주 w~w+6의 고유 활동 사용자가 분모다. 같은 사용자 여러 날 방문은 1명이다.
- 그 집합 중 w+7~w+13에 전체 Event가 없는 사용자가 분자다.
- 기준 월말 또는 완료일까지 두 주가 모두 끝난 가장 최근 연속 주차 쌍을 사용한다. 기준 주가 이전 달로 걸칠 수 있으며 실제 날짜를 표시한다.
- 방학·시험·공휴일 등 이용 필요성 변화를 고려한다. 100%−가입 D7 또는 100%−Range KPI로 계산하지 않는다.

**기준 주 계산 — 참조 SQL**

```sql
WITH cutoff AS (
  SELECT LEAST(LAST_DAY(@start_dt), @event_complete_dt) AS cutoff_dt
), last_week AS (
  SELECT DATE_SUB(
           DATE_TRUNC(DATE_ADD(cutoff_dt, INTERVAL 1 DAY), WEEK(MONDAY)),
           INTERVAL 1 DAY) AS next_week_end
  FROM cutoff
)
SELECT DATE_SUB(next_week_end, INTERVAL 13 DAY) AS base_week_start,
       DATE_SUB(next_week_end, INTERVAL 7 DAY) AS base_week_end,
       DATE_SUB(next_week_end, INTERVAL 6 DAY) AS next_week_start,
       next_week_end
FROM last_week;
```

선택 월이 미래면 계산 결과가 현재 마지막 주로 조용히 바뀌지 않도록 N/A로 차단한다. 위 쿼리는 날짜 산식이며 배치 완료/미래 월 차단은 아래 집계와 함께 적용한다.

**자연어 불변식**

1. 기준 주 시작~다음 주 종료 14일 전체가 완전해야 한다. 다음 주 월~토만 보고 확정 이탈로 표시하지 않는다.
2. next_week_returned_users + next_week_nonreturn_users = base_week_users다. 두 집합의 교집합은 없다.
3. 다른 어떤 코인 서비스라도 다음 주 Any Event가 있으면 앱 미복귀가 아니다. 이는 동일 서비스 복귀만 인정하는 서비스 이탈과 다르다.
4. 첫 주에 없고 다음 주에만 신규 유입된 사용자는 분모에 추가하지 않는다. 다음 주 종료 후 복귀는 이 주차의 판정을 소급 변경하지 않는다.
5. 카드에서 여러 기준 주의 스냅샷을 SUM하지 않는다. 해당 기준 주 미적재면 N/A이며 임의로 이전 적재 주를 고르지 않는다.

**실제 BI 입력** — 집계 Gold 새 metric_type 구현 후 사용.

고정 필터: `metric_type='app_weekly_nonreturn'`, `service_name='__all__'`, `period_n=1`, `cohort_user_segment='not_applicable'`, `metric_dt=계산한 기준 주 월요일`.

Metric `base_week_users`:

```sql
SUM(denominator_users)
```

Metric `next_week_nonreturn_users`:

```sql
CASE WHEN COUNT(*) = 0 OR COUNTIF(is_complete IS DISTINCT FROM TRUE) > 0 THEN NULL
     ELSE SUM(numerator_users) END
```

Metric `app_weekly_nonreturn_rate` — `.1%`:

```sql
CASE WHEN COUNT(*) = 0 OR COUNTIF(is_complete IS DISTINCT FROM TRUE) > 0 THEN NULL
     ELSE SAFE_DIVIDE(SUM(numerator_users), SUM(denominator_users)) END
```

대상 0명은 N/A다. 카드에는 미복귀자/기준 주 인원, 기준 주·다음 주의 실제 날짜, 데이터 기준일을 표시한다. 사용자 속성 필터만 연결하며 서비스·코호트 신규/기존·일간 활성 필터는 연결하지 않는다. is_complete=true 필터로 일부 행을 조용히 제거하지 않는다.

**차트 집계 참조 SQL**

```sql
WITH cutoff AS (
  SELECT LEAST(LAST_DAY(@start_dt), @event_complete_dt) AS cutoff_dt
), bounds AS (
  SELECT DATE_SUB(
    DATE_SUB(DATE_TRUNC(DATE_ADD(cutoff_dt, INTERVAL 1 DAY), WEEK(MONDAY)),
             INTERVAL 1 DAY), INTERVAL 13 DAY) AS base_week_start
  FROM cutoff
), stats AS (
  SELECT b.base_week_start,
         COUNT(m.metric_row_id) AS aggregate_rows,
         COUNTIF(m.metric_row_id IS NOT NULL AND m.is_complete IS DISTINCT FROM TRUE) AS incomplete_rows,
         SUM(m.denominator_users) AS base_week_users,
         SUM(m.numerator_users) AS nonreturn_users
  FROM bounds b
  LEFT JOIN `kap-chat.gold.mart_service_metrics_daily` m
    ON m.metric_type = 'app_weekly_nonreturn' AND m.metric_dt = b.base_week_start
   AND m.service_name = '__all__' AND m.period_n = 1
   AND m.cohort_user_segment = 'not_applicable'
   -- 필요한 사용자 특성 조건은 이 ON에 넣어 빈 결과의 날짜 행을 보존한다.
  GROUP BY b.base_week_start
)
SELECT *, DATE_ADD(base_week_start, INTERVAL 7 DAY) AS next_week_start,
       DATE_ADD(base_week_start, INTERVAL 13 DAY) AS next_week_end,
       CASE WHEN DATE_TRUNC(@start_dt, MONTH) > @event_complete_dt
              OR base_week_start < @event_complete_start_dt
              OR DATE_ADD(base_week_start, INTERVAL 13 DAY) > @event_complete_dt
              OR aggregate_rows = 0 OR incomplete_rows > 0 THEN NULL
            ELSE SAFE_DIVIDE(nonreturn_users, base_week_users) END AS nonreturn_rate
FROM stats;
```

**불변식 검증 SQL** — 공통 인원/도메인 검사와 함께 수행한다.

```sql
SELECT *
FROM `kap-chat.gold.mart_service_metrics_daily`
WHERE metric_type = 'app_weekly_nonreturn'
  AND metric_dt BETWEEN @start_dt AND @end_dt
  AND (metric_dt IS DISTINCT FROM DATE_TRUNC(metric_dt, WEEK(MONDAY))
       OR service_name IS DISTINCT FROM '__all__'
       OR period_n IS DISTINCT FROM 1
       OR cohort_user_segment IS DISTINCT FROM 'not_applicable'
       OR window_start_dt IS DISTINCT FROM DATE_ADD(metric_dt, INTERVAL 7 DAY)
       OR window_end_dt IS DISTINCT FROM DATE_ADD(metric_dt, INTERVAL 13 DAY)
       OR is_complete IS DISTINCT FROM (
         metric_dt >= event_complete_start_dt
         AND DATE_ADD(metric_dt, INTERVAL 13 DAY) <= event_complete_dt));
```

#### 그래프 1. 서비스별 순서 기반 퍼널

**목적·대상·정의**

정해진 경로의 어느 구간에서 다음 단계로 이동하지 않는지 확인하여 후속 조사·개선 지점을 찾는다. 개선 전후에는 같은 퍼널 버전·세션 완료·관측 조건으로 비교한다. 단계 이탈만으로 UI/UX 문제를 확정하지 않는다. 마지막 행동은 경로 도달이지 이용 목적 달성·만족·실제 거래 완료의 자동 증거가 아니다.

| funnel_id | 차트 단계 | 총 단계 |
| --- | --- | --- |
| signup | 가입 시작 → 약관 동의 → 본인 인증 → 정보 입력 → 가입 완료 | 5 |
| shop | 메인 방문 → 상점 진입 → 상점 상세 조회 → 전화 클릭 | 4 |
| bus | 메인 방문 → 버스 진입 → 출발 또는 도착지 확인 → 경로 검색 | 4 |
| cafeteria | 메인 방문 → 식단 진입 → 식사 시간 선택 → 메뉴 공유 | 4 |
| timetable | 메인 방문 → 시간표 진입 → 검색·학기·교육과정 선택 → 이미지 저장 | 4 |
| board | 메인 방문 → 게시판 진입 → 공지 탭 선택·검색 → 분류된 공지 읽기 | 4 |
| grad_calc | 메인 방문 → 졸업계산기 진입 → 학과·학기 선택 또는 과목 편집 등 탐색 | 3 |

이번 사용자 제공 확정 목록은 위 7개다. 기존 8개안의 시설을 자동 추가하지 않는다. UI 단계 설명과 Silver의 실제 분류 키·발생 순서가 일치해야 하며, 미분류 단계를 Gold CASE로 만들어 채우지 않는다. 졸업계산기 탐색 등의 필수 이벤트가 제공되지 않으면 해당 퍼널은 검증 대기다.

**세션과 기간 불변식**

- 대상은 기간 안에 해당 퍼널 첫 단계에 진입한 식별 가능한 사용자다. 상점 등 메인 시작 퍼널의 첫 단계에는 **그 세션에서 이후 해당 서비스에 가지 않은 메인 사용자도 포함**한다. 서비스 진입 사용자만 남겨 첫 단계 분모를 축소하지 않는다.
- 동일 pseudo·동일 검증 세션 안에 단계 1~k를 순서대로 충족한 경로가 있어야 U_k에 포함한다. 다른 세션의 클릭을 이어 붙이지 않는다. 메인 이벤트의 service_name과 후속 서비스가 다르므로 서비스 WHERE로 메인을 먼저 제거하지 않는다.
- 단계 도달 집합은 U_last⊆…⊆U_2⊆U_1. 집합 포함관계 자체를 검사한다. 인원 수가 감소하기만 한다고 올바른 사용자 경로임이 입증되지는 않는다.
- 기간은 첫 단계 최초 진입일에 적용한다. 마지막 날 시작한 세션의 후속 이벤트는 세션 완료까지 읽는다. 미완료 세션을 같은 기준으로 모든 단계에서 제외하고 제외 세션 수를 표시한다.
- 사용자가 여러 완전 세션에서 도달해도 선택 기간의 해당 단계에서는 1명이다. 한 사용자가 완전·미완료 세션을 모두 가지면 완전 세션의 유효 경로는 집계하고 미완료 세션은 제외 세션 수에 포함한다.
- 누락/충돌 세션 키·불명확한 시각 동률·필수 분류 결손으로 검증되지 않은 퍼널은 N/A/검증 대기다. 0명/100% 이탈로 바꾸지 않는다.
- 도달 단계 k의 직전 대비 전환율=|U_k|/|U_(k−1)|. 첫 단계는 대상이 있을 때 100%.
- 현재 단계 k의 다음 단계 이탈률=1−|U_(k+1)|/|U_k|. 마지막 단계에는 표시하지 않는다.
- 전체 경로 전환율=|U_last|/|U_1|. 분모 0은 N/A. 같은 단계의 직전 전환율과 다음 이탈률은 서로 다른 구간을 가리킨다.

**Gold 계산·저장 계약**

현재 44/20 계약에서는 이 단계로 진행하지 않는다. 5.0.11의 45번째 `funnel_session_facts` 확장안이 구현됐을 때 아래 Dataset과 Metric을 사용한다. 새 물리 테이블은 만들지 않는다. 모든 순서 판정은 Silver 입력을 읽는 사용자 Gold 내부 CTE에서 완료한다. 별도 배열 원소를 일간 활동량과 JOIN해서 집계하지 않는다.

**Dataset SQL — ds_funnel_user_step (확장안 전용)**

```sql
SELECT
  g.event_dt, g.user_pseudo_id, g.gender, g.major, g.entry_year, g.user_type,
  g.build_id, g.user_snapshot_at, g.event_complete_start_dt, g.event_complete_dt,
  f.funnel_id, f.funnel_version, f.session_key, f.anchor_dt,
  f.is_complete, f.max_step_reached, f.total_steps,
  step_no
FROM `kap-chat.gold.mart_kpi_user_daily` g
CROSS JOIN UNNEST(g.funnel_session_facts) f
CROSS JOIN UNNEST(GENERATE_ARRAY(1, f.total_steps)) step_no
```

이 Dataset의 Grain은 pseudo×세션×퍼널버전×퍼널×단계다. 미도달 후속 단계도 행을 생성하므로 완료 첫 단계 대상이 있으면 마지막 단계 0명을 표시할 수 있다. 원래 44컬럼 Dataset에 이 SQL을 실행하면 컬럼이 없으므로 실패하는 것이 정상이다. 확장 검증 전 등록하지 않는다.

**실제 BI 입력 — Metrics 각각 등록**

Metric `funnel_reached_users`:

```sql
CASE WHEN COUNTIF(is_complete) = 0 THEN NULL
     ELSE COUNT(DISTINCT IF(is_complete AND max_step_reached >= step_no,
                            user_pseudo_id, NULL)) END
```

Metric `funnel_previous_conversion` — 단계 1은 완전한 대상이 있으면 1:

```sql
SAFE_DIVIDE(
  COUNT(DISTINCT IF(is_complete AND max_step_reached >= step_no, user_pseudo_id, NULL)),
  COUNT(DISTINCT IF(is_complete AND max_step_reached >= GREATEST(step_no - 1, 1),
                    user_pseudo_id, NULL))
)
```

Metric `funnel_next_dropoff` — 마지막 단계 N/A:

```sql
CASE WHEN MIN(step_no) = MAX(total_steps) THEN NULL
     ELSE 1 - SAFE_DIVIDE(
       COUNT(DISTINCT IF(is_complete AND max_step_reached >= step_no + 1,
                         user_pseudo_id, NULL)),
       COUNT(DISTINCT IF(is_complete AND max_step_reached >= step_no,
                         user_pseudo_id, NULL))) END
```

Metric `funnel_overall_conversion` — 별도 카드에 사용 가능:

```sql
SAFE_DIVIDE(
  COUNT(DISTINCT IF(is_complete AND max_step_reached = total_steps, user_pseudo_id, NULL)),
  COUNT(DISTINCT IF(is_complete, user_pseudo_id, NULL))
)
```

Metric `funnel_excluded_sessions` — 미완료 세션 수, 단계별 값을 다시 SUM하지 않음:

```sql
COUNT(DISTINCT IF(is_complete IS FALSE,
  TO_JSON_STRING(STRUCT(user_pseudo_id AS user_pseudo_id, session_key AS session_key)), NULL))
```

위 Metric은 퍼널 한 개·버전 한 개를 고정하는 조건이다. 단계별 차트에서는 step_no를 그룹에 유지한다. 대상 세션이 없거나 입력 관측 범위 자체가 미완료/미적재인 경우의 상태는 별도 배치/퍼널 품질 게이트로 표시한다. 입력 누락을 이 집계식이 검출하는 것은 아니다.

Calculated Column `funnel_step_label` — 설명용 최소형. 서비스별 단계명 CASE는 위 승인 표의 funnel_id×step_no를 그대로 사용한다.

```sql
CONCAT(CAST(step_no AS STRING), '단계')
```

| 차트 항목 | 설정 |
| --- | --- |
| Dataset | ds_funnel_user_step, 45컬럼 확장안 구현 후 |
| 퍼널 필터 | funnel_id 한 개, funnel_version 한 개 |
| 단계 차원 | step_no 숫자 오름차순, 승인된 단계명 표시 |
| 값 | funnel_reached_users |
| 시간 필터 | event_dt 범위 — 부모 event_dt=anchor_dt 동치 검증 필수 |
| 보조 표 | 단계, 도달자, 직전 전환율, 다음 이탈률 |
| 전체 전환율 | funnel_overall_conversion 별도 카드 |
| 사용자 특성 필터 | gender / major / entry_year / user_type |
| 연결하지 않을 필터 | 서비스 이용 플래그, day/period/cohort 신규·기존 |
| 미완료 표시 | funnel_excluded_sessions, 배치/세션 관측 완료 상태 |

퍼널 플러그인의 자동 백분율이 '전체 단계 인원 합 대비 비중'인지 '첫 단계 대비'인지 확인한다. 설정에서 원하는 직전 전환율·다음 이탈률을 지원하지 않으면 같은 Dataset의 보조 표로 제공한다. 내장 툴팁이 두 정의를 모두 지원한다고 단정하지 않는다.

**차트 결과 참조 SQL — 45컬럼 확장안 전용**

```sql
WITH facts AS (
  SELECT g.user_pseudo_id, f.*
  FROM `kap-chat.gold.mart_kpi_user_daily` g
  CROSS JOIN UNNEST(g.funnel_session_facts) f
  WHERE g.event_dt BETWEEN @start_dt AND @end_dt
    AND f.funnel_id = @funnel_id AND f.funnel_version = @funnel_version
  -- 사용자 속성 조건은 g.gender/major/entry_year/user_type으로 이 WHERE에 적용한다.
), counts AS (
  SELECT step_no,
    COUNTIF(is_complete) AS complete_session_rows,
    COUNT(DISTINCT IF(is_complete AND max_step_reached >= step_no,
                      user_pseudo_id, NULL)) AS users
  FROM facts CROSS JOIN UNNEST(GENERATE_ARRAY(1, total_steps)) step_no
  GROUP BY step_no
), paired AS (
  SELECT *, LAG(users) OVER (ORDER BY step_no) AS prev_users,
         LEAD(users) OVER (ORDER BY step_no) AS next_users,
         FIRST_VALUE(users) OVER (ORDER BY step_no) AS first_users,
         LAST_VALUE(users) OVER (
           ORDER BY step_no ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
         ) AS last_users
  FROM counts
)
SELECT step_no, IF(complete_session_rows = 0, NULL, users) AS reached_users,
       SAFE_DIVIDE(users, IF(step_no = 1, users, prev_users)) AS previous_conversion,
       IF(next_users IS NULL, NULL, 1 - SAFE_DIVIDE(next_users, users)) AS next_dropoff,
       SAFE_DIVIDE(last_users, first_users) AS overall_conversion
FROM paired ORDER BY step_no;
```

위 LAG/LEAD는 **선택 기간의 사용자 중복 제거가 끝난 단계별 결과**에 적용한다. 시간축 d−7 DAU 비교를 LAG로 대신한다는 뜻이 아니다. 전체 쿼리를 Metric 칸에 붙이지 않는다. 모든 facts가 없으면 차트가 비므로 '대상 없음/검증 대기'와 승인 단계 목록 표시는 별도 UI 처리다.

**퍼널 불변식 검증 — 확장안 구현 시**

```sql
-- 논리 원소 키: 전체 테이블에서 검사해 다른 event_dt에 복제된 원소도 탐지한다.
SELECT g.user_pseudo_id, f.session_key, f.funnel_id, f.funnel_version, COUNT(*) AS n
FROM `kap-chat.gold.mart_kpi_user_daily` g
CROSS JOIN UNNEST(g.funnel_session_facts) f
GROUP BY 1, 2, 3, 4 HAVING COUNT(*) != 1;
```

```sql
SELECT g.event_dt, g.user_pseudo_id, f.*
FROM `kap-chat.gold.mart_kpi_user_daily` g
CROSS JOIN UNNEST(g.funnel_session_facts) f
WHERE f.anchor_dt IS DISTINCT FROM g.event_dt
   OR f.funnel_id IS NULL OR f.funnel_version IS NULL OR f.session_key IS NULL
   OR f.is_complete IS NULL OR f.max_step_reached IS NULL OR f.total_steps IS NULL
   OR f.max_step_reached < 1 OR f.max_step_reached > f.total_steps
   OR ARRAY_LENGTH(f.step_reached_at) IS DISTINCT FROM f.max_step_reached
   OR DATE(f.step_reached_at[SAFE_OFFSET(0)], 'Asia/Seoul') IS DISTINCT FROM f.anchor_dt
   OR EXISTS (
     SELECT 1 FROM UNNEST(f.step_reached_at) t WITH OFFSET i
     WHERE t IS NULL OR (i > 0 AND t <= f.step_reached_at[SAFE_OFFSET(i-1)])
   );
```

추가 blocking 검사: funnel_id별 total_steps와 버전별 단계 매핑 일치, 모든 적격 첫 단계 세션의 보존(후속 서비스 진입 없는 메인 포함), Silver 증거 Event의 시각·사용자·세션 일치, 단계별 사용자 집합 포함관계. 배열 안의 숫자 관계만 검증하면 잘못된 순서 계산까지 입증하지 못한다.

#### 배포 전 공통 검증 사례와 구현 상태

| 영역 | 반드시 포함할 사례 |
| --- | --- |
| MAU·신규 | 한 사용자의 여러 날짜·여러 서비스, 활동 없는 가입행, 신규 D0 누락, 시작 월 경계, 월초 관측 누락, 미래 월, 필터 후 0명, **(2026-09-18 추가) `data_as_of_dt` 각주가 항상 함께 표시되는지, 미적재 미래 월이 실제 0명과 구분 없이 0으로 보이는 케이스를 의도적으로 재현해 운영상 한계로 문서화됐는지, `event_complete_dt` 이후 날짜에 부분 적재 행이 실제로 존재해 카드 값에 포함되는 사례를 재현해 이를 월 완료값으로 오인하지 않는지, 늦게 도착한 Event가 과거 월 값을 사후에 변경할 수 있음을 확인했는지, `data_as_of_dt`와 `latest_active_event_dt`가 서로 다를 수 있는 사례, `latest_active_event_dt`가 사용자 특성 필터에 따라 달라지는 사례, 카드 본값의 조회 범위와 YoY 비교 Metric의 실제 기간이 다를 때 두 기간이 화면에 각각 표시되는지, MAU·신규 카드에 다개월 범위를 선택하지 못하게 했는지 또는 다개월 선택 시 월별로 그룹화되어 각 월이 독립 계산되는지** |
| YoY | 전년 데이터 없음/0명, 진행 월 동일 경과일, 윤년 2월, 현재 Snapshot 재분류, 양쪽 동일 속성 필터 |
| Range | D0만 활동, D1·D3·D7 다중 복귀=1명, D7 미완료 조기 복귀도 제외, 월말 유입 후 다음 달 복귀, 소표본 29/30, Entry 없는 Any Event만 복귀 |
| 앱 미복귀 | 기준 주 여러 날 중복, 다음 주 다른 서비스만 방문, 다음 주만 신규 유입, 종료 일요일 포함, 종료 다음 날 복귀, 14일 중 수집 공백 |
| 퍼널 | 단계 역전·생략·반복, 타 세션 연결 금지, 자정 통과, 시간 동률, 미완료 세션, 메인만 방문, 여러 세션/여러 날짜 같은 사용자 DISTINCT, 해당 기간에 첫 단계 없는 사용자 |
| 공통 | NULL 특성 조합 보존, 두 Gold 동일 build/Snapshot, 해시 키 및 자연 키 유일성, 원천 대상 집합 누락/초과 양방향 대조 |

**MAU·신규 정책 변경 상태 (2026-09-18)**

```text
정책 계약: 확정
Gold ETL 구현: 미구현
운영 BigQuery 검증: 미완료
Superset 등록: 미완료
```

**기존 검증 SQL 보완 사항:** `!=`/`NOT BETWEEN`은 NULL에서 TRUE가 아니므로 필수 컬럼 not_null 테스트를 반드시 별도로 적용한다. is_complete 검사에는 새 metric_type의 기준 구간을 포함한다. retention_daily도 주간과 마찬가지로 모든 D0~D56 행 존재·분모 불변 검사를 추가한다. 여러 배치가 섞이지 않았다는 검사만으로 두 테이블 공개가 원자적이라고 입증하지 않는다.

이번 작업은 설계 문서 편집 및 참조 SQL 검토다. BigQuery 실행 결과나 Superset UI 검증, 실제 테이블 생성, 45번째 컬럼 적용을 수행했다고 표시하지 않는다. 특히 그래프 2~6의 기존 계약을 삭제하거나, 퍼널 구현을 위해 Silver 분류/ID 로직 수정까지 사용자 작업으로 확장하지 않는다.

**공식 참고 자료**

- [Superset SQL Templating](https://superset.apache.org/user-docs/using-superset/sql-templating/) — 시간 필터를 논리 Dataset 내부에 전달하는 기능과 remove_filter 동작. 설치 버전·템플릿 활성화·실제 생성 SQL 확인이 필요하다.
- [BigQuery aggregate functions](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/aggregate_functions) — 조건부 COUNT DISTINCT와 COUNTIF. COUNTIF는 TRUE만 세므로 NULL 필수값은 별도 검증한다.

### 6.15 KPI 4개 및 퍼널 — 쉬운 설명과 시각화 구성 (2026-09-10)

이 절은 6.14의 계산 계약을 쉽게 설명한 공유용 문안이다. KPI 이름은 사용자 확인에 따라 이탈률로 유지하며, 판정은 다음 주 미이용이다. 실제 배포 결과가 아니다.

# KPI 4개 및 퍼널 — 불변식과 시각화 방법

## 공통 기준

불변식은 데이터를 계산할 때 반드시 지켜야 하는 규칙이다.

- 사용자는 user_pseudo_id로 구분한다. 같은 사람이 기기 변경 등으로 다른 식별자를 가지면 서로 다른 사용자로 집계될 수 있다.
- 날짜는 한국 시간을 기준으로 하고, 한 주는 월요일부터 일요일까지로 본다.
- 성별·학과 등의 필터를 선택하면 전체 대상과 그중 재방문·이탈한 사람에게 같은 조건을 적용한다.
- 성별·학과 정보가 없는 사용자도 제외하지 않고 ‘미상’으로 포함한다.
- 가입 기록만 있고 실제 이용 기록이 없으면 활성 사용자로 세지 않는다.
- 수집이 끝났는데 이용자가 없으면 0, 아직 확인할 수 없으면 ‘확인 불가’로 표시한다.
- 비율을 계산할 대상이 0명이면 0%가 아닌 ‘대상 없음’으로 표시한다.
- 여러 그룹의 비율을 합칠 때는 사람 수를 먼저 더한 뒤 비율을 계산한다. 그룹별 비율을 단순 평균하지 않는다.

---

## 1. MAU

**무엇을 보는가?**

한 달 동안 코인을 한 번 이상 이용한 사용자 수를 본다. 앱 전체 이용 규모가 늘거나 줄었는지 확인하는 지표다.

**계산 기간**

날짜 필터 시작일이 속한 달의 1일부터 월말까지다. 아직 끝나지 않은 달은 데이터 수집이 완료된 날짜까지만 계산한다.

**불변식 — 반드시 지킬 규칙**

1. 한 사용자가 여러 날 방문하거나 여러 서비스를 이용해도 한 달에 한 명으로 센다.
2. 실제 이벤트가 한 번 이상 기록된 사용자만 포함한다. 가입 기록만 있는 사용자는 포함하지 않는다.
3. 같은 조건에서 어느 하루의 이용자 수가 그달 전체 이용자 수보다 많을 수 없다.
4. 같은 조건에서 그달 신규 유저 수가 MAU보다 많을 수 없다.
5. 필요한 기간의 데이터가 빠져 있으면 완성된 월간 수치처럼 표시하지 않는다.
6. 작년과 비교할 때는 비교 기간의 데이터도 모두 있어야 한다. 작년 값이 0이면 증가율을 계산하지 않는다.

**확인할 관계**

- 월 신규 유저 수 ≤ MAU
- 그달의 각 날짜 이용자 수 ≤ MAU

**Superset 시각화 방법**

- 차트: 큰 숫자 카드(Big Number).
- 제목: ‘MAU’.
- 표시값: 해당 월에 실제 이벤트가 있는 사용자를 중복 없이 센 값.
- 숫자는 ‘1,234명’처럼 표시한다.
- 날짜별로 나누지 않고 한 달 전체를 하나의 숫자로 보여준다.
- 아래에는 ‘집계 기간: 9/1~9/9’처럼 실제 기간을 표시한다.
- 작년 비교값이 준비되어 있으면 ‘전년 같은 기간 대비 +8.2%’를 보조 정보로 표시한다. 진행 중인 달을 작년 한 달 전체와 비교하지 않는다.
- 같은 카드에 비교값을 넣기 어려우면 작은 보조 카드로 배치한다.

---

## 2. 신규 유저 수

**무엇을 보는가?**

해당 월에 코인에서 처음 관측된 사용자 수를 본다. 회원가입자 수와는 다르다.

**계산 기간**

MAU와 동일하게 날짜 필터 시작일이 속한 달을 기준으로 한다. 진행 중인 달은 데이터 수집 완료일까지 계산한다.

**불변식 — 반드시 지킬 규칙**

1. 사용자는 처음 관측된 날짜에만 신규로 센다.
2. 예전에 방문했던 사용자가 이번 달 처음 방문했다고 해서 신규가 되지는 않는다.
3. 신규 표시인 is_new_user는 이용 날짜와 최초 관측일이 같을 때만 1이어야 한다.
4. 한 사용자의 최초 관측일 기록이 빠지거나 중복되지 않아야 한다.
5. 같은 조건에서 신규 유저는 MAU에 포함되어야 한다.
6. 그달 활성 사용자를 신규와 기존으로 나누면 서로 겹치지 않고, 두 수를 더하면 MAU가 된다.
7. 회원가입 여부로 신규 유저를 판단하지 않는다.

**확인할 관계**

- 월 신규 유저 수 + 월 기존 이용자 수 = MAU

**Superset 시각화 방법**

- 차트: 큰 숫자 카드(Big Number).
- 제목: ‘신규 유저 수’.
- 표시값: 해당 월에 처음 관측된 사용자 수.
- 사용자별 최초 관측일 기록이 정확하다는 조건에서 is_new_user를 합산한다.
- 숫자는 ‘123명’처럼 표시한다.
- MAU 카드와 같은 집계 기간을 사용하고 나란히 배치한다.
- 설명에 ‘가입 여부와 관계없이 처음 관측된 사용자’라고 표시한다.
- 작년 같은 관측 기간의 값이 있으면 증감률을 함께 보여준다.

---

## 3. 범위 리텐션

**무엇을 보는가?**

처음 들어온 사용자가 다음 날부터 7일째까지 한 번이라도 다시 이용했는지 본다.

여기서 다시 이용했다는 기준은 서비스 진입 등 미리 정한 Entry 활동이다. 모든 이벤트를 이용으로 보는 MAU와는 기준이 다르다.

**계산 방법**

기준 월에 처음 관측된 사용자 중 7일 뒤까지 확인할 수 있는 사람만 대상으로 한다.

범위 리텐션 = 다음 날부터 7일째 사이에 다시 이용한 사람 수 ÷ 확인 가능한 대상 사람 수

**불변식 — 반드시 지킬 규칙**

1. 사용자마다 처음 관측된 날짜를 기준으로 1~7일 뒤를 확인한다. 첫날 이용은 재방문에 포함하지 않는다.
2. 7일 동안 여러 번 방문해도 재방문자 한 명으로 센다.
3. 아직 7일이 지나지 않았거나 필요한 데이터가 빠졌으면 계산 대상에서 제외한다. 이미 돌아왔더라도 동일하게 제외한다.
4. 7일을 모두 확인했는데 돌아오지 않았다면 전체 대상에는 포함하고 재방문자에는 포함하지 않는다.
5. 재방문자 수는 전체 계산 대상 수보다 클 수 없다.
6. 처음 들어온 날이 월말이어도 다음 달까지 7일을 이어서 확인한다.
7. 계산 대상이 없으면 ‘대상 없음’, 대상은 있는데 아무도 돌아오지 않았으면 0%다.

**확인할 관계**

- 계산 대상 수 = 재방문자 수 + 돌아오지 않은 사람 수
- 재방문자 수 ≤ 계산 대상 수

**Superset 시각화 방법**

- 차트: 큰 숫자 카드(Big Number).
- 제목: ‘범위 리텐션’.
- 표시값: ‘35.0%’처럼 소수점 한 자리의 비율.
- 계산을 끝낸 대상의 재방문자 수와 전체 대상 수를 각각 더한 뒤 나눈다.
- 보조 정보: ‘재방문 35명 / 확인 가능한 대상 100명’.
- 설명: ‘첫 방문 다음 날부터 7일째까지의 Entry 재방문’.
- 처음 들어온 기준 월과 데이터 기준일을 함께 표시한다.
- 보조 인원을 카드에 함께 넣기 어려우면 아래에 작은 표를 배치한다.
- 기존 표시 규칙에 따라 대상이 30명 미만이면 비율 대신 ‘표본 부족’을 표시하고 대상 인원은 보여준다. 사람을 집계에서 삭제하는 것은 아니다.

---

## 4. 이탈률

**무엇을 보는가?**

기준 주에 코인을 이용한 사람 중 바로 다음 주에는 한 번도 이용하지 않은 사람의 비율을 본다.

**계산 방법**

이탈률 = 기준 주 이용자 중 다음 주에 이용하지 않은 사람 수 ÷ 기준 주 전체 이용자 수

날짜 필터 시작일이 속한 달의 월말과 데이터 수집 완료일 중 이른 날짜를 기준으로, 두 주를 모두 확인할 수 있는 가장 최근 주차를 선택한다.

**불변식 — 반드시 지킬 규칙**

1. 계산 대상은 기준 주에 실제 이벤트가 있었던 사용자다.
2. 기준 주에 이용하고 다음 주에도 이용했다면 복귀자다.
3. 기준 주에 이용했지만 다음 주에는 이벤트가 한 번도 없다면 이탈자다.
4. 같은 사용자를 복귀자와 이탈자로 동시에 세지 않는다.
5. 다음 주에 처음 들어온 사용자는 기준 주의 계산 대상에 포함하지 않는다.
6. 두 주의 데이터가 모두 수집된 뒤에 확정한다.
7. 다다음 주에 돌아와도 해당 두 주의 이탈 판정은 그대로다. 뒤늦게 도착한 이벤트로 잘못된 기록을 바로잡는 경우는 예외다.
8. 전체 대상이 없으면 ‘대상 없음’, 대상은 있는데 이탈자가 없으면 0%다.
9. 범위 리텐션과 기준이 다르므로 ‘100% − 범위 리텐션’으로 계산하지 않는다.

**확인할 관계**

- 기준 주 이용자 수 = 다음 주 복귀자 수 + 이탈자 수
- 이탈자 수 ≤ 기준 주 이용자 수
- 같은 기준으로 계산하고 대상이 있으면 이탈률 + 복귀율 = 100%

**Superset 시각화 방법**

- 차트: 큰 숫자 카드(Big Number).
- 제목: ‘이탈률’.
- 표시값: ‘20.0%’처럼 소수점 한 자리의 비율.
- 보조 정보: ‘이탈 20명 / 기준 주 이용자 100명’.
- 기준 주와 다음 주를 실제 날짜로 표시한다. 예: ‘기준 주 8/24~8/30 → 다음 주 8/31~9/6’.
- 선택된 한 쌍의 주차만 계산한다. 여러 주의 값을 한꺼번에 더하지 않는다.
- 설명: ‘기준 주 이용자 중 다음 주 미이용 비율’.
- 두 주의 확인이 끝나지 않았으면 0% 대신 ‘확인 불가’를 표시한다.

**해석 시 주의할 점**

여기서 이탈은 다음 주 한 주 동안 이용하지 않았다는 뜻이다. 영구 이탈이나 회원 탈퇴를 뜻하지 않는다.

---

## 5. 퍼널

**무엇을 보는가?**

사용자가 정해진 이용 순서를 따라갈 때 어느 단계에서 많이 멈추는지 본다.

‘같은 세션’은 데이터에서 같은 한 번의 이용 흐름으로 묶인 기록을 뜻한다. 다른 세션의 행동을 이어 붙이지 않는다.

**대상과 단계**

| 대상 | 단계 |
| --- | --- |
| 회원가입 | 가입 시작 → 약관 동의 → 본인 인증 → 정보 입력 → 가입 완료 |
| 주변 상점 | 메인 방문 → 상점 진입 → 상점 상세 조회 → 전화 클릭 |
| 버스 | 메인 방문 → 버스 진입 → 출발 또는 도착지 확인 → 경로 검색 |
| 식단 | 메인 방문 → 식단 진입 → 식사 시간 선택 → 메뉴 공유 |
| 시간표 | 메인 방문 → 시간표 진입 → 검색·학기·교육과정 선택 → 이미지 저장 |
| 게시판 | 메인 방문 → 게시판 진입 → 공지 탭 선택·검색 → 분류된 공지 읽기 |
| 졸업계산기 | 메인 방문 → 졸업계산기 진입 → 학과·학기 선택 또는 과목 편집 등 탐색 |

**불변식 — 반드시 지킬 규칙**

1. 같은 사용자가 같은 세션에서 정해진 순서대로 도달해야 다음 단계로 넘어간 것으로 센다.
2. 서로 다른 세션에서 한 행동을 이어 붙여 완료한 것으로 만들지 않는다.
3. 중간에 다른 행동을 해도 필수 단계를 순서대로 거친 경로가 있으면 인정한다.
4. 같은 사용자가 여러 번 시도해도 선택 기간의 각 단계에서는 한 명으로 센다.
5. 다음 단계에 도달한 사람은 반드시 앞 단계에도 포함되어야 한다. 따라서 다음 단계 사람 수가 앞 단계보다 많을 수 없다.
6. 확인이 끝난 세션만 모든 단계에 동일하게 사용한다. 아직 확인 중인 세션을 이탈로 확정하지 않는다.
7. 날짜 필터는 첫 단계에 들어온 날짜에 적용한다. 마지막 날 시작해 다음 날 이어진 행동도 같은 세션이면 확인한다.
8. 첫 단계에 사람이 있으면 첫 단계 도달률은 100%, 없으면 ‘대상 없음’이다.
9. 같은 두 단계 사이에서 다음 단계로 넘어간 비율과 넘어가지 않은 비율을 더하면 100%다. 앞 단계가 0명이면 두 비율을 계산하지 않는다.
10. 마지막 단계에는 다음 단계 이탈률을 표시하지 않는다.

**확인할 관계**

- 첫 단계 사람 수 ≥ 두 번째 단계 사람 수 ≥ … ≥ 마지막 단계 사람 수
- 다음 단계 전환율 = 다음 단계 사람 수 ÷ 현재 단계 사람 수
- 다음 단계 이탈률 = 1 − 다음 단계 전환율
- 전체 전환율 = 마지막 단계 사람 수 ÷ 첫 단계 사람 수

**Superset 시각화 방법**

- 차트: 퍼널 차트(Funnel Chart).
- 상단에 ‘퍼널 종류’ 선택 필터를 두고 회원가입·주변 상점 등을 한 번에 하나씩 선택한다.
- 단계 이름별로 사람 수를 표시한다. 단계는 인원 크기가 아닌 실제 진행 순서대로 배치한다.
- 단계 이름 앞에 ‘1. 메인 방문’, ‘2. 상점 진입’처럼 번호를 붙여 순서를 분명히 한다.
- 퍼널 안에는 단계 이름과 도달 인원을 표시한다.
- 아래에는 ‘단계 / 도달 인원 / 직전 단계 대비 전환율 / 다음 단계 이탈률’ 표를 함께 둔다.
- 전체 전환율은 차트 위나 옆에 작은 숫자 카드로 표시한다.
- 차트에서 기본 제공하는 비율이 전체 대비인지 직전 단계 대비인지 확인한다. 원하는 기준과 다르면 계산한 값을 보조 표에 표시한다.
- 필터로 선택한 서비스의 다음 단계에 진입한 사람만 먼저 남기지 않는다. 메인에서 멈춘 사람도 첫 단계 인원에 포함되어야 한다.

**해석 시 주의할 점**

퍼널에서 멈췄다고 반드시 화면이 불편하다는 뜻은 아니다. 사용 목적이나 이벤트 누락도 함께 확인한다. 전화 클릭도 실제 통화나 주문 완료를 뜻하지 않는다.

---

## 대시보드 배치와 필터

- 상단: MAU / 신규 유저 수 / 범위 리텐션 / 이탈률 카드 4개를 나란히 배치한다.
- 하단: 퍼널 종류 필터, 퍼널 차트, 단계별 보조 표를 배치한다.
- 날짜 필터: KPI는 시작일이 속한 달을 기준으로 계산하고, 퍼널은 선택한 시작일~종료일을 그대로 사용한다. 이탈률은 해당 기준으로 확인 가능한 최근 두 주를 선택한다.
- 성별·학과·입학연도·사용자 유형 필터는 KPI와 퍼널에 동일한 의미로 연결한다.
- 퍼널 종류 필터는 퍼널에만 적용한다. 전체 코인 KPI 4개에는 적용하지 않는다.
- 모든 예시 숫자는 화면 설명용이며 실제 측정값이 아니다.

## 구현 시 확인할 사항

MAU와 신규 유저 수는 현재 사용자 Gold에서 계산할 수 있다. 범위 리텐션과 이탈률은 해당 결과를 집계 Gold에 추가해야 하며, 퍼널은 사용자별 세션과 단계 순서를 판정한 결과를 저장하도록 구조를 확장해야 한다.

날짜 범위 변경, 관측 완료 여부, 작년 비교, ‘표본 부족’ 문구는 차트 선택만으로 자동 적용되지 않는다. 계산 결과와 필터 연결을 함께 구성한다. 설치된 Superset 버전에 따라 카드 설명·비교값 표시 옵션은 다를 수 있으므로, 한 카드에 담기 어려운 정보는 보조 카드나 표로 표시한다.

차트 생성과 표시 형식은 [Superset 차트 작성 안내](https://superset.apache.org/user-docs/using-superset/exploring-data/)와 [숫자 표시 형식 안내](https://superset.apache.org/user-docs/using-superset/number-formatting/)를 참고한다.



### 6.16 대화 전체 정리 및 최종 설계 결정 (2026-11-06)

KOIN Gold 테이블 설계 — 대화 전체 정리 및 최종 결정
정리일: 2026-11-06
기준: 이번 대화에서 사용자가 확인한 서비스 운영 상태와 최종 설계 방향

1. 문서의 성격과 기준

이 문서는 이번 대화의 확인 내용, 결정, 수정 이유, 대시보드 제공 범위와 후속 작업을 정리한 요약본이다. 대화의 발언을 그대로 옮긴 전문은 아니다.

권위 원문은 IdeaProjects/KOIN_DATA/notion_bigquery_gold_design.md다. 5장은 Gold 계약, 6장은 BI 대시보드 카탈로그이며, 이번 대화의 변경은 5.0.12와 6.16에 기록한다.

기존 보완 검토 문서, v8 대안, 복사용 텍스트는 참고 자료이며 권위 원문을 대체하지 않는다. 실제 SQL 구현, 운영 BigQuery 배포, Superset 연결 완료와 설계 방향 확정을 구분한다.

2. 처음 확인한 설계와 남은 문제

대화 시작 시 최신 기준은 다음과 같았다.

• 사용자 Gold mart_kpi_user_daily: 44컬럼
• 집계 Gold mart_service_metrics_daily: 20컬럼
• 물리 Gold 테이블 2개
• 두 Gold 모두 검증된 Silver Event/User 직접 참조
• 별도 Intermediate와 Gold→Gold 참조 없음
• 사용자 기준: user_pseudo_id
• 사용자 Gold의 행 단위: event_dt × user_pseudo_id
• 사용자 행 생성: Event 날짜 UNION 가입 날짜
• 사용자 속성: 동일하게 고정된 현재 Silver User Snapshot 기준
• 과거의 dense D0~D365 spine은 현재 사용자 Gold 계약에서 사용하지 않음

당시 남아 있던 핵심 사항은 다음과 같았다.

• 정확한 임의 기간 사용자 DISTINCT 순서 퍼널을 위한 저장 구조
• 최초 방문 D1~D7 Range 리텐션용 metric_type
• 앱 전체 다음 주 미복귀용 metric_type
• 동일 Snapshot 고정과 두 테이블 공동 공개 방식
• 실제 Silver 입력명·필수 컬럼·수집 완전성·세션 처리 검증
• 과거 38컬럼 코드 및 단일 99컬럼 설계와 최신 계약의 구분

일별 단계 인원을 합산하면 기간 고유 사용자 수를 보존할 수 없으므로 기존 44/20컬럼만으로 요구한 순서 퍼널을 제공할 수 없다고 확인했다.

3. 로깅 네이밍 규칙 완성이 Gold에 주는 영향

사용자는 로깅 네이밍 규칙을 완료해 event_label의 틀이 갖춰졌다고 설명했다.

이에 따라 다음 설계의 근거가 명확해진다.

• 서비스·행동별 이벤트 식별
• Entry·Core·서비스 활동 플래그의 입력 매핑
• 퍼널 단계별 이벤트 매핑
• 규칙에 없는 label·필수 단계 누락 검사
• 명세 버전·적용일에 따른 과거/현재 이벤트 구분

다만 다음 세 단계는 구분한다.

네이밍 규칙 완성 → 실제 앱 이벤트 수집 → Silver 분류 제공

규칙이 있다는 사실만으로 실제 이벤트 수집이나 Silver 배포가 완료됐다고 보지 않는다. Gold는 Silver가 제공하는 분류를 소비하며, 누락된 Silver 분류나 사용자 식별 로직을 Gold CASE로 복구하지 않는다.

label은 행동의 의미를 제공하지만 동일 세션의 순서, 기간 사용자 중복 제거, 리텐션 관측 구간 계산을 대신하지 않는다. 따라서 퍼널 결과 저장 컬럼과 KPI용 metric_type 추가는 여전히 필요하다.

4. 서비스 종료·개발 중단에 관한 사용자 확인

사용자가 직접 확인한 상태는 다음과 같다.

• 졸업계산기: 기능 종료
• 동아리: 기능 종료
• 새 주변상점: 개발 중단
• 미래의 주변상점: 개발 중단
• 기존 주변상점: 현행 분석 대상으로 유지

처음에는 레거시 문서를 현행 목록에서 분리해 보관하는 방안을 제안했다. 이후 사용자가 기능 종료·개발 중단을 확인했으므로 해당 대상을 현재 Gold 분석 범위에서도 제외하는 방향으로 정리했다.

현재 명세 목록에서 제외하는 것과 과거 문서·데이터를 삭제하는 것은 다르다. 과거 이벤트 해석을 위해 종료일·대체 명세·적용 기간과 함께 이력을 보존한다. 과거 데이터를 삭제하라는 결정은 하지 않았다.

종료일의 실제 날짜와 구버전 이벤트의 포함·제외 기간은 아직 제공되지 않았으므로 별도 확인한다.

5. 최종 Gold 구조와 컬럼 수

사용자는 현행 서비스 범위와 퍼널·리텐션 구성으로 Gold 설계를 진행하는 방향에 동의했다. 이에 따라 다음을 최종 설계 방향으로 기록한다.

사용자 Gold: mart_kpi_user_daily
• 기존 사용자 44컬럼에서 used_grad_calc_flg 제거 → 43컬럼
• funnel_session_facts 중첩 컬럼 추가 → 최종 44컬럼

집계 Gold: mart_service_metrics_daily
• 기존 20컬럼 유지
• KPI용 metric_type 2개 추가

즉, 최종 방향은 물리 Gold 2개, 사용자 44 / 집계 20컬럼이다.

중요: 최종 숫자는 다시 44/20이지만 기존 44/20과 동일 스키마가 아니다. used_grad_calc_flg를 제거하고 funnel_session_facts를 추가한 새 계약이다. 단순히 컬럼 개수만 비교해 호환된다고 판단하지 않는다.

동아리는 이미 기존 Gold 범위 밖이므로 추가 컬럼 제거가 없다. 새 주변상점·미래의 주변상점은 별도 Gold 컬럼을 만들었던 대상이 아니므로 컬럼 수가 추가로 줄지 않는다. 현행 주변상점용 used_shop_flg는 유지한다.

이전에 검토 메모에서 승인 대기로 두었던 퍼널 컬럼과 metric_type 추가는 이번 대화 마지막의 진행 동의를 근거로 설계 방향에 채택한다. 세부 입력·세션·운영 방식까지 모두 검증되거나 승인됐다는 의미는 아니다.

6. 퍼널 대시보드 — 최종 6개

1) 회원가입
가입 시작 → 약관 동의 → 본인 인증 → 정보 입력 → 가입 완료

2) 주변상점
메인 방문 → 상점 진입 → 상점 상세 조회 → 전화 클릭

3) 버스
메인 방문 → 버스 진입 → 출발 또는 도착지 확인 → 경로 검색

4) 식단
메인 방문 → 식단 진입 → 식사 시간 선택 → 메뉴 공유

5) 시간표
메인 방문 → 시간표 진입 → 검색·학기·교육과정 선택 → 이미지 저장

6) 게시판·공지사항
메인 방문 → 게시판 진입 → 공지 탭 선택·검색 → 분류된 공지 읽기

위 경로는 분석 설계의 기준이며 현행 로깅 명세 및 실제 UI·Silver 분류와 대조해야 한다. 게시판을 팀원모집으로 재해석하지 않는다. 이번에 공유된 로깅 명세 목록에 서비스가 있다는 이유만으로 복덕방·사장님·배너·콜밴팟·학교 부서 정보·팀원모집·모의수강신청을 자동 추가하지 않는다.

시설은 리텐션 대상에 남지만 이번 퍼널 대상에는 없다. 졸업계산기·동아리·새 주변상점·미래의 주변상점은 현재 퍼널 대상에서 제외한다.

차트에서 제공할 값:
• 단계별 기간 고유 사용자 수
• 직전 단계 대비 전환율
• 다음 단계 이탈률
• 전체 경로 전환율
• 미완료 세션 제외 수 및 검증 상태

분모 0은 N/A, 마지막 단계에는 다음 단계 이탈률을 표시하지 않는다.

7. 퍼널 계산·저장 원칙

사용자 Gold에 다음 중첩 컬럼을 추가한다.

funnel_session_facts ARRAY<STRUCT<
  funnel_id STRING,
  funnel_version STRING,
  session_key STRING,
  anchor_dt DATE,
  is_complete BOOL,
  max_step_reached INT64,
  total_steps INT64,
  step_reached_at ARRAY<TIMESTAMP>
>>

• 원소는 사용자×검증된 세션×퍼널×버전당 하나다.
• anchor_dt는 해당 세션의 퍼널 첫 단계 최초 진입일(KST)이다.
• 부모 event_dt=anchor_dt인 행에만 저장하고 다른 날짜에 복제하지 않는다.
• 퍼널 없는 부모 행은 빈 배열이다.
• 동일 세션 안에서 단계 시각이 엄격히 증가하는 유효 경로만 인정한다.
• 필수 단계 생략·다른 세션 간 연결로 도달을 만들지 않는다.
• 자정을 넘긴 후속 이벤트도 읽고 첫 단계 진입일에 결과를 저장한다.
• 메인 시작 퍼널은 이후 해당 서비스에 가지 않은 메인 방문자도 첫 단계 분모에 포함한다.
• 관측 완료 세션 집합을 모든 단계에 공통 적용한다.
• 동일 사용자가 여러 세션·여러 날짜에 도달해도 선택 기간의 해당 단계에서 한 명으로 센다.
• Gold가 순서와 완료를 계산하고 BI는 UNNEST와 DISTINCT 집계만 수행한다.
• 배열을 펼친 결과에서 부모의 일간 이벤트 수·활동량을 SUM해 중복 집계하지 않는다.

아직 구체화할 조건:
• 세션 키의 stream/property 충돌과 NULL 처리
• 시간 동률의 순서 근거
• 세션 종료·지연 수집 완료 기준
• 분류 버전과 적용일
• 배열 최대 크기와 사용자당 세션 분포
• 늦은 완료에 따른 과거 anchor 파티션 재계산 범위

8. 서비스별 리텐션 대시보드

서비스 리텐션은 기준일에 해당 서비스를 이용한 사용자가 이후 같은 서비스를 다시 이용했는지 평가한다.

Entry 기준:
• 주변상점 shop
• 버스 bus
• 게시판·공지사항 board
• 시간표 timetable
• 시설 facility

해당 서비스 Any Event 기준:
• 식단 cafeteria
• 메인 main
• 계정 account

앱 전체:
• __all__ = 전체 Any Event
• main은 실제 메인 화면이며 앱 전체와 다르다.

대시보드 형태:
• 일간 D0~D56 코호트 리텐션 표
• 주간 W0~W8 리텐션 커브
• 서비스 및 현재 사용자 속성별 비교

retention_daily는 기준일 c의 서비스 활동 코호트가 c+D에 같은 서비스를 사용하는지 평가한다.

retention_weekly는 고정된 일별 코호트 기준으로 W0=c, Wn=c+7n−6~c+7n 구간에 한 번 이상 같은 서비스를 사용하는지 평가한다. 다음 달력 주와 혼동하지 않는다.

미복귀는 관측 완료 시 0, 평가 불가는 NULL로 구분한다. 미성숙 코호트 행도 보존한다. 그래프 2·3은 선택 코호트 중 미완료가 있으면 해당 점·셀 전체를 NULL로 표시하는 기존 정책을 유지한다.

여러 기준일의 코호트를 합친 분모는 사용자×코호트 기준일 수이며 기간 고유 사용자 수가 아니다. 일별·주별 DISTINCT 인원을 합쳐 기간 고유 사용자 수로 제공하지 않는다.

신규·기존 구분은 앱 전체 GA4 최초 관측 기준이며 서비스 첫 이용 기준으로 바꾸지 않는다. 사용자 속성은 현재 고정 Snapshot 기준이며 과거 당시 속성으로 설명하지 않는다.

9. 신규·가입 리텐션

신규 사용자 Range 리텐션:
• 최초 관측일 c의 전체 신규 사용자가 대상이다.
• c+1~c+7에 전체 Entry가 한 번 이상 있으면 복귀다.
• 여러 날 복귀해도 한 명이다.
• c~c+7의 수집이 완전히 검증된 코호트만 분자·분모에 포함한다.
• 이미 조기 복귀했어도 D7까지 관측이 끝나지 않으면 제외한다.
• 제외 인원을 별도로 표시한다.
• 평가 인원 30명 미만은 비율을 숨기되 분모는 표시하는 정책을 유지한다.

가입 리텐션:
• 가입일 행에 정확한 D1·D7·D14·D30의 전체 Entry 복귀 여부를 저장한다.
• 가입 이후 N일 이내 한 번 이상 복귀한 Range 지표와 다르다.
• 가입일은 signup_completed_at 기준이며 first_seen_at으로 대체하지 않는다.
• 관측 미완료는 NULL이다.
• 가입 원천 신선도와 입력값 의미를 검증한다.

10. 이탈·미복귀 대시보드

서비스 56일 미이용:
• churn_56d 유지
• 대상: 주변상점·버스·식단·게시판·시간표·시설, 6개 서비스
• 스냅샷 T까지 관측된 해당 서비스 이용자 중 T−55~T에 해당 서비스를 이용하지 않은 사용자를 평가한다.
• main·account·__all__은 서비스 56일 이탈 그래프 대상에서 제외한다.

앱 전체 다음 주 미복귀:
• 기준 주 월요일~일요일의 전체 Any Event 사용자가 대상이다.
• 바로 다음 주 월요일~일요일에 전체 Any Event가 없으면 미복귀다.
• 다음 주에 다른 서비스만 사용해도 앱 복귀다.
• 연속 두 달력 주 전체의 수집 완전성을 확인한다.
• 기준 주 사용자 집합을 먼저 중복 제거하며 일별 미복귀 수를 더하지 않는다.

과거 분자에 있던 ‘4달 동안 이벤트 없음’은 다음 주 미복귀 정의와 충돌하므로 사용하지 않는다. 서비스 56일 미이용과 앱 다음 주 미복귀도 서로 대체하지 않는다.

11. 집계 Gold의 metric_type

20컬럼을 유지하고 다음 다섯 종류를 설계한다.

• retention_daily
• retention_weekly
• churn_56d
• first_seen_range_entry_d1_d7 — 이번 대화에서 추가 방향 채택
• app_weekly_nonreturn — 이번 대화에서 추가 방향 채택

집계는 실제 서비스·기간·사용자 속성·세그먼트 조합만 저장한다. ROLLUP/CUBE 전체 합계 행을 섞지 않고 NULL 사용자 속성 조합을 보존한다.

완료 행은 0≤분자≤분모이며 저장행의 분모는 양수다. 미완료 행의 분자는 NULL이다. 키·도메인·완전성 테스트는 새 metric_type을 포함하도록 확장한다.

12. MAU·신규 사용자 카드 정책

• Superset에서 선택한 단일 달력 월의 사용자 Gold를 직접 집계한다.
• MAU는 is_active_any_event=1인 user_pseudo_id의 DISTINCT다.
• Event 없는 가입일 전용 행을 MAU에 포함하지 않는다.
• 신규 사용자는 앱 전체 최초 관측 기준이며 가입자 수와 다르다.
• event_complete_dt로 카드 본값을 자동 캡핑하지 않는다.
• 검증 완료 기준일을 각주로 표시한다.
• 완료 기준일 이후 부분 적재 행이 카드에 포함될 수 있으므로 진행 월은 부분 집계값으로 해석한다.
• YoY는 별도 동일 경과일 비교와 관측 조건을 적용한다.
• 전체 앱 KPI에는 서비스·퍼널 필터를 연결하지 않는다.

13. 배치·입력 검증과 공개

두 Gold는 동일하게 고정된 User Snapshot과 공통 build_id·user_snapshot_at·완전 구간을 사용한다. 같은 시각 문자열을 붙이는 것만으로 동일 Snapshot을 보장하지 않는다.

구체화할 운영 절차:
• 동일 입력을 고정하고 재시도할 수 있는 방법
• 실제 Silver relation·분류 버전·시간대 기록
• 두 모델 각각의 품질 검사와 공통 메타데이터·KPI 대조
• 두 결과가 모두 통과한 뒤 공개하는 방식
• 한쪽 실패 시 이전 정상본 유지 및 공동 롤백

세대별 보존과 외부 공개 제어값은 검토된 후보이며 최종 운영 방식으로 확정한 것은 아니다. 후보 relation·추가 행·제어 저장소가 물리 Gold 2개 제약과 맞는지 확인한다.

입력 검증:
• 실제 운영 Silver Event 모델명과 필수 분류 컬럼
• Event 고유성, User pseudo 고유성, 대상 Event→User 관계
• first_seen_at·가입일·is_deleted 등 타입과 의미
• 입력 타입에 맞는 KST 날짜 변환
• 가입 원천 신선도
• 날짜 구간 내부 수집 공백과 지연 수집
• 퍼널 단계와 실제 UI·로그의 대응

Silver 수정·ID 복원·원천 분류 재작성은 사용자 Gold 작업 범위 밖이다.

14. 검토 문서에서 추가 확인한 사항

공유된 Gold_44_20_계약_보완검토_2026-11-06.md는 검토 메모로 읽었다.

• v8의 36/31컬럼 대안은 현재 계약이 아니다.
• 가입 원천 신선도, 이벤트 없는 가입일 행 제외, 정상본 보존 필요성은 유효한 보완이다.
• 문서에 적힌 2026-11-06 Stage 관측과 변환 기대 ID 426개 차이는 이번 대화에서 근거를 독립 재검증하지 않았다.
• 해당 내용을 현재 검증 완료 사실로 승격하지 않는다.
• 검토 메모는 권위 원문을 대체하지 않는다.

15. 구현·검증 상태

이번 대화에서 수행한 것:
• 인수인계·권위 문서 확인
• 기존 로컬 Gold SQL의 이전 구조·참조 경로 일부 확인
• 공유된 보완 검토 문서 읽기
• 종료·개발 중단 서비스에 대한 사용자 확인
• 최종 서비스 범위·퍼널 확장·metric_type 추가 방향 정리
• 복사용 정리본 작성 및 최신 결정의 기준 문서 기록

이번 대화에서 수행하지 않은 것:
• 새 네이밍 규칙 원문과 실제 이벤트의 전체 대조
• 현행 6개 퍼널의 실제 순차 전환 검증
• 최신 Gold SQL/YAML·테스트 구현
• BigQuery 실데이터 재조회·배포
• Airflow 변경·실행
• Superset 등록·UI 수치 검증
• 레거시 Notion 문서 이동·삭제
• Silver SQL 수정

문서에 기록된 이전 표본 확인은 현재 수집 상태를 보장하지 않는다. 최종 설계로 진행하기로 한 것과 실제 대시보드 제공 완료를 혼동하지 않는다.

16. 다음 작업 순서

1) 현행 로깅 매핑표 작성
서비스 / 행동 / event_label / Silver 분류 / Entry·Core 여부 / 퍼널 단계 / 적용일·버전

2) 실제 Silver 입력 대조
필수 이벤트 수집·분류·세션 키·시각·관계·수집 완전성·가입 원천 신선도 확인

3) 세부 실행 계약 마무리
종료일·구버전 포함 범위, 세션 완료·동률·늦은 이벤트, Snapshot 고정, 공동 공개·실패 복구

4) 최신 계약에 맞춰 Gold 구현
사용자 44컬럼(졸업계산기 제거+퍼널 배열 추가), 집계 20컬럼(metric_type 5종), SQL/YAML·테스트 정합화

5) Stage 검증
인공 사례·실제 KPI·원천 집합 양방향 대조·품질·비용 검증

6) 검증된 배치의 Superset 연결
KPI 카드, 퍼널 6개, 서비스 코호트·커브, 가입 리텐션, 서비스 56일 미이용·앱 다음 주 미복귀 구성

설계 방향은 정해졌으며 다음 실무 작업의 출발점은 현행 로깅 매핑표와 실제 Silver 입력 검증이다.

### 6.17 대시보드 전체 구성안 — 탭·차트·필터 (2026-11-06)

KOIN Gold 기반 대시보드 전체 구성안
작성일: 2026-11-06
기준: 권위 문서 5.0.12·6.16의 최종 서비스 범위 및 사용자 44 / 집계 20컬럼 계약

이 문서는 대시보드 화면·필터 배치 제안이다. 기존 KPI 4개와 그래프 6개의 계산 의미를 유지하고, 가입 리텐션을 별도 보조 영역으로 배치한다. Superset 구현·운영 데이터 검증·배포 결과는 아니다.

1. 전체 구성

대시보드 이름: KOIN 서비스 현황

대시보드는 하나로 구성하고 다음 세 개의 탭으로 나눈다.

• 탭 1. 종합 현황 — 얼마나 이용하며 신규 유입과 앱 복귀 상태는 어떤가?
• 탭 2. 퍼널 — 서비스 이용 경로의 어느 단계에서 멈추는가?
• 탭 3. 리텐션·미이용 — 다시 이용하는가, 가입 후 돌아오는가, 장기간 이용하지 않는가?

주요 분석 구성은 기존 KPI 4개 + 그래프 6개 + 가입 리텐션 보조 영역 1개다. 퍼널 상세표·분모·각주 등은 기존 구성요소의 보조 표시이며, 실제 Superset 차트 객체 수가 11개라는 뜻은 아니다.

화면 개요:

[KOIN 서비스 현황]
[성별] [학과] [입학연도] [사용자 유형]
검증 완료 기준일 / 최근 갱신 시각

[종합 현황] [퍼널] [리텐션·미이용]

탭 1. 종합 현황
  [기준 월]
  [MAU] [신규 유저 수] [신규 D1~D7 리텐션] [다음 주 앱 미복귀율]
  [서비스 이용 기간] [서비스 선택]
  [서비스별 기간 이용자 수]
  [서비스별 DAU 추이] [7일 전 동일 요일 대비 증감]

탭 2. 퍼널
  [퍼널 종류] [첫 단계 진입 기간] [퍼널 버전]
  [전체 전환율 및 대상/제외 세션 정보]
  [단계별 고유 사용자 퍼널]
  [단계 / 도달 인원 / 직전 대비 전환율 / 다음 단계 이탈률]

탭 3. 리텐션·미이용
  A. 서비스 재방문
     [서비스] [코호트 기준일 기간] [전체/신규/기존]
     [일간 D0~D56 코호트 표]
     [주간 W0~W8 리텐션 커브]
  B. 가입 후 재방문
     [가입 기간]
     [D1 / D7 / D14 / D30 리텐션 및 각 평가 인원]
  C. 장기 미이용
     [판정 기준일] [대상 서비스]
     [서비스별 56일 미이용률 및 분자/분모]

2. 탭 1 — 종합 현황

2.1 KPI 카드 4개

K1. MAU
• 질문: 선택한 한 달 동안 앱을 이용한 사용자는 몇 명인가?
• 데이터: 사용자 Gold
• 계산: 선택 월에 is_active_any_event=1인 pseudo DISTINCT
• 가입일 전용의 이벤트 없는 행 제외
• 선택한 단일 달력 월을 직접 집계하며 event_complete_dt 자동 캡핑 없음
• 진행 월은 부분값으로 안내하고 검증 완료 기준일 병기
• YoY는 비교 데이터가 검증된 경우에만 같은 경과일 기준으로 별도 표시

K2. 신규 유저 수
• 질문: 선택한 한 달 동안 앱에 처음 들어온 사용자는 몇 명인가?
• 데이터: 사용자 Gold
• 앱 전체 최초 관측 기준. 회원가입자 수 또는 서비스 첫 이용자 수가 아님
• MAU와 같은 선택 월을 사용하고 최초 관측일 행 보존 검증 필요
• 진행 월 부분값 및 기준일 표시 정책은 MAU와 동일

K3. 신규 D1~D7 리텐션
• 질문: 선택 월의 신규 사용자가 다음 날~7일째에 Entry로 한 번 이상 돌아왔는가?
• 데이터: 집계 Gold / first_seen_range_entry_d1_d7
• 표시: 재방문율, 재방문자/평가 가능 인원, 평가 대기 인원
• 선택 월은 최초 관측일에 적용. 복귀 관측은 다음 달까지 이어질 수 있음
• D7까지 완전 관측된 코호트만 분자·분모에 포함
• 기존 최소 30명 표시 정책 유지. 소표본이어도 인원은 표시
• 기준 월의 시작 구간 자체가 누락됐다면 공식 월 KPI는 확인 불가

K4. 다음 주 앱 미복귀율
• 질문: 기준 주 이용자가 바로 다음 주에 앱을 이용하지 않은 비율은 얼마인가?
• 데이터: 집계 Gold / app_weekly_nonreturn
• 표시: 미복귀율, 미복귀자/기준 주 인원, 기준 주와 다음 주의 실제 날짜
• 선택 월말과 검증 완료 기준일 중 이른 날까지 두 주가 모두 끝난 가장 최근 연속 월~일 주차 쌍
• 기준 주가 이전 달로 걸칠 수 있으므로 실제 기간을 숨기지 않음
• 여러 주의 분모·분자를 합쳐 카드 하나로 만들지 않음
• 다음 주에 다른 서비스만 이용해도 앱 복귀
• 56일 서비스 미이용 또는 100%−신규/가입 리텐션과 다른 지표
• 목표 주차가 미적재·불완전하면 확인 불가. 적재된 이전 주로 조용히 대체하지 않음

K1~K4에는 성별·학과·입학연도·사용자 유형과 KPI 기준 월만 연결한다. 서비스·퍼널·코호트 신규/기존 필터는 연결하지 않는다. 지표별 관측 기간은 각각 명시한다.

2.2 서비스별 기간 이용자 수 — G4

• 형태: 서비스별 막대 그래프. 신규/기존을 배타적으로 분리한 누적 막대 가능
• 질문: 선택 기간에 각 서비스를 이용한 고유 사용자는 몇 명인가?
• 데이터: 사용자 Gold의 서비스 활동 플래그
• 같은 사용자가 여러 날 이용해도 서비스별 기간 내 한 명
• 서비스 신규는 ‘해당 서비스의 첫 이용’이 아니라 ‘선택 기간에 앱 전체에서 처음 관측된 사용자 중 해당 서비스 이용자’
• 기존=해당 서비스 기간 이용자−위 신규 집합
• 동일 사용자를 같은 서비스의 신규·기존 양쪽에 넣지 않음
• 서비스 간 중복은 존재하므로 서비스별 인원을 더해 앱 전체 고유 인원으로 표시하지 않음
• 기본 비교는 주변상점·버스·식단·게시판·시간표·시설 6개, 메인·계정은 선택 가능한 보조 대상

2.3 서비스별 DAU·WoW — G5

• 형태: 날짜별 추이 그래프 + 선택 서비스의 전주 대비 상세표
• 질문: 서비스 이용이 날짜별로 어떻게 변했고, 7일 전 같은 요일과 비교하면 어떠한가?
• 데이터: 사용자 Gold
• 서비스 활동 조건을 충족한 일간 고유 사용자
• WoW는 같은 날짜의 7일 전과 비교. 조회 시작일 전 7일도 비교용으로 읽음
• 양쪽 날짜 수집이 검증된 경우에만 확정 비교값 표시
• 전주 분모가 0 또는 관측 불가면 증감률 N/A
• 일별 신규/기존 분류는 각 날짜의 앱 최초 관측 기준이며 G4의 기간 고정 분류와 구분
• 진행일 부분값은 확정일 추이와 구분하여 표시

G4·G5의 서비스 이용 기간은 KPI 기준 월과 별도 필터다. 기본값은 같은 월로 맞추되, 사용자가 임의 기간을 선택해도 월 KPI까지 임의 기간 고유 사용자 수로 바뀌지 않게 한다.

3. 탭 2 — 퍼널

3.1 퍼널 선택 6개 — G1

• 회원가입: 시작 → 약관 동의 → 본인 인증 → 정보 입력 → 완료
• 주변상점: 메인 → 상점 진입 → 상세 조회 → 전화 클릭
• 버스: 메인 → 버스 진입 → 출발/도착지 확인 → 경로 검색
• 식단: 메인 → 식단 진입 → 식사 시간 선택 → 메뉴 공유
• 시간표: 메인 → 시간표 진입 → 검색·학기·교육과정 선택 → 이미지 저장
• 게시판·공지사항: 메인 → 게시판 진입 → 탭 선택·검색 → 공지 읽기

차트는 한 번에 퍼널 한 개·버전 한 개를 선택한다. 서비스명만 같은 서로 다른 버전의 경로를 섞지 않는다. 실제 단계 매핑은 현행 로깅 및 Silver 검증을 통과해야 한다.

3.2 화면 표시

• 전체 경로 전환율
• 첫 단계 고유 사용자 수
• 미완료 세션 제외 수
• 단계별 도달 사용자 퍼널
• 상세표: 단계 / 고유 사용자 수 / 직전 대비 전환율 / 다음 단계 이탈률
• 데이터 검증 상태, 선택 경로와 실제 기간

3.3 해석·계산 규칙

• 날짜는 첫 단계 최초 진입일에 적용
• 메인 시작 퍼널은 서비스에 진입하지 않은 메인 방문자도 첫 단계에 포함
• 동일 세션의 유효한 순차 경로만 인정
• 기간 전체 단계별 pseudo DISTINCT. 일별 인원을 합산하지 않음
• 미완료 세션은 모든 단계에서 공통 제외
• 가입이 여러 세션에 걸치면 하나의 경로로 연결하지 않음
• 따라서 전체 가입 완료자 수와 가입 퍼널 최종 도달자 수가 다를 수 있음
• 전화 클릭은 실제 통화·주문 완료, 메뉴 공유는 서비스 만족의 자동 증거가 아님
• 검증되지 않은 필수 단계는 0명이나 100% 이탈로 표시하지 않음
• 마지막 단계에 다음 단계 이탈률은 표시하지 않음
• 데이터는 사용자 Gold의 funnel_session_facts를 펼친 표시용 Dataset에서 조회. 새 물리 Gold 테이블은 추가하지 않음

4. 탭 3 — 리텐션·미이용

4.1 서비스 일간 코호트 리텐션 — G2

• 형태: 코호트 Heatmap 또는 Pivot
• 행: 선택 서비스의 활동 기준일
• 열: D0~D56
• 값: 같은 서비스를 해당 경과일에 다시 이용한 비율
• 셀 보조 정보: 복귀자 수 / 코호트 분모 / 관측 완료 상태
• 데이터: 집계 Gold / retention_daily
• 필터: 서비스 한 개, 코호트 기준일 기간, 전체/신규/기존
• 신규/기존은 앱 전체 최초 관측을 기준으로 anchor에서 고정. 서비스 최초 이용으로 해석하지 않음

4.2 서비스 주간 리텐션 커브 — G3

• 형태: 경과 주차별 선 그래프
• X축: W0~W8
• Y축: 같은 서비스 구간 복귀율
• 데이터: 집계 Gold / retention_weekly
• G2와 같은 서비스·코호트 기간·세그먼트 필터 사용
• W0는 기준일, W1은 기준일 다음 날~7일째, W2는 8~14일째
• 달력상의 다음 월~일 주차와 다름
• 선택한 여러 일별 코호트를 통합하면 사용자×코호트 기준일 단위로 집계
• 비율 평균 대신 분자 합계/분모 합계
• 동일 사용자가 여러 anchor에 속할 수 있으므로 기간 고유 사용자 리텐션으로 이름 붙이지 않음
• G2·G3은 선택 코호트 중 미완료가 있으면 해당 셀/점 전체 NULL을 유지. 성숙 코호트만 남기는 K3와 정책이 다름

G2·G3 서비스 목록:
• Entry: 주변상점·버스·게시판·시간표·시설
• 해당 서비스 Any Event: 식단·메인·계정
• 앱 전체 비교용 __all__: 전체 Any Event
• main은 메인 화면이며 __all__과 다름

서비스 기준일 필터는 코호트를 고르는 필터다. 기준일 이후 최대 D56의 복귀 이벤트를 조회 기간 밖이라는 이유로 제거하지 않는다. 리텐션 전체에 is_active=1 또는 used_service=1 필터를 걸어 미복귀 분모를 없애지 않는다.

4.3 가입 사용자 리텐션 — R1, 보조 영역

• 형태: D1·D7·D14·D30 비교표 또는 막대 + 분모 표
• 질문: 선택 기간에 가입한 사용자가 정확히 N일 뒤 앱 Entry로 돌아왔는가?
• 데이터: 사용자 Gold의 가입일 행과 is_signup_retained_d1/d7/d14/d30
• 필터: 가입 기간
• 반환 조건은 앱 전체 Entry이며 개별 서비스 필터를 연결하지 않음
• Dn별 분모=해당 가입 리텐션 필드가 NULL이 아닌 평가 가능 사용자 수
• Dn별 분자=해당 가입 리텐션 필드의 합
• 관측 미완료 NULL과 완료 미복귀 0을 구분
• D1·D7·D14·D30의 평가 가능 분모가 다를 수 있으므로 각각 표시
• 가입일에 이벤트가 없더라도 유효한 가입 코호트라면 분모에서 임의 제외하지 않음
• 신규 첫 방문 D1~D7 Range와 구분. 해당 날짜 하루의 정확한 DN 복귀 지표
• 기존 리텐션 소표본 표시 정책과 분모 노출 원칙을 유지

4.4 서비스별 56일 미이용 — G6

• 형태: 서비스별 비율 막대 + 미이용자/분모 상세표
• 질문: 기준일까지 관측된 해당 서비스 이용자 중 최근 56일 동안 그 서비스를 이용하지 않은 비율은 얼마인가?
• 데이터: 집계 Gold / churn_56d
• 필터: 판정 기준일 T, 대상 서비스
• 관측 창: T−55~T
• 판정 기준일 한 개만 선택. 여러 기준일의 스냅샷을 SUM하지 않음
• 대상 서비스: 주변상점·버스·식단·게시판·시간표·시설 6개
• 메인·계정·앱 전체는 이 차트의 서비스 선택에서 제외
• 다른 서비스만 이용하면 앱에는 복귀했더라도 해당 서비스의 56일 미이용에 해당할 수 있음
• 필요한 56일과 과거 이용 이력이 검증되지 않으면 확인 불가
• 회원 탈퇴·영구 이탈·K4의 다음 주 앱 미복귀와 다른 지표

5. 필터 적용 범위

공통 사용자 필터:
• 성별, 학과, 입학연도, 사용자 유형
• 모든 차트의 대상과 분자·분모에 동일 조건 적용
• 현재 고정 User Snapshot 기준이며 과거 당시 속성으로 설명하지 않음
• NULL 속성은 미상으로 보존

날짜·지표별 필터:
• KPI 기준 월 → K1~K4. K1·K2는 활동 월, K3는 최초 관측 월, K4는 해당 월 기준으로 계산된 실제 두 주
• 서비스 이용 기간 → G4·G5의 event_dt
• 퍼널 첫 단계 진입 기간 → G1의 anchor_dt
• 코호트 기준일 기간 → G2·G3의 metric_dt
• 가입 기간 → R1의 first_signup_dt. 가입일 행만 사용
• 판정 기준일 → G6의 metric_dt=T

선택 필터:
• 서비스 이용 선택 → G4·G5
• 리텐션 서비스 및 전체/신규/기존 → G2·G3
• 장기 미이용 대상 서비스 → G6, 위 6개만
• 퍼널 종류·버전 → G1
• 플랫폼·디바이스는 일간 대표값이라 코호트 분모를 왜곡할 수 있으므로 이번 공통 필터에 추가하지 않음

하나의 전역 날짜 필터를 모든 차트의 event_dt·metric_dt에 그대로 적용하지 않는다. 사용자는 각 영역의 날짜 의미를 제목과 안내에서 확인할 수 있어야 한다.

6. 원천과 주요 구성요소 대응

사용자 Gold mart_kpi_user_daily:
• K1 MAU
• K2 신규 유저 수
• G4 서비스별 기간 이용자
• G5 서비스별 DAU·WoW
• R1 가입 리텐션
• G1 퍼널: funnel_session_facts를 펼친 표시용 Dataset

집계 Gold mart_service_metrics_daily:
• K3 신규 D1~D7 Range Entry 리텐션
• K4 다음 주 앱 미복귀율
• G2 서비스 일간 코호트
• G3 서비스 주간 커브
• G6 서비스 56일 미이용

이 배치는 물리 Gold 2개·사용자 44/집계 20컬럼 계약을 변경하지 않는다.

7. 상태·안내 표시

• 수집 완료, 대상 존재, 실제 이용/복귀 없음 → 0명 또는 0%
• 분모 0 → 대상 없음
• 관측 이력 부족·수집 공백·필수 분류 미검증 → 확인 불가/검증 대기
• 아직 성숙하지 않은 코호트 → 지표별 완료 정책 적용 및 대기 인원 표시
• 두 Gold의 공개 배치가 일치하지 않으면 공동 공개 게이트에서 차단
• 검증 완료 기준일과 최근 갱신 시각을 구분
• 첫 방문, 가입, 서비스 이용, 앱 복귀의 정의를 혼용하지 않음
• 종료된 졸업계산기·동아리 및 개발 중단된 새/미래 주변상점은 현행 선택 목록에서 제외
• 기존 주변상점과 시설은 현행 분석 대상에 유지

8. 구현 전 남은 조건

이 구성안으로 화면 배치를 구체화할 수 있지만 실제 제공에는 다음이 필요하다.

• 현행 로깅과 6개 퍼널 단계의 Silver 매핑 확인
• 세션 키·시간 동률·종료·지연 수집 기준
• 신규·가입·56일 미이용 판정을 위한 이력과 완전성 검증
• 동일 Snapshot과 두 Gold 공동 공개·실패 복구 설계
• 최신 계약의 Gold SQL/YAML·테스트 구현
• 실제 Superset 필터 적용 범위·표시 방식·생성 SQL 검증
• 사용자 DISTINCT, 신규/기존 배타성, 평가 분모, 미완료 상태, 서비스 필터 누출을 포함한 수치 대조

### 6.18 SQL 초안·Stage 구조·Superset 쿼리 검증 기록 (2026-11-06)

#### 완료 범위

| 항목 | 실제 상태 |
| --- | --- |
| 사용자 Gold SQL | 최신 구성 44컬럼 초안 작성. 졸업계산기 제거, 가입 DN 플래그·main·메타데이터·퍼널 배열 포함 |
| 집계 Gold SQL | 20컬럼, metric_type 5종 초안 작성 |
| 입력 의존성 | 두 모델 모두 Silver Event/User 직접 참조, 동일 시점 time travel 읽기 |
| Stage 테이블 | 두 테이블 구조 생성 완료, 각각 0행 |
| Superset 쿼리 | 퍼널·서비스 이용자·DAU/WoW·앱 주간 미복귀 Dataset SQL 및 Metric 식 작성 |
| 정적 검증 | dbt parse·dbt 엔진을 통한 오프라인 컴파일, 참조 그래프·Stage source 확인 |
| BigQuery 문법 | 두 Gold SELECT, Superset Dataset 4개·Metric 그룹 5개, 핵심 테스트 SQL 5개 dry-run 통과 |
| 계산 사례 | 인공 사용자 16명·이벤트 42건을 사용한 검증 22개, BigQuery 실행 실패 항목 0개 |
| 실제 적재·운영 검증 | 미실행. 새 SDK 로깅과 Silver 분류 반영 후 수행 |
| Superset UI | Dataset·차트 등록 및 설치 버전의 실제 필터 동작 검증 미실행 |

일반 dbt CLI compile은 ADC 연결 단계에서 진행되지 않아 중단했다. 위 컴파일 결과는 실제 dbt parser/compiler를 데이터베이스 접속 없이 호출한 결과다. SQL의 BigQuery 유효성은 별도 API dry-run으로 확인했다. 실데이터 full refresh의 처리량·성능을 측정한 결과는 아니다.

#### 파일 위치

- 사용자 모델: `dbt/models/gold/mart_kpi_user_daily.sql`
- 집계 모델: `dbt/models/gold/mart_service_metrics_daily.sql`
- 공통 입력·실행 계약: `dbt/macros/gold_contract.sql`
- 사용자·퍼널 계산: `dbt/macros/gold_user_query.sql`
- 집계 계산: `dbt/macros/gold_metrics_query.sql`
- 명세 대조 예시: `dbt/macros/gold_new_logging_mapping.sql`
- 컬럼·타입·스키마 생성: `scripts/gold_schema.py`
- 컴파일·공동 공개 SQL 생성: `scripts/gold_stage.py`
- 미확정 항목을 비워 둔 실행 계약 양식: `scripts/gold_build_contract.example.json`
- 인공 사례: `dbt/macros/gold_fixture.sql`, `dbt/tests/assert_gold_44_20_fixture.sql`
- 구조·입력·불변식 검사: `dbt/tests/assert_gold_44_20_*.sql`
- Superset Dataset: `superset/sql/gold_44_20/funnel_dataset.sql`, `service_users_dataset.sql`, `service_dau_wow_dataset.sql`, `weekly_nonreturn_dataset.sql`
- Superset 저장 Metric 및 차트 고정 조건: `superset/sql/gold_44_20/metrics.yaml`

이전 38컬럼용 일부 테스트는 역사 설명과 함께 비활성화하고 최신 테스트로 대체했다. Intermediate 모델·테스트는 기존 파일로 보존한다. 이 절은 커밋·PR·Airflow 배포 완료 기록이 아니다.

#### 실제 Stage 확인

- Silver Event: 21,593,491행, event_id 고유 21,593,491개, event_id NULL 0, 날짜 NULL 0, service_name NULL 0.
- pseudo NULL 3건은 USER×DAY 대상에서 제외한다.
- Gold 대상 Event→User 관계 누락 0, User 중복 조인 0.
- Silver User: 57,732행, 고유 pseudo 57,732개, pseudo·first_seen NULL 0.
- Event 관측 범위는 2024-07-11~2026-11-01. 이 MIN/MAX를 검증된 완전 구간으로 채택하지 않았다.
- ga_session_id 결측 100,255건, 동일 pseudo+ga 키가 24시간을 넘는 관측 1,877개가 있어 세션 의미·키 재사용 확인이 필요하다. 플랫폼 간 동일 키 관측 0만으로 스트림 간 충돌까지 검증했다고 보지 않는다.
- WEB은 전체 관측 범위 안에 이벤트 미관측 날짜 16개가 있다. 0건과 미수집을 구분할 원천 근거가 필요하다.
- 현재 Silver 분류에는 Android main 단계가 관측되지 않으며, 서비스별 단계 제공 플랫폼도 다르다. 기존 데이터의 분포를 새 명세 수집 결과로 간주하지 않는다.
- 현재 User에서 관측된 가장 최근 signup_completed_at 날짜는 2026-09-25다. 가입 원천 신선도·매핑 의미는 추가 확인한다.

Stage 스키마 생성 job은 `job_5kapOSXXa5JK1eQ0W4P7SJFUNTi4`(project `koin-stage-438512`, location `asia-northeast3`)이다. 재확인한 두 테이블 컬럼 수는 44/20이고 행 수는 0/0이다.

#### 인공 사례 검증

22개 검증은 이벤트 없는 가입행의 MAU 제외, 자정 통과 anchor, 다른 날짜에 퍼널 결과 복제 금지, 메인만 방문한 분모, 다른 세션 연결 금지, 시각 동률, 역순·반복 후 유효 경로, 직접 진입, 미완료 세션, 가입 D1/미성숙 D7, Range 다중 복귀 중복 제거·분모 보존·미성숙 조기 복귀, 주간 OR, 55/56일 경계, 주간 고유 분모·다른 서비스 앱 복귀, NULL 속성 보존, 가입 5단계 및 여러 세션 가입을 포함한다.

검증 job `job_DYtRqwBTOLDfmchJ695dHSFpAhRL`은 `totalRows=0`으로 실패 항목이 없음을 확인했다. 재개 후 결과 조회로 재확인했으며 같은 검증을 다시 실행한 것은 아니다. 이 결과는 합성 입력에 대한 계산 검증이며 실제 SDK·Silver의 단계 수집 증거가 아니다.

#### 새 명세와 연결할 입력 계약

[로깅 통합 가이드](https://app.notion.com/p/3c30221954bc8214b1c481c5bbb6fba5)와 [네이밍 사전](https://app.notion.com/p/38b0221954bc831b912c012d8af2c857)을 읽었다. 사용자는 개발자가 아직 새 로깅을 적용하지 않았다고 직접 확인했다.

명세에서 직접 확인해 입력 대조 예시에 넣은 값:

| event_label | Silver가 제공해야 할 분석 의미 |
| --- | --- |
| shop__shop_list__shop_detail__entry__click | shop / shop_view / 서비스 단계 2 |
| cafeteria__cafeteria__share__kakao__click | cafeteria / share / 서비스 단계 3 |
| timetable__timetable__timetable_export__image_save__click | timetable / save / 서비스 단계 3 |
| account__sign_up_policy__sign_up__terms_agree__click | account / terms_agreement / 가입 단계 2 |
| account__identity_verification__sign_up__code_verify_success__click | account / identity_verification / 가입 단계 3 |

예시 확인은 전체 6개 퍼널 매핑 확정을 뜻하지 않는다. Gold에서 미분류 이벤트를 위 예시로 보정하지 않고 제공된 Silver 분류가 기대 의미와 맞는지 검사한다. 전체 매핑표·실제 적용일·플랫폼별 가능 경로는 구현 담당자와 확정해야 한다.

특히 메인 방문을 별도로 관측할 근거, 가입 정보 입력 단계의 관측 시점, 가입 완료의 성공 조건, 식단 공유의 앱 전용 범위를 확인한다. 논리 화면명은 실제 화면 방문 이벤트와 구분하고 클릭은 기능 성공과 구분한다. 신규 명세가 완성됐다는 이유로 Gold 구조 설계를 기다릴 필요는 없으며, 이 미결 사항은 입력·실행 조건으로 남긴다.

#### 공개 절차 초안과 다음 단계

1. 새 로깅 SDK 배포 및 Silver 분류 반영을 확인한다. Silver 수정은 담당자 의존성이며 Gold 작업에서 수행하지 않는다.
2. 전체 6경로 매핑, 세션 키·동률·종료·지연 정책, 가입 신선도와 관측 이력을 검증한다.
3. 실제 배포일·고정 읽기 시점·완전 구간·지표 기준일 범위·승인된 세션 값과 검증 근거로 실행 계약을 채운다. 예시 JSON의 NULL·FALSE·0은 운영값이 아니다.
4. 활성 dbt 환경에서 `python scripts/gold_stage.py compile-offline --contract <계약.json> --dbt <dbt 실행파일> --target <임시 산출물 디렉터리>`로 컴파일한다. 일반 CLI compile 경로도 제공되며 인증 환경이 필요하다.
5. `publish-sql`은 배포·입력 검증 플래그가 모두 TRUE이고 근거가 있을 때만 Stage 전용 공개 SQL을 생성한다. 컴파일 계약·SQL 해시 불일치도 차단한다. 독립 모델 `dbt run/build`는 차단한다.
6. 생성 SQL은 고정된 입력 재검사 → 임시 후보 2개 생성·검사 → 두 Gold DML 공동 교체 순서다. 한쪽 실패 시 트랜잭션 이전 정상본을 유지하는 설계이며 실제 후보 적재·장애 복구 실행 검증은 남아 있다.
7. 실제 원천 대비 수치·집합·비용을 검증한 뒤 Superset Dataset·차트를 등록하고 필터 적용 범위, 갱신·캐시의 배치 일치, N/A·소표본·미완료 표시를 확인한다.

Superset 가상 Dataset의 날짜 처리는 [공식 SQL Templating 문서](https://superset.apache.org/docs/configuration/sql-templating/)의 `get_time_filter(..., remove_filter=True)`를 사용한다. 설치 버전·템플릿 활성화·실제 생성 SQL은 아직 확인하지 않았다. 문법 검증은 테스트용 날짜 표현식으로 렌더링한 SQL에 대한 것이다.

현재 완료 상태는 **SQL 초안 작성 + Stage 테이블 구조 생성 + 문법·합성 계산 검증**이다. **실제 새 로깅 수치 적재·Superset 화면 제공은 후속**이다.





### 6.19 GitHub Draft PR 준비 및 새 네이밍룰 대조 (2026-11-06)

최신 원격 main(`19f6e0b`)을 fetch로 확인하고, `feat/gold-new-logging-44-20` 브랜치에 최신 44/20 Gold만 분리했다. 기존 로컬 main의 미커밋 파일은 보존하며 Silver·Airflow·Intermediate 수정은 포함하지 않는다.

- 기준 명세: [로깅 통합 가이드](https://app.notion.com/p/3c30221954bc8214b1c481c5bbb6fba5), [네이밍 사전](https://app.notion.com/p/38b0221954bc831b912c012d8af2c857). 이번 준비에서 원문을 다시 읽었다.
- 일반 라벨은 `service__page__feature[__detail]__category`의 4~5구간이고 `lower_snake_case`를 사용한다. 마지막 구간은 기존 승인 `event_category`와 일치하며 `event_name`의 DA1/DA2를 유지한다.
- Gold는 새 라벨 토큰을 분리해 진단하고 Silver가 제공하는 서비스·Entry·Core·퍼널 분류를 소비한다. Gold에서 과거 라벨을 새 라벨로 치환하거나 Silver 분류를 복구하지 않는다.
- 입력 테스트와 Stage 공개 SQL 생성기에 DA1/DA2 일반 라벨의 형식·구간 수·category 접미 검사를 둔다. 명세의 동결·승인 예외를 임의로 일반 규칙에 맞춰 바꾸지 않는다. 해당 이벤트가 입력 기간에 포함되면 예외 범위와 처리 계약을 먼저 확인해야 한다.
- 논리 `screen_view=label page`는 실제 메인 화면 방문의 증거가 아니다. 현재 검사는 screen_view 원천 전달·실제 방문 수집을 검증하지 않는다. 전체 6개 경로 매핑·실제 호출·SDK 배포 확인은 여전히 대기다.

이번 브랜치에서 재확인한 결과:

| 항목 | 결과 |
| --- | --- |
| 최신 main 기반 dbt parse·오프라인 컴파일 | 통과. dbt-core 1.12.6 / bigquery adapter 1.9.2. DB 접속 없음 |
| 컬럼 및 의존성 | 사용자 44 / 집계 20, 두 모델 모두 Silver Event/User 직접 참조 |
| 미검증 실행 계약 | 공개 SQL 생성 차단 확인 |
| 공개 SQL 생성 | 합성 계약으로 네이밍 ASSERT가 임시 후보 생성 전에 배치되고 공동 트랜잭션이 생성됨을 확인. 실행하지 않음 |
| 합성 계산 22개 | BigQuery 결과 0행(실패 없음), job `job_ZRGi4ouOWV4dDMFeOCgKJ0LFdQlw`, asia-northeast3. cache hit이며 실데이터 검증 아님 |

컴파일에는 별도 임시 합성 계약을 사용했다. 예시 JSON의 날짜 NULL·검증 FALSE·세션 0을 실제 운영값으로 채운 것이 아니다. 저장소의 dbt 1.9 계열 호환을 위해 유지한 accepted_values 인자 형식은 dbt-core 1.12에서 deprecation 경고 1건을 출력한다.

현재 상태는 **Stage 테이블 구조 생성 완료, 실데이터 적재·퍼널·리텐션 검증 대기**다. Draft PR은 실데이터 검증 전까지 유지한다. 입력 계약 확정 → Stage 적재·원천 수치/집합·비용·공동 공개/실패 복구 검증 → PR에 결과 추가 및 리뷰·병합 → Superset 검증 → 별도 승인으로 운영 반영 순서를 따른다. 이 PR만으로 BigQuery 적재·운영 배포·Superset 등록을 실행하지 않는다.


### 6.20 PR #31 보완 — 검사 범위·후보 검증·세션 품질 (2026-11-06)

이 절은 6.19의 네이밍 검사·공개 전 검증 설명을 보완한다. 44/20컬럼과 두 Gold 모델의 Silver 직접 참조는 유지한다. 실제 새 로깅은 아직 배포·수집 확인 전이므로 SDK/Silver 실데이터 검증 완료로 표시하지 않는다.

**Notion 대조 및 네이밍 검사 범위**

[통합 규칙 v1.0](https://app.notion.com/p/4000221954bc81469ea6dbe19c7d8be7), [로깅 통합 가이드](https://app.notion.com/p/3c30221954bc8214b1c481c5bbb6fba5), [네이밍 사전](https://app.notion.com/p/38b0221954bc831b912c012d8af2c857)을 재조회했다. 품절 제보 원문·라벨·category·value와 Notion 명세는 수정하지 않았다.

- 실행 계약에 `naming_scopes`(platform, event_name, start_dt, end_dt, evidence)를 추가했다. 실제 배포 근거가 있는 플랫폼·DA1/DA2·기간만 일반 네이밍 검사를 적용한다. 빈 범위로는 공개 SQL을 생성하지 못한다.
- Silver에 검증된 앱/SDK 버전 필드가 없으므로 버전별 검증 완료를 주장하지 않는다. 동일 플랫폼·기간에 구버전이 섞이면 `approved_legacy_labels`의 platform/event_name/event_label/event_category 정확 일치와 source_url/evidence로만 승인한다. wildcard·prefix 예외는 허용하지 않으며 예시 목록은 비워 둔다.
- Notion v1.0 3-2절에 명시된 DA1 `cafeteria__cafeteria__soldout_submit` + category submit/fail만 고정 결과형 예외로 보존한다. 다른 category나 유사 라벨은 자동 예외가 아니다.
- 버스의 `bus__header__timetable__click` 같은 기존 목적지형 4구간은 일반 문법도 통과하므로 강제 변환하지 않는다. 새 목적지나 feature의 의미까지 승인하는 검사는 아니며, 전체 매핑 검증은 별도다.
- 범위 안의 미등록 구형/잘못된 라벨은 실패한다. 범위 밖은 `naming_outside_scope`로 보고하며 새 네이밍 검증 통과로 세지 않는다. 이를 이유로 Gold 활동 이벤트를 임의 제거하거나 Silver 분류를 복구하지 않는다. 공식 지표 공개에는 기존 수집 완전성·매핑 검증 게이트도 계속 필요하다.

**공개 직전 후보 검증**

`gold_stage.py publish-sql`이 컴파일된 의미 검증 9개와 두 모델 YAML의 일반 컬럼 테스트 50개를 읽고, Gold 참조를 같은 실행의 임시 후보로 바인딩해 `ASSERT NOT EXISTS`로 실행한다. 입력·네이밍·명세 대조·사용자 불변식·리텐션 구간·퍼널 원천 증거·배치·음수/중복 검사를 포함한다. 현재 공개 테이블의 INFORMATION_SCHEMA를 보는 2개 컬럼 목록 테스트는 후보 검사 대신 사용하지 않는다. 44/20 목록 일치는 컴파일 계약 대조로 확인하며 공개 INSERT는 계약의 컬럼을 명시한다.

퍼널 원천 검사는 단계별 시각/사용자/세션/퍼널의 실제 Silver 증거, 등록된 총 단계 수와 버전, 첫 단계 대상 보존 및 중복 facts를 확인한다. 리텐션은 57개 일별/9개 주별 구간과 period_n·분모 불변을 검사한다. 모델 SQL뿐 아니라 검증 SQL·품질 조회 SQL·일반 컬럼 테스트도 해시 고정하며, 계약/검증 목록/해시가 달라지면 재컴파일해야 한다. 모든 검사가 성공한 후에만 기존 공동 교체 트랜잭션을 시작한다.

**세션 키 품질 조회**

`dbt/analyses/gold_input_quality.sql`은 별도 조회 SQL이다. 세 번째 물리 Gold 테이블이나 45번째 사용자 컬럼을 만들지 않는다. 동일 Snapshot의 Gold 대상 입력에서 퍼널 대상 이벤트의 ga_session_id 결측/비정상 사유별 event_count·distinct_users를 반환한다. `funnel_session_key_excluded`는 두 사유를 합친 고유 사용자도 중복 제거한다. day_platform 및 whole_input 집계를 제공하며 일별 distinct_users를 합산해 기간 고유 사용자로 쓰지 않는다. 사유별 행도 서로 중첩되므로 전체 행 수를 합산하지 않는다.

`excluded_sessions`는 기존 배열에 남은 미완료 세션 수다. 키가 없어 제외된 규모를 대표하지 않으며, 새 품질 결과도 정확한 제외 세션 수라고 부르지 않는다. 공개 SQL에는 임시 품질 결과 SELECT가 포함되며 스크립트의 해당 SELECT 결과/child job을 저장할 수 있다. 공개 전 실패 시에도 독립 조회가 가능하다:

```bash
python scripts/gold_stage.py quality-sql --contract <실행계약.json> --target <컴파일디렉터리>
```

이 명령은 SQL 출력만 수행한다. 실운영 계약의 NULL·FALSE를 임의로 채워 실행하지 않는다.

**회귀 검증 결과**

- dbt parse/엔진 오프라인 컴파일 및 44/20컬럼·직접 Silver 의존성 확인 통과.
- Python 공개 게이트·예외 범위·검증 바인딩·계약/해시 변경 차단 8개 통과.
- 기존 합성 계산 22개 실패 0행: job `job_qkomzdTE-ClPbFRaxtf334tOtRJ7` (cache hit).
- 네이밍/세션 품질 합성 16개 실패 0행: job `job_tniQIcZHsvPDYlXKpIWWoJ0PeyIj`.
- 정상 후보/역순 퍼널/리텐션 구간 누락 합성 3개 실패 0행: job `job_sjKK2bvoZo__JAqXfxKvQ6eFdUC6`.
- 실제 생성기의 공개 직전 흐름을 합성 입력·임시 후보만으로 실행: job `job_tzuMrbyQ7Fuf1uZntcxk_KOeKNza`, 결과 `all_candidate_checks_passed`.
- 임시 후보에서 일별 period_n=7을 삭제한 실행은 `assert_gold_44_20_retention_grid`에서 차단: job `job_WbrgeuKfdsI9jegxxCKY_wdE8SXZ`.
- 퍼널 시각을 원천에 없는 값으로 바꾼 실행은 `assert_gold_44_20_funnel_source`에서 차단: job `job_rAFJqYwI41z7a9i2nanbXCUICvIX`.

모든 job은 Stage project, asia-northeast3다. 마지막 세 실행은 실제 Silver/Gold 참조 및 물리 공개 구간을 제거한 재현 SQL이며 실제 Gold 교체·트랜잭션 장애 복구를 검증한 것이 아니다. `scripts/gold_stage_regression.py`로 같은 합성 계약/컴파일 산출물에서 valid/missing_retention/funnel_without_source 시나리오 SQL을 재생성할 수 있다. 기존 dbt-core 1.12의 accepted_values 인자 deprecation 경고 1건은 유지한다.

현재 상태: 세 코드 문제 보완·합성 회귀 검증 완료. Stage 실데이터·비용·실제 공동 공개/실패 복구·Superset 검증은 여전히 대기다. PR #31은 Draft로 유지하며 운영 Airflow 변경·병합·운영 배포를 수행하지 않는다.


### 6.21 Silver 실행과 Gold 검증 테스트 격리 (2026-11-06)

36e5f78에서 Silver V2/User 단독 및 초기 적재 완료 후 일별·월별 선택에 Gold 테스트 4개가 간접 선택되는 것을 실제 dbt ls로 확인했다. Gold 태그만으로는 기본 eager 간접 선택을 막지 못한다.

- `dbt_project.yml`에 `gold_validation_enabled: false`를 선언했다.
- Silver를 직접 참조하는 `assert_gold_44_20_input`, `assert_gold_44_20_naming`, `assert_gold_44_20_new_mapping_examples`, `assert_gold_44_20_funnel_source`는 해당 변수가 boolean true인 경우에만 enabled가 된다. 문자열 "true"나 숫자 1은 허용하지 않는다.
- `scripts/gold_stage.py`의 일반·오프라인 Gold 전용 컴파일 경로는 동일한 vars에서 이 값을 true로 전달한다. Silver 모델·태그·Airflow 설정은 수정하지 않는다.
- 컴파일 및 공개 SQL 생성 단계에서 필수 의미 테스트 9개의 활성 Manifest 존재를 검사한다. 과거 SQL 파일과 해시가 남아 있어도 테스트가 누락/비활성화된 Manifest로 공개를 진행하지 못한다.
- 일반 실행에서는 기본 Snapshot 2000-01-01을 사용하는 네 테스트가 선택되지 않는다. 이 기본 날짜를 실제 관측/운영 날짜로 바꾸거나 입력 준비 완료로 간주한 것이 아니다.

회귀 검증:

| 실행/검사 | 결과 |
| --- | --- |
| Silver V2 단독 / User 단독 / 두 모델 선택 | Gold 테스트 각 0개 |
| tag:airflow_daily / tag:airflow_monthly | Gold 테스트 각 0개 |
| 위 일별·월별에서 initial_load_required 제외 | Gold 테스트 각 0개 |
| Gold 태그만 선택, 변수 미지정 | Silver 읽기 Gold 테스트 4개 제외 |
| 변수 false / 문자열 "true" / 숫자 1 | 위 네 테스트 제외 |
| Gold 변수 boolean true + Gold 태그 | 필수 의미 검사 9개 및 일반 컬럼 검사 50개 모두 포함 |
| 공개 게이트·해시·후보 바인딩 Python 회귀 | 기존 8개 + 누락/비활성 Manifest 2개 = 10개 통과 |
| 실제 dbt ls 회귀 | 5개 테스트 메서드, 12개 선택 조합 통과 |
| Gold parse/오프라인 컴파일 | 통과. 이전 산출물과 모델·검증·품질 SQL 62개를 strip 비교해 차이 0개 |
| 공개 SQL 생성 | 활성 Manifest로 성공. 실제 실행 없음 |

추가 재현 검사는 `scripts/tests/test_gold_dbt_selection.py`다. dbt-bigquery가 설치된 환경에서 `python -m unittest discover -s scripts/tests -p test_gold_dbt_selection.py -v`로 실행한다. dbt 미설치 시 skip되므로 그 상태를 격리 검증 통과로 취급하지 않는다. 이번 검증은 dbt-core 1.12.6 / bigquery adapter 1.9.2 환경에서 실제로 실행했다. 컴파일의 기존 accepted_values deprecation 경고와 반복 dbtRunner 호출의 라이브러리 ResourceWarning/DeprecationWarning은 테스트 실패가 아니다.

이번 변경은 테스트 활성화/선택과 누락 방지에 한정된다. 계산 SQL 62개가 이전과 동일해 BigQuery 합성 실행을 반복하지 않았다. BigQuery 실제 적재·SDK 배포·Stage 실데이터/비용/공개 복구·운영 Airflow·병합은 수행하지 않았으며 PR #31은 Draft를 유지한다. 사용자는 Silver도 직접 담당한다고 범위를 확장했으나 이번 PR 수정에서 Silver 매핑을 변경하지는 않았다. 다음 단계는 Silver 신·구 로깅 매핑과 입력 계약 정리다.


### 6.22 새 로깅 Silver 매핑 초안 및 합성 Silver→Gold 검증 (2026-11-06)

사용자는 Silver도 직접 담당한다고 명시했고, 새 SDK 로그 수집 확인은 Gold 공개 전으로 미루되 Notion 명세 기반 구현과 합성 검증을 먼저 진행하도록 승인했다. 이번 절은 그 범위의 결과다. 실제 수집·배포·실데이터 검증으로 승격하지 않는다.

Gold PR #31(09dde93)은 그대로 두고, 그 브랜치 위에서 `feat/silver-logging-v1-mapping`을 분리했다. Silver 변경은 별도 Draft PR로 검토하며 #31에 의존한다. 실제 Stage 테이블·운영 Airflow·Notion 원문은 수정하지 않는다.

**구현**

- 기존 Silver Event의 분류 CASE와 출력 스키마는 유지한다. 마지막에 Stage 전용 opt-in 매핑을 적용하는 분기만 추가했다. 기본 비활성 SQL은 09dde93과 공백 정규화 비교 시 동일하다. ID 선정·사용자 결합·가입 원천·기존 Android custom_session_id 정책은 바꾸지 않는다.
- `silver_logging_v1_enabled=false`, `silver_logging_validation_enabled=false`, `silver_logging_v1_scopes=[]`, `silver_logging_v1_legacy_labels=[]`가 기본값이다. 켜려면 실제 플랫폼·DA1/DA2·적용 시작/종료일·근거가 필요하다. prod target 또는 Stage 외 프로젝트는 컴파일에서 차단한다.
- 새 매핑은 원문 event_label/event_name/event_category/platform 정확 일치다. 라벨의 접두어만으로 서비스·퍼널 단계를 추정하지 않는다. 선언된 범위의 대상 서비스 신형 라벨이 미등록/잘못된 owner·category·플랫폼이면 unmapped/단계 NULL로 남겨 기존 화면명 때문에 main으로 잘못 분류되는 것을 방지한다. 범위 밖과 대상 외 서비스는 기존 결과를 유지한다.
- 구형 단일 구간 라벨과 기존 분류 기간을 보존한다. 신·구 구조형 라벨이 같은 기간에 섞이면 `silver_logging_v1_legacy_labels`에 platform/event_name/event_label/event_category/start_dt/end_dt/source_url/evidence를 정확히 등록해 기존 분류를 유지한다. wildcard는 허용하지 않는다. 실제 앱/SDK 버전 필드는 검증되지 않았으므로 버전별 적용 완료라고 하지 않는다.
- 품절 결과형 라벨 및 기존 품절/실험 6개 라벨은 원문과 기존 분류를 그대로 통과시킨다. 품절 기능·A/B·category·value·전송 조건은 재설계하거나 분석하지 않았다. 이 보존 목록이 Gold의 실제 입력 승인/구형 예외 등록을 대신하지는 않는다.

**Notion 근거와 매핑 범위**

[통합 가이드](https://app.notion.com/p/3c30221954bc8214b1c481c5bbb6fba5), [공통 네이밍 규칙](https://app.notion.com/p/4000221954bc81469ea6dbe19c7d8be7), [네이밍 사전](https://app.notion.com/p/38b0221954bc831b912c012d8af2c857)과 각 개별 새 로깅 본문을 읽었다. 카탈로그 `silver_logging_v1_rules`의 각 행에 개별 원문 page ID를 기록했다. 라벨 34종 / 근거 행 35개 / 플랫폼별 계약 77개이며, 280개 전체 로깅의 전수 매핑 완료를 뜻하지 않는다.

| 분석 서비스 | 구현한 단계·행동 | 플랫폼·미결 사항 |
| --- | --- | --- |
| shop | 목록 진입 / 상점 상세 클릭 / 전화 클릭 | 구 모바일 홈 전체보기와 새 WEB 인기 카드 구분. WEB 미확인 전체보기를 자동 허용하지 않음 |
| bus | 버스 진입 / 출발·도착 확인 / 조회 클릭 | 실제 main 접두 라벨도 분석 대상은 bus. 논리 main 방문으로 중복 생성하지 않음 |
| cafeteria | 카드·전체보기·헤더 진입 / 식사 시간 선택 / 공유 클릭 | 공유는 ANDROID/IOS만. iOS 빈 카드 more 공유 콜백 때문에 해당 more 경로는 미결로 제외 |
| timetable | 헤더·카테고리·프로필 진입 / 검색·학기·커리큘럼 선택 / 이미지 저장 클릭 | WEB 전용 탐색과 모바일 공통 동작 구분 |
| board | 공지 진입 / 검색 진입·실행 / 공지 선택 | WEB 제목 진입과 앱 하단 네비 진입 구분 |
| account | 가입 시작 / 약관 동의 / 인증 성공 | 학생·외부인 선택과 완료 버튼은 account로만 분류하고 퍼널 단계는 NULL |

가입 4단계의 ‘정보 입력 완료’ 관측과 5단계의 성공 조건은 현행 V2 명세에서 입증하지 못했다. [학생·외부인 선택](https://app.notion.com/p/9bd0221954bc833c845a818f39ef8ca0)을 form_entry로 대체하지 않으며, [회원가입 완료 버튼](https://app.notion.com/p/4830221954bc8355887e01f988251647)은 기존 click/value/발생 조건 보존 명세이므로 서버 성공으로 해석하지 않는다. 인증 성공만 [번호 일치 시점 명세](https://app.notion.com/p/9dd0221954bc83328f3101973bcaff2b)를 근거로 단계 3에 둔다. 실제 메인 방문을 증명할 새 이벤트도 임의로 만들지 않는다.

**파일 및 재현**

- 실제 모델 연결: `dbt/models/silver/silver_events_v2.sql`
- 정확 일치 카탈로그·Stage/범위/예외 게이트: `dbt/macros/silver_logging_v1.sql`
- 합성 입력: `dbt/macros/silver_logging_v1_fixture.sql`
- SELECT형 매핑 검사: `dbt/tests/assert_silver_logging_v1_mapping_fixture.sql`
- 임시 Silver→Gold 연결 스크립트: `dbt/analyses/assert_silver_logging_v1_gold_fixture.sql`
- 컴파일 도구: `scripts/silver_logging_stage.py`, Python 게이트 검사: `scripts/tests/test_silver_logging_v1.py`

```bash
python scripts/silver_logging_stage.py --target <임시산출물디렉터리>
python scripts/silver_logging_stage.py --target <임시산출물디렉터리> --synthetic-model
python -m unittest discover -s scripts/tests -p 'test_silver*.py' -v
```

두 컴파일 명령은 DB 접속/모델 실행이 없다. 기본은 합성 검증만 활성화하며, synthetic-model 옵션도 합성 기간으로 활성 분기의 SQL을 컴파일할 뿐이다. 운영 로깅 적용일을 설정하는 명령이 아니다. summary의 logging_deployed/coverage_verified/mapping_verified는 false다. 합성 fixture 안의 true 플래그는 계산 사례만을 위한 것이며 실행 계약 템플릿을 바꾸지 않는다.

**검증 결과**

- dbt parse와 실제 엔진 오프라인 컴파일(기본 분기·활성 분기) 통과. 실제 활성 Silver SELECT의 BigQuery dry-run 통과.
- Python 10개: 기존 파티션 5개 + 새 Stage/범위/예외/카탈로그 5개 통과.
- 기존 Gold 선택 격리 회귀 5개 통과. 일반 Silver 일별·월별에 Gold 검사가 섞이지 않음.
- 합성 매핑 입력 44개: 정상 경로 27이벤트 + 오류/구형/동결/범위/논리 main 사례 17개. 행별 기대 분류와 행 수·중복·원문/ID 보존·구형/품절 결과 보존 검사 실패 0행. job `job_UG-ImMtGeq73vJK54bUzBonO3x_y`.
- 합성 Silver→Gold 연결: 임시 분류 결과 27이벤트와 합성 User 입력으로 사용자 활동·5개 서비스 4단계 경로·가입 단계 3까지만 도달·가입 D1·서비스 D1·범위 D1~D7·불변식·리텐션 57/9구간 검사 실패 0행. job `job_w2O34WcczKiEkpZ14sL4LnJAKwVP`.
- 두 실행은 koin-stage-438512 / asia-northeast3이며 실제 Silver/Gold 테이블을 읽거나 교체하지 않았다. 연결 스크립트의 main 시작점은 명시적으로 주입한 합성 기존 main 사실이다. 실제 새 SDK의 main 관측 증거가 아니다. User 데이터도 합성 입력이며 silver__users 원천/결합 SQL의 실데이터 검증을 대체하지 않는다.

하나의 거대 SELECT는 query-planning 복잡도 제한에 걸려 연결 검증을 CREATE TEMP TABLE 경계로 분리했다. 실패한 중간 실행을 통과 근거로 사용하지 않는다. 기존 dbt accepted_values 인자 경고는 유지한다.

다음은 미결 매핑 의미(가입 4/5단계·실제 main·플랫폼 예외)와 실행 계약을 정리하고, 새 SDK 실제 수집 이후 적용 기간·버전·세션·User 입력·완전 구간을 검증하는 일이다. 그 전까지 Gold 공개는 차단하고 두 PR은 Draft로 유지한다. Stage/운영 적재·PR 병합·실제 공동 공개/복구·비용·Superset 검증은 이번 작업에 포함하지 않았다.


### 6.23 PR 검토 보완: 서비스 분류·플랫폼 지원·전수 합성 검증 (2026-11-06)

이 절은 6.22의 미등록 라벨 처리와 플랫폼 예외·검증 범위를 갱신한다. 44/20 물리 스키마와 동결 로깅 원문은 유지한다. 실제 새 로그 수집 확인을 뒤로 미룬 것은 개발 순서의 변경이며 공개 승인이 아니다.

**서비스 분류와 퍼널 분리**

`silver_logging_v1_classify`는 정확 일치 서비스 계약과 퍼널 계약을 분리한다. Notion에 근거가 있는 프로필 로그인·로그아웃·비밀번호 변경을 account 이용으로 포함하되 퍼널 단계·Entry/Core는 부여하지 않는다. 범위 안 대상 서비스의 미등록 라벨·owner/category/platform 불일치는 실제 활성 경로에서 ERROR로 계산을 중단한다. 기존 화면명으로 자동 복원하거나 unmapped로 조용히 누락하지 않는다. 승인된 구형 계약·적용 기간과 품절/실험 7개 원문 보존은 그대로다. diagnostic_only는 합성 검증의 오류 사례 관찰용이며 활성 모델에서 사용하지 않는다.

등록 범위는 라벨 37종 / 근거 행 41개 / 플랫폼별 계약 86개다. 기존 77개를 전부 포함한다. 계정 비퍼널 계약 13개도 정상 분류 사례로 검사한다. 전체 280개 이벤트의 매핑 완료를 뜻하지 않으며 실제 관측된 미등록 라벨은 원문 근거를 추가하고 재검증해야 한다.

**플랫폼·경로 처리**

- iOS `main__main__more__click`: 정상 전체보기와 빈 식단 카드 콜백을 구분할 수 있는 필드 증거가 없다. cafeteria 서비스에는 포함하고 단계는 NULL로 둔다. 해당 콜백이 있는 세션의 식단 퍼널은 is_complete=false로 제외해 미확인 진입을 실제 이탈로 계산하지 않는다. 정상 경로의 완료율 활성화에는 추가 경로 증거가 필요하다.
- WEB 시간표 카테고리: Notion 본문의 모바일웹 `/category` 근거를 반영했다. 정확 라벨·DA1·click·WEB에 더해 page_location이 `/category`, `/category/…`, `/category?…`, `/category#…`인 경우만 진입 단계로 분류한다. 경로가 없거나 다르면 활성 계산을 차단한다. 앱과 모든 WEB 경로를 일괄 허용하지 않는다.
- 새로운 메인 방문을 논리 접두어나 서비스 진입으로 합성하지 않는다. 가입 4/5단계도 사용자 유형 선택·완료 버튼으로 대체하지 않는다.

`gold_funnel_support`의 18개 계약은 다음과 같다. ‘지원’은 명세상 단계 경로가 있다는 의미이며 실제 배포·수집 검증 완료를 뜻하지 않는다.

| 퍼널 | WEB | ANDROID | IOS |
| --- | --- | --- | --- |
| signup | 미지원: 4/5단계 미확인 | 미지원 | 미지원 |
| shop | 지원 | 지원 | 지원 |
| bus | 지원 | 지원 | 지원 |
| cafeteria | 미지원: 공유 없음 | 지원 | 지원: more 콜백 세션 제외 |
| timetable | 지원 | 미지원: 탐색 미매핑 | 미지원: 탐색 미매핑 |
| board | 미지원: 탐색 미매핑 | 지원 | 지원 |

지원하지 않는 퍼널은 is_complete=false이고 Superset reached_users는 유효 세션이 없으면 NULL(N/A)이다. 실제 이탈 0명과 구분한다. facts에 세션 플랫폼 컬럼이 없으므로 일별 platform_dominant를 세션 플랫폼 필터로 사용하지 않는다. 플랫폼별 지원표와 `gold_input_quality`의 미지원/경로 미확인 사유를 함께 확인한다.

**공개 게이트**

Gold 실행 계약에 main_visit_verified, main_visit_verified_evidence, main_visit_platforms, funnel_support_verified, funnel_support_verified_evidence를 추가했다. 기본은 false/빈 값이다. 공개 도구는 기존 배포·완전 구간·가입 원천·매핑·세션 조건과 함께 근거를 요구한다. 실제 메인 관측이 승인된 플랫폼만 서비스 퍼널의 완료 관측 대상이 될 수 있다. 지원표는 공개 SQL에서 후보 품질 결과와 함께 출력하며 트랜잭션 전에 기존 의미 검사 9개+일반 검사 50개를 실행한다. 가입 5단계는 지원표에서도 차단하므로 설정 true만으로 성공 퍼널이 되지 않는다.

**검증**

- Silver/Gold 실제 dbt 엔진 오프라인 컴파일 통과. 활성 Silver SELECT BigQuery dry-run 통과(추정 1,357,103 bytes). 실테이블 실행·교체 없음.
- Silver Python 11개(파티션 5+게이트/계약 6), Gold 공개 게이트 12개 통과. 일반 Silver 단독·일별·월별과 Gold opt-in 선택 회귀 5개/12조합 통과. 비활성 합성 SQL은 본문 렌더링까지 격리해 기본 dbt parse에 영향을 주지 않는다.
- 독립 고정 기대 카탈로그 `silver_logging_v1_expected.sql`의 86개 정상 입력: 서비스·단계·순서·Entry/Core·원문·행 수/중복 보존·account 이용 검사 실패 0행. job `job_8rSofXAoiVH9dFK2IIHryHI5fOSJ`.
- 기존 경계/구형/동결 포함 44개 입력 매핑 검사 실패 0행. job `job_4S9mS_0Cf1euOIErALQHTLS4p231`.
- Silver→Gold 27이벤트 연결과 활동·퍼널·리텐션·구간 검사 실패 0행. job `job_4GLIjSSmWZAL_CuvE3G7ntNi1GpL`. 합성 main은 실제 수집 증거가 아니다.
- Gold 지원표·미지원·main 게이트·NULL 지표·iOS 모호 세션 7개 검사 실패 0행. job `job_dZsd_-N6Z_Hc1byof2HJ1PHbD13W`.
- 최종 Gold 후보 검증 9개+일반 검사 50개 모두 통과: job `job_zlzuS0rUmTX6XulMsWZEwnWAoQLm`. 실제 공개 DML은 제거한 합성 스크립트이며 지원표·품질 보고까지 실행했다.
- 실제 strict 분기의 미등록 라벨은 `Silver v1 service contract missing`으로 차단: job `job_pvtZgTdDxUlcI7dsJultWYW-eTmg`. 잘못된 WEB 경로도 `Silver v1 route contract missing`으로 차단: job `job_4l_5aNzOOBWg6v4bzmJvF7V1cZUh`. 두 실행은 의도한 실패 검증이다.

모든 합성 실행은 Stage asia-northeast3의 SELECT/임시 테이블이며 실제 Silver/Gold 원천을 대체 입력으로 사용하지 않았다. 일반 모델 dry-run은 문법·참조 확인이고 실제 데이터 정확성 검증이 아니다. 초기 개발 중 실패한 구문/파싱 실행은 통과 근거에 포함하지 않는다. 기존 accepted_values 인자 경고는 남아 있다.

PR #31과 #32는 Draft를 유지한다. #32는 #31 브랜치를 대상으로 하며 #31 처리 후 대상 브랜치와 차이를 다시 확인한다. 다음은 새 SDK 수집 이후 실제 적용 기간·플랫폼/버전·메인/가입 증거·Silver User/세션/완전 구간 검증, Stage Gold 수치·비용·공개/실패 복구 검증이다. 운영 Airflow·실제 테이블 공개·GitHub 병합은 수행하지 않는다.


### 6.24 Stage Airflow Silver V2/User 전환 준비 (2026-11-06)

사용자는 Airflow에서 기존 silver_events 대신 silver_events_v2와 silver__users를
갱신하도록 전환하고, 스케줄링 기간은 기존 silver_events와 동일하게 유지하도록
요청했다. #32 브랜치 위의 별도 feat/stage-silver-v2-airflow에서 구현한다.

- KOIN_DATA_SILVER_V2_ONLY=false가 기본이다. false일 때 기존 모델 선택/운영 동작은
  유지한다. true이면 daily/monthly 태그와 두 모델명의 교집합으로 V2/User 및 각
  모델의 테스트만 선택한다. legacy silver_events, Gold, 합성 검사는 제외한다.
- Stage dev, 출력 koin-stage-438512, GA4/앱 DB 프로젝트 모두 Stage, 원천 데이터셋
  명시, BOOTSTRAP_COMPLETE=true가 필요하다. 최초 적재 여부는 사람이 실제 이력과
  입력 검사를 확인한 뒤 설정하며 테이블 존재만으로 켜지 않는다.
- DAG 파싱 및 첫 validate_dates task에서 환경을 검사한다. V2로 파싱한 DAG의
  실행 환경이 옵션 false/운영 원천/최초 적재 미완료로 바뀌면 downstream을 차단한다.
- 일별은 기존 매일 09:00 KST·어제까지 최근 3일이며 수동 start_date/end_date 동작도
  유지한다. 월별은 기존 매월 1일 12:00·예정일 30일 전~실제 실행일 어제, 당일
  09시 daily 성공 대기와 reconcile_window=true 정책을 유지한다.
- V2 선택 옵션과 새 네이밍 매핑 활성화는 별개다. 새 로깅 적용/Gold 인증 플래그를
  켜지 않는다. 두 Silver 모델은 별도 쓰기이므로 한쪽 실패 시 양쪽 쓰기를 원자적으로
  롤백한다고 보장하지 않는다. Gold 연결/공개는 이번 변경에 포함하지 않는다.
- 저장소 dbt ref에서 legacy Event 직접 의존은 찾지 못했다. 외부 Superset/직접 SQL
  사용처까지 확인한 것은 아니며 legacy 테이블을 삭제/이름 변경하지 않는다.

현재 Stage 테이블 메타데이터 읽기 전용 확인: silver_events_v2 21,593,491행,
silver__users 57,732행. 두 테이블 모두 주요 Gold 입력 컬럼이 있고 마지막 수정은
2026-11-03 09:54 KST다. 앱 DB 원천 analytics_427218788.koin_users도 존재(5,827행),
테이블 마지막 수정은 2025-11-10이다. 이는 메타데이터 관측이며 최초 전체 이력·실제
로깅·가입 스냅샷 신선도 검증 완료를 뜻하지 않는다. 새 테이블을 무조건 만들거나
전체 재적재하지 않고, 기존 이력·원천 준비 상태를 먼저 확인한다.

재현 절차·실행 대상·Stage 환경 예시는 airflow/README.md에 기록했다. 실제 Stage
.env, 최초 적재 완료/V2 플래그, 컨테이너 또는 운영 스케줄은 변경하지 않았다.
Docker Engine 연결이 없어 실제 Airflow/Cosmos 컨테이너 DAG 파싱·수동 실행은
별도 검증으로 남긴다. Python 정책/실제 dbt ls/날짜 회귀 검사는 별도로 기록한다.

검증 결과: Python 회귀 45개 모두 통과(실제 dbt ls 선택6개/16호출, 공개 게이트12개,
월별 날짜7개, 신규 Stage 환경/일별 날짜9개, 기존 Silver 파티션5개, 매핑6개).
일별·월별 V2 선택은 정확히 두 모델이고 연결 테스트도 두 모델 범위에만 속한다.
Gold/합성 검사 및 legacy Event는 제외된다. Airflow Python 구문 검사 통과.
기존 dbt accepted_values 경고/라이브러리 ResourceWarning은 유지하며, 초기 테스트
경로가 dbt 플러그인 탐색을 방해한 실패는 수정 후 재실행했고 통과 근거에 포함하지
않는다. 실제 Airflow 컨테이너 DAG 파싱·수동 실행·스케줄 활성화는 아직 수행하지 않았다.


### 6.25 Stage 로컬 Airflow 실기동·V2/User 전환 검증 (2026-11-06)

6.24의 Docker 미기동/실행 검증 대기 상태를 이번 절로 갱신한다. 사용자가 Stage
Airflow 구성·실행과 후속 V2/User 전환을 승인했다. 로컬에서만 별도 메타데이터 DB와
Airflow3.0.1/Cosmos1.16.0/dbt-core1.12.6/BigQuery1.9.2로 실행했다. 실제 운영 서버,
Production 테이블, GitHub 병합은 변경하지 않았다. 로컬 계정·환경·Compose는
Git 제외 파일로 보관하고 비밀값은 문서/PR에 기록하지 않는다.

**입력·기존 실패 확인**

- 처음에는 최초 적재 플래그가 false여서 기존 silver_events만 실행됐다. 사용자
  화면에서 시작한 예약/수동 실행의 두 unique 검사에서 각각 893건 실패를 확인했다.
  실패 결과를 무시하거나 성공으로 바꾸지 않고 전환 중 미완료 실행을 종료했다.
- 기존 V2 21,593,491행은 event_id가 모두 고유하고 필수 분류/날짜 NULL이 없었다.
  User57,732행도 고유하고 필수값 NULL/역전 시각이 없으며 V2의 사용자 결합 누락0.
  preflight job_cy6cMDlBFuQCMtPlEAJhHinHdHVj, 실제 dbt 검사15개 PASS.
- V2 파티션은 2024-07-11~2026-11-01, User최초 관측은 2024-05-03부터 보존돼 있었다.
  전체 재생성 대신 누락된 2026-11-02~11-05를 명시 범위로 보충했다. 원천 최근5개
  export와 월별 보정+UTC전날 원천36개가 모두 존재함을 먼저 확인했다.

**전환·실제 실행**

Stage 출력/두 원천 프로젝트를 검증한 후 로컬 BOOTSTRAP_COMPLETE 및
SILVER_V2_ONLY를 true로 반영하고 API/스케줄러/DAG 프로세서/트리거를 재생성했다.
일별에는 V2/User 실행·테스트와 validate_dates, 월별에는 동일 모델과 날짜 검증·
wait_for_daily만 포함된다. 기본 false인 운영 선택 정책은 유지한다.

- 보충 수동 실행 manual__2026-11-06T10:22:02.220652+00:00 성공, V2/User 실행·테스트
  모두 성공. conf start_date=20261102/end_date=20261105.
- 기존 오전9시 실행 scheduled__2026-11-06T00:00:00+00:00을 새 DAG 구성으로 clear 후
  재실행해 성공했다. 이전 legacy task는 Airflow가 removed로 처리했고, V2/User
  실행·테스트가 실제 성공했다. 원래 오류 로그/이력은 보존했다.
- 월별 scheduled__2026-11-01T03:00:00+00:00도 날짜 검증부터 재실행해 성공했다.
  실제 실행일인 11월6일 오전9시 daily 성공을 기다린 뒤 10월2일~11월5일을
  reconcile_window=true로 보정했다. 센서 조건/기간을 우회하지 않았다.
- 두 DAG는 Stage에서 활성 상태다. 매일09시/최근3일, 매월1일12시/기존30일 보정
  정책은 유지한다. 같은 파티션의 수동/예약 쓰기가 겹치지 않도록 daily에도
  max_active_runs=1을 추가했다. 이는 실행 동시성 제한이며 주기/기간 변경이 아니다.

**사후 검증과 범위**

최근 이벤트: 11월2일342행,3일512행,4일139행,5일242행. 각 날짜 event_id가 모두
고유하다. 보정한 10월2일~11월5일 이벤트의 사용자 결합 누락0. User57,940행과
고유 키57,940개가 같고 최초 관측2024-05-03은 보존, 마지막 관측2026-11-05
23:59:04.274001로 갱신됐다. job_6K6YN_QZSsojQVN1dcoXaKA4DPLz.

Python 전체 회귀46개 통과(기존45+일별 직렬화1). 실제 Airflow 로그인·건강 상태,
DAG 로딩 오류0, 두 모델의 실제 쓰기/테스트, 재실행, 월별 daily 대기를 확인했다.
처음 전환하면서 종료한 legacy 수동 실행은 실패 이력으로 남아 있다. 기존 legacy
테이블 중복 자체를 복구했다는 의미는 아니며 전환 후 실행 대상에서 제외했다.

V2/User 갱신 성공은 새 SDK 배포·네이밍 매핑 활성화나 Gold 공개 승인이 아니다.
새 로깅 매핑 및 Gold 인증 플래그는 비활성 상태이고, 앱 DB 원천의 최신성·실제
메인/가입 관측·수집 완전 구간·Gold 수치/비용/공개 복구는 여전히 별도 검증이다.

사후 전체 Event는20,692,264행이다. 전환 전21,593,491행과의 차이는 월별 검증 범위의
기존913,333행이 Stage 계산12,106행으로 바뀐 결과다. Stage 원시 이벤트는 같은
구간12,113행이며 정제 모델·unique 검사를 통과했다. time travel 대조에서 변경일35개,
요청 구간 밖 변경0일을 확인했다(job_Ol4imBms3L_Zrqc9_qYOgIkHy6WU).
기존 적재 job2c1f5841-1d3d-48c0-81a7-53f9daa5f4f7의 referencedTables가
kap-chat.analytics_432041405였음을 확인했다. 현재 실행 원천은 Stage다. 따라서
범위 밖에 남은 과거 운영 원천 기반 이력과 최근 Stage 원천을 같은 모집단이라고
가정하지 않는다. Gold 이력 비교/완전 구간 승인 전 출처 정합성 검증이 필요하다.
해당 범위 밖 데이터 복구/재생성이나 Production 조회·쓰기는 수행하지 않았다.


### 6.26 승인 원천 복구·User Snapshot 재계산·DAG 공통 쓰기 제어 (2026-11-06)

사용자는 운영 원천 읽기→Stage 출력 방식으로 출처를 통일하고 Event와 User를
함께 복구하도록 승인했다. 먼저 두 Stage DAG를 중지했다. 코드 버전d7ecba3,
당시 원천/프로파일/기간 설정을 보존하고 현재 Event/User 및 혼합 전10:20UTC의
Event/User Snapshot을 각각 만들었다(4개,7일 만료). 원본 실행 이력은 보존했다.
Production 쓰기와 GitHub 병합은 하지 않는다.

**출력과 원천 계약 분리**

출력 프로젝트는 반드시 koin-stage-438512이고 프로파일은 dev다. GA4/앱 DB 원천은
별도 KOIN_DATA_SILVER_SOURCE_CONTRACT JSON에 프로젝트·데이터셋4개 및 evidence를
명시하고 실행 환경이 정확히 일치해야 한다. 이번 승인 원천은 두 source 모두
kap-chat.analytics_432041405다. 출력까지 운영으로 바꾸거나 명시 계약 없이
묵시적 기본 원천을 사용하는 것은 차단한다. 기존 Stage 원천 강제 정책을 대체한다.
원천 계약/출력 제한의 성공·실패 회귀 검사를 추가했다.

**Event/User 후보와 공동 복구**

- Event는 변경된2026-10-02~11-05의35일만 승인 원천에서 재계산해 후보를 만들었다.
- User는 MERGE 영향을 되돌리기 위해 혼합 전 Snapshot57732명을 기존 상태로 삼아
  승인 원천으로 재계산했다. 현재57940명을 그대로 MERGE 입력으로 쓰지 않았다.
- Stage 원천 작업으로 추가됐던208명 중 승인 원천에도 있는3명을 제외한205명은
  후보에서 제거됐다. 승인 원천의 새 사용자412명을 반영해 후보58144명이 됐다.
  혼합 전 기준 기존 사용자 변경은 Stage작업2198명, 승인 원천 후보2156명이다.
- 속성별 비교에서 Stage작업으로 달라졌던 user_type1960건, signup_completed_at2169건,
  is_deleted/is_mysql_mapped각1628건은 승인 원천 후보에서 혼합 전 값으로 돌아왔다.
  first_seen_at9건도 복구됐다. 신규 관측에 따른 last_seen/지원 수/대표ID 등은
  승인 원천 계산 결과를 사용하고 과거 행 수/속성을 억지로 맞추지 않았다.
- 후보 generic15개+관계/범위/기존 User기간 보존3개 검사 모두 통과한 후 Stage의
  35일 Event 교체와 User 전체 후보 교체를 하나의 트랜잭션으로 반영했다.
  반영 전 동시 변경이 없는지 검사하고 commit 전 전체Event→User 관계도 검사했다.

후보 Event1072813행, User58144행. 기존에 존재했던10월2일~11월1일의 Event는
모두 후보와 같은 키/내용으로 복구됐고, 현재 승인 원천 재계산에서 새 키426개가
추가 관측됐다. 기존 키 삭제/동일 키 내용 변경은0이다. 범위 밖은 날짜별 건수와
전체 행 지문을 비교해 변경0일을 확인했다. 따라서 과거 건수와 같다는 이유만으로
복구를 판단하지 않았다. source-repair Snapshot/후보는 Stage silver에만 생성했다.

**DAG 간 쓰기 제어**

Stage V2모드에서 daily/monthly의 모든 dbt실행·테스트 task에 같은
koin_stage_silver_writes pool과pool_slots=1을 적용했다. 실제 Airflow pool도1slot이다.
날짜 검증과 daily성공 대기 센서는 pool밖에 둔다. 같은 DAG내 max_active_runs=1과
함께 사용하며, 일별·월별·수동 dbt쓰기 사이의 동시 실행을 막는다. 개별 task단위
직렬화이므로 전체DAG가 한꺼번에 락을 보유하는 것은 아니고 두 모델의 통상 갱신을
원자적으로 만든 것도 아니다. 직접CLI/BigQuery 복구는 이 pool밖이므로 DAG중지 후
진행 중 쓰기가 없는 상태에서만 수행해야 한다.

스케줄은 일별09시/최근3일, 월별1일12시/기존30일보정으로 유지했다. 새 로깅 매핑과
Gold공개 플래그는 비활성이다. Production최초 적재·운영선택정책·리뷰/병합은 별도다.

**검증 완료 결과**

Python 전체49개 통과. 실제 운영 원천→Stage 경로에서09시 예약 재실행과 일별/월별
수동 실행을 동시에 제출했다. 세 실행 모두 성공했고 공통pool의 dbt task12개의
실제 시작/종료 구간을 비교해 겹침0건(서로 다른DAG간 겹침도0건)을 확인했다.
월별은 실제09시daily성공을 기다렸으며 센서는쓰기pool밖에서 대기했다. Stage의
두 스케줄은 기존 주기대로 복구했고 Production은 변경하지 않았다.

최종 Event21,752,971행, User58,144행/고유키58,144개. User 최초 관측2024-05-03은
보존됐고 마지막 관측은 승인원천의2026-11-05 23:58:30.714039이다. 보정35일의
Event→User결합 누락0, 복구후 가입/유형/삭제/매핑 속성과 승인후보 불일치0.
job_LbscFebWXCbkizx9dhnwoVxIHWuF. 이는 Gold 공개 승인이 아니다.

근거: Snapshot job_QaoGUZcYj1AVBleyy0a3KrMH6MgJ,
Event후보 job_0otKB109WCS4alW9aXYE4NlUTzPS,
User후보 job_zaca9DiJ9yoect_zQOdjeXyVcgfn,
후보검사 job_9eyrQ2pHomsbJAFyZbbW_2lJWWh9,
User차이 job_Mh4xSoEp6lHCQpen1NJBDUwp9-xL,
속성비교 job_FwCN6o0GUfsTci2BNdv3JbUq75tb,
공동복구 job_qjYb-gH0f8_A5IZNAdJK-hhTTrIP,
범위밖지문 job_HmSGzJRu3qx-89ZWX701YjLA20Ez,
기존행비교 job_N5Vd3yIQm47N56fkgj5FzH3qtjDo.
수동실행은 daily manual__2026-11-06T11:00:42.933699+00:00,
monthly manual__2026-11-06T11:00:42.650786+00:00이며 실행·검사 모두success다.
복구 전/혼합 전 Snapshot과 후보는7일 만료로 보존한다.

Production 준비 시에는 현재 Stage전용 V2옵션을 그대로 운영에서 켜지 않는다.
운영 두 테이블 존재/초기 범위/비용을 다시 확인하고 최초 적재와 품질 검사를 먼저
수행해야 한다. 운영용 모델선택·공통쓰기pool과 기존silver_events 사용처 전환을
별도로 검토한 뒤 운영스케줄을 변경한다. 이 작업에서 운영쓰기/병합은 하지 않았다.


### 6.27 Production Silver 병행 배포 정책 (2026-11-06)

사용자가 Stage 검증 후 운영 배포 준비·최초 적재·검증·스케줄 활성화를 요청했다.
출력과 GA4/app_db 입력은 kap-chat / analytics_432041405에 고정한다.
Event 최초 범위는 2024-07-11~2026-11-05, User는 원천 전체 2024-05-03~2026-11-05다.
운영 원본 Event와 사용처를 유지하고 KOIN_DATA_SILVER_PROD_MODE=parallel로 시작한다.
일별은 silver_events + silver_events_v2 + silver__users, 월별은 V2/User 두 모델이다.
기존 일별 09시·최근 3일, 월별 1일 정오·30일 보정과 당일 09시 성공 의존을 유지한다.
Stage 전용 옵션은 false, 신규 로깅 매핑·Gold 인증/공개는 계속 비활성이다.
원천 계약·두 모델 최초 적재 검증 JSON·BOOTSTRAP_COMPLETE를 모두 요구한다.
기존 사용처 전환 증거 없이는 운영 v2_only를 차단한다.
운영 공통 pool koin_prod_silver_writes 1 slot으로 일별·월별·수동 dbt task를 직렬화한다.
풀은 직접 SQL 작업이나 전체 DAG의 원자성을 보장하지 않는다.
라이브 체크아웃 대신 별도 release와 Airflow 전용 Compose overlay를 사용한다.
이 절의 배포 결과는 실제 적재·실행 확인 후 아래에 기록한다.


운영 배포·검증 결과:
- 실행 코드: 39958d3, 별도 release `/home/ubuntu/koin-releases/silver-prod-39958d3`.
- Event 21,752,971행, 2024-07-11~2026-11-05 연속 848일. User 58,144행,
  최초 관측 2024-05-03, 사용자 키 중복·필수값 누락·Event 결합 누락 0건.
- 운영 서비스 계정 dbt 품질 검사 15개 통과. 로컬 회귀 50개 + 운영 dbt 선택 검사 1개 통과.
- 실제 일별 수동 검증과 월별 예약 실행 모두 성공. 두 DAG의 dbt task 10개가 공통 풀에서
  겹침 없이 실행됐다. 월별은 활성화 후 11월 1일 예약분이 생성되어 10월 2일~11월 5일을
  보정했고, 실행 당일 11월 6일 09시 daily 성공을 확인했다.
- 일별 다음 실행 11월 7일 09시 KST, 월별 다음 실행 12월 1일 12시 KST.
- API·Scheduler·Dag Processor·Triggerer 정상, DAG 로딩 오류 0건.
- 라이브 main 체크아웃과 dashboard_assets/는 보존. 원본 .env/Compose/컨테이너 설정/
  DAG 상태/메타데이터를 비공개 백업했으며, 기본 Compose도 release overlay를 계속 사용한다.
- 후보·검증 근거 job: `koin_prod_bootstrap_silver_events_v2_20261106_v1`,
  `koin_prod_bootstrap_silver__users_20261106_v1`, `koin_prod_bootstrap_validation_20261106_v2`,
  `koin_prod_silver_initial_publish_20261106_v1`, `koin_prod_silver_postwrite_validation_20261106_v1`.
- 기존 silver_events는 일별 갱신을 유지한다. V2 단독 전환·사용처 변경은 하지 않았다.
- PR #34는 #33 기반 Draft로 유지한다. 신규 로깅 매핑과 Gold 공개·실데이터 지표 인증은
  이번 Silver 배포와 별개이며 아직 활성화하지 않았다.

### 6.28 사용자 원천 CDC 재적재·Silver 계정 속성 복구 (2026-11-07)

사용자 요청으로 mysql-users-prod의 koin.users 객체를 전체 재적재했다.
원천 연결·대상 프로젝트·기존 스키마는 유지했다. 복구 전 원천을 동일 analytics 데이터셋에
koin_users_before_cdc_recovery_20261107로 복사하고, Silver User를
silver__users_before_cdc_recovery_20261107 Snapshot으로 보존했다(각 7일 만료).
일별·월별 DAG를 잠시 중지하고 활성 실행 0건을 확인한 뒤 복구했으며, 완료 후 둘 다 재개했다.

- Datastream 재적재: 09:48:07~09:48:11 KST COMPLETED, 스트림 RUNNING/오류 없음.
- 원천 논리 조회: 6,227→6,261행, id 고유 6,261, 새 ID 34/기존 ID 제거 0건.
  최신 created_at은 2026-09-25T12:30:22Z→2026-11-06T17:48:17Z로 전진했다.
- 기존 max_staleness=1시간은 최신 CDC 데이터가 있어도 구 저장본을 반환했다.
  0초 최신 조회로 복구분을 확인하고, 최종 Datastream dataFreshness=60s와
  BigQuery max_staleness=1분으로 일치시켰다. 더 잦은 CDC 병합/쿼리 비용이 발생할 수 있다.
- 일반 증분 User build(reconcile_window=false, 11월 4~6일)를 운영 서비스 계정으로 실행했다.
  User 58,144행 유지, 계정 속성 23행 갱신, 키·대표 ID·first/last_seen 변경 0건.
  dbt 검사 5개 통과, 원천 대비 계정 속성 불일치·중복/Null 키·미래 가입일 0건.
- 오늘 정기 09시 DAG는 09:02:33 성공했고 V2 10검사/User 5검사 모두 통과했다.
  서버 runtime 39958d3과 GitHub PR #34의 실행 파일 53개 해시가 모두 일치한다.
- 일별 다음 실행 11월 8일 09시, 월별 12월 1일 12시 KST. 기존 Event 병행 유지.
- GA4 events_20261106은 확인 시 미도착이다. 최근 내보내기 LOAD 오류는 없었으며,
  GA4 일별 내보내기 시각은 보장되지 않는다. 원천 도착 전 해당 날짜를 생성/대체하지 않았다.
  GA4 Admin 설정 조회는 OAuth scope 부족으로 확인하지 못했다. 도착 후 재처리와 커버리지
  확인이 남으며, 최신 일자까지 완료됐다고 인증하지 않는다.
- MySQL 직접 SQL 전수 대조는 하지 않았다. 기존 연결을 통한 Datastream 전체 재적재와
  BigQuery·Silver 정합성 검증 결과다. Gold·가입 퍼널/리텐션·Superset 공개 검증은 별도다.

근거 Job: koin_cdc_recovery_backups_20261107_v1,
koin_cdc_recovery_force_fresh_read_20261107_v1,
koin_cdc_recovery_final_quality_20261107_v1.
상세 로컬 기록: /mnt/c/Users/sm222/koin_cdc_recovery_20261107.json.
