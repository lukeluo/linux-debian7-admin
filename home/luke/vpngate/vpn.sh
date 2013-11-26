#!/bin/bash

# get two parameters : ip and port, try to connect to ssl vpn. if success return 0, else return 1


if [ "x$1" ==  "x" ];
then
	echo "Usage: vpn.sh connect ip port ";
	echo "	     vpn.sh disconnect ";
	exit 1;
fi 

if [ "x$1" == "xdisconnect" ];
then
	# delete old sslvpn and collect original ip address for route delete

	echo $(cat vpndel.cmd | vpncmd | grep "^VPN Server Hostname" | cut -d "|" -f 2 | cut -d " " -f 1 | cut -d ":" -f 1 ) | xargs sudo ./route.sh del;
	exit 0;
fi 

if [ "x$1" == "xconnect" ];
then

	if [ "x$2" == "x" ] || [ "x$3" == "x" ];
	then
		echo "Usage: vpn.sh connect ip port ";
		exit 1;
	fi
fi		

# delete old sslvpn and collect original ip address for route delete
echo $(cat vpndel.cmd | vpncmd | grep "^VPN Server Hostname" | cut -d "|" -f 2 | cut -d " " -f 1 | cut -d ":" -f 1 ) | xargs sudo ./route.sh del;



# ensure ip/port is open via nc(netcat). 

alive=$(nc --timeout=1 $2 $3 < /dev/random )

if [ "x$alive" == "x" ]; then
	echo "nc $2:$3 succeeds.";
else
	echo "nc $2:$3 fails.";
    	exit 1;
fi



# generate ssl.vpn

./vpndef.sh $2 $3

# delete old sslvpn and collect original ip address for route delete

echo $(cat vpndel.cmd | vpncmd | grep "^VPN Server Hostname" | cut -d "|" -f 2 | cut -d " " -f 1 | cut -d ":" -f 1 ) | xargs sudo ./route.sh del

# import new vpn definition

cat vpnimport.cmd | vpncmd
cat vpnconnect.cmd | vpncmd  

sleep 1

isConnected=$(cat vpnlist.cmd | vpncmd | grep  Status  | cut -d "|" -f 2)

echo "vpn status is $isConnected"

if [ $isConnected != "Connected" ];
then
	#disconnect the old vpn first
	./vpn.sh disconnect
	exit 1;
fi;

# add new route 
echo $(cat vpnlist.cmd | vpncmd | grep "^VPN Server Hostname" | cut -d "|" -f 2 | cut -d " " -f 1 | cut -d ":" -f 1 ) | xargs sudo ./route.sh add

# test if vpnconnection is up

ping -q -c 2 youtube.com

if [ $? -eq 0 ]; then
    echo "vpn connection to $2:$3 SUCCEEDS!"
    exit 0;
else
    echo "vpn connection to $2:$3 FAILS!"
    exit 1;
fi

