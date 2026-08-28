"""GA4 이벤트를 silver 레이어로 적재하는 일일 dbt 파이프라인.

Cosmos가 dbt 프로젝트를 읽어 모델 하나하나를 Airflow task로 변환한다.
모델 간 ref() 의존성이 곧 task 순서가 되고, 각 모델의 dbt test는
해당 모델 바로 뒤에 붙는다(TestBehavior.AFTER_EACH).

구성 요소가 컨테이너 안 세 곳에 나뉘어 있다.
  - dbt 실행 파일: /home/airflow/dbt-venv/bin/dbt  (이미지에 구운 격리 venv)
  - dbt 프로젝트 : /opt/airflow/dbt                 (호스트 ./dbt 마운트)
  - 이 DAG       : /opt/airflow/dags                (호스트 ./airflow/dags 마운트)
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

# Airflow 본체와 라이브러리를 섞지 않기 위해 dbt는 별도 venv에 격리해 두었다.
# Cosmos 실행 모드는 LOCAL이지만, 실행 파일이 이 venv를 가리키므로 의존성은 분리된다.
# (Cosmos의 VIRTUALENV 모드와 달리 런타임 설치가 없어 빠르고 재현 가능하다.)
DBT_EXECUTABLE = "/home/airflow/dbt-venv/bin/dbt"

# 출력 대상은 DBT_TARGET 환경변수가 정한다. 로컬은 dev(stage), 서버는 prod.
DBT_TARGET = os.getenv("DBT_TARGET", "dev")

profile_config = ProfileConfig(
    profile_name="koin_data",
    target_name=DBT_TARGET,
    profiles_yml_filepath=f"{DBT_PROJECT_DIR}/profiles.yml",
)

project_config = ProjectConfig(
    dbt_project_path=DBT_PROJECT_DIR,
    # packages.yml이 없고 컨테이너에 git도 없으므로 dbt deps를 건너뛴다.
    install_dbt_deps=False,
)

execution_config = ExecutionConfig(
    dbt_executable_path=DBT_EXECUTABLE,
    # 기본값 DBT_RUNNER는 dbt를 라이브러리로 import해 같은 프로세스에서 돌리므로
    # Airflow 본체에 dbt가 설치돼 있어야 한다. 격리 venv를 쓰려면 별도 프로세스로 실행한다.
    invocation_mode=InvocationMode.SUBPROCESS,
)

render_config = RenderConfig(
    # 태그가 없는 검증·전환 중 모델은 일별 운영 DAG에 자동으로 추가하지 않는다.
    select=["tag:airflow_daily"],
    # 모델 실행 직후 해당 모델의 test를 돌린다. dbt build와 같은 흐름.
    test_behavior=TestBehavior.AFTER_EACH,
    dbt_executable_path=DBT_EXECUTABLE,
    # DAG 파싱 시점의 dbt ls도 같은 이유로 별도 프로세스에서 돌린다.
    invocation_mode=InvocationMode.SUBPROCESS,
)

# GA4는 확정 데이터를 최근 며칠에 걸쳐 갱신하므로 매 실행 3일치를 다시 만든다.
# insert_overwrite라 파티션이 통째로 교체되어 삭제·변경까지 반영된다.
LOOKBACK_DAYS = 3

# GA4 확정 export는 전날까지만 존재하므로 오늘은 처리하지 않는다.
#
# 주의: Airflow 3에서 cron 문자열은 CronTriggerTimetable을 쓰며,
# data_interval_start는 "직전 구간의 시작"이 아니라 실행 시각 그 자체다
# (data_interval 길이가 0). 따라서 어제를 얻으려면 직접 1일을 빼야 한다.
OFFSET_DAYS = 1

# 처리 날짜는 항상 Airflow가 정한다.
#   * 스케줄 실행: 실행일 기준 어제까지의 최근 LOOKBACK_DAYS일
#                 (7/26 09:00 실행 → 20260723 ~ 20260725)
#   * 수동 실행  : Trigger DAG w/ config로 넘긴 날짜를 그대로 사용
#       {"start_date": "20240711", "end_date": "20260725"}   ← 전체 적재도 이렇게
#
# conf에 날짜가 하나라도 있으면 두 값 모두 conf에서만 읽는다. 한쪽만 넣었을 때
# 나머지를 자동값으로 채우면 의도하지 않은 범위(예: 2년치)가 조용히 돌 수 있어,
# 빈 값을 그대로 넘겨 모델의 "둘 다 지정" 검증에서 실패하게 만든다.
#
# dag_run.conf는 스케줄 실행에서 None이므로 or {} 로 감싼다.
DATE_VARS = {
    "start_date": (
        "{% set conf = dag_run.conf or {} %}"
        "{% if conf.get('start_date') or conf.get('end_date') %}"
        "{{ conf.get('start_date', '') }}"
        "{% else %}"
        "{{ (data_interval_start - macros.timedelta(days="
        + str(OFFSET_DAYS + LOOKBACK_DAYS - 1)
        + ")) | ds_nodash }}"
        "{% endif %}"
    ),
    "end_date": (
        "{% set conf = dag_run.conf or {} %}"
        "{% if conf.get('start_date') or conf.get('end_date') %}"
        "{{ conf.get('end_date', '') }}"
        "{% else %}"
        "{{ (data_interval_start - macros.timedelta(days="
        + str(OFFSET_DAYS)
        + ")) | ds_nodash }}"
        "{% endif %}"
    ),
}


def validate_conf_dates(dag_run: Any = None, **_: Any) -> None:
    """수동 실행으로 넘어온 날짜를 dbt에 전달하기 전에 검증한다.

    두 값은 모델에서 SQL 리터럴로 삽입되므로 형식이 어긋나면 여기서 끊는다.
    모델도 같은 검증을 하지만(CLI로 직접 실행하는 경로가 있으므로),
    DAG에서 먼저 막아 잘못된 범위로 BigQuery를 스캔하지 않게 한다.
    """
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

dbt_ga4_daily = DbtDag(
    dag_id="dbt_ga4_daily",
    project_config=project_config,
    profile_config=profile_config,
    execution_config=execution_config,
    render_config=render_config,
    operator_args={"vars": DATE_VARS},
    # 전날 데이터를 KST 오전에 처리한다. GA4 확정 export가 도착할 시간을 준다.
    schedule="0 9 * * *",
    start_date=pendulum.datetime(2026, 7, 25, tz="Asia/Seoul"),
    catchup=False,
    default_args={
        "retries": 1,
        "retry_delay": timedelta(minutes=5),
    },
    tags=["dbt", "ga4", "silver"],
    doc_md=__doc__,
)

# Cosmos가 만든 dbt task들 앞에 날짜 검증을 세운다.
# roots는 검증 task를 추가하기 전에 잡아둔다.
_dbt_root_tasks = list(dbt_ga4_daily.roots)

with dbt_ga4_daily:
    validate_dates = PythonOperator(
        task_id="validate_dates",
        python_callable=validate_conf_dates,
    )
    for _root in _dbt_root_tasks:
        validate_dates >> _root
