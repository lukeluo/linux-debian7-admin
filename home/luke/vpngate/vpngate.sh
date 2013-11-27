#!/bin/bash

echo $1


if  [ "x$1" == "xdisconnect" ];
then
	./vpn.sh disconnect;
	exit 0;
fi



if  [ "x$1" == "xcsv" ];
then
	./csv.sh
	exit 0;
fi

if  [ "x$1" == "xstatus" ];
then
	cat vpnlist.cmd | vpncmd
	ip route
	exit 0;
fi

if  [ "x$1" == "xconnect" ];
then

	# if csv.good does not exist, generate one

	[ -e "./csv.good" ] || ./csv.sh
	

	# if csv.good is older then 4 hours, regenerate csv.good

	test $(find . -name "csv.good"  -mmin +240) && ./csv.sh

	while read line 
	do
		# disconnect possible pending/old connection first, ensure routing is o.k
		./vpn.sh disconnect

		echo -n $line | xargs ./vpn.sh connect;
		if [ $? -eq 0 ];
		then
			exit 0;
		fi


	done < csv.good
	exit 1;


fi


echo "Usage: vpngate.sh connect/disconnect/csv/status"

