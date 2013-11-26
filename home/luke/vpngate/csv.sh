#!/bin/bash

rm -f ./csv.raw


while read line
        do

		echo "downloading csv.raw from $line ......"

		wget -e use_proxy=yes -e http_proxy=127.0.0.1:8087 -O csv.raw --timeout=5 --tries=2 $line

		if [ $? -eq 0 ];
		then 
			break
		
		fi


        done < mirror.list

# get rid of header lines in csv.raw and extract good vpn servers to vpn.good

	cat csv.raw | sed '1,2d' | ./csv.awk 
