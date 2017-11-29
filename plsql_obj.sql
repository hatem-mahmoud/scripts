set echo off pages 0 lines 200 feed off head off sqlblanklines off trimspool on trimout on

spool plsql_obj.sed

select 's/OBJ='||OBJECT_ID||' SOBJ='||SUBPROGRAM_ID||'/'||OBJECT_NAME||'.'||PROCEDURE_NAME||'/g' SED from dba_procedures;

spool off
exit
