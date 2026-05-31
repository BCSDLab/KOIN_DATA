# AGENTS.md

이 저장소는 KOIN GA4 데이터 플랫폼을 위한 monorepo입니다.

## 기본 규칙

- 로컬 절대경로는 커밋하지 않습니다.
- 코드, 설정 템플릿, 문서, dbt 모델, 스크립트만 Git으로 관리합니다.
- `.env`, secrets, 로그, dbt 생성물, 로컬 데이터는 커밋하지 않습니다.
- 스크립트와 설정에서는 가능한 한 상대경로를 사용합니다.
- 환경변수 prefix는 `KOIN_DATA_`를 사용합니다.
- 문서와 운영 메모는 기본적으로 한국어로 작성합니다.

## Docker

- 서버 실행 환경은 Ubuntu Server + Docker Engine + Docker Compose plugin을 기준으로 합니다.
- 서버에 Docker Desktop은 필요하지 않습니다.
- 서비스별 의존성이 커지면 컨테이너를 분리합니다.
- MVP 단계에서는 Airflow 컨테이너에서 dbt를 실행해도 됩니다.

## Airflow

- DAG는 `airflow/dags`에 둡니다.
- plugin은 `airflow/plugins`에 둡니다.
- 로그는 런타임 산출물이므로 Git에 커밋하지 않습니다.
- DAG는 BigQuery/dbt 작업을 오케스트레이션합니다.
- GA4 대량 데이터를 VM으로 내려받는 방식은 피합니다.

## dbt

- dbt 프로젝트 경로는 `dbt/koin`입니다.
- GA4 BigQuery Export 원본 테이블은 `models/sources`에 선언합니다.
- downstream 모델은 GA4 원본 export 테이블을 직접 조회하지 않습니다.
- 레이어 순서는 `sources` -> `staging` -> `bronze` -> `silver` -> `marts`입니다.
- Superset은 `marts`/gold 테이블만 조회하도록 구성합니다.

## Scripts

- 스크립트는 `scripts`에 둡니다.
- 스크립트는 가능하면 여러 번 실행해도 안전하게 작성합니다.
- 스크립트는 `.env` 기반으로 동작하게 합니다.
- 사용자 개인 경로를 하드코딩하지 않습니다.
