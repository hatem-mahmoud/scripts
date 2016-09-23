# This script generate extended off_cpu,on_cpu,Hot/Cold flamegaph for a specific Oracle session
# Author : Hatem Mahmoud <h.mahmoud87@gmail.com>
# BLOG : https://mahmoudhatem.wordpress.com
#
#
#Run eventsname.sql and place the output file eventsname.sed in the current directory
#Update the folowing variable before running the script
#

oracle_path=/oracle11/install/bin/oracle
flamegraph_base=/home/oracle/scripts/FlameGraph-master


echo "**********************"
echo "Begin data collection for " $2 " Seconds"
echo "Target process " $1
echo "**********************"


rm -f wait.data*
rm -f wait_*
rm -f on_perf.data*
rm -f off_perf.data*
rm -f all_perf.data*

perf probe -x $oracle_path kskthbwt event=%dx
perf probe -x $oracle_path kskthewt event=%si
perf record -e probe_oracle:kskthbwt -e probe_oracle:kskthewt  -o wait.data.raw -p $1  sleep  $2  &
perf record -F 999  -g -o on_perf.data0 -p $1 sleep  $2 &
perf record -e sched:sched_stat_sleep -e sched:sched_switch  -e sched:sched_process_exit  -g -o off_perf.data.raw -p  $1  sleep $2


echo "**********************"
echo "Begin of data analysis"
echo "**********************"


#Wait event analysis

perf script -i wait.data.raw >  wait.data0

wait_number=`wc -l wait.data0 | awk '{print $1}'`
wait_begin=0
wait_end=0
wait_event=0
wait_line_nb=1
wait_end=0

#Formating Wait event trace as "wait_begin wait_end wait_event#"

while test $wait_number -gt $wait_line_nb
  do
     if [[ $wait_line_nb == 1 && `sed -n "$wait_line_nb"p wait.data0` == *"kskthewt"* ]]
       then
        wait_line_nb=$(($wait_line_nb+1))
     fi
        wait_begin=`sed -n "$wait_line_nb"p wait.data0 | awk '{split($4,array,".") ; print array[1] substr(array[2],1,length(array[2])-1)}'`
        wait_event=`sed -n "$wait_line_nb"p wait.data0 | awk '{print $7}'`
        wait_line_nb=$(($wait_line_nb+1))
        wait_end=`sed -n "$wait_line_nb"p wait.data0 | awk '{split($4,array,".") ; print array[1] substr(array[2],1,length(array[2])-1)}'`
        wait_line_nb=$(($wait_line_nb+1))
        echo $wait_begin" "$wait_end" "$wait_event  >> wait_list.txt
done

#Off cpu analysis

echo "---"
echo "Generating Off cpu flamegraph"
echo "---"

perf inject -v -s -i off_perf.data.raw -o off_perf.data0
perf script -F comm,pid,tid,cpu,time,period,event,ip,sym,dso,trace -i off_perf.data0 > off_perf.data1

wait_line_nb=-1

while read -r line
do
if [[ $line == "oracle"* ]]
  then
    stack_timestamp=`echo "$line" | awk '{split($4,array,".") ; print array[1] substr(array[2],1,length(array[2])-1)}'`
    echo "$line" >> off_perf.data2

  wait_event="On_cpu(oracle)"

  while read -r wait_line
  do
    wait_line_nb=`echo $wait_line | awk '{print $1}'`
    w_b=`echo $wait_line | awk '{print $2}'`
    w_e=`echo $wait_line | awk '{print $3}'`
    w_n=`echo $wait_line | awk '{print $4}'`
   if [[ $stack_timestamp -ge  $w_b && $stack_timestamp -le $w_e   ]]
    then
     wait_event=$w_n
      break
    elif [[ $stack_timestamp -lt $w_e ]]
      then
      break
   fi

  done <<EOF
   $(nl wait_list.txt | awk  -v var="$wait_line_nb" ' NR >= var { print $0}')
EOF

  elif [[ -z $line  ]]
   then
        echo "xxxxxxxxxx   Off_cpu(system)()" >> off_perf.data2
        echo "xxxxxxxxxx   "$wait_event "()">> off_perf.data2
        echo $line  >> off_perf.data2
 else
     echo $line >> off_perf.data2
  fi
done < off_perf.data1



nb_cpu=`lscpu -p=cpu | grep -v "#" | wc -l`
cat  off_perf.data2 | awk -v var=$nb_cpu ' NF > 4 { exec = $1; period_ms = int($5 / 1000000 / var) } NF > 1 && NF <= 4 && period_ms > 0 { print $2 }  NF < 2 && period_ms > 0 { printf "%s\n%d\n\n", exec, period_ms }'  | $flamegraph_base/stackcollapse.pl  | sed -f eventsname.sed  > off_perf.data3
cat  off_perf.data3| $flamegraph_base/flamegraph.pl --countname=ms --title="Off-CPU Time Flame Graph" --colors=io > offcpu.svg

#On cpu analysis

echo "---"
echo "Generating On cpu flamegraph"
echo "---"

perf script -i on_perf.data0  > on_perf.data1

wait_line_nb=-1

while read -r line
do
if [[ $line == "oracle"* ]]
  then
    stack_timestamp=`echo "$line" | awk '{split($3,array,".") ; print array[1] substr(array[2],1,length(array[2])-1)}'`
    echo "$line" >> on_perf.data2

  wait_event="On_cpu(oracle) ()"
  while read -r wait_line
  do
    wait_line_nb=`echo $wait_line | awk '{print $1}'`
    w_b=`echo $wait_line | awk '{print $2}'`
    w_e=`echo $wait_line | awk '{print $3}'`
    w_n=`echo $wait_line | awk '{print $4}'`    

   if [[ $stack_timestamp -ge  $w_b && $stack_timestamp -le $w_e   ]]
    then
     wait_event=$w_n
	 break
	elif [[ $stack_timestamp -lt $w_e ]]
	 then
	 break
   fi

  done  <<EOF
   $(nl wait_list.txt | awk  -v var="$wait_line_nb" ' NR >= var { print $0}')
EOF

  elif [[ -z $line  ]]
   then
        echo "xxxxxxxxxx   On_cpu(system) ()" >> on_perf.data2
		echo "xxxxxxxxxx   "$wait_event" ()" >> on_perf.data2
        echo $line >> on_perf.data2
 else
     echo $line >> on_perf.data2
  fi
done < on_perf.data1


cat on_perf.data2  | $flamegraph_base/stackcollapse-perf.pl | sed -f eventsname.sed  > on_perf.data3
cat on_perf.data3 |  $flamegraph_base/flamegraph.pl --title="On-CPU Time Flame Graph" > oncpu.svg



#On Cpu /Off cpu Mixed flame graph
echo "---"
echo "Generating Mixed cpu flamegraph"
echo "---"

cat  off_perf.data3 > all_perf.data
cat  on_perf.data3 >> all_perf.data
cat all_perf.data  |  $flamegraph_base/flamegraph.pl --countname=ms --title="Mixed-CPU Time Flame Graph" > allcpu.svg

















