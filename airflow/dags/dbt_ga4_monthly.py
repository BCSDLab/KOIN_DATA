"""태그로 선택한 Silver 모델을 전체 이력으로 재생성하는 월간 dbt 파이프라인.

월간 실행은 ``airflow_monthly`` 태그가 있는 모델만 선택하고 dbt의
``--full-refresh``를 사용한다. 처리 시작일은 서버의
``KOIN_DATA_GA4_HISTORY_START_DATE`` 환경변수로 지정한다.

수동 실행에서는 다음과 같이 날짜 범위를 명시적으로 재정의할 수 있다.

    {"start_date": "YYYYMMDD", "end_date": "YYYYMMDD"}
"""

from __future__ import annotations

import os
import re
from datetime import timedelta
from typing import Any

import pendulum
from airflow.providers.standard.operators.python import PythonOperator
from cosmos import DbtDag, ExecutionConfig, ProfileConfig, ProjectConfig, RenderConfig
from cosmos.constants import InvocationMode, TestBehavior

DATE_PATTERN = re.compile(r"^\d{8}$")

DBT_PROJECT_DIR = "/opt/airflow/dbt"
DBT_EXECUTABLE = "/home/airflow/dbt-venv/bin/dbt"
DBT_TARGET = os.getenv("DBT_TARGET", "dev")
HISTORY_START_DATE = os.getenv("KOIN_DATA_GA4_HISTORY_START_DATE", "")

profile_config = ProfileConfig(
    profile_name="koin_data",
    target_name=DBT_TARGET,
    profiles_yml_filepath=f"{DBT_PROJECT_DIR}/profiles.yml",
)

project_config = ProjectConfig(
    dbt_project_path=DBT_PROJECT_DIR,
    install_dbt_deps=False,
)

execution_config = ExecutionConfig(
    dbt_executable_path=DBT_EXECUTABLE,
    invocation_mode=InvocationMode.SUBPROCESS,
)

render_config = RenderConfig(
    select=["tag:airflow_monthly"],
    test_behavior=TestBehavior.AFTER_EACH,
    dbt_executable_path=DBT_EXECUTABLE,
    invocation_mode=InvocationMode.SUBPROCESS,
)

# Airflow 3의 cron DAG에서 data_interval_start는 실행 시각이다. 매월 1일
# 정오 실행 시 전날(전월 말)까지 적재해, 당일 미확정 GA4 Export를 제외한다.
MONTHLY_DATE_VARS = {
    "start_date": (
        "{% set conf = dag_run.conf or {} %}"
        "{% if conf.get('start_date') or conf.get('end_date') %}"
        "{{ conf.get('start_date', '') }}"
        "{% else %}"
        + HISTORY_START_DATE
        + "{% endif %}"
    ),
    "end_date": (
        "{% set conf = dag_run.conf or {} %}"
        "{% if conf.get('start_date') or conf.get('end_date') %}"
        "{{ conf.get('end_date', '') }}"
        "{% else %}"
        "{{ (data_interval_start - macros.timedelta(days=1)) | ds_nodash }}"
        "{% endif %}"
    ),
}


def validate_monthly_dates(dag_run: Any = None, **_: Any) -> None:
    """수동 범위 또는 월간 전체 이력 시작일 설정을 실행 전에 검증한다."""
    conf = (dag_run.conf if dag_run else None) or {}
    start_date, end_date = conf.get("start_date"), conf.get("end_date")

    if not start_date and not end_date:
        if not DATE_PATTERN.match(HISTORY_START_DATE):
            raise ValueError(
                "스케줄 월간 실행에는 KOIN_DATA_GA4_HISTORY_START_DATE를 "
                "YYYYMMDD 형식으로 설정해야 합니다."
            )
        return

    if not (start_date and end_date):
        raise ValueError(
            "start_date와 end_date는 반드시 함께 지정해야 합니다. "
            f"받은 conf: {conf!r}"
        )

    for key, value in (("start_date", start_date), ("end_date", end_date)):
        if not DATE_PATTERN.match(str(value)):
            raise ValueError(
                f"{key}는 숫자 8자리(YYYYMMDD)여야 합니다. 받은 값: {value!r}"
            )

    if str(start_date) > str(end_date):
        raise ValueError(
            f"start_date({start_date})가 end_date({end_date})보다 늦을 수 없습니다."
        )


dbt_ga4_monthly = DbtDag(
    dag_id="dbt_ga4_monthly",
    project_config=project_config,
    profile_config=profile_config,
    execution_config=execution_config,
    render_config=render_config,
    operator_args={
        "vars": MONTHLY_DATE_VARS,
        "full_refresh": True,
    },
    # 일별 09:00 KST 실행과 겹치지 않도록 매월 1일 12:00 KST에 실행한다.
    schedule="0 12 1 * *",
    start_date=pendulum.datetime(2026, 8, 1, tz="Asia/Seoul"),
    catchup=False,
    max_active_runs=1,
    default_args={
        "retries": 1,
        "retry_delay": timedelta(minutes=10),
    },
    tags=["dbt", "ga4", "silver", "monthly"],
    doc_md=__doc__,
)


_dbt_root_tasks = list(dbt_ga4_monthly.roots)

with dbt_ga4_monthly:
    validate_dates = PythonOperator(
        task_id="validate_dates",
        python_callable=validate_monthly_dates,
    )
    for _root in _dbt_root_tasks:
        validate_dates >> _root
