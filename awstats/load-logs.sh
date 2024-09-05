#!/bin/sh
#
# Update awstats statictics for a given configuration with the given web server
# log files.
#
# usage: sh load-logs.sh awstats_config_name /var/log/apache2/myvhost.access.log*
#
set -e -u

awstats_installdir=/usr/share/awstats
www_user=www-data


shquot() {
	# source: https://github.com/riiengineering/shfun/blob/main/lib/quote/shquot.sh
sed -e "s/'/'\\\\''/g" -e "1s/^/'/" -e "\$s/\$/'/" <<EOF
$*
EOF
}

awstats_update() {
	_config=${1:?}
	shift

	printf 'awstats update %s from %s\n' "${_config}" "$*"

	"${awstats_installdir:?}"/tools/logresolvemerge.pl "$@" \
	| su -s /bin/sh - "${www_user:?}" -c "awstats -config=$(shquot "${_config}") -update -LogFile='cat |'"

	unset -v _config
}


config=${1:?'no config name'}
shift

awstats_update "${config:?}" "$@"