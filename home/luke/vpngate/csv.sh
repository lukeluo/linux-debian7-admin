#!/bin/bash

rm -f ./csv.raw


while read line
        do

		echo "downloading csv.raw from $line ......"

		wget -O csv.raw --timeout=10 --tries=2 $line

		if [ $? -eq 0 ];
		then 
			break
		
		fi


        done < mirror.list

# get rid of header lines in csv.raw and extract good vpn servers to vpn.good

	cat csv.raw | sed '1,2d' | ./csv.awk 
