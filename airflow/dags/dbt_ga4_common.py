"""GA4 dbt 스케줄 DAG가 공유하는 설정과 날짜 검증 함수."""

from __future__ import annotations

import os
import re
from typing import Any

from airflow.providers.standard.operators.python import PythonOperator
from cosmos import ExecutionConfig, ProfileConfig, ProjectConfig, RenderConfig
from cosmos.constants import InvocationMode, TestBehavior

DATE_PATTERN = re.compile(r"^\d{8}$")

DBT_PROJECT_DIR = "/opt/airflow/dbt"

# Airflow 본체와 라이브러리를 섞지 않기 위해 dbt는 별도 venv에 격리해 두었다.
DBT_EXECUTABLE = "/home/airflow/dbt-venv/bin/dbt"

# 출력 대상은 DBT_TARGET 환경변수가 정한다. 로컬은 dev(stage), 서버는 prod.
DBT_TARGET = os.getenv("DBT_TARGET", "dev")


def create_profile_config() -> ProfileConfig:
    return ProfileConfig(
        profile_name="koin_data",
        target_name=DBT_TARGET,
        profiles_yml_filepath=f"{DBT_PROJECT_DIR}/profiles.yml",
    )


def create_project_config() -> ProjectConfig:
    return ProjectConfig(
        dbt_project_path=DBT_PROJECT_DIR,
        # packages.yml이 없고 컨테이너에 git도 없으므로 dbt deps를 건너뛴다.
        install_dbt_deps=False,
    )


def create_execution_config() -> ExecutionConfig:
    return ExecutionConfig(
        dbt_executable_path=DBT_EXECUTABLE,
        # 기본값 DBT_RUNNER는 dbt를 라이브러리로 import해 같은 프로세스에서 돌린다.
        # 격리 venv를 쓰므로 별도 프로세스로 실행한다.
        invocation_mode=InvocationMode.SUBPROCESS,
    )


def create_render_config(model_tag: str) -> RenderConfig:
    """지정 태그 모델과 그 테스트만 Cosmos task로 렌더링한다."""
    return RenderConfig(
        # 모델 실행 직후 해당 모델의 test를 돌린다. dbt build와 같은 흐름.
        test_behavior=TestBehavior.AFTER_EACH,
        dbt_executable_path=DBT_EXECUTABLE,
        # DAG 파싱 시점의 dbt ls도 별도 프로세스에서 돌린다.
        invocation_mode=InvocationMode.SUBPROCESS,
        select=[f"tag:{model_tag}"],
    )


def create_date_vars(lookback_days: int) -> dict[str, str]:
    """실행일 기준 확정된 최근 날짜 구간을 dbt vars로 전달한다."""
    if lookback_days < 1:
        raise ValueError("lookback_days는 1 이상이어야 합니다.")

    # GA4 확정 export는 전날까지만 존재하므로 오늘은 처리하지 않는다.
    # Airflow 3의 cron DAG에서 data_interval_start는 실행 시각이므로, 어제를
    # 얻기 위해 직접 하루를 뺀다.
    offset_days = 1

    # conf에 날짜가 하나라도 있으면 두 값 모두 conf에서만 읽는다. 한쪽만 넣었을
    # 때 나머지를 자동값으로 채우면 의도하지 않은 대범위 스캔이 생길 수 있다.
    return {
        "start_date": (
            "{% set conf = dag_run.conf or {} %}"
            "{% if conf.get('start_date') or conf.get('end_date') %}"
            "{{ conf.get('start_date', '') }}"
            "{% else %}"
            "{{ (data_interval_start - macros.timedelta(days="
            + str(offset_days + lookback_days - 1)
            + ")) | ds_nodash }}"
            "{% endif %}"
        ),
        "end_date": (
            "{% set conf = dag_run.conf or {} %}"
            "{% if conf.get('start_date') or conf.get('end_date') %}"
            "{{ conf.get('end_date', '') }}"
            "{% else %}"
            "{{ (data_interval_start - macros.timedelta(days="
            + str(offset_days)
            + ")) | ds_nodash }}"
            "{% endif %}"
        ),
    }


def validate_conf_dates(dag_run: Any = None, **_: Any) -> None:
    """수동 실행 날짜를 dbt에 전달하기 전에 형식과 순서를 검증한다."""
    conf = (dag_run.conf if dag_run else None) or {}
    start_date, end_date = conf.get("start_date"), conf.get("end_date")

    if not start_date and not end_date:
        return  # 스케줄 실행. 날짜는 Airflow가 계산한다.

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


def create_date_validation_task() -> PythonOperator:
    """각 DAG의 dbt root task 앞에 둘 날짜 검증 task를 만든다."""
    return PythonOperator(
        task_id="validate_dates",
        python_callable=validate_conf_dates,
    )
