# usage: pass 2fa your_secret
#
# it will print the current TOTP code the secret is already stored in pass.
# Otherwise it will ask for the secret and store it in pass.

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || exit 1

PASS=${PROGRAM:-pass}

command -v oathtool >/dev/null 2>&1 || {
	printf 'Cannot find oathtool.\n' >&2
	exit 1
}

case $1
in
	(*/*) secret_path="${1%/*}/.2fa.${1##*/}" ;;
	(*) secret_path=".2fa.${1}" ;;
esac
secret_file="${PREFIX}/${secret_path}.gpg"

if test -f "${secret_file}"
then
	"${GPG}" "${GPG_OPTS[@]}" --quiet --decrypt "${secret_file}" \
	| head -n1 \
	| oathtool --totp --base32 -
else
	printf 'No such secret found: %s\n' "$1" >&2
	printf 'Creating a new one. Please paste the secret presented to you by the application.\n' >&2
	PASSWORD_STORE_DIR=${PREFIX} "${PASS}" insert "${secret_path}"
fi
