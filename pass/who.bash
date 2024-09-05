# usage: pass who your_secret
#
# it will print the keys which are able to decrypt this password.

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || exit 1

LC_ALL=C "${GPG}" --decrypt --list-only --verbose "${PREFIX}/$1.gpg" 2>&1 \
| sed -n -e 's/^.*public key is \([[:alnum:]]*\)$/\1/p' \
| while read -r _key
  do
	  gpg --list-keys "${_key}" 2>/dev/null || printf '%s\n\n' "${_key}"
  done
