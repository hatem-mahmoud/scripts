#!/bin/bash
#
# plsql_profiler.sh
#
# This script is a geeky PL/SQL profiler
# Usage:  ./plsql_profiler.sh "PID"
#
# Author : Hatem Mahmoud <h.mahmoud87@gmail.com>
# BLOG 	 : https://mahmoudhatem.wordpress.com
#
# Tested in oracle 12.2.0.1
# Note: this is an experimental script, use at your own risk


PROFILE_PID=$1
> stap_stat
stap -v -x $PROFILE_PID line_tracker.stp -o line_tracker.txt   2> stap_stat  &
until grep -q starting stap_stat; do sleep 0.01; done
perf record -g -T -o perf.data -p $PROFILE_PID &
read -p "profiling started, press enter to stop" a
kill -s SIGTERM %1
kill -s SIGINT %2

perf script -i perf.data > perf.data.script01

cat perf.data.script01 | while read PROFILE_LINE; do
info_line=`echo $PROFILE_LINE | awk -F' ' '{print $5}'`
if [ "$info_line" == "cpu-clock:"  ]
then
echo $PROFILE_LINE
echo  "     7fff8131fed4 |"`echo $PROFILE_LINE | awk -F' ' '{print $3}' | tr -d -c 0-9`"| (time)"
else
echo $PROFILE_LINE
fi
done > perf.data.script02


cat perf.data.script02 |  /home/oracle/scripts/FlameGraph-master/stackcollapse-perf.pl  > perf.data.collapse01
>cache_resolver
echo 0 > current_depth
cat line_tracker.txt | xargs -i ./sql_resolver2.sh {} > line_tracker2.txt
cat line_tracker2.txt >> perf.data.collapse01
cat perf.data.collapse01  |  sort -t'|' -k2 -n > perf.data.collapse02

last_object="null"
monitor=0
>perf.data.collapse03
cat perf.data.collapse02 | while read PROFILE_LINE; do
info_line=`echo $PROFILE_LINE | awk -F'|' '{print $1}'`

if [ "$info_line" == "Line End" ]
then 
monitor=0
fi

if [ $monitor == 1 ]
then 

if [ "$info_line" == "Line Tracker" ]
then 
last_object=`echo $PROFILE_LINE | awk -F'|' '{print $3}'`
else
echo $last_object";"`echo $PROFILE_LINE | awk -F'|' '{print $1}'` >> perf.data.collapse03
fi

fi

if [ "$info_line" == "Line Begin" ]
then 
monitor=1
fi

done 

cat perf.data.collapse03  |  tr ' ' '_' | sort | uniq -c |awk '{print $2" "$1}' >  out.perf-folded
/home/oracle/scripts/FlameGraph-master/flamegraph.pl out.perf-folded > plsql_profile.svg

 
