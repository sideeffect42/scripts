#!/bin/sh
#
# Merges Apache httpd log files from different directories (e.g. backups).
#
# usage: sh merge-www-logs.sh source-directory destination-directory
#
# This script assumes that the sets of log files are stored in sub-directories
# of the given source-directory and that the sub-directories' names are in
# chronological order when sorted lexicographically (according to LC_COLLATE as
# specified by POSIX).
# All log files named access.log and [vhost].access.log including the common
# logrotate(8) forms of it (i.e. .log.n and .log.n.gz) are processed.
#
# This script will store the merged log files in the given
# destination-directory.
#
set -e -u

awstats_installdir=/usr/share/awstats

incr() { eval ": \$(($1+=1))"; }

zmv() {
	# NOTE: this function only works with two operands!
	printf 'gunzip %s -> %s\n' "$1" "$2"
	zcat "$1" >"$2"
}

SRC_DIR=${1:?}
DST_DIR=${2:?}

# merge directories
for d in "${SRC_DIR:?}"/*
do
	test -d "${d}" || continue
	incr i

	printf 'merging in log directory "%s" (%u)\n' "${d}" $((i))

	for f in "${d:?}"/access.log "${d:?}"/*.access.log
	do
		test -f "${f}" || continue
		mv -v "${f}" "${DST_DIR:?}/$(basename "${f%.log}")_$((i))_0.log"
	done
	for f in "${d:?}"/access.log.*[0-9] "${d:?}"/*.access.log.*[0-9]
	do
		test -f "${f}" || continue
		mv -v "${f}" "${DST_DIR:?}/$(basename "${f%.log*}")_$((i))_${f##*.}.log"
	done
	for f in "${d:?}"/access.log.*[0-9].gz "${d:?}"/*.access.log.*[0-9].gz
	do
		test -f "${f}" || continue
		f=${f%.gz}

		zmv "${f}.gz" "${DST_DIR:?}/$(basename "${f%.log*}")_$((i))_${f##*.}.log"
	done
	unset -v f
done
unset -v d

# dedup
printf '\ndeduplicating log files\n'
while read -r crc sz file
do
	case ${last_cksum-}
	in
		("${crc}${sz}"*)
			printf 'duplicate of %s: ' "${last_cksum#* }"
			rm -v "${file}"
			continue
			;;
		(*)
			last_cksum="${crc}${sz} ${file}"

			# update mtime to first log timestamp
			btime=$(sed -n \
				-e 's/^.*\[\([^:]*:[^]]* [+-][0-9]\{4\}\)\].*$/\1/' \
				-e 's|/| |g' \
				-e 's/:/ /' \
				-e 'p' \
				-e 'q' \
				"${file}")
			touch -c --date="${btime}" "${file}"
			;;
	esac
done <<EOF
$(cksum "${DST_DIR:?}"/*.log | sort -t ' ' -k 1,2n -k 3)
EOF
unset -v crc sz file last_cksum


# report number of requests per day
printf '\ncounting logged requests per day (QA)…\n'
cat "${DST_DIR:?}"/*.log \
| sed -n -e 's/^.*\[\([^:]*\):[^]]* [+-][0-9]\{4\}\].*$/\1/p' \
| awk '{ x[$0]++ } END { for (k in x) printf "%s %u" RS, k, x[k] }' \
| sort -k 1.8,1.12n -k 1.4,1.7M -k 1.1,1.2n


# resolve log files
printf '\nmerging together log files…\n'
while read -r log_stem
do
	printf 'logresolve: %s\n' "${log_stem}"

	"${awstats_installdir:?}"/tools/logresolvemerge.pl \
		"${DST_DIR:?}/${log_stem}${log_stem:+.}"access_*.log \
	| tee "${DST_DIR:?}/${log_stem}${log_stem:+.}access.log" \
	| awk 'END { printf "%u records" RS, NR }'

	rm -f "${DST_DIR:?}/${log_stem}${log_stem:+.}"access_*.log
done <<EOF
$(ls -1 "${DST_DIR:?}"/*.log | sed -e 's|.*/||' -e 's/\(^\|\.\)access.*$//' | sort -u)
EOF
