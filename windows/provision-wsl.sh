#!/usr/bin/env bash
set -euo pipefail

user="$1"
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends ca-certificates curl sudo xz-utils

if ! id "$user" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$user"
  usermod -aG sudo "$user"
  touch "/home/$user/.dotfiles-needs-password"
fi

config="$(realpath /etc/wsl.conf)"
updated="$(mktemp "${config}.XXXXXX")"
trap 'rm -f -- "$updated"' EXIT

cat >"$updated" <<CONF
[boot]
systemd=true

[user]
default=$user
CONF

if [[ -e "$config" ]]; then
  status=0
  cmp -- "$config" "$updated" >/dev/null || status=$?
  case "$status" in
    0) exit 0 ;;
    1) ;;
    *) exit "$status" ;;
  esac

  backup="$(mktemp /etc/wsl.conf.before-dotfiles-XXXXXXXX)"
  cp -p -- "$config" "$backup"
  chown --reference="$config" "$updated"
  chmod --reference="$config" "$updated"
else
  chmod 0644 "$updated"
fi

mv -fT -- "$updated" "$config"
exit 10
