FROM apache/airflow:3.0.1-python3.11

COPY docker/airflow/requirements.txt /requirements.txt
RUN pip install --no-cache-dir \
    --constraint "https://raw.githubusercontent.com/apache/airflow/constraints-3.0.1/constraints-3.11.txt" \
    -r /requirements.txt
