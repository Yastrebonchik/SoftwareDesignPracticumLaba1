#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "Использование: bash $0 <репозиторий> <ветка_1> <ветка_2>" >&2
    exit 1
fi

repository=$1
branch1=$2
branch2=$3

if ! command -v git >/dev/null 2>&1; then
    echo "Ошибка: установите Git." >&2
    exit 1
fi

git check-ref-format "refs/heads/$branch1" >/dev/null
git check-ref-format "refs/heads/$branch2" >/dev/null

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
mkdir -p -- "$script_dir/reports"
temp_dir=$(mktemp -d)
trap 'rm -rf -- "$temp_dir"' EXIT

git clone --quiet --bare -- "$repository" "$temp_dir/repository.git"

for branch in "$branch1" "$branch2"; do
    if ! git -C "$temp_dir/repository.git" show-ref --verify --quiet "refs/heads/$branch"; then
        echo "Ошибка: ветка '$branch' отсутствует в репозитории." >&2
        exit 1
    fi
done

git -C "$temp_dir/repository.git" -c core.quotePath=false diff \
    --no-ext-diff --no-renames --name-status \
    "refs/heads/$branch1" "refs/heads/$branch2" -- > "$temp_dir/changes.txt"

safe_branch1=${branch1//\//_}
safe_branch2=${branch2//\//_}
report="$script_dir/reports/diff_report_${safe_branch1}_vs_${safe_branch2}.txt"

{
    printf 'Отчет о различиях между ветками\n\n'
    printf '================================\n'
    printf 'Репозиторий:    %s\n' "$repository"
    printf 'Ветка 1:       %s\n' "$branch1"
    printf 'Ветка 2:       %s\n' "$branch2"
    printf 'Дата генерации: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    printf '================================\n\n'
    printf 'СПИСОК ИЗМЕНЕННЫХ ФАЙЛОВ\n'
    if [[ -s "$temp_dir/changes.txt" ]]; then
        cat -- "$temp_dir/changes.txt"
    else
        printf 'Различий нет.\n'
    fi
    printf '\nСТАТИСТИКА\n'
    awk -F '\t' '
        $1 == "A" { added++ }
        $1 == "D" { deleted++ }
        $1 == "M" { modified++ }
        $1 != "A" && $1 != "D" && $1 != "M" { other++ }
        END {
            printf "Всего измененных файлов: %d\n", NR
            printf "Добавлено (A): %d\n", added
            printf "Удалено (D): %d\n", deleted
            printf "Изменено (M): %d\n", modified
            printf "Другие изменения: %d\n", other
        }
    ' "$temp_dir/changes.txt"
} > "$report"

printf 'Отчет сохранен: %s\n' "$report"
