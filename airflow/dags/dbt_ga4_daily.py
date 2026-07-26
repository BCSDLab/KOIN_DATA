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
from datetime import timedelta

import pendulum
from cosmos import DbtDag, ExecutionConfig, ProfileConfig, ProjectConfig, RenderConfig
from cosmos.constants import InvocationMode, TestBehavior

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
    # 모델 실행 직후 해당 모델의 test를 돌린다. dbt build와 같은 흐름.
    test_behavior=TestBehavior.AFTER_EACH,
    dbt_executable_path=DBT_EXECUTABLE,
    # DAG 파싱 시점의 dbt ls도 같은 이유로 별도 프로세스에서 돌린다.
    invocation_mode=InvocationMode.SUBPROCESS,
)

# GA4는 확정 데이터를 최근 며칠에 걸쳐 갱신하므로 매 실행 3일치를 다시 만든다.
# insert_overwrite라 파티션이 통째로 교체되어 삭제·변경까지 반영된다.
LOOKBACK_DAYS = 3

# 처리 날짜는 항상 Airflow가 정한다.
#   * 스케줄 실행: 담당 구간(data_interval_start) 기준 최근 LOOKBACK_DAYS일
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
        "{{ (data_interval_start - macros.timedelta(days=" + str(LOOKBACK_DAYS) + "))"
        " | ds_nodash }}"
        "{% endif %}"
    ),
    "end_date": (
        "{% set conf = dag_run.conf or {} %}"
        "{% if conf.get('start_date') or conf.get('end_date') %}"
        "{{ conf.get('end_date', '') }}"
        "{% else %}"
        "{{ data_interval_start | ds_nodash }}"
        "{% endif %}"
    ),
}

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
