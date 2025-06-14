#!/bin/sh
set -e -u

# source:
# https://wiki.raptorcs.com/wiki/Troubleshooting/BMC_Power
# https://git.raptorcs.com/git/talos-system-fpga/tree/main.v?h=v1.08#n277 ff.

fpga_readreg() {
	i2cget -y 12 0x31 "$1"
}
num2bits() {
	# converts a number to bits (LSB first) separated by spaces.
	# if the number is hex, the number of bits printed will equal the "length" of
	# the hex number.
	awk -v h="$1" '
	BEGIN {
		ORS = " "

		if (h ~ /^0x/) {
			l = (length(h) - 2) * 4
		} else {
			l = 1
		}

		do {
			for (i = l; i; --i) {
				b = (h % 2)
				h = (h - b) / 2
				print b
			}
		} while (h);
	}'
}
bitset() {
	test $(($1)) -gt 0
}


read_fpga_version() {
	fpga_version=$(fpga_readreg 0x00)
}

# Power Good Status
read_power_good_status() {
	pgs1_hex=$(fpga_readreg 0x0a)
	read -r pg_atx pg_miscio pg_vdn_cpu1 pg_vdn_cpu2 pg_avdd pg_vio_cpu1 pg_vio_cpu2 pg_vdd_cpu1 <<-EOF
	$(num2bits "${pgs1_hex}")
	EOF
	pgs2_hex=$(fpga_readreg 0x0b)
	read -r pg_vdd_cpu2 pg_vcs_cpu1 pg_vcs_cpu2 pg_vpp_cpu1 pg_vpp_cpu2 pg_vddrvtt_cpu1 pg_vddrvtt_cpu2 _ <<-EOF
	$(num2bits "${pgs2_hex}")
	EOF
}
print_power_good_status() {
	printf '%s: %u\n' \
		'Miscellaneous I/O Power Good' $((pg_miscio)) \
		'CPU1 Vdn Power Good' $((pg_vdn_cpu1)) \
		'CPU2 Vdn Power Good' $((pg_vdn_cpu2)) \
		'AVdd Power Good' $((pg_avdd)) \
		'CPU1 Vio Power Good' $((pg_vio_cpu1)) \
		'CPU2 Vio Power Good' $((pg_vio_cpu2)) \
		'CPU1 Vdd Power Good' $((pg_vdd_cpu1)) \
		'CPU2 Vdd Power Good' $((pg_vdd_cpu2)) \
		'CPU1 Vcs Power Good' $((pg_vcs_cpu1)) \
		'CPU2 Vcs Power Good' $((pg_vcs_cpu2)) \
		'CPU1 Vpp Power Good' $((pg_vpp_cpu1)) \
		'CPU2 Vpp Power Good' $((pg_vpp_cpu2)) \
		'CPU1 Vddr/Vtt Power Good' $((pg_vddrvtt_cpu1)) \
		'CPU2 Vddr/Vtt Power Good' $((pg_vddrvtt_cpu2))
}

# Power Enable Status
read_power_enable_status() {
	# pe... = ...power enable

	pes1_hex=$(fpga_readreg 0x08)
	read -r pe_atx pe_miscio pe_vdn_cpu1 pe_vdn_cpu2 pe_avdd pe_vio_cpu1 pe_vio_cpu2 pe_vdd_cpu1 <<-EOF
	$(num2bits "${pes1_hex}")
	EOF
	pes2_hex=$(fpga_readreg 0x09)
	read -r pe_vdd_cpu2 pe_vcs_cpu1 pe_vcs_cpu2 pe_vpp_cpu1 pe_vpp_cpu2 pe_vddrvtt_cpu1 pe_vddrvtt_cpu2 _ <<-EOF
	$(num2bits "${pes2_hex}")
	EOF
}
print_power_enable_status() {
	printf '%s: %u\n' \
		'Miscellaneous I/O Power Good' $((pe_miscio)) \
		'CPU1 Vdn Power Good' $((pe_vdn_cpu1)) \
		'CPU2 Vdn Power Good' $((pe_vdn_cpu2)) \
		'AVdd Power Good' $((pe_avdd)) \
		'CPU1 Vio Power Good' $((pe_vio_cpu1)) \
		'CPU2 Vio Power Good' $((pe_vio_cpu2)) \
		'CPU1 Vdd Power Good' $((pe_vdd_cpu1)) \
		'CPU2 Vdd Power Good' $((pe_vdd_cpu2)) \
		'CPU1 Vcs Power Good' $((pe_vcs_cpu1)) \
		'CPU2 Vcs Power Good' $((pe_vcs_cpu2)) \
		'CPU1 Vpp Power Good' $((pe_vpp_cpu1)) \
		'CPU2 Vpp Power Good' $((pe_vpp_cpu2)) \
		'CPU1 Vddr/Vtt Power Good' $((pe_vddrvtt_cpu1)) \
		'CPU2 Vddr/Vtt Power Good' $((pe_vddrvtt_cpu2))
}

