# 아키텍처

## 개요

```text
GA4
  -> Google Analytics BigQuery Export (Bronze, 손대지 않음)
  -> Airflow(Cosmos) + dbt on Docker Compose
  -> BigQuery silver/gold
  -> Superset dashboards
```

## 실행 환경

- 실행 환경은 AWS Lightsail의 Ubuntu Server를 기준으로 합니다.
- 서버에는 Docker Engine과 Docker Compose plugin만 설치합니다.
- 서버는 서비스 실행과 관리를 담당합니다.
- 대량 데이터 저장과 처리는 BigQuery가 담당합니다.
- BigQuery 접근은 환경에 따라 나눕니다.
  - 로컬(dev): 개발자 OAuth(gcloud ADC)로 stage 프로젝트에 접근
  - 서버(prod): 전용 service account 키로 운영 프로젝트에 접근
- service account 키는 `secrets/`에만 두고 Git에 올리지 않습니다.

## dbt 레이어

Medallion 3층 구조를 쓰되, Bronze는 GA4 Export를 그대로 사용하므로 직접 만들지 않습니다.

| 레이어 | 내용 | materialization |
| --- | --- | --- |
| `sources` | GA4 export 원본 테이블 선언 | - |
| `silver` | 정제 + 비즈니스 로직을 적용한 분석용 테이블 | 기본 view, 대용량은 incremental |
| `gold` | KPI/집계, 대시보드가 직접 조회 | table |

dbt 공식 권장 이름(`staging`/`intermediate`/`marts`) 대신 조직 용어에 맞춰
`silver`/`gold`를 폴더명과 데이터셋명에 함께 사용합니다.

## 환경 분리

| 환경 | 입력(GA4) | 출력 |
| --- | --- | --- |
| dev | stage 프로젝트 | stage 프로젝트 |
| prod | 운영 프로젝트 | 운영 프로젝트 |

입력은 `_ga4__sources.yml`(`KOIN_DATA_GA4_*`), 출력은 `profiles.yml`(`DBT_TARGET`,
`KOIN_DATA_GCP_PROJECT`)이 결정합니다. 둘 다 기본값은 stage이며, 운영은 환경변수로
명시할 때만 사용합니다.

## 오케스트레이션

Airflow가 dbt를 실행하며, dbt 모델은 Cosmos가 모델 단위 task로 변환합니다.
자세한 내용은 [airflow/README.md](../airflow/README.md)를 참고합니다.

## Superset

Superset은 BigQuery 비용과 대시보드 안정성을 위해 gold 테이블만 조회하도록 구성합니다.
