#!/bin/bash
#
# trace_plsql_func_args.sh
#
# This script trace PL/SQL calls with arguments
# Usage:  ./trace_plsql_func_args.sh PID DELAY
#
# Author : Hatem Mahmoud <h.mahmoud87@gmail.com>
# BLOG 	 : https://mahmoudhatem.wordpress.com
#
# Tested in oracle 12.2.0.1
# Note: this is an experimental script, use at your own risk


#Cleaning up
perf probe --del probe_oracle:pfrinstr_MOVAN 2> /dev/null
perf probe --del probe_oracle:pfrinstr_MOVAN_2 2> /dev/null
perf probe --del probe_oracle:pfrinstr_MOVAN_3 2> /dev/null
perf probe --del probe_oracle:pfrinstr_MOVA 2> /dev/null
perf probe --del probe_oracle:pevm_ENTER 2> /dev/null
perf probe --del probe_oracle:pevm_ENTER_1 2> /dev/null


#TRACING ONE ARGUMENT
perf probe -x  /app/oracle/product/12.2.0/dbhome_1/bin/oracle pfrinstr_MOVA+38  '+0(+0(+0(%cx)))' '+0(+0(+0(%cx)))':"string"  2> /dev/null

#TRACING MULTI ARGUMENTS

perf probe -x  /app/oracle/product/12.2.0/dbhome_1/bin/oracle pfrinstr_MOVAN+60  '+0(+0(+0(%r10)))' '+0(+0(+0(%r10)))':"string"  2> /dev/null
perf probe  -f -x  /app/oracle/product/12.2.0/dbhome_1/bin/oracle pfrinstr_MOVAN+77 '+0(+0(+0(%r9)))' '+0(+0(+0(%r9)))':"string"  2> /dev/null
perf probe  -f -x  /app/oracle/product/12.2.0/dbhome_1/bin/oracle pfrinstr_MOVAN+112 '+0(+0(+0(%cx)))' '+0(+0(+0(%cx)))':"string"  2> /dev/null

#TRACING function call

perf probe  -f -x  /app/oracle/product/12.2.0/dbhome_1/bin/oracle pevm_ENTER+365 SOBJ=%dx:"s32"  2> /dev/null
perf probe  -f -x  /app/oracle/product/12.2.0/dbhome_1/bin/oracle pevm_ENTER+396 OBJ=%r9:"s32"  2> /dev/null


echo "------------------------------------------"
echo "Tracing has just begin for $2 seconds"
echo "------------------------------------------"


perf record -e probe_oracle:pfrinstr_MOVA -e probe_oracle:pfrinstr_MOVAN -e probe_oracle:pfrinstr_MOVAN_2  -e probe_oracle:pfrinstr_MOVAN_3 -e probe_oracle:pevm_ENTER -e probe_oracle:pevm_ENTER_1 -p $1 sleep
 $2


#Cleaning up
perf probe --del probe_oracle:pfrinstr_MOVAN 2> /dev/null
perf probe --del probe_oracle:pfrinstr_MOVAN_2 2> /dev/null
perf probe --del probe_oracle:pfrinstr_MOVAN_3 2> /dev/null
perf probe --del probe_oracle:pfrinstr_MOVA 2> /dev/null
perf probe --del probe_oracle:pevm_ENTER 2> /dev/null
perf probe --del probe_oracle:pevm_ENTER_1 2> /dev/null


perf script > out_to_parse

arg=""
func=""
arg_s=""

while read p; do

probe=`echo $p | cut -d' ' -f5`

if [ "$probe" == "probe_oracle:pevm_ENTER:" ]
then
func=`echo $p | cut -d' ' -f7`
elif [ "$probe" == "probe_oracle:pevm_ENTER_1:" ]
then
func=`echo $p | cut -d' ' -f7`" "$func
if [ "$func" !=  "OBJ=0 SOBJ=1" ]
then
echo "$func" "(" "$arg" ") to_string -> (" "$arg_s" ")" |sed -f  plsql_obj.sed
fi
func=""
arg=""
arg_s=""
else
arg=$arg","`echo $p | cut -d' ' -f7 | cut -d'=' -f2`
arg_s=$arg_s","`echo $p | cut -d' ' -f8 | cut -d'=' -f2`


fi

done <  out_to_parse
