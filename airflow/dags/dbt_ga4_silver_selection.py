"""기존 스케줄과 사용처를 보존하는 Silver V2 전환 정책. DB 접속 없음."""

import os
import json
import re
from collections.abc import Mapping

STAGE_PROJECT = "koin-stage-438512"
PROD_PROJECT = "kap-chat"
PROD_WRITE_POOL = "koin_prod_silver_writes"
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


def production_mode(environ=None):
    env = os.environ if environ is None else environ
    mode = env.get("KOIN_DATA_SILVER_PROD_MODE", "disabled").strip().lower()
    if mode not in ("disabled", "parallel", "v2_only"):
        raise ValueError("KOIN_DATA_SILVER_PROD_MODE는 disabled/parallel/v2_only여야 합니다.")
    return mode


def v2_execution_enabled(environ=None):
    return v2_only_enabled(environ) or production_mode(environ) != "disabled"


def validate_silver_environment(
    environ: Mapping[str, str] | None = None, *, require_v2: bool = False
) -> None:
    """전환 시 출력·원천·최초 적재 완료를 모두 명시적으로 확인한다."""
    env = os.environ if environ is None else environ
    mode = production_mode(env)
    stage = v2_only_enabled(env)
    if stage and mode != "disabled":
        raise ValueError("Stage/Production 전환 옵션을 함께 켤 수 없습니다.")
    if require_v2 and not v2_execution_enabled(env):
        raise ValueError("Silver V2 DAG의 실행 환경이 변경됐습니다. 재파싱 후 다시 실행하세요.")
    if not stage and mode == "disabled":
        return  # 기본/운영 환경의 기존 선택 정책을 유지한다.
    expected_target, expected_project = ("dev", STAGE_PROJECT) if stage else ("prod", PROD_PROJECT)
    if env.get("DBT_TARGET", "dev") != expected_target or env.get("KOIN_DATA_GCP_PROJECT") != expected_project:
        raise ValueError(f"전환 출력은 {expected_target}/{expected_project}에 고정해야 합니다.")
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
    if not stage:
        if any(env.get(key) != PROD_PROJECT for key in ["KOIN_DATA_GA4_PROJECT","KOIN_DATA_APP_DB_PROJECT"]):
            raise ValueError("운영 전환은 승인된 운영 원천 프로젝트가 필요합니다.")
        try:
            proof = json.loads(env.get("KOIN_DATA_SILVER_PROD_BOOTSTRAP_EVIDENCE", ""))
        except (ValueError, TypeError):
            raise ValueError("운영 최초 적재 검증 JSON 근거가 필요합니다.") from None
        if (not isinstance(proof, dict) or proof.get("project") != PROD_PROJECT
            or proof.get("tests_passed") is not True or not proof.get("evidence")
            or not isinstance(proof.get("models"), list)
            or not all(isinstance(name,str) for name in proof["models"])
            or set(proof["models"]) != set(V2_MODELS)):
            raise ValueError("운영 두 모델의 적재·검증 근거가 유효하지 않습니다.")
        if mode == "v2_only" and (env.get("KOIN_DATA_SILVER_LEGACY_CONSUMERS_VERIFIED", "false").lower() != "true"
                                  or not env.get("KOIN_DATA_SILVER_LEGACY_CONSUMERS_EVIDENCE", "").strip()):
            raise ValueError("기존 Event 사용처 전환 검증 전에는 parallel 모드를 사용해야 합니다.")
    if env.get("KOIN_DATA_SILVER_BOOTSTRAP_COMPLETE", "false").strip().lower() != "true":
        raise ValueError("Silver V2/User 최초 적재·검증 후 BOOTSTRAP_COMPLETE=true가 필요합니다.")


def silver_selection(model_tag: str, environ: Mapping[str, str] | None = None) -> dict[str, list[str]]:
    env = os.environ if environ is None else environ
    validate_silver_environment(env)
    mode = production_mode(env)
    if mode != "disabled":
        models = list(V2_MODELS)
        if mode == "parallel" and model_tag == "airflow_daily":
            models.insert(0,"silver_events")
        return {"select": [f"tag:{model_tag},{model}" for model in models], "exclude": []}
    if v2_only_enabled(env):
        # 태그와 모델명의 교집합: legacy와 Gold를 후손 선택(+)으로 끌어오지 않는다.
        return {"select": [f"tag:{model_tag},{model}" for model in V2_MODELS], "exclude": []}
    complete = env.get("KOIN_DATA_SILVER_BOOTSTRAP_COMPLETE", "false").strip().lower() == "true"
    return {"select": [f"tag:{model_tag}"],
            "exclude": [] if complete else ["tag:initial_load_required"]}


def silver_execution_options(environ: Mapping[str, str] | None = None) -> dict:
    """일별·월별·수동 실행의 모든 dbt 쓰기/검사 task에 같은 1-slot pool 적용."""
    env = os.environ if environ is None else environ
    validate_silver_environment(env)
    if v2_execution_enabled(env):
        return {"pool": PROD_WRITE_POOL if production_mode(env) != "disabled" else STAGE_WRITE_POOL, "pool_slots": 1}
    return {}


# 기존 Stage 호출자/검사 호환. 신규 호출자는 환경 공통 이름을 사용한다.
validate_stage_silver_environment = validate_silver_environment
