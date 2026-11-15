#!/usr/bin/env fish
# Creates a random password for each ClickHouse user named and stores it in OpenBao (namespace wyrwood,
# kv homelab/clickhouse/<user>, field password), where role clickhouse reads it. Declare the user, with its grants, in
# clickhouse_users. A user already in OpenBao is kept. Prints nothing secret.
#   fish scripts/openbao/clickhouse-users.fish <user> [<user>...]

set users $argv
if test (count $users) -eq 0
    echo "usage: fish scripts/openbao/clickhouse-users.fish <user> [<user>...]"
    exit 2
end

read --silent --prompt-str 'OpenBao root token: ' token
set -x VAULT_ADDR https://openbao.internal:8200
set -x VAULT_TOKEN $token
set -e token

for u in $users
    set path homelab/clickhouse/$u
    if bao kv get -namespace=wyrwood -mount=kv -field=password $path >/dev/null 2>&1
        echo "$u: already in OpenBao, kept"
        continue
    end
    # 40 characters from [A-Za-z0-9]: safe in XML, URLs and connection strings.
    set pw (openssl rand -base64 60 | string join '' | string replace --all --regex '[^A-Za-z0-9]' '' | string sub --length 40)
    if test (string length -- $pw) -ne 40
        echo "$u: couldn't generate a password; stopping."
        set -e VAULT_TOKEN pw
        exit 1
    end
    bao kv put -namespace=wyrwood -mount=kv $path password=$pw >/dev/null
    set stored (bao kv get -namespace=wyrwood -mount=kv -field=password $path)
    if test "$stored" = "$pw"
        echo "$u: created (length 40)"
    else
        echo "$u: read-back differs; stopping."
        set -e VAULT_TOKEN pw stored
        exit 1
    end
    set -e pw stored
end
set -e VAULT_TOKEN
