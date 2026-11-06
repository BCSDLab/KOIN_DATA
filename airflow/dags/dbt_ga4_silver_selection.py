"""기존 스케줄을 유지하는 Stage Silver V2 전환 정책. DB 접속 없음."""

import os
import json
import re
from collections.abc import Mapping

STAGE_PROJECT = "koin-stage-438512"
V2_MODELS = ("silver_events_v2", "silver__users")
STAGE_WRITE_POOL = "koin_stage_silver_writes"
SOURCE_KEYS = ("KOIN_DATA_GA4_PROJECT", "KOIN_DATA_GA4_DATASET",
               "KOIN_DATA_APP_DB_PROJECT", "KOIN_DATA_APP_DB_DATASET")


def v2_only_enabled(environ: Mapping[str, str] | None = None) -> bool:
    env = os.environ if environ is None else environ
    value = env.get("KOIN_DATA_SILVER_V2_ONLY", "false").strip().lower()
    if value not in ("true", "false"):
        raise ValueError("KOIN_DATA_SILVER_V2_ONLY는 true/false여야 합니다.")
    return value == "true"


def validate_stage_silver_environment(
    environ: Mapping[str, str] | None = None, *, require_v2: bool = False
) -> None:
    """전환 시 출력·원천·최초 적재 완료를 모두 명시적으로 확인한다."""
    env = os.environ if environ is None else environ
    if require_v2 and not v2_only_enabled(env):
        raise ValueError("Stage V2 DAG의 실행 환경이 변경됐습니다. 재파싱 후 다시 실행하세요.")
    if not v2_only_enabled(env):
        return  # 기본/운영 환경의 기존 선택 정책을 유지한다.
    if env.get("DBT_TARGET", "dev") != "dev":
        raise ValueError("Silver V2 전환은 Stage(dev)에서만 허용합니다.")
    if env.get("KOIN_DATA_GCP_PROJECT") != STAGE_PROJECT:
        raise ValueError(f"출력은 반드시 KOIN_DATA_GCP_PROJECT={STAGE_PROJECT}여야 합니다.")
    try:
        contract = json.loads(env.get("KOIN_DATA_SILVER_SOURCE_CONTRACT", ""))
    except (ValueError, TypeError):
        raise ValueError("승인된 KOIN_DATA_SILVER_SOURCE_CONTRACT JSON이 필요합니다.") from None
    if not isinstance(contract, dict) or not isinstance(contract.get("evidence"), str) or not contract["evidence"].strip():
        raise ValueError("원천 계약의 승인 근거 evidence가 필요합니다.")
    for key in SOURCE_KEYS:
        value = env.get(key, "")
        pattern = r"[a-z][a-z0-9-]{4,61}[a-z0-9]" if key.endswith("PROJECT") else r"[A-Za-z_][A-Za-z0-9_]*"
        if not re.fullmatch(pattern, value) or contract.get(key) != value:
            raise ValueError(f"{key}가 승인된 원천 계약과 다릅니다.")
    if env.get("KOIN_DATA_SILVER_BOOTSTRAP_COMPLETE", "false").strip().lower() != "true":
        raise ValueError("Silver V2/User 최초 적재·검증 후 BOOTSTRAP_COMPLETE=true가 필요합니다.")


def silver_selection(model_tag: str, environ: Mapping[str, str] | None = None) -> dict[str, list[str]]:
    env = os.environ if environ is None else environ
    validate_stage_silver_environment(env)
    if v2_only_enabled(env):
        # 태그와 모델명의 교집합: legacy와 Gold를 후손 선택(+)으로 끌어오지 않는다.
        return {"select": [f"tag:{model_tag},{model}" for model in V2_MODELS], "exclude": []}
    complete = env.get("KOIN_DATA_SILVER_BOOTSTRAP_COMPLETE", "false").strip().lower() == "true"
    return {"select": [f"tag:{model_tag}"],
            "exclude": [] if complete else ["tag:initial_load_required"]}


def silver_execution_options(environ: Mapping[str, str] | None = None) -> dict:
    """일별·월별·수동 실행의 모든 dbt 쓰기/검사 task에 같은 1-slot pool 적용."""
    env = os.environ if environ is None else environ
    validate_stage_silver_environment(env)
    return {"pool": STAGE_WRITE_POOL, "pool_slots": 1} if v2_only_enabled(env) else {}
