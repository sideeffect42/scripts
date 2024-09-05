#!/bin/sh

lang=en
awstats_installdir=/usr/share/awstats
awstats_datadir=/var/lib/awstats
awstats_htmloutdir=/var/cache/awstats
www_user=www-data

shquot() {
	# source: https://github.com/riiengineering/shfun/blob/main/lib/quote/shquot.sh
sed -e "s/'/'\\\\''/g" -e "1s/^/'/" -e "\$s/\$/'/" <<EOF
$*
EOF
}

renderstatic() {
	_config=${1:?}
	_year=${2-$(date +%Y)}
	_month=${3-$(date +%m)}

	_outdir=$(printf '%s/%s/%04u/%02u' "${awstats_htmloutdir:?}" "${config}" $((year)) $((month)))

	if test -d "${_outdir}"
	then
		rm -R -f "${_outdir}"
	fi

	su -s /bin/sh - "${www_user:?}" -c "mkdir -p $(shquot "${_outdir}") && $(shquot "${awstats_installdir:?}")/tools/awstats_buildstaticpages.pl -config=$(shquot "${_config}") -year=$((year)) -month=$((month)) -lang=$(shquot "${lang}") -staticlinksext=$(shquot "${lang}.html") -dir=$(shquot "${_outdir}")"
	ln -fs "${_outdir:?}/awstats.${config:?}.${lang:?}.html" "${_outdir:?}/index.${lang:?}.html"
}

for config in 
	$(test -f /etc/awstats/awstats.conf && echo awstats) \
	$(cd /etc/awstats && ls -1 awstats.*.conf 2>/dev/null \
		| sed -e 's/^awstats\.\(.*\)\.conf$/\1/')
do
	for f in "${awstats_datadir:?}"/awstats[0-9][0-9][0-9][0-9][0-9][0-9]."${config:?}".txt
	do
		test -f "${f}" || continue

		f=${f##*/awstats}; f=${f%.${config}.txt}
		year=${f#[0-9][0-9]}
		month=${f%${year}}

		printf 'rendering %s (%04u-%02u)\n' "${config}" $((year)) $((month))

		renderstatic "${config}" "${year}" "${month}" || {
			printf 'rendering failed.\n' >&2
			continue
		}
	done
done
