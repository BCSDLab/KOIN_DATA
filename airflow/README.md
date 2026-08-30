# Airflow

GA4 → BigQuery 데이터 파이프라인을 오케스트레이션한다.
dbt 모델 실행은 [Cosmos](https://astronomer.github.io/astronomer-cosmos/)가 담당한다.

## 폴더 구조

```
airflow/
├── dags/            # DAG 파일 (평평하게 둔다)
│   ├── dbt_ga4_common.py
│   ├── dbt_ga4_daily.py
│   └── dbt_ga4_monthly.py
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
| monthly (`dbt_ga4_monthly`) | `airflow_monthly` | 매월 1일, 전날까지 최근 30일 |
| 수동 (Trigger DAG w/ config) | 해당 DAG의 태그 | conf로 넘긴 `start_date` ~ `end_date` |

GA4는 확정 데이터를 며칠에 걸쳐 갱신하므로 daily는 최근 3일을 다시 만든다.
모델이 `insert_overwrite`라 파티션이 통째로 교체되어 추가뿐 아니라 삭제·변경도 반영된다.

monthly는 1일 12시(KST)에 시작하며, 같은 날 09시 daily DAG의 성공을 먼저 확인한다.
따라서 두 DAG가 같은 파티션이나 사용자 행을 동시에 쓰지 않는다. 월간 실행은
`reconcile_window=true`를 함께 넘긴다. 이때 `silver__users`의 기존 행은
`first_seen_at`, `last_seen_at`, `gender`, `major`만 보정한다.

전환 후보 모델의 최초 전체 적재는 daily DAG를 수동 실행하지 않고, 운영에서
`silver_events_v2`와 `silver__users`만 명시 선택해 별도로 수행한다. daily 태그에는
기존 `silver_events`도 포함되므로, 최초 적재를 위해 기존 테이블까지 다시 쓰지 않기
위해서다. 전체 적재 날짜 범위는 반드시 명시하고 실행 전 비용을 확인한다.

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
