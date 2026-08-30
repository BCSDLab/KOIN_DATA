"""GA4 Silver 모델의 최근 30일 월간 보정 dbt 파이프라인.

`airflow_monthly` 태그 모델만 실행한다. silver_events_v2는 최근 30일
파티션을 다시 만들고, silver__users는 reconcile_window=true로 실행해 기존
사용자의 first_seen_at, last_seen_at, gender, major만 보정한다.
"""

from __future__ import annotations

from datetime import timedelta
from typing import Any

import pendulum
from airflow.providers.standard.sensors.external_task import ExternalTaskSensor
from cosmos import DbtDag
from dbt_ga4_common import (
    create_date_validation_task,
    create_date_vars,
    create_execution_config,
    create_profile_config,
    create_project_config,
    create_render_config,
)

MONTHLY_LOOKBACK_DAYS = 30
DAILY_SCHEDULE_HOUR = 9


def same_day_daily_logical_date(
    logical_date: pendulum.DateTime, **_: Any
) -> pendulum.DateTime:
    """월간 실행일과 같은 날짜의 09시 daily DAG logical date를 반환한다."""
    return logical_date.replace(
        hour=DAILY_SCHEDULE_HOUR,
        minute=0,
        second=0,
        microsecond=0,
    )


dbt_ga4_monthly = DbtDag(
    dag_id="dbt_ga4_monthly",
    project_config=create_project_config(),
    profile_config=create_profile_config(),
    execution_config=create_execution_config(),
    render_config=create_render_config("airflow_monthly"),
    operator_args={
        "vars": {
            **create_date_vars(MONTHLY_LOOKBACK_DAYS),
            "reconcile_window": True,
        }
    },
    # monthly는 같은 날 09시 daily가 성공한 뒤에 시작한다.
    schedule="0 12 1 * *",
    start_date=pendulum.datetime(2026, 9, 1, tz="Asia/Seoul"),
    catchup=False,
    default_args={
        "retries": 1,
        "retry_delay": timedelta(minutes=5),
    },
    tags=["dbt", "ga4", "silver", "monthly"],
    doc_md=__doc__,
)

# 월간과 일간이 같은 파티션/사용자 행을 동시에 쓰지 않게 일간 성공을 기다린다.
_dbt_root_tasks = list(dbt_ga4_monthly.roots)

with dbt_ga4_monthly:
    wait_for_daily = ExternalTaskSensor(
        task_id="wait_for_daily",
        external_dag_id="dbt_ga4_daily",
        external_task_id=None,
        execution_date_fn=same_day_daily_logical_date,
        allowed_states=["success"],
        failed_states=["failed"],
        check_existence=True,
        mode="reschedule",
        poke_interval=60,
        timeout=6 * 60 * 60,
    )
    validate_dates = create_date_validation_task()
    validate_dates >> wait_for_daily
    for _root in _dbt_root_tasks:
        wait_for_daily >> _root
