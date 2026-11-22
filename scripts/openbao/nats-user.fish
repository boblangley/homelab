#!/usr/bin/env fish
# Adds one NATS user to account APP, with its permissions in its user JWT, and stores its .creds in OpenBao
# (namespace wyrwood, kv homelab/nats/<name>, field creds). The nsc stores and keys come from homelab/nats/nsc (made
# by nats-bootstrap.fish), are used in a throwaway nats-box container whose working directory is in memory, and go
# back with the new user. Its output passes through a 0700 directory in /dev/shm and is shredded there. The server
# needs no change: it trusts any user that APP signs.
#
# Adds a user; a user that exists is refused. With --update it instead widens a user that exists: the subjects are
# added to its allow lists and a new JWT is issued for the same key, which the user's next connection uses (restart
# the service). --update only adds; it refuses a direction that has no allow list, where adding would restrict a user
# that is unrestricted there (admin, workspace). The old JWT stays valid with its narrower permissions, so widening needs nothing else. Narrowing an
# existing user means revoking its old JWT in the account (nsc revocations), which changes the account JWT in
# homelab/nats/server and restarts NATS on the next Apply.
#
# Subjects are comma-separated. Without --pub or --sub a new user is unrestricted in that direction.
#   fish scripts/openbao/nats-user.fish <name> [--pub 'a.>,$JS.API...'] [--sub '_INBOX.>']
#   fish scripts/openbao/nats-user.fish <name> --update [--pub SUBJECTS] [--sub SUBJECTS]

argparse 'pub=' 'sub=' update -- $argv; or exit 2
set name $argv[1]
# One name and nothing else: a stray word (an unquoted second subject, say) is refused, not dropped.
if test (count $argv) -ne 1; or not string match --quiet --regex '^[a-z][a-z0-9_-]{0,62}$' -- "$name"
    echo "usage: fish scripts/openbao/nats-user.fish <name> [--update] [--pub SUBJECTS] [--sub SUBJECTS]"
    exit 2
end
if set -q _flag_update; and test -z "$_flag_pub$_flag_sub"
    echo "--update needs --pub or --sub: the subjects to add"
    exit 2
end

read --silent --prompt-str 'OpenBao root token: ' token
# BAO_* as well: bao prefers them, and a devcontainer may set BAO_ADDR to its Wyrwood socket.
set -x BAO_ADDR https://openbao.internal:8200
set -x BAO_TOKEN $token
set -x VAULT_ADDR $BAO_ADDR
set -x VAULT_TOKEN $token
set -e token
function kv
    bao kv $argv[1] -namespace=wyrwood -mount=kv $argv[2..]
end
function fail
    echo $argv
    set -e -g BAO_TOKEN VAULT_TOKEN
    exit 1
end

set store (kv get -field=tgz homelab/nats/nsc 2>/dev/null)
test -n "$store"; or fail "homelab/nats/nsc has no tgz; run nats-bootstrap.fish first."

set inner '
set -eu
export HOME=/nsc NKEYS_PATH=/nsc/keys NSC_HOME=/nsc/nsc
base64 -d | tar xz -C /nsc
nsc env -s /nsc/stores >/dev/null 2>&1
if nsc describe user -a APP -n "$NATS_USER" >/dev/null 2>&1; then
  [ -n "${NATS_UPDATE:-}" ] || { echo "exists" >&2; exit 3; }
  # An allow list only grows; on a direction with none (unrestricted) it would start one and restrict the user.
  nats=$(nsc describe user -a APP -n "$NATS_USER" --json | jq -c .nats)
  [ -z "${NATS_PUB:-}" ] || [ "$(echo "$nats" | jq ".pub.allow // [] | length")" -gt 0 ] || { echo "pub unrestricted" >&2; exit 5; }
  [ -z "${NATS_SUB:-}" ] || [ "$(echo "$nats" | jq ".sub.allow // [] | length")" -gt 0 ] || { echo "sub unrestricted" >&2; exit 5; }
  set -- edit user -a APP -n "$NATS_USER"
else
  [ -z "${NATS_UPDATE:-}" ] || { echo "missing" >&2; exit 4; }
  set -- add user -a APP "$NATS_USER"
fi
[ -n "${NATS_PUB:-}" ] && set -- "$@" --allow-pub "$NATS_PUB"
[ -n "${NATS_SUB:-}" ] && set -- "$@" --allow-sub "$NATS_SUB"
nsc "$@" >/dev/null 2>&1
mkdir -p /nsc/out
nsc generate creds -a APP -n "$NATS_USER" -o /nsc/out/user.creds >/dev/null 2>&1
tar czf /nsc/out/nsc.tgz -C /nsc stores keys nsc
tar cz -C /nsc/out . | base64 | tr -d "\n"
'

set work (mktemp -d /dev/shm/nats-user.XXXXXX)
chmod 0700 $work
set bundle (printf '%s' $store | docker run --rm -i --tmpfs /nsc:mode=0700 \
    -e "NATS_USER=$name" -e "NATS_PUB=$_flag_pub" -e "NATS_SUB=$_flag_sub" -e "NATS_UPDATE=$_flag_update" \
    natsio/nats-box:0.20.2 sh -c $inner)
set rc $status
set -e store
if test $rc -eq 3
    rmdir $work
    fail "user $name exists already; nothing changed. To add subjects to it, use --update."
end
if test $rc -eq 4
    rmdir $work
    fail "user $name doesn't exist; nothing changed. To add it, leave out --update."
end
if test $rc -eq 5
    rmdir $work
    fail "user $name has no allow list in a direction you gave; --update would restrict it, so nothing changed."
end
if test $rc -ne 0; or test -z "$bundle"
    rmdir $work
    fail "nsc failed; nothing changed."
end
printf '%s' $bundle | base64 -d | tar xz -C $work
set -e bundle
if not test -s $work/user.creds; or not test -s $work/nsc.tgz
    shred -u $work/* 2>/dev/null; rmdir $work
    fail "nsc didn't produce the creds or the store; nothing changed."
end

set bad 0
base64 -w0 $work/nsc.tgz > $work/nsc.b64
kv put homelab/nats/$name creds=@$work/user.creds >/dev/null; or set bad 1
kv put homelab/nats/nsc tgz=@$work/nsc.b64 >/dev/null; or set bad 1
function same
    test (printf '%s' (kv get -field=$argv[2] $argv[1]) | sha256sum | string sub --length 64) = (printf '%s' (cat $argv[3]) | sha256sum | string sub --length 64)
end
same homelab/nats/$name creds $work/user.creds; or set bad 1
same homelab/nats/nsc tgz $work/nsc.b64; or set bad 1
shred -u $work/*
rmdir $work

if test $bad -eq 0
    set verb added
    set -q _flag_update; and set verb updated
    echo "$verb $name: creds at homelab/nats/$name, homelab/nats/nsc updated"
else
    echo "something failed or read back DIFFERENT; check homelab/nats/$name and homelab/nats/nsc"
end
set -e -g BAO_TOKEN VAULT_TOKEN
