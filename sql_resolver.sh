func_var=`echo $1 | cut -d: -f1 `
offset_var=0x`echo $1 | cut -d: -f2`
kglhd_var=0x`echo $1 | cut -d: -f3`
padding=`echo $1 | cut -d: -f4`

# ARGUMENT 1 and 3 of funtion pfrln0lookup  have to be investigated in more detail for now i just put any address that s mapped to VAS of the target process
line_var=`sqlplus / as sysdba <<EOF 2>&1 | grep -i function | cut -d' ' -f4
oradebug setmypid
oradebug call pfrln0lookup 0x7ffff3c6bc38 $kglhd_var 0x7ffff3c6bc38 $offset_var
exit;
EOF`


obj_var=`sqlplus / as sysdba <<EOF 2>&1 | grep -i obj | tail -1
 SELECT 'Object : '||KGLNAOWN||'.'||KGLNAOBJ as name FROM "X\\$KGLOB" where  to_number(KGLHDADR,'XXXXXXXXXXXXXXXX')  = to_number(substr('$kglhd_var', instr(lower('$kglhd_var'), 'x')+1) ,'XXXXXXXXXXXXXXXX') ;
exit;
EOF`

printf "%-`echo $padding`s"
echo func : $func_var /  line number : `echo $((16#$line_var))` /  $obj_var
