#!/bin/bash
if [ "x$2" == "x" ]; 
then
  echo "vpn server ip missing!  ./route.sh add/del vpn_server_ip [device]" 
  exit 1
fi

if [ "x$3" == "x" ];
then
	echo "device not specified. Default to wlan0";
	dev=wlan0;
else
	dev=$3;
fi


	case "$1" in

	add)

	  

	# restore default route to home network
	ip route delete default
	ip route add default via 192.168.100.1 dev $dev

	# obtain ip address for vpn_se
	ifdown vpn_se
	ifup vpn_se


	# add route to vpn server

	ip route add $2/32 via 192.168.100.1 dev $dev
	ip route delete default
	ip route add default via 10.211.254.254 dev vpn_se


	;;

	del)

	
	ip route del $2/32
	ip route del default
	ip route add default via 192.168.100.1 dev $dev
	ifdown vpn_se


	;;

	esac




