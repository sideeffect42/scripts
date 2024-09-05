#!/bin/sh
set -u

confirm() {
	local _r
	while :
	do
		printf '%s [y/n] ' "${1:-?}"
		read -r _r
		case ${_r}
		in
			([Yy]*)
				return 0
				;;
			([Nn]*)
				return 1
				;;
			(*)
				continue
				;;
		esac
	done
}

finally() {
	__finally="${__finally:-rc=\$?}; $*"
	trap "${__finally:?}; exit \$((rc))" EXIT
}

opkg_tmp_install() {
	local p
	for p
	do
		case $(opkg list "${p}")
		in
			('')
				opkg update
				break
				;;
		esac
	done

	${*:+opkg -d ram install "$@"}
}

find_mountpoint() {
	local dev devid mounted_dev

	dev=${1:?}

	# resolve "aliases" (e.g. /dev/root)
	read -r devid <"/sys/class/block/${dev#/dev/}/dev"
	mounted_dev=$(awk -v devid="${devid}" 'devid==$3 { print $9 }' /proc/self/mountinfo)

	awk -v dev="${mounted_dev:-${dev}}" 'dev==$9 { print $5 }' /proc/self/mountinfo
}

find_rootdev() {
	local devid sysdev

	devid=$(awk -v dev='/dev/root' 'dev==$9 { print $3 }' /proc/self/mountinfo)
	sysdev=$(cd "/sys/dev/block/${devid:?}" 2>/dev/null && pwd -P)

	test -b "/dev/${sysdev##*/}" \
	&& printf '/dev/%s' "${sysdev##*/}"
}

find_overlaydev() {
	awk '"/overlay" == $5 { print $9 }' /proc/self/mountinfo
}

fstype() {
	awk -v dsk="${1:?}" '
	/^#/ { next }
	dsk == $1 || dsk == $2 {
		print $3
		exit
	}
	' /proc/self/mounts /etc/fstab
}

loop_bind() {
	local dev loopdev

	dev=${1:?}

	command -v losetup >/dev/null 2>&1 || opkg_tmp_install losetup >&2 || return 2

	loopdev=$(losetup --find) || return 1
	losetup "${loopdev}" "${dev}" || return 1

	printf '%s' "${loopdev}"
}

needs_part_resize() {
	local dev syspart sysdisk disksize rootstart rootsize rootpartno p

	dev=${1:?}

	syspart=$(cd "/sys/class/block/${dev##*/}" && pwd -P) || return 2
	sysdisk=$(cd "${syspart:?}/.." && pwd -P) || return 2

	read -r disksize <"${sysdisk:?}/size"
	read -r rootstart <"${syspart:?}/start"
	read -r rootsize <"${syspart:?}/size"

	test $((disksize)) -gt 0 || return 1
	test $((rootstart)) -gt 0 || return 1
	test $((rootsize)) -gt 0 || return 1

	# The partition needs a resize if there is more than 2 MiB (4096 * 512B) of
	# space remaining after the partition.
	if test $((rootstart + rootsize + 4096)) -ge $((disksize))
	then
		# less than 2 MiB of space left, no resize needed
		return 1
	fi

	# There is more than 2 MiB of space remaining after the root partition.
	# Check if the root partition is the last partition on the disk, because
	# it can only be resized if it is.
	read -r rootpartno <"${syspart:?}/partition"

	for p in "${sysdisk:?}"/*/partition
	do
		if test "$(cat "${p:?}")" -gt $((rootpartno))
		then
			# cannot resize, because not the last partition
			return 1
		fi
	done

	# resize needed
	return 0
}

needs_fs_resize() {
	local dev partsize fssize

	dev=${1:?}

	fssize=$(df -k "${dev}" | awk 'NR==2 { print $2 * 2 }')
	read -r partsize <"/sys/class/block/${dev##*/}/size"

	test $((fssize)) -gt 0 || return 1
	test $((partsize)) -gt 0 || return 1

	# NOTE: we need to add something to fssize to account for file system overhead
	test $((fssize + (4 * 1024 * 1024))) -lt $((partsize))
}

resize_partition() {
	local dev partnum

	dev=${1:?}
	partnum=${2:?}

	command -v parted >/dev/null 2>&1 || opkg_tmp_install parted >&2 || return 2

	parted "${dev}" resizepart $((partnum)) 100% \
	&& partprobe "${dev}"
}

fsck_ext4() {
	local fsdev

	fsdev=${1:?}

	command -v e2fsck >/dev/null 2>&1 || opkg_tmp_install e2fsprogs >&2 || return 2

	(
		if grep -qF "${fsdev}" /proc/self/mounts
		then
			mount -o remount,ro "${fsdev}" || return 2
			finally 'mount -o remount,rw "${fsdev}"'
		fi

		# try to fsck three times, sometimes it does not work on the succeed try
		for _ in 1 2 3
		do
			e2fsck -f -p "${fsdev}" && break
		done
	)
}

resize_ext4() {
	local fsdev

	fsdev=${1:?}

	command -v resize2fs >/dev/null 2>&1 || opkg_tmp_install resize2fs >&2 || return 2

	fsck_ext4 "${fsdev}" || return 1

	resize2fs "${fsdev}" \
	&& sync
}

