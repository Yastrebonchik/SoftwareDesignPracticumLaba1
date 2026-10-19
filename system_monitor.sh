#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

if [[ $# -ne 1 ]]; then
    echo "Использование: bash $0 START|STOP|STATUS" >&2
    exit 1
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
script_path="$script_dir/$(basename -- "${BASH_SOURCE[0]}")"
report_dir="$script_dir/reports"
pid_file="$script_dir/.system_monitor.pid"
mkdir -p -- "$report_dir"

is_running() {
    [[ -f "$pid_file" ]] || return 1
    read -r pid < "$pid_file" || return 1
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    [[ -r "/proc/$pid/cmdline" ]] || return 1
    grep -zFxq -- "$script_path" "/proc/$pid/cmdline"
}

read_cpu() {
    awk '/^cpu / {
        total = 0
        for (i = 2; i <= 9; i++) total += $i
        printf "%.0f %.0f\n", total, $5 + $6
        exit
    }' /proc/stat
}

collect_metrics() {
    local total_before idle_before total_after idle_after cpu_used
    local all_memory free_memory memory_used disk_used load_average
    local timestamp report_date csv_file

    read -r total_before idle_before < <(read_cpu)
    sleep 1
    read -r total_after idle_after < <(read_cpu)
    cpu_used=$(awk -v t1="$total_before" -v t2="$total_after" \
        -v i1="$idle_before" -v i2="$idle_after" 'BEGIN {
            total = t2 - t1
            printf "%.2f", (total > 0 ? 100 * (total - (i2 - i1)) / total : 0)
        }')

    read -r all_memory free_memory memory_used < <(
        awk '
            /^MemTotal:/ { total = $2 }
            /^MemFree:/ { free = $2 }
            END { printf "%.2f %.2f %.2f\n", total / 1024, free / 1024, 100 * (total - free) / total }
        ' /proc/meminfo
    )
    disk_used=$(df -P / | awk 'NR == 2 { gsub(/%/, "", $5); print $5 }')
    load_average=$(awk '{ print $1 }' /proc/loadavg)
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    report_date=${timestamp%% *}
    csv_file="$report_dir/system_report_${report_date}.csv"

    if [[ ! -s "$csv_file" ]]; then
        printf 'timestamp;all_memory;free_memory;%%memory_used;%%cpu_used;%%disk_used;load_average_1m\n' > "$csv_file"
    fi
    printf '%s;%s;%s;%s;%s;%s;%s\n' "$timestamp" "$all_memory" \
        "$free_memory" "$memory_used" "$cpu_used" "$disk_used" "$load_average" >> "$csv_file"
}

if [[ "$1" == "__run" ]]; then
    exec 8> "$script_dir/.system_monitor.worker.lock"
    flock -n 8 || exit 1
    sleep_pid=''
    trap 'exit 0' TERM INT
    trap 'if [[ -n "$sleep_pid" ]]; then kill "$sleep_pid" 2>/dev/null || true; wait "$sleep_pid" 2>/dev/null || true; fi' EXIT
    while true; do
        started_at=$SECONDS
        collect_metrics
        delay=$((600 - (SECONDS - started_at)))
        if (( delay > 0 )); then
            sleep "$delay" &
            sleep_pid=$!
            wait "$sleep_pid"
            sleep_pid=''
        fi
    done
fi

exec 9> "$script_dir/.system_monitor.control.lock"
flock 9

case "$1" in
    START)
        if is_running; then
            echo "Мониторинг уже запущен. PID: $pid"
            exit 0
        fi
        nohup bash "$script_path" __run </dev/null >> "$report_dir/system_monitor.log" 2>&1 9>&- &
        pid=$!
        printf '%s\n' "$pid" > "$pid_file"
        sleep 0.2
        if is_running; then
            echo "Мониторинг запущен. PID: $pid"
        else
            echo "Ошибка запуска. См. $report_dir/system_monitor.log" >&2
            exit 1
        fi
        ;;
    STATUS)
        if is_running; then
            echo "Мониторинг запущен. PID: $pid"
        else
            echo "Мониторинг не запущен."
            exit 1
        fi
        ;;
    STOP)
        if is_running; then
            kill "$pid"
            for ((attempt = 0; attempt < 50; attempt++)); do
                if ! is_running; then
                    break
                fi
                sleep 0.1
            done
            if is_running; then
                echo "Процесс еще завершается. Повторите STOP позже." >&2
                exit 1
            fi
            echo "Мониторинг остановлен. PID: $pid"
        else
            echo "Мониторинг не запущен."
        fi
        rm -f -- "$pid_file"
        ;;
    *)
        echo "Неизвестная команда. Используйте START, STOP или STATUS." >&2
        exit 1
        ;;
esac
