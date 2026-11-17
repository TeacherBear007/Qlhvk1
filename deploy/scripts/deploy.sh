#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
[[ "$EUID" == 0 ]] || { echo "Chạy deploy bằng SSH root." >&2; exit 1; }
release=$(cd "$(dirname "$0")/../.." && pwd)
deploy_id=$(basename "$release")
[[ "$deploy_id" =~ ^[a-f0-9]{40}-[0-9]+-[0-9]+$ ]] || { echo "Sai deploy ID."; exit 1; }
app_changed=${1:-true}
key_file=${2:-/dev/null}
[[ "$app_changed" == true || "$app_changed" == false ]] || exit 1
base=/opt/qlhvk1
data=/var/lib/qlhvk1/AppData
mkdir -p "$base/state" /var/lib/qlhvk1 /var/backups/qlhvk1
chmod 700 "$base" /var/lib/qlhvk1 /var/backups/qlhvk1
exec 9>/var/lock/qlhvk1-deploy.lock
flock -w 1200 9
for command in docker python3 openssl curl nginx certbot systemctl tar; do
    command -v "$command" >/dev/null || { echo "Thiếu công cụ: $command" >&2; exit 1; }
done
docker compose version
old_release=$(readlink -f "$base/current" 2>/dev/null || true)
old_ready=false
[[ ! -f "$base/.env" || ! -f "$base/docker-compose.yml" || ! -d "$old_release" ]] || old_ready=true
compose_changed=true
if [[ -f "$base/docker-compose.yml" ]] && cmp -s "$release/docker-compose.yml" "$base/docker-compose.yml"; then
    compose_changed=false
fi
if [[ "$old_ready" == false ]]; then app_changed=true; fi
candidate="$release/docker-compose.yml"
if [[ "$compose_changed" == false ]]; then candidate="$base/docker-compose.yml"; fi
candidate_env="$release/.deploy.env"
touched=false
dc() { docker compose --project-directory "$base" --env-file "$candidate_env" -f "$candidate" "$@"; }
old_dc() { docker compose --project-directory "$base" --env-file "$base/.env" -f "$base/docker-compose.yml" "$@"; }
cleanup() {
    code=$?
    trap - EXIT
    [[ "$key_file" == /dev/null ]] || rm -f "$key_file"
    if (( code != 0 )) && [[ "$touched" == true ]]; then
        dc stop qlhvk1 || true
        if [[ "$old_ready" == true ]]; then
            old_dc up -d --no-build qlhvk1 || true
            echo "Deploy lỗi: đã yêu cầu chạy lại image/cấu hình cũ; AppData được giữ nguyên." >&2
        else
            echo "Deploy đầu chưa hoàn tất; giữ AppData để chạy lại, không nhập đè." >&2
        fi
    fi
    exit "$code"
}
trap cleanup EXIT

if [[ "$app_changed" == true || "$compose_changed" == true ]]; then
    if [[ "$app_changed" == true ]]; then
        printf 'QLHV_IMAGE_TAG=%s\nQLHV_BUILD_CONTEXT=%s\n' "$deploy_id" "$release" > "$candidate_env"
    else
        cp "$base/.env" "$candidate_env"
    fi
    dc config --quiet
    # Build xong mới dừng ứng dụng đang chạy.
    if [[ "$app_changed" == true ]]; then dc build --pull qlhvk1; fi
    python3 "$release/deploy/scripts/import-initial-data.py" "$release/deploy/seed" "$data" "$key_file"
    [[ "$key_file" == /dev/null ]] || rm -f "$key_file"
    touched=true
    if [[ "$old_ready" == true ]]; then old_dc stop -t 30 qlhvk1; fi
    # Sao lưu khi không còn tiến trình ứng dụng ghi SQLite, bao gồm DB, WAL, keys và marker.
    tar -czf "/var/backups/qlhvk1/AppData-before-$deploy_id.tar.gz" -C "$(dirname "$data")" AppData
    image=$(python3 - "$candidate_env" <<'PY'
import sys
from pathlib import Path
values = dict(line.split("=", 1) for line in Path(sys.argv[1]).read_text().splitlines() if "=" in line)
print("qlhvk1:" + values["QLHV_IMAGE_TAG"])
PY
)
    app_uid=$(docker run --rm --entrypoint id "$image" -u)
    app_gid=$(docker run --rm --entrypoint id "$image" -g)
    chown -R "$app_uid:$app_gid" "$data"
    chmod 700 "$data"
    # Marker trong accounts.db bảo đảm lệnh này chỉ đổi mật khẩu đúng một lần.
    dc run --rm --no-deps -T qlhvk1 --deployment-initialize
    dc up -d --no-build qlhvk1
    healthy=false
    for ((attempt=0; attempt<60; attempt++)); do
        if curl --fail --silent --max-time 3 http://127.0.0.1:8989/health >/dev/null; then
            healthy=true; break
        fi
        sleep 2
    done
    [[ "$healthy" == true ]] || { echo "Ứng dụng không qua healthcheck." >&2; exit 1; }
fi

# Tự so hash với lần triển khai thành công trên server để xử lý cả việc chạy lại workflow lỗi.
bash "$release/deploy/scripts/update-nginx.sh" "$release/deploy/nginx/k1qlhv.conf"
if [[ "$app_changed" == true || "$compose_changed" == true ]]; then
    if [[ "$compose_changed" == true ]]; then
        install -m 0600 "$release/docker-compose.yml" "$base/docker-compose.yml"
    fi
    install -m 0600 "$candidate_env" "$base/.env"
    if [[ "$app_changed" == true ]]; then
        ln -sfn "$release" "$base/.current-next"
        mv -Tf "$base/.current-next" "$base/current"
    fi
fi
printf '%s\n' "$deploy_id" > "$base/state/last-successful-deploy"
touched=false
echo "Deploy hoàn tất. AppData: /var/lib/qlhvk1/AppData"
echo "Mật khẩu lần đầu: root đọc /var/lib/qlhvk1/AppData/tai-khoan-server.txt; không in vào Actions."
