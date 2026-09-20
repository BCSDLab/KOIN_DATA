"""GA4 Silver 모델의 월간 보정 dbt 파이프라인.

`airflow_monthly` 태그 모델만 실행한다. 예정 실행일 기준 30일 전부터 실제
실행일의 어제까지 처리한다. silver__users는 reconcile_window=true로 실행해 기존
사용자의 first_seen_at, last_seen_at, gender, major만 보정한다.
최초 적재 완료 설정을 켜기 전에는 두 후보의 dbt task를 만들지 않는다.
"""

from __future__ import annotations

from datetime import timedelta

import pendulum
from airflow.providers.standard.operators.python import PythonOperator
from airflow.providers.standard.sensors.external_task import ExternalTaskSensor
from cosmos import DbtDag
from dbt_ga4_common import (
    SCHEDULE_TIMEZONE,
    create_cron_schedule,
    create_execution_config,
    create_profile_config,
    create_project_config,
    create_render_config,
)
from dbt_ga4_monthly_dates import (
    monthly_daily_logical_date,
    monthly_date_var,
    prepare_monthly_window,
)


dbt_ga4_monthly = DbtDag(
    dag_id="dbt_ga4_monthly",
    project_config=create_project_config(),
    profile_config=create_profile_config(),
    execution_config=create_execution_config(),
    render_config=create_render_config("airflow_monthly"),
    operator_args={
        "vars": {
            "start_date": "{{ monthly_date_var(ti.xcom_pull(task_ids='validate_dates'), 'start_date') }}",
            "end_date": "{{ monthly_date_var(ti.xcom_pull(task_ids='validate_dates'), 'end_date') }}",
            "reconcile_window": True,
        }
    },
    user_defined_macros={"monthly_date_var": monthly_date_var},
    # 지연 실행도 실제 실행일의 09시 daily 성공을 확인한다.
    schedule=create_cron_schedule("0 12 1 * *"),
    start_date=pendulum.datetime(2026, 9, 1, tz=SCHEDULE_TIMEZONE),
    catchup=False,
    max_active_runs=1,
    default_args={
        "retries": 1,
        "retry_delay": timedelta(minutes=5),
    },
    tags=["dbt", "ga4", "silver", "monthly"],
    doc_md=__doc__,
)

# 날짜 계획에 해당하는 일간 실행이 끝난 뒤 월간 보정을 시작한다.
_dbt_root_tasks = list(dbt_ga4_monthly.roots)

with dbt_ga4_monthly:
    wait_for_daily = ExternalTaskSensor(
        task_id="wait_for_daily",
        external_dag_id="dbt_ga4_daily",
        external_task_id=None,
        execution_date_fn=monthly_daily_logical_date,
        allowed_states=["success"],
        failed_states=["failed"],
        check_existence=True,
        mode="reschedule",
        poke_interval=60,
        timeout=6 * 60 * 60,
    )
    validate_dates = PythonOperator(
        task_id="validate_dates",
        python_callable=prepare_monthly_window,
    )
    validate_dates >> wait_for_daily
    for _root in _dbt_root_tasks:
        wait_for_daily >> _root
