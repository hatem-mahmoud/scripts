set echo off pages 0 lines 200 feed off head off sqlblanklines off trimspool on trimout on

spool latchname.sed

select 's/\<laddr='||trim( to_char(to_number(addr,'xxxxxxxxxxxxxxxxxxxxxxx'),'xxxxxxxxxxxxxxxxxxxxx') )||'\>/'||'lname='||replace(name,'/','\/')||' \(Level'||LEVEL#||'\)/g'  SED from v$latch_children;
select 's/\<laddr='||trim( to_char(to_number(addr,'xxxxxxxxxxxxxxxxxxxxxxx'),'xxxxxxxxxxxxxxxxxxxxx') )||'\>/'||'lname='||replace(name,'/','\/')||' \(Level'||LEVEL#||'\)/g'  SED from v$latch_parent;

spool off
exit
