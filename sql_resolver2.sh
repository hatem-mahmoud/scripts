var=`echo $1 | cut -d"|" -f4`
state=`echo $1 | cut -d"|" -f1 `
offset_var=0x`echo $1 | cut -d"|" -f3`
kglhd_var=0x`echo $1 | cut -d"|" -f4`
time=`echo $1 | cut -d"|" -f2`
depth=`echo $1 | cut -d"|" -f5`
p_obj_var=""
cur_depth=`cat  current_depth`


if [ -z $depth ] 
then
depth=0
fi

if [ $var != 0 ] 
then

cache_test=`grep "$kglhd_var $offset_var"   cache_resolver`

if [ -z "$cache_test" ] 
then

line_var=`sqlplus / as sysdba <<EOF 2>&1 | grep -i function | cut -d' ' -f4
oradebug setmypid
oradebug call pfrln0lookup 0x7ffff3c6bc38 $kglhd_var 0x7ffff3c6bc38 $offset_var
exit;
EOF`


obj_var=`sqlplus / as sysdba <<EOF 2>&1 | grep "O:" |  tail -1  | tr -d ';'
 SELECT 'O:'||KGLNAOWN||'.'||KGLNAOBJ as name FROM "X\\$KGLOB" where  to_number(KGLHDADR,'XXXXXXXXXXXXXXXX')  = to_number(substr('$kglhd_var', instr(lower('$kglhd_var'), 'x')+1) ,'XXXXXXXXXXXXXXXX') ;
exit;
EOF`

if [ $cur_depth  -gt 0 ] 
then
for (( c=1; c<=$cur_depth; c++ ))
do
p_obj_var="$p_obj_var"`cat  current_depth_s.$c`";"
done
fi

if [ $depth -eq 99999 ]
then
 echo $(($cur_depth - 1 ))  >  current_depth

elif [ $depth -gt 1 ]
then 

echo $obj_var`echo "("$((16#$line_var))`")" >  current_depth_s.`echo $(($cur_depth + 1 ))`

echo $(($cur_depth + 1 ))  >  current_depth


fi

if [ $cur_depth  -gt 0 ] 
then
echo "Line Tracker|"$time"|"$p_obj_var""$obj_var"("`echo $((16#$line_var))`")"
else
echo "Line Tracker|"$time"|"$obj_var"("`echo $((16#$line_var))`")"
fi

echo $kglhd_var $offset_var "/"$obj_var"("`echo $((16#$line_var))`")" >>  cache_resolver

else


if [ $cur_depth  -gt 0 ] 
then
for (( c=1; c<=$cur_depth; c++ ))
do
p_obj_var="$p_obj_var"`cat  current_depth_s.$c`";"
done
fi

if [ $depth = 99999 ]
then
 echo $(($cur_depth - 1 ))  >  current_depth

elif [ $depth -gt 1 ]
then

echo `echo $cache_test  | cut -d"/" -f2` >  current_depth_s.`echo $(($cur_depth + 1 ))`

echo $(($cur_depth + 1 ))  >  current_depth


fi

if [ $cur_depth  -gt 0 ] 
then
echo "Line Tracker|"$time"|"$p_obj_var`echo $cache_test  | cut -d"/" -f2`
else
echo "Line Tracker|"$time"|"`echo $cache_test  | cut -d"/" -f2`
fi

fi

elif [ "$state" != "Line Tracker" ] 
then

echo $state"|"$time"|0|0"

fi




