#!/bin/sh
#
# Rewrite the commit authors in the SVN log.
# This script requires access to the server repository. It does not work on
# working copies.
#
# As always it is recommended to create a backup _before_ running this script!
#
# usage example: update-authors.sh /var/lib/svn/repos svn_user.map
#
# The map file (svn_user.map) provides the mapping from old to new user names.
# The file contains one mapping per line. Each line consists of the old user
# name and the new user name separated by white space.
# 
# e.g.:
# 
# john jdoe
# peter pmuster
# hans hvader
#
set -e -u

repo_path=${1:?'missing repo'}
user_map=${2:?'missing user map'}

export repo_path user_map

command -v svnadmin >/dev/null 2>&1 || {
	printf '%s: No such command\n' svnadmin >&2
	exit 1
}
command -v svnlook >/dev/null 2>&1 || {
	printf '%s: No such command\n' svnlook >&2
	exit 1
}
test -d "${repo_path:?}" || {
	printf '%s: No such directory\n' "${repo_path}"
	exit 1
}
test -s "${user_map:?}" || {
	printf '%s: No such file\n' "${user_map}"
	exit 1
}

_cleanup() {
	rm -f "${repo_path:?}/.prop.tmp"
}
trap _cleanup EXIT

lastrev=$(svnlook youngest "${repo_path:?}")

test $((lastrev)) -gt 0 \
&& svnlook info -r $((lastrev)) "${repo_path:?}" >/dev/null \
|| {
	echo 'Failed to determine latest revision' >&2
	exit 1
}

rev=0
while test $((rev+=1)) -le $((lastrev))
do
	rev_author=$(svnlook author -r $((rev)) "${repo_path:?}") 
	printf '%u %s\n' $((rev)) "${rev_author}"
done \
| awk '
  BEGIN {
	  while ((getline < ENVIRON["user_map"])) {
		  user_map[$1] = $2
	  }
  }

  {
	  rev = $1
	  old_author = substr($0, index($0, " ")+1)

	  if ((old_author in user_map) && old_author != user_map[old_author])
		  printf "%u %s\n", rev, user_map[old_author] 
  }
  ' \
| while read -r rev new_author
  do
	  printf '%s' "${new_author}" >"${repo_path:?}/.prop.tmp"
	  svnadmin setrevprop "${repo_path}" -r $((rev)) svn:author "${repo_path:?}/.prop.tmp" </dev/null
  done
