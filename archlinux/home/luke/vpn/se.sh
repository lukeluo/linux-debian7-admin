#!/usr/bin/bash

function vlist
{
	sudo vpncmd localhost /client /csv /cmd accountlist vpn | sed -n -e '$p' 
}

function vdisconnect
{
	sudo vpncmd localhost /client /csv /cmd accountdisconnect vpn > /dev/null
}

function vconnect
{
	sudo vpncmd localhost /client /csv /cmd accountdelete vpn > /dev/null
	sudo vpncmd localhost /client /csv /cmd accountimport ./vpn.def > /dev/null
	sudo vpncmd localhost /client /csv /cmd accountconnect vpn > /dev/null
	sleep 3
}

function validate
{

	rm -f server.txt

	while read server 
	do
		echo -n "testing $server ...."
		nc -z -w1 $server  && echo " good " && echo $server >> server.txt && continue
		echo " bad"

	done < candidate.txt

	cp server.txt candidate.txt
	echo "server validated!"

	return 0


}

function server
{

	# $1 is country code
	echo "country code: $1" 

	#HostName,IP,Score,Ping,Speed,CountryLong,CountryShort,NumVpnSessions,Uptime,TotalUsers,TotalTraffic,LogType,Operator,Message,OpenVPN_ConfigData_Base64

	http_proxy="http://127.0.0.1:8087" wget -O iphone.txt "http://www.vpngate.net/api/iphone/" || exit

	cat iphone.txt | pyp "pp[2:] | mm[14]" | base64 -d -i | grep -i '^remote' | pyp "w[1:3] | w" > port.txt
	cat iphone.txt | pyp "pp[2:] | mm[2],mm[4],mm[6],mm[7] | p,fp" --text_file port.txt  | grep -E -i "$1" > qos.txt
	cat qos.txt | pyp "int(w[1])>40000000 and int(w[3])<20 and int(w[0])>400000 | w[4:6] | w" > candidate.txt

	validate

	echo "sever generated!"

	return 0
}

function disconnect
{

	eval "ip=$(vlist | sed -n -e '$p' | cut -d, -f3 | cut -d: -f 1)"
	vdisconnect

	sudo systemctl stop dhcpcd@vpn_se.service
	sudo ip r del default
	sudo ip r add default via 192.168.100.1
	sudo ip a flush dev vpn_se 

	if [ ! -z $ip ]; then
		sudo ip r del $ip/32
	fi;
	echo "vpn disconnected!"
	return 0

}

function connect
{
	while read server 
	do
		disconnect

		ip=$(echo $server | pyp "w[0]")
		port=$(echo $server | pyp "w[1]")
		echo "connecting to $ip $port ......."
		
		sed -e "s/string Hostname.*$/string Hostname $ip/g" -e "s/uint Port.*$/uint Port $port/g" vpn.template > vpn.def
		vconnect

		vlist | grep Connected > /dev/null  || continue

		sudo ip r add $ip/32 via 192.168.100.1 
		sudo ip r del default
		sudo systemctl start dhcpcd@vpn_se.service
		nc -z -w1 youtube.com 80 &&  echo "vpn connect to $ip $port success!" && break

	done < server.txt

	return 0

}


case $1 in
'server')
	server $2
;;
'validate')
	validate
;;
'disconnect')
	disconnect
;;
'connect')
	connect
;;
'vlist')
	vlist
;;
*)
	echo "parameter error.  ./se.sh  connect|disconnect|server|validate"
;;
esac

