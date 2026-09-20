"""월간 보정의 실행 날짜와 daily 대기 날짜를 한 번에 결정한다."""

from datetime import datetime, timedelta
from typing import Any
from zoneinfo import ZoneInfo

KST = ZoneInfo("Asia/Seoul")
MONTHLY_LOOKBACK_DAYS = 30
DAILY_SCHEDULE_HOUR = 9


def execution_day():
    return datetime.now(KST).date()


def prepare_monthly_window(
    dag_run: Any = None, data_interval_start: datetime | None = None, **_: Any
) -> dict[str, str]:
    """예정 시작일을 유지하고 종료일을 실제 실행일의 어제까지 확장한다."""
    conf = (dag_run.conf if dag_run else None) or {}
    if "start_date" in conf or "end_date" in conf:
        raise ValueError(
            "monthly는 start_date/end_date 수동 지정을 허용하지 않습니다. "
            "날짜 설정 없이 실행하거나 기존 실행의 validate_dates부터 downstream까지 다시 실행하세요."
        )

    today = execution_day()
    run_type = getattr(dag_run, "run_type", None)
    run_type = getattr(run_type, "value", run_type)
    if run_type == "manual":
        # 수동 실행은 현재 월의 월간 보정만 허용한다.
        scheduled_day = today.replace(day=1)
    elif data_interval_start is not None:
        if data_interval_start.tzinfo is None:
            raise ValueError("monthly 기준 시각에는 시간대가 필요합니다.")
        scheduled_day = data_interval_start.astimezone(KST).date()
    else:
        raise ValueError("monthly의 예정 실행 시각을 확인할 수 없습니다.")

    if scheduled_day > today:
        raise ValueError("미래에 예정된 monthly 실행을 미리 처리할 수 없습니다.")

    return {
        "start_date": (scheduled_day - timedelta(days=MONTHLY_LOOKBACK_DAYS)).strftime("%Y%m%d"),
        "end_date": (today - timedelta(days=1)).strftime("%Y%m%d"),
        "execution_day": today.isoformat(),
    }


def monthly_date_var(window: dict[str, str] | None, key: str) -> str:
    """날짜가 바뀐 부분 재시도로 오래된 보정 범위를 다시 쓰지 않게 한다."""
    if not window or window.get("execution_day") != execution_day().isoformat():
        raise ValueError(
            "monthly 날짜 계획이 없거나 실행일이 변경됐습니다. "
            "validate_dates와 모든 downstream task를 함께 다시 실행하여 "
            "처리 종료일을 확장하고 해당 날짜 daily 성공을 다시 확인하세요."
        )
    return window[key]


def monthly_daily_logical_date(
    logical_date: datetime | None, ti: Any, **_: Any
) -> datetime:
    """처리 범위를 확정한 실제 실행일의 KST 09시 daily를 기다린다."""
    window = ti.xcom_pull(task_ids="validate_dates")
    monthly_date_var(window, "end_date")
    return datetime.fromisoformat(window["execution_day"]).replace(
        hour=DAILY_SCHEDULE_HOUR, tzinfo=KST
    )
