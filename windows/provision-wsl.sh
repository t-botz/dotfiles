#!/usr/bin/env bash
set -euo pipefail

user="$1"
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends ca-certificates curl python3 sudo xz-utils

if ! id "$user" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$user"
  usermod -aG sudo "$user"
  touch "/home/$user/.dotfiles-needs-password"
fi

python3 - "$user" <<'PY'
import configparser
import io
from pathlib import Path
import sys
import uuid

path = Path("/etc/wsl.conf")
before = path.read_text() if path.exists() else ""
config = configparser.ConfigParser(interpolation=None)
config.read_string(before)

changed = False
for section, key, value in [("boot", "systemd", "true"), ("user", "default", sys.argv[1])]:
    if config.get(section, key, fallback=None) != value:
        if not config.has_section(section):
            config.add_section(section)
        config.set(section, key, value)
        changed = True

if changed:
    if path.exists():
        backup = path.with_name(path.name + ".before-dotfiles-" + uuid.uuid4().hex)
        backup.write_text(before)
    output = io.StringIO()
    config.write(output)
    path.write_text(output.getvalue())
    sys.exit(10)
PY
