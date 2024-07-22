#!/bin/sh
set -e -u

if test -r /boot/update-petitboot.conf
then
	. /boot/update-petitboot.conf
fi

: "${os_name:=Linux}"
: "${console:=hvc0}"
: "${default_console:=${consoles%%[= ]*}}"

{
	printf 'default %s (%s)\n\n' "${os_name}" "${default_console}"

	if test -e /boot/kernel
	then
		default_kernel_file=kernel
	elif test -e /boot/vmlinuz
	then
		default_kernel_file=vmlinuz
	elif test -e /boot/vmlinux
	then
		default_kernel_file=vmlinux
	fi

	if test -e /boot/initramfs
	then
		default_initramfs_file=initramfs
	elif test -e /boot/initrd.img
	then
		default_initramfs_file=initrd.img
	fi

	for kernel in vmlinuz-* ${default_kernel_file:+${default_kernel_file}.old ${default_kernel_file}}
	do
		unset -v kernel_suffix kernel_version id console initrd args

		case ${kernel}
		in
			(*.old)
				kernel_suffix=old
				kernel=${kernel%.${kernel_suffix}}
				;;
		esac

		case ${kernel}
		in
			(vmlinuz-*)
				kernel_version=${kernel#vmlinuz-}
				;;
			(${default_kernel_file-})
				kernel_version=''
				;;
		esac
		
		for console in ${consoles}
		do
			id=${kernel_version:+-${kernel_version}}${kernel_suffix:+.${kernel_suffix}}

			image=${kernel}${kernel_suffix:+.${kernel_suffix}}
			initrd=${default_initramfs_file}${id}${kernel_version:+.img}

			test -f "/boot/${image}" || continue

			args=$(
				for c in ${consoles}
				do
					test "${c}" != "${console}" || continue
					printf 'console=%s ' "${c#*=}"
				done

				# primary console
				printf 'console=%s ' "${console#*=}"
			)

			printf 'name %s (%s%s)\n' "${os_name}" "${console%%=*}" "${id:+, ${id#?}}"
			printf 'image %s\n' "/${image}"
			if test -n "${initrd-}" -a -f "/boot/${initrd-}"
			then
				printf 'initrd %s\n' "/${initrd}"
			else
				:  # error?
			fi
			printf 'args %s%s\n' "${args}" "${append-}"
			printf '\n'
		done
	done
} >/boot/petitboot.conf.tmp || {
	# petitboot.conf generation failed
	rc=$?
	test ! -f /boot/petitboot.conf.tmp || rm /boot/petitboot.conf.tmp
	exit $((rc))
}

cp -p /boot/petitboot.conf /boot/petitboot.conf-
cat /boot/petitboot.conf.tmp >/boot/petitboot.conf
rm /boot/petitboot.conf.tmp
