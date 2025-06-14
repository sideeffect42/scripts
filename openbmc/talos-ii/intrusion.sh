#!/bin/sh
set -e -u

test -d /sys/class/gpio/gpiochip280 || exit 1
GPIO_BASE=280

to_int() { printf '%u' \'"$1"; }

BMC_INTRUDER_N=$((GPIO_BASE + 8 * ($(to_int H) - $(to_int A)) + 2))
BMC_CLR_INTR=$((GPIO_BASE + 8 * ($(to_int H) - $(to_int A)) + 3))

case ${1:-detect}
in
	(detect)
		test -d /sys/class/gpio/gpio$((BMC_INTRUDER_N)) || {
			echo $((BMC_INTRUDER_N)) >>/sys/class/gpio/export
			echo 1 >/sys/class/gpio/gpio$((BMC_INTRUDER_N))/active_low
			echo in >/sys/class/gpio/gpio$((BMC_INTRUDER_N))/direction
			# XXX: Is falling correct?
			echo falling >/sys/class/gpio/gpio$((BMC_INTRUDER_N))/edge
		}

		value=$(cat /sys/class/gpio/gpio$((BMC_INTRUDER_N))/value)
		if test $((value)) -eq 0
		then
			echo 'case was not opened'
			exit 0
		else
			echo 'case was opened. INTRUSION DETECTED!'
			exit 1
		fi
		;;
	(reset)
		test -d /sys/class/gpio/gpio$((BMC_CLR_INTR)) || {
			echo $((BMC_CLR_INTR)) >>/sys/class/gpio/export
			#echo ? >/sys/class/gpio/gpio$((BMC_CLR_INTR))/active_low
			echo out >/sys/class/gpio/gpio$((BMC_CLR_INTR))/direction
		}

		i=0
		while test $((i+=1)) -lt 20
		do
			echo 1 >/sys/class/gpio/gpio$((BMC_CLR_INTR))/value
		done
		echo 0 >/sys/class/gpio/gpio$((BMC_CLR_INTR))/value
		;;
	(-h|--help|--usage|help)
		printf '%s {detect|reset|help}\n' "$0"
		exit 0
		;;
esac
