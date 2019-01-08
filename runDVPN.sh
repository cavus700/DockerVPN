#!/bin/bash
docker run -d --name dvpn-container --sysctl net.ipv4.ip_forward=0 --cap-add=NET_ADMIN --device /dev/net/tun:/dev/net/tun -p 1194:1194/udp dvpn:latest
