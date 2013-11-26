#!/usr/bin/awk -f
BEGIN { FS = "," ;
	OFS = "," ;
	system("rm -f csv.good");
	}

{
	#1:hostname
	#2:IP
	#3:score
	#4:ping
	#5:speed
	#6:countrylong
	#7:countryshort
	#8:numvpnsession
	#9:uptime
	#10:totalusers
	#11:totaltraffic
	#12:Logtype
	#13:Operator
	#14:Message
	#15:Openvpn_configdata_base64


	if (($7 == "JP" || $7 == "KR") \
		 && ($3 > 450000)  \
		 && ($5 > 40000000) \
		 && ($4 < 80) \
		 && ($8 < 10) \
	   )

	{
#		print $7,$3,$5,$4,$8;
		system ("echo -n " $15 " | tr -d '\n\r'  |  base64 -d | ./openvpncfg.awk  >> csv.good " );	
	}

}
	
