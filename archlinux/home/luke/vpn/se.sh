#!/usr/bin/bash

# vpncmd exe
VPNCMD=/usr/local/vpnclient/vpncmd

# default gateway in your network
DEFGATEWAY=192.168.200.1

# default gateway in your network
DEFIF=wlp3s0

# the softether vpn link name
VPNIF=vpn_se

# ppp link interface in L2tp/ipsec
PPPIF=ppp0

# while connecting to softehter vpn in "$VPNCMD", how many seconds to wait for "connected" before consider it a bad server
VPNCONNECT_WAIT=10

# http proxy for wget to retrive vpn server csv list, if any
#export http_proxy=
export http_proxy="http://127.0.0.1:8087"

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

# directory to store generated openvpn config file
OPENVPNDIR="/home/luke/work/vpn/openvpn/"

function switchdns()
{
	sudo resolvconf -d $DEFIF
	echo "NAMESERVERS=$1" | sudo resolvconf -a $DEFIF
	sudo resolvconf -u
	return 0

}

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

		 wget --timeout=9 --tries=1 -O iphone.txt "$mirror/api/iphone" &&   wget --timeout=9 --tries=1 -O vpn.html "$mirror/en" && return 0; 

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

	# generate openvpn config file for all servers
	cat iphone.txt | pyp "pp[2:] | mm[14]" | base64 -d -i | sed -e '/^#/d' -e '/^;/d' -e '/^\s*$/d' >  openvpn.conf.all

	# generate "ip tcpport udpport" for all ssl/openvpn servers
	cat vpn.html | grep do_openvpn.aspx | sed -e 's/.*do_openvpn\.aspx//g' | cut -d '&' -f 2,3,4 | sed -e 's/ip=//g' -e 's/\&tcp=/ /g' -e 's/\&udp=/ /g' > port.txt	

	# generate "ip" for all l2tp/ipsec servers
	cat vpn.html |  grep do_openvpn.aspx |  grep -i "href='howto_l2tp.aspx'"|  sed -e 's/.*do_openvpn\.aspx//g' | cut -d '&' -f 2,3,4 | sed -e 's/ip=//g' -e 's/\&tcp=/ /g' -e 's/\&udp=/ /g' | cut -d ' ' -f 1 > ipsec.candidate	
	

	cat iphone.txt | pyp "pp[2:] | mm[1],mm[2],mm[4],mm[6],mm[7]" | grep -i -E  "$cc" > qos.txt
	cat qos.txt | pyp "int(w[2]) > $MINSPEED and int(w[4]) < $MAXSESSION and int(w[1]) > $MINSCORE | w[0],w[3] " > candidate.ipcc

	# put candidate.ipcc into a bash associate array(dictionary), keyed with "ip":
	declare -A dict
	while read candidate 
	do	
		ip=$(echo $candidate | cut -d ' ' -f 1)	
		cc=$(echo $candidate | cut -d ' ' -f 2)	
		dict["$ip"]="$cc"

	done < candidate.ipcc
	
	# loop port.txt. If the ip is in "dict", then output an item in "candidate.txt" combining both "candidate.ipcc" and "port.txt"
	rm -rf candidate.txt

	while read port
	do
		ip=$(echo $port | cut -d ' ' -f 1)
		tcp=$(echo $port | cut -d ' ' -f 2)
		udp=$(echo $port | cut -d ' ' -f 3)
		[ "x${dict["$ip"]}" != "x" ] && [ "x$tcp" != "x" ] && [ "x$udp" != "x" ] && echo $ip $tcp $udp ${dict[$ip]} >> candidate.txt 

	done < port.txt


	validate

	# generate corresponding openvpn config files for servers in "server.txt". We only generate UDP openvpn, since TCP openvpn is barred by "the firewall -- GFW"

	rm -rf $OPENVPNDIR
	[ -d $OPENVPNDIR ] || mkdir -p $OPENVPNDIR

	# loop server.txt 
	while read server
	do
		ip=$(echo $server | cut -d ' ' -f 1)
		tcp=$(echo $server | cut -d ' ' -f 2)
		udp=$(echo $server | cut -d ' ' -f 3)
		
		[ $udp != "0" ] && grep -A 100 -B 2 $ip openvpn.conf.all | grep "</key>" -B 100 | sed -e "s/proto.*$/proto udp/g" -e "s/remote .*$/remote $ip $udp/g" > $OPENVPNDIR/$ip
		# prepare ovpn for tunnelblick openvpn under Mac
		mkdir $OPENVPNDIR/$ip.tblk
		cp $OPENVPNDIR/$ip  $OPENVPNDIR/$ip.tblk/$ip.ovpn

	done < server.txt
	

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
		local udp=$(echo $server | pyp "w[2]")
		local country=$(echo $server | pyp "w[3]")
		echo "connecting to $ip $port $country......."
		
		sed -e "s/string Hostname.*$/string Hostname $ip/g" -e "s/uint Port .*$/uint Port $port/g"  -e "s/uint PortUDP .*$/unit PortUDP $udp/g" vpn.template > vpn.def
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
	sudo ip r add default dev $PPPIF

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

	cat ipsec.server ipsec.archive > ipsec.tmp
	cat ipsec.tmp | sort | uniq > ipsec.archive

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
		localip=$(ip a show dev $DEFIF up | grep inet | grep -v inet6 | sed -e 's/\/.*$//g' -e 's/.*inet //g')
		
		sed -e "s/conn .*/conn $server/g" -e "s/right=.*/right=$server/g" -e "s/left=.*/left=$localip/g" -e "s/leftnexthop=.*/leftnexthop=$DEFGATEWAY/g" ipsec.template > ipsec.conf
		sudo ipsec addconn --config ./ipsec.conf --addall
		sudo ipsec auto --up $server

		sudo xl2tpd-control add $server lns=$server "ppp debug"=yes pppoptfile="/etc/ppp/options.l2tpd.client" "length bit"=yes
		sudo xl2tpd-control connect $server 
		sleep $VPNCONNECT_WAIT
		iprouteadd $server
		

		nc -z -w1 youtube.com 80 &&  echo "vpn connect to $server success!" &&  break
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

function oconnect()
{

	# $1 is country code

	cc=''
	[  "x$1" != "x" ] && cc=$(echo $1 | pyp "p.replace(',','|')") 
		
	while read server
	do
		
		 if [ "x$cc" != "x" ]; then 
			 echo $server | grep -q -i -E "$cc" || continue
		 fi
		

		local ip=$(echo $server | pyp "w[0]")
		local port=$(echo $server | pyp "w[1]")
		local udp=$(echo $server | pyp "w[2]")
		local country=$(echo $server | pyp "w[3]")
		echo "connecting to $ip $port $country......."

		sudo systemctl start openvpn@$ip
		sleep  $VPNCONNECT_WAIT

		(journalctl -u openvpn@$ip | grep "Initialization Sequence Completed" > /dev/null ) &&  nc -z -w1 youtube.com 80 &&  echo "openvpn connect to $ip $udp $country success!" && break

		sudo systemctl stop openvpn@$ip
		

	done < server.txt

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
'oconnect')
	oconnect $2
;;
'odisconnect')
	sudo pkill openvpn
;;
'vlist')
	vlist
;;
'csv')
	csv	
;;
'switchdns')
	switchdns $2
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
