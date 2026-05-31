# 운영

## 시작

```bash
cp .env.example .env
docker compose up -d --build
./scripts/init_airflow.sh
```

## 백업

Postgres metadata DB에는 Airflow와 Superset 상태가 저장됩니다. 주기적으로 백업해야 합니다.

```bash
./scripts/backup_postgres.sh
```

## 보안

- Airflow와 Superset 포트를 인터넷 전체에 공개하지 않습니다.
- 회사 IP 제한, VPN, IAP, HTTPS 등 접근 제어를 둡니다.
- `.env`와 `secrets/`는 Git에 커밋하지 않습니다.

## 저장공간

Docker volume, 로그, 이미지, BigQuery 비용을 주기적으로 확인합니다. Superset은 gold 테이블만 조회하도록 유지합니다.
