#!/usr/bin/fish

if test (hostname -s) != tinomen-dev; or test (id -u) -ne 0
    echo 'Run this script with sudo on tinomen-dev.' >&2
    exit 1
end

set -l repo (path resolve (path dirname (status filename))/..)
set -l key "$repo/roles/accounts/files/ansible.pub"
set -l runner 192.168.0.10
set -l account ansible
set -l uid 1501
set -l account_home /home/ansible

ssh-keygen -lf "$key" >/dev/null; or exit 1
systemctl is-active --quiet sshd; or exit 1
if not getent group "$account" >/dev/null
    groupadd --gid "$uid" "$account"; or exit 1
end
if not getent passwd "$account" >/dev/null
    useradd --uid "$uid" --gid "$account" --home-dir "$account_home" --create-home \
        --shell /bin/bash --password '!' "$account"; or exit 1
end
if test (id -u "$account") != "$uid"; or test (id -g "$account") != "$uid"; or \
        test (getent passwd "$account" | cut -d: -f6) != "$account_home"
    echo 'The ansible account already exists with different settings.' >&2
    exit 1
end

install -d -m 0700 -o "$account" -g "$account" "$account_home/.ssh"; or exit 1
printf 'restrict,from="%s" %s\n' "$runner" (string trim < "$key") | \
    install -m 0600 -o "$account" -g "$account" /dev/stdin "$account_home/.ssh/authorized_keys"; or exit 1

set -l sudoers (mktemp); or exit 1
printf 'ansible ALL=(ALL) NOPASSWD: ALL\n' > "$sudoers"
if not visudo -cf "$sudoers"; or not install -m 0440 -o root -g root "$sudoers" /etc/sudoers.d/ansible
    rm -f "$sudoers"
    exit 1
end
rm -f "$sudoers"
ufw allow in on enp4s0 proto tcp from "$runner" to any port 22 comment 'HomeLab Actions runner'; or exit 1
runuser -u "$account" -- sudo -n true; or exit 1
echo 'HomeLab runner SSH key and passwordless sudo are installed.'