# ATX Power State
read_atx_power_state() {
	atx_pg_hex=$(fpga_readreg 0x07)
	read -r atx_pg atx_pr atx_errfound atx_operr atx_waiterr atx_cpu2_present atx_ast_vga_disabled atx_mode_set <<-EOF
	$(num2bits "${atx_pg_hex}")
	EOF
}
print_atx_power_state() {
	printf '%s: %u\n' \
		'ATX Power Good' $((atx_pg)) \
		'ATX Power Requested' $((atx_pr)) \
		'Error Found' $((atx_errfound)) \
		'Operation Found' $((atx_operr)) \
		'Wait Error' $((atx_waiterr)) \
		'CPU2 Present' $((atx_cpu2_present)) \
		'AST VGA Disabled' $((atx_ast_vga_disabled)) \
		'Mode Set' $((atx_mode_set))
}

# LED Config
read_led_config() {
	led_config=$(fpga_readreg 0x11)
	read -r led_invert_hdd _ <<-EOF
	$(num2bits "${led_config}")
	EOF
}
print_led_config() {
	printf '%s: %u\n' \
		'Invert HDD Activity LED' $((led_invert_hdd))
}

# System Override

read_system_override() {
	sys_override_hex=$(fpga_readreg 0x33)
	read -r sys_atx_force sys_mfr_enable_cpu2_vreg sys_mfr_force_cpu2_present _ <<-EOF
	$(num2bits "${sys_override_hex}")
	EOF
}
print_system_override() {
	printf '%s: %u\n' \
		'ATX Force Enable' $((sys_atx_force)) \
		'MFR Force Enable CPU2 Voltage Regulators' $((sys_mfr_enable_cpu2_vreg)) \
		'MFR Force CPU2 Present' $((sys_mfr_force_cpu2_present))
}


case ${1-}
in
	(all-regs)
		read_power_good_status
		echo 'Power Good Status:'
		print_power_good_status | sed 's/^/ /'

		read_power_enable_status
		echo 'Power Enable Status:'
		print_power_enable_status | sed 's/^/ /'

		read_atx_power_state
		echo 'ATX Power State:'
		print_atx_power_state | sed 's/^/ /'

		read_led_config
		echo 'LED Config:'
		print_led_config | sed 's/^/ /'

		read_system_override
		echo 'System Override:'
		print_system_override | sed 's/^/ /'
		;;
	(fpga-version)
		read_fpga_version
		printf 'FPGA bitstream version: %u\n' "${fpga_version}"
		;;
	(power-state)
		read_atx_power_state
		if bitset $((atx_errfound)) && bitset $((atx_operr))
		then
			if bitset $((atx_pr))
			then
				# 0x?E
				printf 'General fault detected in power sequencing.\n'
			else
				# 0x?C
				printf 'Timeout, previous or current operational fault detected.\n'
			fi
		elif bitset $((atx_pr))
		then
			if bitset $((atx_pg))
			then
				# 0x?3
				printf 'ATX power good.\n'
			else
				# 0x?2
				printf 'ATX power requested but not yet provided.\n'
			fi
		else
			# 0x?0
			# ???
			printf 'System off.\n'
		fi
		;;
	(help|*)
		# usage
		printf '%s {all-regs|fpga-version|power-state|help}\n' "$0"
		test "${1-}" = help || exit 2
		;;
esac
