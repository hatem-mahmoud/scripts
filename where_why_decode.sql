set echo off pages 0 lines 200 feed off head off sqlblanklines off trimspool on trimout on

spool where_why_decode.sed

select 's/\<where='||indx||'\>/'||'where='||replace(KSLLWNAM,'/','\/')||' \(why='||replace(KSLLWLBL,'/','\/')||'\)/g'  SED from x$ksllw ;

spool off
exit
