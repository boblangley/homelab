#!/usr/bin/env fish
# Adds one NATS user to account APP, with its permissions in its user JWT, and stores its .creds in OpenBao
# (namespace wyrwood, kv homelab/nats/<name>, field creds). The nsc stores and keys come from homelab/nats/nsc (made
# by nats-bootstrap.fish), are used in a throwaway nats-box container whose working directory is in memory, and go
# back with the new user. Its output passes through a 0700 directory in /dev/shm and is shredded there. The server
# needs no change: it trusts any user that APP signs.
#
# Only adds: a user that exists is refused. Narrowing an existing user means revoking its old JWT in the account
# (nsc revocations), which changes the account JWT in homelab/nats/server and restarts NATS on the next Apply.
#
# Subjects are comma-separated. Without --pub or --sub the user is unrestricted in that direction.
#   fish scripts/openbao/nats-user.fish <name> [--pub 'a.>,$JS.API...'] [--sub '_INBOX.>']

argparse 'pub=' 'sub=' -- $argv; or exit 2
set name $argv[1]
if not string match --quiet --regex '^[a-z][a-z0-9_-]{0,62}$' -- "$name"
    echo "usage: fish scripts/openbao/nats-user.fish <name> [--pub SUBJECTS] [--sub SUBJECTS]"
    exit 2
end

read --silent --prompt-str 'OpenBao root token: ' token
set -x VAULT_ADDR https://openbao.internal:8200
set -x VAULT_TOKEN $token
set -e token
function kv
    bao kv $argv[1] -namespace=wyrwood -mount=kv $argv[2..]
end
function fail
    echo $argv
    set -e -g VAULT_TOKEN
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
  echo "exists" >&2; exit 3
fi
set -- add user -a APP "$NATS_USER"
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
    -e NATS_USER=$name -e NATS_PUB=$_flag_pub -e NATS_SUB=$_flag_sub \
    natsio/nats-box:0.20.2 sh -c $inner)
set rc $status
set -e store
if test $rc -eq 3
    rmdir $work
    fail "user $name exists already; nothing changed."
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
    echo "added $name: creds at homelab/nats/$name, homelab/nats/nsc updated"
else
    echo "something failed or read back DIFFERENT; check homelab/nats/$name and homelab/nats/nsc"
end
set -e -g VAULT_TOKEN
