"""Собирает grafana/dashboards/service-overview.json"""
import json

DS = {"type": "grafana-clickhouse-datasource", "uid": "clickhouse"}
T = "monitoring.service_events"
R = "monitoring.service_stats_1m"
F = "$__timeFilter(timestamp)"
SV = "service IN ($service)"
TS, TB = (2, "timeseries"), (0, "table")  # format плагина: 0=table, 2=time series


def target(sql, fmt):
    return {"datasource": DS, "editorType": "sql", "format": fmt[0], "queryType": fmt[1],
            "rawSql": sql, "refId": "A"}


def pos(x, y, w, h):
    return {"x": x, "y": y, "w": w, "h": h}


def stat(pid, title, sql, unit, gp, decimals=None, thresholds=None):
    steps = thresholds or [{"color": "green", "value": None}]
    d = {"unit": unit, "thresholds": {"mode": "absolute", "steps": steps}}
    if decimals is not None:
        d["decimals"] = decimals
    return {"id": pid, "type": "stat", "title": title, "datasource": DS, "gridPos": gp,
            "targets": [target(sql, TB)], "fieldConfig": {"defaults": d, "overrides": []},
            "options": {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
                        "colorMode": "value", "graphMode": "none"}}


def ts(pid, title, sql, unit, gp, stack=False):
    custom = {"drawStyle": "line", "lineWidth": 1, "fillOpacity": 15, "showPoints": "never"}
    if stack:
        custom["stacking"] = {"mode": "normal", "group": "A"}
    return {"id": pid, "type": "timeseries", "title": title, "datasource": DS, "gridPos": gp,
            "targets": [target(sql, TS)],
            "fieldConfig": {"defaults": {"unit": unit, "custom": custom}, "overrides": []},
            "options": {"legend": {"displayMode": "table", "placement": "bottom", "calcs": ["mean", "max"]},
                        "tooltip": {"mode": "multi"}}}


def table(pid, title, sql, gp):
    return {"id": pid, "type": "table", "title": title, "datasource": DS, "gridPos": gp,
            "targets": [target(sql, TB)], "fieldConfig": {"defaults": {}, "overrides": []},
            "options": {"showHeader": True}}


panels = [
    stat(1, "Запросов в секунду (среднее)",
         f"SELECT count() / greatest(1, dateDiff('second', $__fromTime, $__toTime)) AS rps FROM {T} WHERE {F} AND {SV}",
         "reqps", pos(0, 0, 5, 4), 1),
    stat(2, "Доля ошибок 5xx",
         f"SELECT 100 * countIf(status >= 500) / greatest(1, count()) AS err FROM {T} WHERE {F} AND {SV}",
         "percent", pos(5, 0, 5, 4), 2,
         [{"color": "green", "value": None}, {"color": "orange", "value": 1}, {"color": "red", "value": 3}]),
    stat(3, "Latency p95",
         f"SELECT quantile(0.95)(duration_ms) AS p95 FROM {T} WHERE {F} AND {SV}",
         "ms", pos(10, 0, 5, 4), 0,
         [{"color": "green", "value": None}, {"color": "orange", "value": 300}, {"color": "red", "value": 800}]),
    stat(4, "Latency p99",
         f"SELECT quantile(0.99)(duration_ms) AS p99 FROM {T} WHERE {F} AND {SV}",
         "ms", pos(15, 0, 5, 4), 0,
         [{"color": "green", "value": None}, {"color": "orange", "value": 600}, {"color": "red", "value": 1500}]),
    stat(5, "Всего запросов",
         f"SELECT count() AS total FROM {T} WHERE {F} AND {SV}",
         "short", pos(20, 0, 4, 4)),
    ts(6, "RPS по сервисам",
       f"SELECT $__timeInterval(timestamp) AS time, service, count() / $__interval_s AS rps "
       f"FROM {T} WHERE {F} AND {SV} GROUP BY time, service ORDER BY time",
       "reqps", pos(0, 4, 12, 8), stack=True),
    ts(7, "Доля ошибок 5xx по сервисам (из минутного агрегата)",
       f"SELECT $__timeInterval(minute) AS time, service, "
       f"100 * sum(errors_5xx) / greatest(1, sum(requests)) AS err_pct "
       f"FROM {R} WHERE $__timeFilter(minute) AND {SV} GROUP BY time, service ORDER BY time",
       "percent", pos(12, 4, 12, 8)),
    ts(8, "Latency: p50 / p95 / p99",
       f"SELECT $__timeInterval(timestamp) AS time, quantile(0.5)(duration_ms) AS p50, "
       f"quantile(0.95)(duration_ms) AS p95, quantile(0.99)(duration_ms) AS p99 "
       f"FROM {T} WHERE {F} AND {SV} GROUP BY time ORDER BY time",
       "ms", pos(0, 12, 12, 8)),
    {"id": 9, "type": "piechart", "title": "Классы HTTP-статусов", "datasource": DS, "gridPos": pos(12, 12, 6, 8),
     "targets": [target(f"SELECT concat(toString(intDiv(status, 100)), 'xx') AS status_class, count() AS requests "
                        f"FROM {T} WHERE {F} AND {SV} GROUP BY status_class ORDER BY status_class", TB)],
     "fieldConfig": {"defaults": {}, "overrides": []},
     "options": {"pieType": "donut", "legend": {"displayMode": "table", "placement": "right", "values": ["value", "percent"]},
                 "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": True}}},
    ts(10, "Ошибки (5xx) по сервисам, шт.",
       f"SELECT $__timeInterval(timestamp) AS time, service, countIf(status >= 500) AS errors "
       f"FROM {T} WHERE {F} AND {SV} GROUP BY time, service ORDER BY time",
       "short", pos(18, 12, 6, 8), stack=True),
    table(11, "Самые медленные эндпоинты",
          f"SELECT service, endpoint, count() AS requests, round(avg(duration_ms), 1) AS avg_ms, "
          f"quantile(0.95)(duration_ms) AS p95_ms, round(100 * countIf(status >= 500) / count(), 2) AS err_pct "
          f"FROM {T} WHERE {F} AND {SV} GROUP BY service, endpoint ORDER BY p95_ms DESC LIMIT 10",
          pos(0, 20, 10, 9)),
    table(12, "Последние ошибки (лог)",
          f"SELECT timestamp, service, host, endpoint, status, duration_ms, message, trace_id "
          f"FROM {T} WHERE {F} AND {SV} AND level = 'ERROR' ORDER BY timestamp DESC LIMIT 50",
          pos(10, 20, 14, 9)),
]

dashboard = {
    "uid": "service-overview",
    "title": "Service Overview (Lab 4)",
    "tags": ["lab4", "clickhouse"],
    "timezone": "browser",
    "schemaVersion": 39,
    "version": 1,
    "refresh": "10s",
    "time": {"from": "now-30m", "to": "now"},
    "templating": {"list": [{
        "name": "service", "label": "Сервис", "type": "query", "datasource": DS,
        "definition": f"SELECT DISTINCT service FROM {T} ORDER BY service",
        "query": f"SELECT DISTINCT service FROM {T} ORDER BY service",
        "multi": True, "includeAll": True, "refresh": 2,
        "current": {"selected": True, "text": "All", "value": "$__all"}}]},
    "panels": panels,
}

with open("grafana/dashboards/service-overview.json", "w", encoding="utf-8") as f:
    json.dump(dashboard, f, ensure_ascii=False, indent=2)
print("ok")
