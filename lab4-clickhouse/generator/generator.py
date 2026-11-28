"""Генератор событий веб-сервиса -> ClickHouse. Имитирует 5 микросервисов, волнообразную нагрузку
и периодические «инциденты» (рост ошибок и латентности у payments)"""
import json
import math
import os
import random
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timedelta, timezone

URL = os.getenv("CLICKHOUSE_URL", "http://localhost:8123")
USER = os.getenv("CLICKHOUSE_USER", "lab")
PASSWORD = os.getenv("CLICKHOUSE_PASSWORD", "lab_pass")
DB = os.getenv("CLICKHOUSE_DB", "monitoring")
BASE_RPS = float(os.getenv("BASE_RPS", "60"))
BACKFILL_MINUTES = int(os.getenv("BACKFILL_MINUTES", "60"))

# service: (вес в трафике, число хостов, [(метод, путь, базовая латентность мс, базовая доля 5xx)])
SERVICES = {
    "auth": (3, 2, [("POST", "/login", 40, 0.004), ("POST", "/refresh", 15, 0.002), ("GET", "/me", 10, 0.001)]),
    "catalog": (5, 3, [("GET", "/products", 35, 0.002), ("GET", "/products/{id}", 20, 0.002), ("GET", "/categories", 12, 0.001)]),
    "search": (4, 2, [("GET", "/search", 90, 0.006), ("GET", "/suggest", 25, 0.003)]),
    "orders": (2, 2, [("POST", "/orders", 120, 0.008), ("GET", "/orders/{id}", 30, 0.003)]),
    "payments": (1, 2, [("POST", "/pay", 200, 0.010), ("POST", "/refund", 150, 0.008)]),
}
ERR_MSGS = {
    500: "internal server error",
    502: "bad gateway: upstream closed connection",
    503: "service unavailable: connection pool exhausted",
    504: "upstream timeout",
}
CLIENT_ERR = {400: "bad request", 401: "unauthorized", 404: "not found", 429: "too many requests"}
WEIGHTS = [v[0] for v in SERVICES.values()]
NAMES = list(SERVICES)


def incident_active(ts: datetime) -> bool:
    """Инцидент в payments: минуты 11-13 каждого 15-минутного цикла."""
    return (ts.minute % 15) in (11, 12, 13)


def make_event(ts: datetime) -> dict:
    svc = random.choices(NAMES, WEIGHTS)[0]
    _, hosts, endpoints = SERVICES[svc]
    method, path, base_lat, base_err = random.choice(endpoints)
    incident = svc == "payments" and incident_active(ts)

    latency = base_lat * random.lognormvariate(0, 0.45) * (5 if incident else 1)
    err_p = base_err * (25 if incident else 1)
    r = random.random()
    if r < err_p:
        status = random.choice(list(ERR_MSGS))
        message = ERR_MSGS[status]
        level = "ERROR"
        latency *= random.uniform(1.5, 4)
    elif r < err_p + 0.03:
        status = random.choice(list(CLIENT_ERR))
        message = CLIENT_ERR[status]
        level = "WARN"
    else:
        status = 201 if method == "POST" else 200
        message = ""
        level = "INFO"
    duration = int(latency)
    if level == "INFO" and duration > 500:
        level, message = "WARN", "slow request"

    return {
        "timestamp": ts.strftime("%Y-%m-%d %H:%M:%S.") + f"{ts.microsecond // 1000:03d}",
        "service": svc,
        "host": f"{svc}-{random.randint(1, hosts)}",
        "method": method,
        "endpoint": path,
        "status": status,
        "duration_ms": duration,
        "bytes_sent": int(random.lognormvariate(7, 1)) if status < 400 else random.randint(50, 300),
        "level": level,
        "user_id": random.randint(1, 5000),
        "trace_id": str(uuid.uuid4()),
        "message": message,
    }


def rps_at(ts: datetime) -> float:
    t = ts.timestamp()
    wave = 1 + 0.35 * math.sin(2 * math.pi * t / 600) + 0.15 * math.sin(2 * math.pi * t / 97)
    return max(1.0, BASE_RPS * wave)


def insert(rows: list) -> None:
    if not rows:
        return
    query = f"INSERT INTO {DB}.service_events FORMAT JSONEachRow"
    req = urllib.request.Request(
        f"{URL}/?{urllib.parse.urlencode({'query': query})}",
        data="\n".join(json.dumps(r) for r in rows).encode(),
        headers={"X-ClickHouse-User": USER, "X-ClickHouse-Key": PASSWORD},
        method="POST",
    )
    urllib.request.urlopen(req, timeout=30).read()


def insert_retry(rows: list) -> None:
    for attempt in range(30):
        try:
            insert(rows)
            return
        except (urllib.error.URLError, ConnectionError, TimeoutError) as e:
            print(f"insert failed ({e}), retry {attempt + 1}/30", flush=True)
            time.sleep(2)
    raise SystemExit("ClickHouse unavailable")


def events_for_second(sec_start: datetime) -> list:
    n = max(0, int(random.gauss(rps_at(sec_start), math.sqrt(BASE_RPS))))
    return [make_event(sec_start + timedelta(microseconds=random.randint(0, 999_999))) for _ in range(n)]


def backfill() -> None:
    if BACKFILL_MINUTES <= 0:
        return
    end = datetime.now(timezone.utc).replace(microsecond=0)
    cur = end - timedelta(minutes=BACKFILL_MINUTES)
    print(f"backfill {BACKFILL_MINUTES} min of history...", flush=True)
    buf, total = [], 0
    while cur < end:
        buf += events_for_second(cur)
        cur += timedelta(seconds=1)
        if len(buf) >= 20000:
            insert_retry(buf)
            total += len(buf)
            buf = []
    insert_retry(buf)
    print(f"backfill done: {total + len(buf)} rows", flush=True)


def main() -> None:
    backfill()
    print("live generation started", flush=True)
    next_tick = time.time()
    while True:
        sec_start = datetime.now(timezone.utc).replace(microsecond=0)
        insert_retry(events_for_second(sec_start))  # батч раз в секунду
        next_tick += 1
        time.sleep(max(0.0, next_tick - time.time()))


if __name__ == "__main__":
    main()
