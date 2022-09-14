# Setup Network Namespaces, connected via VRF

The `myvrf` script make use of a CSV config file with
the default name: `vrf.conf`, where each row specify a Network 
Namespace (NetNS) and its IP network.

The NetNS will be connected to a VRF device. 

The "connection" is done with the help of VETH devices.
The VETH (virtual Ethernet) device is a local Ethernet tunnel.
Devices are created in pairs. Packets transmitted on one device
in the pair are immediately received on the other device,
hence we can think of them as a virtual Ethernet cable.

First, make sure to have IP forwarding enabled:

    echo 1 > /proc/sys/net/ipv4/ip_forward

As an example, the content of the `netns.conf` file can look like:

    east,192.168.15.0
    west,192.168.15.0

Running the script with the above config and the `--dry-run` switch
will show all the commands the will be executed
(note: we also set up an `xcable` veth pair):

    ❯ ./myvrf --dry-run
    sudo ./fix-vrf-rules.sh
    ip rule list
    sudo ip netns add east
    sudo ip netns add west
    sudo ip link add vrf-0 type vrf table 10
    sudo ip link set dev vrf-0 up
    sudo ip link add veth-east type veth peer name veth-east-vrf
    sudo ip link add veth-west type veth peer name veth-west-vrf
    sudo ip link add xcable type veth peer name xcable-vrf
    sudo ip link set veth-east netns east
    sudo ip link set veth-east-vrf master vrf-0
    sudo ip link set veth-west netns west
    sudo ip link set veth-west-vrf master vrf-0
    sudo ip link set xcable-vrf master vrf-0
    sudo ip -n east addr add 192.168.15.2/24 dev veth-east
    sudo ip -n east link set veth-east up
    sudo ip addr add 192.168.15.1/24 dev veth-east-vrf
    sudo ip link set veth-east-vrf up
    sudo ip -n east route add default via 192.168.15.1
    sudo ip route add 192.168.15.0/24 dev vrf-0
    sudo ip -n west addr add 192.168.16.2/24 dev veth-west
    sudo ip -n west link set veth-west up
    sudo ip addr add 192.168.16.1/24 dev veth-west-vrf
    sudo ip link set veth-west-vrf up
    sudo ip -n west route add default via 192.168.16.1
    sudo ip route add 192.168.16.0/24 dev vrf-0
    sudo ip addr add 192.168.99.2/24 dev xcable
    sudo ip link set xcable up
    sudo ip addr add 192.168.99.1/24 dev xcable-vrf
    sudo ip link set xcable-vrf up

The setup looks like this:

```
                  Network Namespaces
 ┌──────────────────┐               ┌──────────────────┐
 │  WEST            │               │ EAST             │
 │                  │               │                  │
 │                  │               │                  │
 │                  │               │                  │
 └────────┬─────────┘               └─────────┬────────┘
 VETH-WEST│ 192.168.16.2             VETH-EAST│
          │                       192.168.15.2│
          │                                   │
          │                                   │
          │                                   │
          │                                   │
          │      ┌──────────────────┐         │
          │      │       VRF-0      │         │
          └──────┤                  ├─────────┘
    VETH-WEST-VRF│                  │VETH-EAST-VRF
    192.168.16.1 │    192.168.99.1  │192.168.15.1
                 └────────┬─────────┘
                          │
                          │XCABLE
                          │
                   192.168.99.2

```

## Configure

To actually execute the commands, run:

    > ./myvrf
    

## Test case

From one shell start a simple Web Server in one NetNS (east):

    sudo ip netns exec east python3 -m http.server

From another shell and namespace (west), GET a file from the Web Server:

    sudo ip netns exec west wget http://192.168.15.2:8000/

We can verify that the connection was made, by listing the connection status in east:

    ❯ sudo ip netns exec east netstat -tupn
    Active Internet connections (w/o servers)
    Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name    
    tcp6       0      0 192.168.15.2:8000       192.168.16.2:50640      TIME_WAIT   -                   
    

