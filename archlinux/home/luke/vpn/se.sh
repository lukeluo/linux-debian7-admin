#!/usr/bin/bash

# vpncmd exe
VPNCMD=/usr/local/vpnclient/vpncmd

# default gateway in your network
DEFGATEWAY=192.168.100.1

# your network device which will be used to create vpn connectiong
NETIF=wlp3s0

# the softether vpn link name
VPNIF=vpn_se

# while connecting to softehter vpn in "$VPNCMD", how many seconds to wait for "connected" before consider it a bad server
VPNCONNECT_WAIT=10

# http proxy for wget to retrive vpn server csv list, if any
#export http_proxy=
#export http_proxy="http://127.0.0.1:8087"

# Quality of Service parameters  for selecting vpn servers

# default country code (short), to select vpn server from these countries
CC=JP,KR

# MINSPEED  (in bits/second), network speed should be greater than MINSPEED
#MINSPEED=40000000
MINSPEED=4000000

# MINSCORE the "quality" parameter provided by vpngate.net, greater than
MINSCORE=450000

# MAXSESSION  the current connected sessions in vpn servers, less than
MAXSESSION=20

function vlist()
{
	sudo $VPNCMD localhost /client /csv /cmd accountlist vpn | sed -n -e '$p' | grep -E '[[:digit:]]' 
}

function vdisconnect()
{
	sudo $VPNCMD localhost /client /csv /cmd accountdisconnect vpn > /dev/null
}

function vconnect()
{
	vdisconnect
	sudo $VPNCMD localhost /client /csv /cmd accountdelete vpn > /dev/null
	sudo $VPNCMD localhost /client /csv /cmd accountimport ./vpn.def > /dev/null
	sudo $VPNCMD localhost /client /csv /cmd accountconnect vpn > /dev/null
	sleep $VPNCONNECT_WAIT
}

function routedel()
{
	local ip=$1
	sudo systemctl stop dhcpcd@$VPNIF.service
	sudo ip r del default
	sudo ip r add default via $DEFGATEWAY
	sudo ip a flush dev $VPNIF

	[ "x$ip" != "x" ] && sudo ip r del $ip/32 
	

}

function routeadd()
{
	local ip=$1
	[ "x$ip" = "x" ] && echo "empty gateway. routeadd failed." && return 1
	sudo ip r add $ip/32 via $DEFGATEWAY
	sudo ip r del default
	sudo systemctl start dhcpcd@$VPNIF.service

}

function validate()
{
	
	[ ! -f "candidate.txt" ] && echo "no candidate.txt. validate failed." && return 1
	[ -f server.txt ] && rm -f server.txt
	local goodserver=0

	while read candidate
	do
		server=$(echo $candidate | pyp "w[0],w[1]")
		
		echo -n "testing $candidate ...."
		nc -z -w1 $server  && echo -n " good " && echo $candidate >> server.txt && echo $(( ++goodserver )) && continue
		echo " bad"

	done < candidate.txt

	#cp server.txt candidate.txt
	echo "$goodserver servers validated!"

	# archive good servers
	cat server.txt server.archive | sort | uniq > /tmp/servers
	cp /tmp/servers ./server.archive

	

	return 0


}

function csv()
{
#	wget -O iphone.txt "http://www.vpngate.net/api/iphone/" || exit 
#	wget -O iphone.txt "http://c-24-126-131-219.hsd1.ga.comcast.net:45937/api/iphone/" || exit 

	while read mirror
	do

		 wget --timeout=9 --tries=1 -O iphone.txt "$mirror/api/iphone" && return 0; 

	done < mirror.txt
	exit;


}
function server()
{

	
	# $1 is country code
	if [  "x$1" != "x" ]; then
		 cc=$(echo $1 | pyp "p.replace(',','|')") 
	else 
		 cc=$(echo $CC | pyp "p.replace(',','|')") 
		
	fi

	csv

	#HostName,IP,Score,Ping,Speed,CountryLong,CountryShort,NumVpnSessions,Uptime,TotalUsers,TotalTraffic,LogType,Operator,Message,OpenVPN_ConfigData_Base64 

	cat iphone.txt | pyp "pp[2:] | mm[14]" | base64 -d -i | grep -i '^remote' | pyp "w[1:3] | w" > port.txt
	cat iphone.txt | pyp "pp[2:] | mm[2],mm[4],mm[6],mm[7] | p,fp" --text_file port.txt  | grep -i -E  "$cc" > qos.txt
	cat qos.txt | pyp "int(w[1]) > $MINSPEED and int(w[3]) < $MAXSESSION and int(w[0]) > $MINSCORE | w[4:6],w[2:3] | w" > candidate.txt

	validate

	echo "sever generated!"

}

