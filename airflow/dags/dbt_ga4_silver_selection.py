"""기존 스케줄을 유지하는 Stage Silver V2 전환 정책. DB 접속 없음."""

import os
from collections.abc import Mapping

STAGE_PROJECT = "koin-stage-438512"
V2_MODELS = ("silver_events_v2", "silver__users")


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
    for key in ("KOIN_DATA_GCP_PROJECT", "KOIN_DATA_GA4_PROJECT", "KOIN_DATA_APP_DB_PROJECT"):
        if env.get(key) != STAGE_PROJECT:
            raise ValueError(f"Stage 전환에는 {key}={STAGE_PROJECT}가 필요합니다.")
    for key in ("KOIN_DATA_GA4_DATASET", "KOIN_DATA_APP_DB_DATASET"):
        if not env.get(key, "").strip():
            raise ValueError(f"Stage 원천 {key}를 명시해야 합니다.")
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
