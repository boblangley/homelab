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
# BAO_* as well: bao prefers them, and a devcontainer may set BAO_ADDR to its Wyrwood socket.
set -x BAO_ADDR https://openbao.internal:8200
set -x BAO_TOKEN $token
set -x VAULT_ADDR $BAO_ADDR
set -x VAULT_TOKEN $token
set -e token

# 0: stored; 1: not stored; 2: OpenBao refused or couldn't be reached (error printed). A failed read must never be
# taken for "not stored", which would go on to create and overwrite.
function kv_exists -a p
    set err (bao kv get -namespace=wyrwood -mount=kv $p 2>&1 >/dev/null)
    and return 0
    string match --quiet '*No value found*' -- "$err"; and return 1
    printf '%s\n' $err >&2
    return 2
end
for u in $users
    set path homelab/clickhouse/$u
    kv_exists $path
    switch $status
        case 0
            echo "$u: already in OpenBao, kept"
            continue
        case 2
            echo "$u: can't read $path from $BAO_ADDR; stopping."
            set -e BAO_TOKEN VAULT_TOKEN
            exit 1
    end
    # 40 characters from [A-Za-z0-9]: safe in XML, URLs and connection strings.
    set pw (openssl rand -base64 60 | string join '' | string replace --all --regex '[^A-Za-z0-9]' '' | string sub --length 40)
    if test (string length -- $pw) -ne 40
        echo "$u: couldn't generate a password; stopping."
        set -e BAO_TOKEN VAULT_TOKEN pw
        exit 1
    end
    bao kv put -namespace=wyrwood -mount=kv $path password=$pw >/dev/null
    set stored (bao kv get -namespace=wyrwood -mount=kv -field=password $path)
    if test "$stored" = "$pw"
        echo "$u: created (length 40)"
    else
        echo "$u: read-back differs; stopping."
        set -e BAO_TOKEN VAULT_TOKEN pw stored
        exit 1
    end
    set -e pw stored
end
set -e BAO_TOKEN VAULT_TOKEN
