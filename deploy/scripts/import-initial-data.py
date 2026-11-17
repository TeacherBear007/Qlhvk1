#!/usr/bin/env python3
"""Nhập bản AppData mã hóa duy nhất khi thư mục đích chưa có dữ liệu."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import tarfile
import tempfile

seed, target, key = map(Path, sys.argv[1:4])
# Không copy đè, không gộp dữ liệu mẫu vào dữ liệu đang chạy trên server.
if target.exists() and any(target.iterdir()):
    if not all((target / name).is_file() for name in ("accounts.db", "business.db")):
        raise SystemExit("AppData đã có dữ liệu nhưng thiếu database: dừng, không ghi đè.")
    print("Giữ nguyên AppData hiện có; bỏ qua bản dữ liệu ban đầu.")
    sys.exit(0)
if not key.is_file() or not key.read_text().strip():
    raise SystemExit("Lần triển khai đầu cần GitHub Secret INITIAL_DATA_KEY.")
target.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix=".qlhvk1-import-", dir=target.parent) as work:
    work = Path(work)
    archive = work / "appdata.tar.gz"
    subprocess.run([
        "openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2", "-iter", "200000",
        "-in", str(seed / "appdata.tar.gz.enc"), "-out", str(archive),
        "-pass", "file:" + str(key)
    ], check=True)
    expected = (seed / "appdata.sha256").read_text().split()[0]
    if hashlib.sha256(archive.read_bytes()).hexdigest() != expected:
        raise SystemExit("Bản dữ liệu giải mã không đúng checksum; không nhập.")
    stage = work / "AppData"
    stage.mkdir(mode=0o700)
    with tarfile.open(archive, "r:gz") as source:
        # Chỉ nhận file/thư mục bên trong AppData; không symlink, hardlink hoặc đường dẫn vượt ra ngoài.
        for member in source.getmembers():
            relative = Path(member.name)
            if relative.is_absolute() or ".." in relative.parts or not (member.isfile() or member.isdir()):
                raise SystemExit("Tệp dữ liệu chứa đường dẫn hoặc kiểu tệp không hợp lệ.")
        source.extractall(stage)
    manifest = json.loads((stage / ".qlhvk1-seed.json").read_text())
    if manifest.get("project") != "qlhvk1" or manifest.get("format") != 1:
        raise SystemExit("Sai phiên bản bản dữ liệu.")
    for database, expected_tables in manifest["tables"].items():
        if database not in ("accounts.db", "business.db"):
            raise SystemExit("Sai tên database.")
        with sqlite3.connect("file:" + str(stage / database) + "?mode=ro", uri=True) as db:
            if db.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
                raise SystemExit("Database lỗi integrity_check.")
            for table, count in expected_tables.items():
                quoted = '"' + table.replace('"', '""') + '"'
                if db.execute("SELECT COUNT(*) FROM " + quoted).fetchone()[0] != count:
                    raise SystemExit("Số bản ghi không khớp bản localhost.")
    for entry in stage.rglob("*"):
        entry.chmod(0o700 if entry.is_dir() else 0o600)
    if target.exists():
        target.rmdir()  # Chỉ xóa thư mục RỖNG; có dữ liệu phát sinh thì dừng.
    stage.rename(target)  # Cùng filesystem: chuyển cả bộ dữ liệu sau khi kiểm tra thành công.
print("Đã nhập đủ AppData localhost; các lần deploy sau không nhập lại.")