## Show configuration    

    > ./myvrf --show

    # sudo ip -n east a ls
    1: lo: <LOOPBACK> mtu 65536 qdisc noop state DOWN group default qlen 1000
        link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    75: veth-east@if74: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
        link/ether 62:c9:2d:d6:ab:aa brd ff:ff:ff:ff:ff:ff link-netnsid 0
        inet 192.168.15.2/24 scope global veth-east
           valid_lft forever preferred_lft forever
        inet6 fe80::60c9:2dff:fed6:abaa/64 scope link
           valid_lft forever preferred_lft forever

    # sudo ip netns exec east ip route show
    default via 192.168.15.1 dev veth-east
    192.168.15.0/24 dev veth-east proto kernel scope link src 192.168.15.2

    # sudo ip -n west a ls
    1: lo: <LOOPBACK> mtu 65536 qdisc noop state DOWN group default qlen 1000
        link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    77: veth-west@if76: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
        link/ether 6e:20:a2:ce:d1:e2 brd ff:ff:ff:ff:ff:ff link-netnsid 0
        inet 192.168.16.2/24 scope global veth-west
           valid_lft forever preferred_lft forever
        inet6 fe80::6c20:a2ff:fece:d1e2/64 scope link
           valid_lft forever preferred_lft forever

    # sudo ip netns exec west ip route show
    default via 192.168.16.1 dev veth-west
    192.168.16.0/24 dev veth-west proto kernel scope link src 192.168.16.2

    # ip a ls
    70: vrf-0: <NOARP,MASTER,UP,LOWER_UP> mtu 65575 qdisc noqueue state UP group default qlen 1000
    link/ether 26:b4:d6:19:2e:45 brd ff:ff:ff:ff:ff:ff
    71: veth-east-vrf@if72: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master vrf-0 state UP group default qlen 1000
    link/ether 46:a7:e4:e0:4e:f0 brd ff:ff:ff:ff:ff:ff link-netns east
    inet 192.168.15.1/24 scope global veth-east-vrf
       valid_lft forever preferred_lft forever
    inet6 fe80::44a7:e4ff:fee0:4ef0/64 scope link 
       valid_lft forever preferred_lft forever
    73: veth-west-vrf@if74: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master vrf-0 state UP group default qlen 1000
    link/ether ba:4c:a8:75:6f:52 brd ff:ff:ff:ff:ff:ff link-netns west
    inet 192.168.16.1/24 scope global veth-west-vrf
       valid_lft forever preferred_lft forever
    inet6 fe80::b84c:a8ff:fe75:6f52/64 scope link 
       valid_lft forever preferred_lft forever
    75: xcable-vrf@xcable: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master vrf-0 state UP group default qlen 1000
    link/ether 4e:09:c6:7d:4b:6f brd ff:ff:ff:ff:ff:ff
    inet 192.168.99.1/24 scope global xcable-vrf
       valid_lft forever preferred_lft forever
    inet6 fe80::4c09:c6ff:fe7d:4b6f/64 scope link 
       valid_lft forever preferred_lft forever
    76: xcable@xcable-vrf: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether 9e:b0:07:e4:4b:cc brd ff:ff:ff:ff:ff:ff
    inet 192.168.99.2/24 scope global xcable
       valid_lft forever preferred_lft forever
    inet6 fe80::9cb0:7ff:fee4:4bcc/64 scope link 
       valid_lft forever preferred_lft forever

    # ip route show vrf vrf-0
    192.168.15.0/24 dev veth-east-vrf proto kernel scope link src 192.168.15.1 
    192.168.16.0/24 dev veth-west-vrf proto kernel scope link src 192.168.16.1 
    192.168.99.0/24 dev xcable-vrf proto kernel scope link src 192.168.99.1 

    # ip link show vrf vrf-0
    71: veth-east-vrf@if72: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master vrf-0 state UP mode DEFAULT group default qlen 1000
    link/ether 46:a7:e4:e0:4e:f0 brd ff:ff:ff:ff:ff:ff link-netns east
    73: veth-west-vrf@if74: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master vrf-0 state UP mode DEFAULT group default qlen 1000
    link/ether ba:4c:a8:75:6f:52 brd ff:ff:ff:ff:ff:ff link-netns west
    75: xcable-vrf@xcable: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master vrf-0 state UP mode DEFAULT group default qlen 1000
    link/ether 4e:09:c6:7d:4b:6f brd ff:ff:ff:ff:ff:ff
    
    # netstat -rn
    Kernel IP routing table
    Destination     Gateway         Genmask         Flags   MSS Window  irtt Iface
    192.168.15.0    0.0.0.0         255.255.255.0   U         0 0          0 vrf-0
    192.168.16.0    0.0.0.0         255.255.255.0   U         0 0          0 vrf-0
    192.168.99.0    0.0.0.0         255.255.255.0   U         0 0          0 xcable

    ❯ sudo ip netns exec east ip route show
    default dev veth-east scope link 
    192.168.15.0/24 dev veth-east proto kernel scope link src 192.168.15.2 

    ❯ sudo ip netns exec west ip route show
    default dev veth-west scope link 
    192.168.16.0/24 dev veth-west proto kernel scope link src 192.168.16.2 

## Cleanup

    > ./myvrf --cleanup
