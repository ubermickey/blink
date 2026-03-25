#!/bin/sh

set -eu

# Generate host keys
ssh-keygen -A

ensure_user() {
  user="$1"
  if ! id "$user" >/dev/null 2>&1; then
    useradd -m -d "/home/${user}" "$user"
  fi
}

prepare_ssh_dir() {
  user="$1"
  home="/home/${user}"
  mkdir -p "${home}/.ssh"
  touch "${home}/.ssh/authorized_keys"
  chmod 700 "${home}/.ssh"
  chmod 644 "${home}/.ssh/authorized_keys"
}

# no-password uses the legacy encrypted hash for compatibility.
ensure_user no-password
echo no-password:U6aMy0wojraho | chpasswd -e
prepare_ssh_dir no-password
chown -R no-password:no-password /home/no-password

ensure_user partial
echo "partial:partial" | chpasswd
prepare_ssh_dir partial
chown -R partial:partial /home/partial

ensure_user regular
echo "regular:regular" | chpasswd
prepare_ssh_dir regular
chown -R regular:regular /home/regular

# Download files for SFTP tests
# curl -X GET https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.4.99.tar.xz --output /home/no-password/linux.tar.xz
# chown no-password:no-password /home/no-password/linux.tar.xz
# chown -R no-password:no-password /home/no-password/copy_test
