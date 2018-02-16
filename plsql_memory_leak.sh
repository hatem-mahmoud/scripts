#!/bin/bash
#
# plsql_memory_leak.sh
#
# This script help in identifing the PL/SQL program and line number responsible for a particular memory allocation
# Usage: ./plsql_memory_leak.sh ospid interval ndumbs allocation_reason_desc_address
#
# Example : ./plsql_memory_leak.sh 796 0.01 100 12F7BB6C
#
# Author : Hatem Mahmoud <h.mahmoud87@gmail.com>
# BLOG 	 : https://mahmoudhatem.wordpress.com
#
# Tested in oracle 12.2.0.1
# Note: this is an experimental script, use at your own risk

echo ----------------------------------
echo collecting $3 errorstacks samples !
echo ----------------------------------

trace_file_name=`sqlplus / as sysdba <<EOF 2>&1 | grep trace |   cut -d' ' -f2
oradebug setospid $1
oradebug pdump interval=$2 ndumps=$3 errorstack 1
oradebug tracefile_name
exit;
EOF`
echo ------------------------
echo Tracefile to be parsed !
echo $trace_file_name
echo ------------------------

>plsql_memory_leak.txt

egrep  "package|procedure|anonymous block|call     kghalf| $4|SQL Call Stack" $trace_file_name > parsed_trace.txt

plsql_string=""
block=0

while read p; do

if [ "$p" == "----- PL/SQL Call Stack -----" ]
 then
        block=1
        plsql_string=""
elif [ ! -z "`echo $p | grep call`" ]
 then
        block=2
 else

 if [ $block == 1 ]
  then

        plsql_string=`echo $p "->" $plsql_string`

 elif [  $block == 2 ] &&  [ ! -z "`echo $p | grep $4`" ]
  then

        echo $plsql_string >> plsql_memory_leak.txt
        block=0

 fi

fi


done <  parsed_trace.txt


cat plsql_memory_leak.txt |  sort | uniq -c
