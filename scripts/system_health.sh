#!/usr/bin/env bash
set -euo pipefail

disk_limit=80
cpu_limit=90
mem_limit=85
json=false
log_file="${HEALTH_LOG_FILE:-health_log.txt}"
max_bytes=1048576

usage() { printf '%s\n' "Usage: $0 [--disk N] [--cpu N] [--mem N] [--json] [--log FILE] [--help]"; }
while (($#)); do
  case "$1" in
    --disk) disk_limit=$2; shift 2;;
    --cpu) cpu_limit=$2; shift 2;;
    --mem) mem_limit=$2; shift 2;;
    --json) json=true; shift;;
    --log) log_file=$2; shift 2;;
    --help) usage; exit 0;;
    *) printf '[ERROR] Unknown option: %s\n' "$1" >&2; usage >&2; exit 2;;
  esac
done
for value in "$disk_limit" "$cpu_limit" "$mem_limit"; do
  [[ "$value" =~ ^[0-9]+$ && "$value" -le 100 ]] || { echo '[ERROR] thresholds must be 0-100' >&2; exit 2; }
done

rotate() {
  if [[ -f "$log_file" ]] && (( $(wc -c < "$log_file") >= max_bytes )); then
    mv -- "$log_file" "${log_file}.1"
  fi
}
rotate
timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
load=$(awk '{print $1}' /proc/loadavg)
mem=$(free | awk '/Mem:/ {printf "%.0f", ($3/$2)*100}')
cpu=$(top -bn1 | awk -F'[, ]+' '/Cpu\(s\)/ {print int(100-$8)}')
warnings=()
while read -r filesystem usage; do
  if [[ "$usage" =~ ^[0-9]+$ ]] && ((usage > disk_limit)); then
    warnings+=("disk:$filesystem=$usage%")
  fi
done < <(df -P | awk 'NR>1 {gsub(/%/,"",$5); print $6,$5}')
((cpu > cpu_limit)) && warnings+=("cpu=${cpu}%") || true
((mem > mem_limit)) && warnings+=("memory=${mem}%") || true
top_processes=$(ps -eo pid,comm,%mem --sort=-%mem | head -n 6 | tail -n 5 | tr '\n' ';' | sed 's/;$/ /')
if "$json"; then
  warning_json=''
  for warning in "${warnings[@]}"; do
    [[ -n "$warning_json" ]] && warning_json+=','
    warning_json+="\"${warning//\"/\\\"}\""
  done
  printf '{"timestamp":"%s","cpu_percent":%s,"memory_percent":%s,"load_1m":"%s","warnings":[%s],"top_processes":"%s"}\n' "$timestamp" "$cpu" "$mem" "$load" "$warning_json" "${top_processes//\"/\\\"}" | tee -a "$log_file"
else
  { printf '[%s] CPU=%s%% MEM=%s%% LOAD=%s\n' "$timestamp" "$cpu" "$mem" "$load"; printf 'Top processes: %s\n' "$top_processes"; for warning in "${warnings[@]}"; do printf '[WARNING] %s\n' "$warning"; done; } | tee -a "$log_file"
fi
(( ${#warnings[@]} == 0 )) && exit 0
critical=false
((cpu >= 95 || mem >= 95)) && critical=true
for warning in "${warnings[@]}"; do [[ "$warning" == disk:* ]] && [[ "${warning##*=}" =~ ^9[5-9]%$|^100%$ ]] && critical=true; done
"$critical" && exit 2
exit 1