function disconnect()
{

	local ip
	eval "ip=$(vlist | cut -d, -f3 | cut -d: -f 1)  "

	vdisconnect

	[ "x$ip" != "x" ] && routedel $ip


	echo "vpn disconnected!"

}

function connect()
{

	# $1 is country code

	cc=''
	[  "x$1" != "x" ] && cc=$(echo $1 | pyp "p.replace(',','|')") 
		
	while read server
	do
		
		 if [ "x$cc" != "x" ]; then 
			 echo $server | grep -q -i -E "$cc" || continue
		 fi
		
		disconnect


		local ip=$(echo $server | pyp "w[0]")
		local port=$(echo $server | pyp "w[1]")
		local country=$(echo $server | pyp "w[2]")
		echo "connecting to $ip $port $country......."
		
		sed -e "s/string Hostname.*$/string Hostname $ip/g" -e "s/uint Port .*$/uint Port $port/g" vpn.template > vpn.def
		vconnect

		vlist | grep -i -q Connected  || continue

		routeadd $ip

		nc -z -w1 youtube.com 80 &&  echo "vpn connect to $ip $port success!" && break

	done < server.txt

}
function iprouteadd()
{
	local server=$1
	[ "x$server" = "x" ] && echo "empty gateway. routeadd failed." && return 1
	sudo ip r add $server/32 via $DEFGATEWAY
	sudo ip r del default
	sudo ip r add default dev ppp0

}
function iproutedel()
{
	local server=$1
	sudo ip r del default
	sudo ip r add default via $DEFGATEWAY

	[ "x$server" != "x" ] && sudo ip r del $server/32 
	

}

function ipvalidate()
{
	
	[ ! -f "ipsec.candidate" ] && echo "no ipsec.candidate. validate failed." && return 1
	[ -f ipsec.server ] && rm -f ipsec.server
	local goodserver=0

	while read candidate
	do
		
		echo -n "testing $candidate ...."
#		ping -c 3   $candidate >/dev/null  && echo -n " good " && echo $candidate >> ipsec.server && echo $(( ++goodserver )) && continue
		nmap -sn  $candidate | grep "Host is up" >/dev/null  && echo -n " good " && echo $candidate >> ipsec.server && echo $(( ++goodserver )) && continue
		echo " bad"

	done < ipsec.candidate

	#cp server.txt candidate.txt
	echo "$goodserver servers validated!"


	return 0


}
function ipconnect()
{

	# $1 is country code

		
	while read server
	do
		
		

		#sudo systemctl restart openswan
		#sudo systemctl restart xl2tpd
		echo "connecting to $server..."
		localip=$(ip a show dev $NETIF up | grep inet | grep -v inet6 | sed -e 's/\/.*$//g' -e 's/.*inet //g')
		
		sed -e "s/conn .*/conn $server/g" -e "s/right=.*/right=$server/g" -e "s/left=.*/left=$localip/g" -e "s/leftnexthop=.*/leftnexthop=$DEFGATEWAY/g" ipsec.template > ipsec.conf
		sudo ipsec addconn --config ./ipsec.conf --addall
		sudo ipsec auto --up $server

		sudo xl2tpd-control add $server lns=$server "ppp debug"=yes pppoptfile="/etc/ppp/options.l2tpd.client" "length bit"=yes
		sudo xl2tpd-control connect $server 
		sleep $VPNCONNECT_WAIT
		iprouteadd $server
		

		nc -z -w1 youtube.com 80 &&  echo "vpn connect to $server success!" && break
		ipdisconnect

	done < ipsec.server

}
function ipdisconnect()
{

	while read server
	do 
		sudo xl2tpd-control disconnect  $server
		sudo ipsec auto --down $server

		[ "x$server" != "x" ] && iproutedel $server

	done < ipsec.server


	echo "ipsec vpn disconnected!"

}

case $1 in
'server')
	server $2
;;
'validate')
	validate
;;
'ipvalidate')
	ipvalidate
;;
'ipconnect')
	ipconnect
;;
'ipdisconnect')
	ipdisconnect 
;;
'disconnect')
	disconnect
;;
'connect')
	connect $2
;;
'vlist')
	vlist
;;
'csv')
	csv	
;;
*)
	echo "parameter error.  ./se.sh  connect|disconnect|server|validate|csv"
	echo "./se.sh server jp,kr"
	echo "if you want to connect to l2tp/ipsec, do :"
	echo "./se.sh ipvalidate"
	echo "./se.sh ipconnect" 
	echo "./se.sh ipdisconnect"
;;
esac
