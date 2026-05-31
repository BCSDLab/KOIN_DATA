# KOIN_DATA - Airflow DAG 관리

KOIN 서비스의 데이터 파이프라인을 위한 Apache Airflow DAG 코드 저장소

---

## 📁 폴더 구조

```
KOIN_DATA/
└── airflow/
    ├── dags/
    │   └── koin/
    │       ├── archive_dag/     # 더 이상 사용하지 않는 DAG 파일 보관
    │       ├── archive_query/   # 더 이상 사용하지 않는 쿼리 파일 보관
    │       ├── query/           # 현재 DAG에서 사용 중인 SQL 쿼리 파일
    │       └── *.py             # 실행 중인 DAG 파일
    └── sensors/                 # Airflow Sensor DAG 파일
```