fsck_f2fs() {
	local fsdev

	fsdev=${1:?}

	command -v fsck.f2fs >/dev/null 2>&1 || opkg_tmp_install f2fsck >&2 || return 2

	(
		if grep -qF "${fsdev}" /proc/self/mounts
		then
			mount -o remount,ro "${fsdev}" || return 2
			finally 'mount -o remount,rw "${fsdev}"'
		fi

		# try to fsck three times, sometimes it does not work on the succeed try
		for _ in 1 2 3
		do
			fsck.f2fs -f "${fsdev}" && break
		done
	)
}

resize_f2fs() {
	local fsdev

	fsdev=${1:?}

	command -v resize.f2fs >/dev/null 2>&1 || { opkg_tmp_install f2fsck >&2; ln -sf fsck.f2fs /tmp/usr/sbin/resize.f2fs; } || return 2

	fsck_f2fs "${fsdev}" || return 1

	if grep -qF "${fsdev}" /proc/self/mounts
	then
		mount -o remount,ro "${fsdev}" || return 2
	fi

	resize.f2fs -f "${fsdev}" \
	&& sync \
	|| return 1

	echo 'File system resized. Reboot the system to update the file system size.'
}

do_resize_partition() {
	local rootpartdev overlaydev rootsysblockdev rootdev

	rootpartdev=${1:?}

	rootsysblockdev=$(cd "/sys/class/block/${rootpartdev#/dev/}" 2>/dev/null && pwd -P) &&
	rootdev=$(cd "${rootsysblockdev:?}/.." 2>/dev/null && PWD=$(pwd -P) && echo "/dev/${PWD##*/}") &&
	read -r rootpartnum <"${rootsysblockdev:?}/partition" || {
		echo 'Failed to find root device.' >&2
		return 1
	}

	printf 'Resizing partition %s...\n' "${rootpartdev}"

	resize_partition "${rootdev}" "${rootpartnum}"
}

do_resize_filesystem() {
	local dev fstype

	dev=${1:?}
	fstype=${2:?}

	case ${dev-}
	in
		(*loop[0-9]*)
			# SquashFS
			case ${fstype}
			in
				(ext4)
					resize_ext4 "${dev}"
					;;
				(f2fs)
					resize_f2fs "${dev}"
					;;
				(*)
					echo 'File system has an unsupported format.' >&2
					return 1
					;;
			esac
			;;
		(*)
			# plain
			(
				mntpnt=$(find_mountpoint "${dev}")

				sync
				mount -o remount,ro "${mntpnt}" || {
					printf 'Failed to remount %s read-only.\n' "${mntpnt}" >&2
					return 1
				}
				sync
				finally 'mount -o remount,rw "${mntpnt}"'

				loopdev=$(loop_bind "${dev}") || {
					printf 'Failed to bind loop device to %s.\n' "${rootpartdev}" >&2
					return 1
				}
				finally 'losetup -d "${loopdev}"'

				case ${fstype}
				in
					(ext4)
						resize_ext4 "${loopdev}"
						;;
					(f2fs)
						resize_f2fs "${loopdev}"
						;;
					(*)
						echo 'File system has an unsupported format.' >&2
						return 1
						;;
				esac
			)
			;;
	esac || return

	# XXX: needed?
	mount_root done || :
}

main() (
	PATH=/tmp/usr/sbin:/tmp/usr/bin:/tmp/sbin:/tmp/bin${PATH:+:}${PATH-}
	LD_LIBRARY_PATH=/tmp/usr/lib:/tmp/lib${LD_LIBRARY_PATH:+:}${LD_LIBRARY_PATH-}
	export PATH LD_LIBRARY_PATH


	rootpartdev=$(find_rootdev) || {
		echo 'Failed to determine root device. Abort.' >&2
		exit 1
	}
	overlaydev=$(find_overlaydev)


	# ---------- resize partition ----------

	if needs_part_resize "${rootpartdev}"
	then
		do_resize_partition "${rootpartdev}" || {
			echo 'Resizing partition failed. Abort.' >&2
			exit 1
		}

		if test -b "${overlaydev}"
		then
			# Resize the overlay loop device so that the file system can be
			# enlarged below.
			command -v losetup >/dev/null 2>&1 || opkg_tmp_install losetup >&2 || return 2
			losetup -c "${overlaydev}"
		fi
	fi


	# ---------- resize file system ----------

	fsdev=${overlaydev:-${rootpartdev}}

	if needs_fs_resize "${fsdev}"
	then
		rootmnt=$(find_mountpoint "${fsdev}")
		fstype=$(fstype "${rootmnt}")

		printf 'Resizing %s file system %s...\n' "${fstype}" "${rootmnt}"

		do_resize_filesystem "${fsdev}" "${fstype}" || {
			echo 'Resizing file system failed. Abort.' >&2
			exit 1
		}


		# complete

		echo 'Resize complete.'
		if test -t 0 && confirm 'Reboot system now?'
		then
			reboot
		fi
	fi
)

main "$@"
