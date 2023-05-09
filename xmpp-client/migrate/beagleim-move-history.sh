#!/bin/sh
set -e -u

# only use system utilities
_PATH=$(command -p getconf PATH) \
&& test -n "${_PATH}" \
&& PATH=${_PATH}
unset -v _PATH

db=~/Library/Containers/org.tigase.messenger.BeagleIM/Data/Library/Application\ Support/BeagleIM/beagleim.sqlite

test -f "${db}" || {
	echo 'are you really using Beagle IM?' >&2
	exit 1
}

test $# -eq 2 || {
	printf 'usage: %s [old jid] [new jid]\n' "$0" >&2
	exit 1
}

! pgrep -i BeagleIM | grep -q . || {
	printf 'please close BeagleIM first.\n' >&2
	exit 1
}

old_account=${1:?}
new_account=${2:?}

tmp_db=$(mktemp "${db}.XXXXXX")

sqlite3 "${db}" ".backup '${tmp_db}'"

for tc in \
	chat_markers:jid \
	chat_markers:sender_jid \
	omemo_sessions:name
do
	sqlite3 "${tmp_db}" "UPDATE ${tc%%:*} SET ${tc#*:} = '${new_account}' WHERE account = '${old_account}' AND ${tc#*:} = '${old_account}';"
done

for tbl in \
	chat_history \
	chat_markers \
	omemo_identities \
	omemo_pre_keys \
	omemo_sessions \
	omemo_signed_pre_keys \
	roster_items
do
	sqlite3 "${tmp_db}" "UPDATE ${tbl} SET account = '${new_account}' WHERE account = '${old_account}';"
done

mv -n -v "${db}" "${db}.bak"
test -f "${db}-shm" && mv -n -v "${db}-shm" "${db}.bak-shm"
test -f "${db}-wal" && mv -n -v "${db}-wal" "${db}.bak-wal"

mv -n -v "${tmp_db}" "${db}"
test -f "${tmp_db}-shm" && mv -n -v "${tmp_db}-shm" "${db}-shm"
test -f "${tmp_db}-wal" && mv -n -v "${tmp_db}-wal" "${db}-wal"