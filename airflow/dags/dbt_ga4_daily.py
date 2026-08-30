"""GA4 Silver 모델을 일별 증분 처리하는 dbt 파이프라인.

`airflow_daily` 태그 모델만 Cosmos task로 렌더링한다. 현재는 기존
silver_events와 전환 후보인 silver_events_v2, silver__users를 함께 실행한다.
"""

from __future__ import annotations

from datetime import timedelta

import pendulum
from cosmos import DbtDag
from dbt_ga4_common import (
    create_date_validation_task,
    create_date_vars,
    create_execution_config,
    create_profile_config,
    create_project_config,
    create_render_config,
)

# GA4는 확정 데이터를 최근 며칠에 걸쳐 갱신하므로 매 실행 3일치를 다시 만든다.
# insert_overwrite라 파티션이 통째로 교체되어 삭제·변경까지 반영된다.
DAILY_LOOKBACK_DAYS = 3

dbt_ga4_daily = DbtDag(
    dag_id="dbt_ga4_daily",
    project_config=create_project_config(),
    profile_config=create_profile_config(),
    execution_config=create_execution_config(),
    render_config=create_render_config("airflow_daily"),
    operator_args={"vars": create_date_vars(DAILY_LOOKBACK_DAYS)},
    # 전날 데이터를 KST 오전에 처리한다. GA4 확정 export가 도착할 시간을 준다.
    schedule="0 9 * * *",
    start_date=pendulum.datetime(2026, 7, 25, tz="Asia/Seoul"),
    catchup=False,
    default_args={
        "retries": 1,
        "retry_delay": timedelta(minutes=5),
    },
    tags=["dbt", "ga4", "silver", "daily"],
    doc_md=__doc__,
)

# Cosmos가 만든 dbt task들 앞에 날짜 검증을 세운다.
_dbt_root_tasks = list(dbt_ga4_daily.roots)

with dbt_ga4_daily:
    validate_dates = create_date_validation_task()
    for _root in _dbt_root_tasks:
        validate_dates >> _root
