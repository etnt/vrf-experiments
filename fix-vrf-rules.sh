#!/bin/sh

# https://stbuehler.de/blog/article/2020/02/29/using_vrf__virtual_routing_and_forwarding__on_linux.html
#
# Creating a VRF on linux (like `ip link add vrf_foobar type vrf table 10`) automatically inserts a
# `l3mdev` rule (both IPv4 and IPv6) with preference 1000 by default.
#
# Sadly this means that the `lookup local` with preference 0 (the table `local` containing your
# addresses in the "default VRF") is queried before that, which breaks routing of packets from a
# VRF to your non-VRF addresses.
#
# So you actually want the `l3mdev` rule before the `lookup local` rule, and this script helps with
# that.
#
# Your VRF routing table usually is contained completely in the table you specified when creating
# the VRF; this script also creates an "pref 2000 l3mdev unreachable" rule to make sure within VRFs
# no routes "outside" the VRF are used.  (As an alternative you could add `unreachable default
# metric 4278198272` routes in both IPv4 and IPv6 VRF tables).
#
# This should still leave enough room to add policy-based routing rules if you need them.
#
# Also see `vrf_prepare()` and `vrf_create()` in linux kernel
# source:tools/testing/selftests/net/forwarding/lib.sh

set -e

has_rule() {
	if [ -n "$(ip $family rule list "$@")" ]; then
		# echo "Have: ip $family rule $*"
		return 0
	else
		# echo "Have not: ip $family rule $*"
		return 1
	fi
}

rule() {
	echo "Running: ip $family rule $*"
	ip $family rule "$@"
}

run() {
	# move lookup local to pref 32765 (from 0)
	if ! has_rule pref 32765 lookup local; then
		rule add pref 32765 lookup local
	fi
	if has_rule pref 0 lookup local; then
		rule del pref 0 lookup local
	fi
	# make sure that in VRFs after failed lookup in the VRF specific table nothing else is reached
	if ! has_rule pref 1000 l3mdev; then
		# this should be added by the kernel when a VRF is created; add it here for completeness
		rule add pref 1000 l3mdev protocol kernel
	fi
	if ! has_rule pref 2000 l3mdev; then # can't search for actions; so can't make sure this is actually using "unreachable"
		rule add pref 2000 l3mdev unreachable
	fi
}

family=-4
run
family=-6
run
