#!/bin/sh
set -e -u

if test $# -ne 2
then
	printf 'usage: %s [old jid] [new jid]\n' "$0" >&2
	exit 1
fi

old_jid=${1:?}
new_jid=${2:?}

conf_dir=~/.local/share/dino

test -d "${conf_dir-}" || {
	echo 'is dino installed?' >&2
	exit 1
}

! pidof dino | grep -q . || {
	echo 'quit dino before running this script' >&2
	exit 1
}

set -x

old_account_id=$(sqlite3 "${conf_dir}/dino.db" "SELECT id FROM account WHERE bare_jid = '${old_jid}';")

tmp_dino_db=$(mktemp "${conf_dir}/dino.db.XXXXXX")

sqlite3 "${conf_dir}/dino.db" ".backup ${tmp_dino_db}"

sqlite3 "${tmp_dino_db}" "UPDATE account SET bare_jid = '${new_jid}' WHERE bare_jid = '${old_jid}';"

mv -n -v "${conf_dir}/dino.db" "${conf_dir}/dino.db.bak"
test -f "${conf_dir}/dino.db-shm" && mv -n -v "${conf_dir}/dino.db-shm" "${conf_dir}/dino.db.bak-shm"
test -f "${conf_dir}/dino.db-wal" && mv -n -v "${conf_dir}/dino.db-wal" "${conf_dir}/dino.db.bak-wal"

mv -n -v "${tmp_dino_db}" "${conf_dir}/dino.db"
test -f "${tmp_dino_db}-shm" && mv -n -v "${tmp_dino_db}-shm" "${conf_dir}/dino.db-shm"
test -f "${tmp_dino_db}-wal" && mv -n -v "${tmp_dino_db}-wal" "${conf_dir}/dino.db-wal"
