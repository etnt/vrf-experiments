#!/bin/bash
set -x
#
# The idea of using `unshare`comes from this post:
# https://stbuehler.de/blog/article/2020/02/29/using_vrf__virtual_routing_and_forwarding__on_linux.html
#
# To run the test case after running this script:
#
#  sudo ip netns exec east python3 -m http.server &
#
#  sudo ip netns exec west wget http://192.168.15.2:8000/
#
netdevices=$(ip -o link | wc -l)

if [ "${netdevices}" -gt 1 ]; then
	# There always is loopback; anything else is probably hardware
	echo "--- Spawning in network namespace to protect environment"
	exec unshare -n "$0"
fi

ip link set dev lo up # lots of stuff breaks without loopback

./fix-vrf-rules.sh # fix ip rule setup. try disabling this line to see what happens.

ip rule list
ip netns add east
ip netns add west
ip link add vrf-0 type vrf table 10
ip link set dev vrf-0 up
ip link add veth-east type veth peer name veth-east-vrf
ip link add veth-west type veth peer name veth-west-vrf
ip link add xcable type veth peer name xcable-vrf
ip link set veth-east netns east
ip link set veth-east-vrf master vrf-0
ip link set veth-west netns west
ip link set veth-west-vrf master vrf-0
ip link set xcable-vrf master vrf-0
ip -n east addr add 192.168.15.2/24 dev veth-east
ip -n east link set veth-east up
ip addr add 192.168.15.1/24 dev veth-east-vrf
ip link set veth-east-vrf up

#ip -n east route add default dev veth-east
ip -n east route add default via 192.168.15.1

ip route add 192.168.15.0/24 dev vrf-0
ip -n west addr add 192.168.16.2/24 dev veth-west
ip -n west link set veth-west up
ip addr add 192.168.16.1/24 dev veth-west-vrf
ip link set veth-west-vrf up

#ip -n west route add default dev veth-west
ip -n west route add default via 192.168.16.1

ip route add 192.168.16.0/24 dev vrf-0
ip addr add 192.168.99.2/24 dev xcable
ip link set xcable up
ip addr add 192.168.99.1/24 dev xcable-vrf
ip link set xcable-vrf up

echo
echo "--- Have fun checking it out yourself (exit the shell to close the experiment)."
export debian_chroot="unshare-setup"
exec bash -i
