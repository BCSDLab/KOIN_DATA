# Lightsail Deploy Guide

## 1. Prepare DNS

Create a Lightsail static IP and point the dashboard domain to it.

```text
superset.bcsdlab.com -> Lightsail static IP
```

## 2. Configure Firewall

In the Lightsail networking tab, allow only:

```text
80/tcp
443/tcp
```

Do not expose `8080`, `8088`, or `5432`.
SSH should be reachable through Tailscale only.

## 3. Configure Environment

```bash
cp .env.example .env
```

Edit `.env` and replace every `change_me` value.

Required production values:

```env
KOIN_DATA_SUPERSET_DOMAIN=superset.bcsdlab.com
KOIN_DATA_CADDY_EMAIL=your-email@example.com
KOIN_DATA_POSTGRES_PASSWORD=<strong-password>
SUPERSET_SECRET_KEY=<strong-secret>
AIRFLOW__WEBSERVER__SECRET_KEY=<strong-secret>
```

## 4. Start Services

```bash
docker compose up -d --build
docker compose ps
```

Caddy automatically requests and renews HTTPS certificates for the configured domain.

## 5. Initialize Airflow

```bash
./scripts/init_airflow.sh
```

## 6. Verify

```bash
curl -I https://superset.bcsdlab.com
docker compose logs --tail=100 caddy
docker compose logs --tail=100 superset
```

Then open:

```text
https://superset.bcsdlab.com
```

## 7. Access Policy

Operators:

```text
Tailscale -> SSH -> Docker management
```

Club members:

```text
Browser -> HTTPS -> Superset login -> dashboard view
```
