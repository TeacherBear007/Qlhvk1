#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
source_file=$1
state_dir=/opt/qlhvk1/state
site=/etc/nginx/sites-available/k1qlhv
enabled=/etc/nginx/sites-enabled/k1qlhv
domain=qlhvk1.hoanganhplus01.io.vn
mkdir -p "$state_dir"
hash=$(sha256sum "$source_file" | cut -d' ' -f1)
old_hash=$(cat "$state_dir/nginx.sha256" 2>/dev/null || true)
if [[ "$hash" == "$old_hash" && -f "$site" && -L "$enabled" ]] &&
   [[ "$(readlink -f "$enabled")" == "$site" ]] &&
   [[ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
    echo "Nginx không đổi: giữ cấu hình HTTPS do Certbot quản lý."
    exit 0
fi
nginx -t
backup=$(mktemp -d "$state_dir/nginx-before.XXXXXX")
[[ ! -e "$site" && ! -L "$site" ]] || cp -a "$site" "$backup/site"
[[ ! -e "$enabled" && ! -L "$enabled" ]] || cp -a "$enabled" "$backup/enabled"
rollback() {
    code=$?
    trap - EXIT
    if (( code != 0 )); then
        rm -f "$site" "$enabled"
        [[ ! -e "$backup/site" && ! -L "$backup/site" ]] || cp -a "$backup/site" "$site"
        [[ ! -e "$backup/enabled" && ! -L "$backup/enabled" ]] || cp -a "$backup/enabled" "$enabled"
        if nginx -t; then systemctl reload nginx; fi
        echo "Cập nhật Nginx/Certbot lỗi; đã khôi phục site trước đó." >&2
    fi
    exit "$code"
}
trap rollback EXIT
# Chỉ thay site khi template thay đổi hoặc site bị thiếu.
if [[ "$hash" != "$old_hash" || ! -f "$site" ]]; then
    install -m 0644 "$source_file" "$site"
fi
ln -sfn "$site" "$enabled"
nginx -t
systemctl reload nginx
# Certbot tự thêm cấu hình SSL và redirect. Chứng chỉ còn hạn được dùng lại.
certbot --nginx --non-interactive --agree-tos \
    --email anhoanganh7777@gmail.com \
    --domain "$domain" --cert-name "$domain" --redirect --keep-until-expiring
nginx -t
systemctl reload nginx
printf '%s\n' "$hash" > "$state_dir/nginx.sha256"
echo "Đã cập nhật k1qlhv, symlink và HTTPS."
