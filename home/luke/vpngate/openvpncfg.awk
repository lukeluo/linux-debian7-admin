#!/usr/bin/awk -f 
BEGIN { OFS = "   ";
	FS = " ";		
}

{
	if ($1 == "proto" && $2 == "udp") exit;
	if ($1 == "remote") print $2,$3;
}
