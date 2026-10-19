#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 || -z ${2:-} ]]; then
    echo "Использование: bash $0 <лог-файл> <непустое_ключевое_слово>" >&2
    exit 1
fi

log_file=$1
keyword=$2

if [[ ! -f "$log_file" || ! -r "$log_file" ]]; then
    echo "Ошибка: лог-файл не существует или недоступен для чтения." >&2
    exit 1
fi

if [[ "$keyword" == *$'\n'* ]]; then
    echo "Ошибка: ключевое слово должно занимать одну строку." >&2
    exit 1
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
mkdir -p -- "$script_dir/reports"
base_name=$(basename -- "$log_file")
matches_file="$script_dir/reports/${base_name}_matches.txt"
summary_file="$script_dir/reports/${base_name}_summary.txt"

result=0
grep -aF -- "$keyword" "$log_file" > "$matches_file" || result=$?
if [[ $result -gt 1 ]]; then
    echo "Ошибка при чтении лог-файла." >&2
    exit "$result"
fi

count=$(wc -l < "$matches_file")
{
    printf 'Исходный файл: %s\n' "$log_file"
    printf 'Ключевое слово: %s\n' "$keyword"
    printf 'Количество найденных строк: %d\n' "$count"
    printf 'Файл с найденными строками: %s\n' "$matches_file"
} > "$summary_file"

cat -- "$summary_file"
printf 'Отчет сохранен: %s\n' "$summary_file"
