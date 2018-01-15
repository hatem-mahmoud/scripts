count=`echo $1 | cut -d: -f1 `
offset_var=0x`echo $1 | cut -d: -f3`
kglhd_var=0x`echo $1 | cut -d: -f2`

if [ "$count" == "" ]
then
echo $1
exit;
fi

# ARGUMENT 1 and 3 of funtion pfrln0lookup  have to be investigated in more detail for now i just put any address that s mapped to VAS of the target process

line_var=`sqlplus / as sysdba <<EOF 2>&1 | grep -i function | cut -d' ' -f4
oradebug setmypid
oradebug call pfrln0lookup $kglhd_var  $kglhd_var  $kglhd_var  $offset_var
exit;
EOF`
obj_var=`sqlplus / as sysdba <<EOF 2>&1 | grep -i obj | tail -1
 SELECT 'Object : '||KGLNAOWN||'.'||KGLNAOBJ as name FROM "X\\$KGLOB" where  to_number(KGLHDADR,'XXXXXXXXXXXXXXXX')  = to_number(substr('$kglhd_var', instr(lower('$kglhd_var'), 'x')+1) ,'XXXXXXXXXXXXXXXX') ;
exit;
EOF`
echo  $obj_var /  line number : `echo $((16#$line_var))` /  count : $count
