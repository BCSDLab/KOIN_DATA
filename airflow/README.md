# Airflow

GA4 → BigQuery 데이터 파이프라인을 오케스트레이션한다.
dbt 모델 실행은 [Cosmos](https://astronomer.github.io/astronomer-cosmos/)가 담당한다.

## 폴더 구조

```
airflow/
├── dags/            # DAG 파일 (평평하게 둔다)
│   ├── dbt_ga4_common.py
│   ├── dbt_ga4_daily.py
│   ├── dbt_ga4_monthly.py
│   ├── dbt_ga4_monthly_dates.py
│   └── dbt_ga4_silver_selection.py
├── plugins/         # Airflow 플러그인
└── logs/            # 런타임 산출물, Git에 커밋하지 않는다
```

DAG가 10개를 넘어가면 그때 그룹핑을 검토한다. Airflow는 `dags/` 아래를 재귀적으로
탐색하고 DAG의 정체성은 파일 경로가 아니라 `dag_id`이므로, 나중에 폴더로 옮겨도
실행 이력은 유지된다.

## 네이밍 컨벤션

### DAG

```
{action}_{domain}_{schedule}     예) dbt_ga4_daily
```

| 요소 | 값 |
| --- | --- |
| action | `dbt` / `ingest` / `dq` / `refresh` |
| domain | 데이터 도메인 (`ga4`, `userdb` 등) |
| schedule | `daily` / `hourly` 등 |

- 레이어(silver/gold)는 **DAG 이름이 아니라 task 이름**에 드러낸다.
  한 DAG가 silver와 gold를 함께 만들 수 있기 때문이다.
- DAG를 나누는 기준은 **스케줄과 의존성**이다. 같은 주기로 돌고 `ref()`로 이어지면
  한 DAG에 두어 Cosmos가 순서를 그리게 하고, 무관하면 나눈다.

### Task

Cosmos가 dbt 모델 이름을 그대로 task 이름으로 쓴다 (`silver_events.run`,
`silver_events.test`). 별도로 만드는 task는 `{동사}_{대상}` 형태로 둔다
(`refresh_superset` 등).

## dbt 실행 구조

Airflow 컨테이너 안에서 세 조각이 맞물린다.

| 위치 | 내용 | 반영 방법 |
| --- | --- | --- |
| `/home/airflow/dbt-venv` | dbt 실행 파일 (격리 venv) | 이미지 빌드 |
| `/opt/airflow/dbt` | dbt 프로젝트 (`./dbt` 마운트) | 파일 수정 즉시 |
| `/opt/airflow/dags` | DAG (`./airflow/dags` 마운트) | 파일 수정 즉시 |

dbt는 Airflow 본체와 파이썬 라이브러리를 공유하지 않도록 별도 venv에 설치해
이미지에 굽는다. Cosmos는 이 venv의 dbt를 `InvocationMode.SUBPROCESS`로 호출한다.

## 날짜 처리

처리 날짜는 **항상 Airflow가 정하고** dbt에 `--vars`로 넘긴다.

| 실행 | 선택 태그 | 범위 |
| --- | --- | --- |
| daily (`dbt_ga4_daily`) | `airflow_daily` | `data_interval_start` 기준 최근 3일 |
| monthly (`dbt_ga4_monthly`) | `airflow_monthly` | 예정 실행일 30일 전 ~ 실제 실행일의 어제 |
| daily 수동 (Trigger DAG w/ config) | `airflow_daily` | conf로 넘긴 `start_date` ~ `end_date` |
| monthly 수동 | `airflow_monthly` | 현재 월 1일의 30일 전 ~ 실제 실행일의 어제. 날짜 직접 지정 금지 |

GA4는 확정 데이터를 며칠에 걸쳐 갱신하므로 daily는 최근 3일을 다시 만든다.
`silver_events_v2`는 Airflow의 `start_date` ~ `end_date`를 조회 범위와
`insert_overwrite`의 교체 파티션 목록(`partitions`)에 함께 사용한다. 양 끝 날짜를
포함한 파티션을 통째로 교체하므로, 결과가 0건인 날짜도 기존 데이터를 비우고
범위 밖 파티션은 유지한다. 세션 계산을 위해 추가로 읽는 전날은 교체 대상이 아니다.
원천 테이블 미도착으로 결과가 비어도 같은 방식으로 비워지므로, 지정 범위의 원천
준비 상태를 확인한 뒤 실행한다.

기존 `silver_events`는 동적 파티션 교체를 유지한다. 결과에 존재하는 날짜의
삭제·변경만 반영하며, 결과가 0건인 날짜의 기존 파티션은 비워지지 않는다.

monthly는 매월 1일 12시(KST), daily는 매일 09시(KST)에 예약된다.
두 DAG 모두 max_active_runs=1로 같은 DAG의 예약·수동 실행을 직렬화한다.
daily/monthly 사이의 임의 수동 실행까지 상호 배제하는 설정은 아니므로,
월별 보정 중 겹치는 daily 수동 실행은 피한다.
monthly의 `validate_dates`는 실행 시점에 날짜 범위를 확정하고 XCom으로 전달한다.
지연 실행에서는 시작일을 유지하고 종료일만 실제 실행일의 어제까지 확장한다.
예를 들어 9월 1일 예정 실행이 9월 5일에 시작되면 8월 2일~9월 4일을 처리하며,
원래 예정일이 아닌 **9월 5일 09시 daily**의 성공을 기다린다. 센서와 dbt 작업은
동일한 날짜 계획을 사용한다. 월간 실행은 `reconcile_window=true`를 함께 넘긴다.
이때 `silver__users`의 기존 행은
`first_seen_at`, `last_seen_at`, `gender`, `major`만 보정한다.

monthly의 conf에 `start_date` 또는 `end_date`가 있으면 빈 값이라도 실행을 거부한다.
과거 속성이 현재 값을 덮어쓰는 과거 기간 수동 보정을 막기 위해서다. 날짜 설정 없이
수동 실행하면 현재 월을 기준으로 위 규칙을 적용한다. 직접 dbt CLI 실행은 이 DAG의
검증을 거치지 않으므로 과거 구간에 `reconcile_window=true`를 사용하지 않는다.

날짜 계획 이후 KST 날짜가 바뀌면 센서와 dbt 템플릿 검증에서 실패한다. 며칠 뒤
재실행할 때는 **`validate_dates`부터 모든 downstream task를 함께 clear**하여
종료일을 다시 확장하고 해당 실행일의 daily 성공을 확인한다. 실패한 dbt task만
재실행해서는 날짜 계획이 갱신되지 않는다. 날짜를 넘겨 이미 실행 중인 쿼리나 별도
수동 daily 실행까지 이 센서가 상호 배제하는 것은 아니므로 중복 실행은 피한다.

전환 후보 모델의 최초 전체 적재는 daily DAG를 수동 실행하지 않고, 운영에서
`silver_events_v2`와 `silver__users`만 명시 선택해 별도로 수행한다. daily 태그에는
기존 `silver_events`도 포함된다. 전체 적재 날짜 범위는 반드시 명시하고 실행 전
비용을 확인한다.

### 전환 후보 모델의 최초 적재와 스케줄 활성화

`KOIN_DATA_SILVER_BOOTSTRAP_COMPLETE`는 기본값이 `false`다. 미설정이거나
`true`가 아니면 daily/monthly에서 `initial_load_required` 태그 모델을 제외한다.
대상은 dbt YAML의 태그로 관리하며, 현재는 `silver_events_v2`와
`silver__users`다. 두 모델의 테스트도 생성하지 않는다. 따라서 기존
daily의 `silver_events`는 계속 실행하지만, 후보 테이블이 최근 3일치만으로
생성되거나 `silver__users`의 최초 운영 적재 보호에 걸리는 상황은 막는다.
monthly는 이때 dbt 모델을 실행하지 않으므로 최초 적재 전에는 일시정지해 둔다.

1. 배포 환경의 설정을 `false`로 유지한 상태에서 코드를 배포한다.
2. 스케줄과 같은 출력 환경에서 두 후보 모델만 명시 선택해 전체 이력을 적재한다.
   날짜 범위와 `reconcile_window=false`를 명시한다. 이 설정은 DAG의 모델 선택만
   제어하므로 모델명을 지정하는 수동 dbt 실행은 가능하다.
3. 두 테이블의 전체 이력 적재 여부, 날짜 범위, 행 수와 dbt 테스트 결과를 확인한다.
   테이블이 존재하는 것만으로 적재 완료를 판단하지 않는다.
4. 해당 배포 환경의 `.env`에서 `KOIN_DATA_SILVER_BOOTSTRAP_COMPLETE=true`로
   변경하고 Airflow 서비스 컨테이너를 재생성해 환경변수를 반영한다. 단순 DAG
   재파싱이나 컨테이너 재시작만으로는 변경한 `.env`가 반영되지 않는다.
5. DAG 재파싱 후 daily에 세 모델, monthly에 두 후보 모델과 각각의 테스트가
   포함됐는지 확인하고 monthly를 활성화한다.

이 설정은 해당 출력 환경의 적재 완료를 운영자가 확인했다는 표시다. 출력 환경을
바꾸거나 후보 테이블을 다시 만들 때는 먼저 `false`로 되돌리고 위 절차를 반복한다.
최초 적재가 필요한 모델을 추가할 때도 먼저 설정을 `false`로 반영한 뒤 해당 모델에
`initial_load_required` 태그를 붙인다. 이 설정은 태그 모델 전체에 공통으로 적용된다.

### Stage에서 기존 Event 대신 V2 + User만 실행하기

`KOIN_DATA_SILVER_V2_ONLY`는 기본 false다. false일 때 위의 기존 동작을 그대로
유지한다. true이면 daily/monthly 모두 태그와 모델명의 교집합으로
`silver_events_v2`, `silver__users` 두 모델과 그 테스트만 선택한다.
기존 `silver_events`·Gold·합성 테스트는 선택하지 않는다. 기존 테이블을 삭제하거나
이름을 바꾸지는 않는다. 저장소의 dbt ref에서는 legacy Event 직접 의존을 찾지
못했지만, 외부 대시보드/직접 SQL 사용처까지 점검한 것은 아니다.

스케줄과 처리 기간은 기존과 같다.

| DAG | 실행 시각(KST) | 처리 범위 |
| --- | --- | --- |
| daily | 매일 09:00 | 전날까지 최근 3일, 수동 날짜 지정도 기존 방식 |
| monthly | 매월 1일 12:00 | 예정일 30일 전부터 실제 실행일의 어제, daily 성공 대기 유지 |

전환은 Stage(dev)에서만 허용한다. DAG 파싱과 첫 검증 task에서 출력 프로젝트,
GA4/앱 DB 원천, 최초 적재 완료 설정을 확인한다. 스케줄러/작업 컨테이너 설정이
달라 V2 옵션이 꺼지거나 원천이 운영으로 변경되면 검증 task가 실패하고 downstream을
실행하지 않는다. 모든 Airflow 서비스에는 같은 환경 설정을 배포해야 한다.

1. Stage daily/monthly를 일시정지하고 두 플래그를 false로 유지한다.
2. 두 모델의 기존 테이블·스키마·전체 이력·원천 도착/가입 스냅샷 최신성을 확인한다.
   이미 충분한 이력이 있으면 전체 재적재하지 않는다. 부족하면 원천의 실제 분석
   시작일부터 종료일까지 명시하고, 비용을 확인한 뒤 별도 dbt 최초 적재를 수행한다.
   기존 daily 수동 실행으로 전체 적재하면 legacy까지 실행되므로 사용하지 않는다.
3. 아래 설정을 Stage 환경에 적용한다. 데이터셋 이름은 실제 준비 상태를 확인한다.
   운영 기본 원천으로의 묵시적 fallback은 허용하지 않는다.

```dotenv
DBT_TARGET=dev
KOIN_DATA_GCP_PROJECT=koin-stage-438512
KOIN_DATA_BIGQUERY_LOCATION=asia-northeast3
KOIN_DATA_GA4_PROJECT=koin-stage-438512
KOIN_DATA_GA4_DATASET=analytics_427218788
KOIN_DATA_APP_DB_PROJECT=koin-stage-438512
KOIN_DATA_APP_DB_DATASET=analytics_427218788
# 아래 두 값은 최초 적재/입력 검증 후에만 true로 설정
KOIN_DATA_SILVER_BOOTSTRAP_COMPLETE=true
KOIN_DATA_SILVER_V2_ONLY=true
```

4. Stage Airflow 컨테이너를 재생성하고 DAG 재파싱 결과를 확인한다. 두 DAG의
   dbt 모델 task가 V2/User 두 개뿐인지 확인하고, 먼저 작은 날짜 범위의 daily를
   수동 실행한다. monthly에는 수동 날짜를 넣지 않는다.
5. 날짜 범위·행 수·원천 최신성·재실행 결과와 각 모델 테스트가 통과한 후 스케줄을
   활성화한다. 기존 스케줄의 주기나 최근 3일 범위를 변경하지 않는다.

선택 재현(모델/테스트 목록 조회이며 적재 없음):

```bash
dbt ls --project-dir dbt --profiles-dir dbt --target dev --resource-type model \
  --select tag:airflow_daily,silver_events_v2 tag:airflow_daily,silver__users
dbt ls --project-dir dbt --profiles-dir dbt --target dev --resource-type test \
  --select tag:airflow_monthly,silver_events_v2 tag:airflow_monthly,silver__users
```

V2 전환과 새 로깅 분류 활성화는 서로 다른 설정이다. 이번 전환 옵션은 새 로깅
적용 기간/플랫폼을 인증하거나 `silver_logging_v1_enabled`를 켜지 않는다.
가입·메인·수집 완전성 등의 Gold 공개 플래그도 변경하지 않는다. Silver 모델별
테스트는 AFTER_EACH 정책이며, 두 Silver 쓰기 전체를 하나의 트랜잭션으로 묶지는
않는다. 향후 Gold는 두 Silver의 갱신·검사가 모두 성공한 뒤 고정 Snapshot으로
계산해야 한다. 이번 변경은 Gold DAG 실행이나 공개 연결을 추가하지 않는다.

운영에서는 V2_ONLY=false를 유지한다. Stage 실패 시 DAG를 멈추고 원인을 확인한다.
V2_ONLY=false로 복귀하면 legacy 선택 정책으로 돌아가지만, 기존 정책에서 bootstrap이
true이면 daily는 세 모델을 선택한다는 점에 주의한다. 완전히 예전 스케줄로 복귀할
경우 두 플래그를 false로 되돌린 뒤 컨테이너 재생성·재파싱으로 선택을 확인한다.

날짜 범위 지정 예시:

```json
{"start_date": "20240711", "end_date": "20260725"}
```

## 접속

| 환경 | 주소 |
| --- | --- |
| 로컬 | `https://airflow.localhost` |
| 서버 | `https://airflow.bcsdlab.com` |

`http://localhost:8080` 직통은 인증 토큰이 실리지 않아 로그인이 반복된다.
반드시 https(Caddy)로 접속한다.
