#!/usr/bin/env bash
# 任务 D 的辅助脚本：在 run3.sh 的负载中按时触发滚动发布，D2 结束后补记重启次数与告警查询的结果。
# 在仓库根目录运行；lbd（默认参数）、Prometheus 已启动，scaler 按任务 D 的参数启动且实例都已就绪。
#
#   scripts/taskd.sh naive               D1 直接替换：172@180s，第 30 秒 POST /rollout?version=v2&mode=naive
#   scripts/taskd.sh graceful            D1 排空加就绪：172@420s，第 30 秒 POST /rollout?version=v3&mode=graceful
#   scripts/taskd.sh heal                D2 自愈：172@480s，结束后记 NRestarts 和告警查询
set -euo pipefail
RATE=${RATE:-172}
SCALER=${SCALER:-http://127.0.0.1:8091}
PROM=${PROM:-http://127.0.0.1:9090}
URL=http://127.0.0.1:8080/api/courses/1
ALERT='sum by (instance) (changes(process_start_time_seconds{job="instances"}[10m]))'
export GEN_CPUS=${GEN_CPUS:-0-1}

rollout() { # <名字> <版本> <方式> <时长>
  (sleep 30; curl -fsS -X POST "$SCALER/rollout?version=$2&mode=$3" && echo "== 已触发 rollout $2 $3") &
  scripts/run3.sh "$1" -url "$URL" -plan "${RATE}@$4"
  wait
}

case ${1:-} in
  naive)    rollout d1-naive v2 naive 180s ;;
  graceful) rollout d1-graceful v3 graceful 420s ;;
  heal)
    scripts/run3.sh d2-heal -url "$URL" -plan "${RATE}@480s"
    d=runs/d2-heal
    for u in $(systemctl list-units --plain --no-legend 'lab3-inst-*' | awk '{print $1}'); do
      echo "$u $(systemctl show -p NRestarts,ActiveState,Result "$u" | tr '\n' ' ')"
    done | tee "$d/nrestarts.txt"
    { echo "# $ALERT"; date -Iseconds
      curl -fsS "$PROM/api/v1/query" --data-urlencode "query=$ALERT"; echo
      echo "# sum(changes(process_start_time_seconds{job=\"instances\"}[10m]))"
      curl -fsS "$PROM/api/v1/query" --data-urlencode 'query=sum(changes(process_start_time_seconds{job="instances"}[10m]))'; echo
    } | tee "$d/alert-query.txt"
    ;;
  *) echo "用法：scripts/taskd.sh naive|graceful|heal" >&2; exit 1 ;;
esac
