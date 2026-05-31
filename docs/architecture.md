# 아키텍처

## 개요

```text
GA4
  -> Google Analytics BigQuery Export
  -> BigQuery raw_ga4
  -> Airflow/dbt on Docker Compose
  -> BigQuery bronze/silver/gold
  -> Superset dashboards
```

## 실행 환경

- 우선 실행 환경은 GCP Compute Engine의 Ubuntu Server VM을 기준으로 합니다.
- 서버에는 Docker Engine과 Docker Compose plugin만 설치합니다.
- VM은 서비스 실행과 관리를 담당합니다.
- 대량 데이터 저장과 처리는 BigQuery가 담당합니다.
- Compute Engine에서는 service account를 붙여 BigQuery에 접근하는 방식을 우선 고려합니다.
- 가능하면 service account JSON key 파일을 서버에 두지 않습니다.

## dbt 레이어

- `sources`: GA4 export 원본 테이블 선언
- `staging`: 컬럼명 정리와 타입 캐스팅
- `bronze`: 프로젝트가 관리하는 canonical schema
- `silver`: 분석용 entity 테이블
- `marts`: Superset이 조회하는 gold 테이블

## Superset

Superset은 BigQuery 비용과 대시보드 안정성을 위해 `marts`/gold 테이블만 조회하도록 구성합니다.
