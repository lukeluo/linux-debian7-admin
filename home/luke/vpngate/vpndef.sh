#!/bin/bash

cat ssl.vpn.template | sed  -e "s/string Hostname.*$/string Hostname $1/g" | sed  -e "s/uint Port.*$/uint Port $2/g" | tr -d '\r' > ssl.vpn

