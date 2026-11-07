# 새 명세 Silver 매핑 보완 — 2026-11-07

## 적용 상태와 범위

로컬 `feat/silver-logging-v1-mapping` 작업 폴더의 사전 준비 코드다.
SDK 배포, Stage/Production 실데이터 재적재, Airflow 변경, Gold 공개, Notion 수정은 하지 않았다.
`silver_logging_v1_enabled=false`, `silver_logging_validation_enabled=false` 기본값과
Stage-only 제한, 적용 기간·플랫폼·담당자·근거를 요구하는 scope 검사를 유지한다.
새 라벨이 아직 수집되지 않는 것은 개발 미적용 상태이며 데이터 장애로 판정하지 않는다.

TEAM Event Log의 현행 13개 서비스 문서에 연결된 393페이지를 확인했다.
새 명세의 정확한 라벨 270종을 등록 범위로 삼았다. 품절 동결 및 관련 A/B,
팀원 모집, 새/미래 주변상점, 레거시 동아리·졸업계산기와 과거 원문·빈 사본은 제외한다.
문서에 새 계약이 없는 행동의 라벨을 임의로 만들지 않는다.
Notion SQL 목록 조회 한도에 걸린 상점·홈·콜밴팟은 저장된 뷰로 목록을 확인했다.

## 변경 내용

- 기존 37라벨/86플랫폼 계약의 의미·경로·퍼널·플랫폼 제한은 보존한다.
- 누락 233라벨/500플랫폼 계약을 `silver_logging_v1_catalog.sql`에 추가한다.
  합계는 270라벨/586플랫폼 계약이다. DB의 플랫폼 속성만으로 기존 37라벨의
  플랫폼 지원을 넓히는 2건은 `held_platform_expansions`에 보류한다.
- 추가 계약은 기본적으로 서비스 분류만 제공한다. 순서·성공 의미가 미확정인
  `funnel_stage`, `step_order`, `service_step_order`는 NULL, Core는 false다.
- 서비스 Entry와 특정 퍼널 단계는 별개다. 명세상 서비스 진입인 헤더·푸터·카테고리,
  버스 시간표·탑승권 등은 명시적인 Entry 목록으로 관리한다. 버스 시간표·탑승권을
  교통편 검색 퍼널의 1단계로 합치지 않는다.
- 식단 코너 전환은 cafeteria 서비스지만 Entry가 아니다. 식단 사진 클릭·셔틀 노선 상세,
  상점 메뉴 탭 등의 `entry` 문자열만으로 서비스 첫 진입이나 Core를 추정하지 않는다.
- `main__main__navigation__main_entry__click`은 main 서비스 클릭으로 분류하지만
  실제 메인 방문 단계로 변환하지 않는다. main 방문 인증은 별도다.
- raw event_label/value/category, event_name, event_id, 사용자·세션 식별자 등 원문은 보존한다.
- 가입 4·5단계, iOS more 빈 카드 경로, 플랫폼별 퍼널 미지원은 기존 보류를 유지한다.

매핑의 분석용 service_name은 라벨 첫 구간을 무조건 복사하는 방식이 아니다.
명세상 홈의 버스 카드→bus, 식단 코너→cafeteria 등 명시적인 예외만 등록한다.
그 밖의 추가 서비스 분류는 해당 새 명세의 서비스 구분을 사용한다.
15개 분류는 account/banner/board/bus/cafeteria/callvan/chat/course_practice/
department/facility/main/owner/real_estate/shop/timetable다. 이 등록이 Gold의
서비스 범위를 자동 확장하거나 모든 서비스를 공통 퍼널로 공개한다는 뜻은 아니다.

## 근거와 재현

- `silver_logging_v1_catalog_20261107.json`: 라벨·담당자·category·플랫폼·서비스·Entry,
  근거 페이지와 설명, 보류·제외 목록. 개인정보 실제 값은 포함하지 않는다.
- `scripts/tests/test_silver_logging_catalog.py`: 중복, 기존 플랫폼 계약과의 충돌,
  근거 목록 일치, 동결·제외 서비스, 문법·category, 논리 main 및 버스 별도 경로 검사.
- `dbt/tests/assert_silver_logging_v1_service_catalog.sql`: 추가 500계약의 분류,
  원문 보존, 행 수·키 보존, scope 밖 전체 결과 보존, 미확정 단계·Core 격리.
- `dbt/tests/assert_silver_logging_v1_service_semantics.sql`: 별도로 선정한 명세 경계 사례.

검증용 변수 `silver_logging_validation_enabled=true`는 합성 검증에서만 사용한다.
일반 Silver 모델의 opt-in을 활성화하지 않고 실제 dbt parser/compiler로 오프라인
컴파일했다(dbt Core 1.10.15 / bigquery adapter 1.9.2). dbt run/test는 실행하지 않았다.

### 검증 결과

- Python 계약 검사 7개 통과.
- 일반 Silver 단독·일별·월별 실행에서 검증 테스트가 섞이지 않는 선택 격리 검사
  5개 통과. Windows 로컬 실행에서는 dbt 로그 핸들을 닫은 뒤 임시 폴더를 정리했다.
- 추가 500플랫폼 계약 검사 실패 0행:
  `job_8PADyCiMbjc5rTJqFTEyQyPVCMh6`.
- 기존 86플랫폼 계약 검사 실패 0행:
  `job_bal8cKRoobWCfadFDstICv5ItDyJ`.
- 기존 경계·구형·동결 포함 합성 매핑 검사 실패 0행:
  `job_49Mn8tIaq1rfOhOpTL4njQ0T7owf`.
- 독립 경계 사례 검사 실패 0행:
  `job_LxGT-xhcmlNeDsKM2samfVkEg9GI`.
- Silver→Gold 합성 계산 실패 0행:
  `job_SamGKlJDfapySD2Zy0TdynbsmFIA`.
- 미등록 새 라벨과 WEB 카테고리 경로 누락은 각각 의도한 오류로 차단됐다.

BigQuery 검증은 `koin-stage-438512`에서 개인 값 없는 합성 SELECT만 실행했다.
기존 Gold fixture의 임시 테이블 정의 4개는 실행 전에 CTE로 변환해 검증했다.
Stage 테이블을 만들거나 바꾸지 않았고, 운영 데이터도 조회·변경하지 않았다.

## 이후 단계

1. 코드 리뷰에서 추가 서비스 Entry 목록 및 서비스 분류 예외를 확인한다.
2. SDK 배포 후 실제 라벨·category·event_name·플랫폼·발생 시점·단일 전송을 확인한다.
3. 배포 근거와 기간을 확정한 scope로 Stage에서 실제 입력을 검증한다.
4. 퍼널에 추가 경로를 연결하려면 서비스 분류와 별도로 순서·단계 의미를 검증한다.
5. 운영 승격과 Gold 공개는 별도 승인·검증 후 진행한다. 현재 flags는 false다.

과거 로깅의 누락·오분류를 이번 변경으로 보정하거나 과거 이력을 재계산하지 않는다.
