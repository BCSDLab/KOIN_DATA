FROM apache/airflow:3.0.1-python3.11

COPY docker/airflow/requirements.txt /requirements.txt
RUN pip install --no-cache-dir \
    --constraint "https://raw.githubusercontent.com/apache/airflow/constraints-3.0.1/constraints-3.11.txt" \
    -r /requirements.txt

# dbt 전용 격리 venv(옆방)를 이미지에 미리 구워둠.
# Airflow 본체와 파이썬 라이브러리가 섞이지 않게 분리 + 런타임 설치 없이 재현성 확보.
# airflow 사용자 소유 경로(/home/airflow)에 둬야 권한 문제가 없다.
# Cosmos가 이 venv의 dbt(/home/airflow/dbt-venv/bin/dbt)를 실행하도록 DAG에서 지정한다.
RUN python -m venv /home/airflow/dbt-venv && \
    /home/airflow/dbt-venv/bin/pip install --no-cache-dir dbt-bigquery~=1.9.0
