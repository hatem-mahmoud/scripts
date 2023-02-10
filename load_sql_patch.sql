SPO load_sql_patch.log;
SET DEF ON TERM OFF ECHO ON FEED OFF VER OFF HEA ON LIN 2000 PAGES 100 LONG 8000000 LONGC 800000 TRIMS ON TI OFF TIMI OFF SERVEROUT ON SIZE 1000000 NUM 20 SQLP SQL>;
SET SERVEROUT ON SIZE UNL;
REM
REM $Header: load_sql_patch.sql 
REM
REM Copyright (c) 2000-2021, Oracle Corporation. All rights reserved.
REM
REM AUTHOR
REM   carlos.sierra@oracle.com Modified by Hatem Mahmoud for use with SQL Patches 
REM
REM SCRIPT
REM   load_sql_patch.sql
REM
REM DESCRIPTION
REM   This script loads a plan from a modified SQL into a Custom SQL
REM   Patch for the original SQL.
REM   If a good performing plan only reproduces with CBO Hints
REM   then you can load the plan of the modified version of the
REM   SQL into a Custom SQL Patch for the orignal SQL.
REM   In other words, the original SQL can use the plan that was
REM   generated out of the SQL with hints.
REM
REM PRE-REQUISITES
REM   1. Have in cache or AWR the text for the original SQL.
REM   2. Have in cache or AWR the plan for the modified SQL
REM      (usually with hints).
REM
REM PARAMETERS
REM   1. ORIGINAL_SQL_ID (required)
REM   2. MODIFIED_SQL_ID (required)
REM   3. PLAN_HASH_VALUE (required)
REM
REM EXECUTION
REM   1. Connect into SQL*Plus as user with access to data dictionary
REM      and privileges to create SQL Patch. Do not use SYS.
REM   2. Execute script load_sql_patch.sql passing first two
REM      parameters inline or until requested by script.
REM   3. Provide plan hash value of the modified SQL when asked.
REM   4. Use a DBA user but not SYS. Do not connect as SYS as the staging
REM      table cannot be created in SYS schema and you will receive an error:
REM      ORA-19381: cannot create staging table in SYS schema
REM
REM EXAMPLE
REM   # sqlplus system
REM   SQL> START load_sql_patch.sql gnjy0mn4y9pbm b8f3mbkd8bkgh
REM   SQL> START load_sql_patch.sql;
REM
REM NOTES
REM   1. This script works on 12c or higher.
REM
SET TERM ON ECHO OFF;
PRO
PRO Parameter 1:
PRO ORIGINAL_SQL_ID (required)
PRO
DEF original_sql_id = '&1';
PRO
PRO Parameter 2:
PRO MODIFIED_SQL_ID (required)
PRO
DEF modified_sql_id = '&2';
PRO
WITH
p AS (
SELECT plan_hash_value
  FROM gv$sql_plan
 WHERE sql_id = TRIM('&&modified_sql_id.')
   AND other_xml IS NOT NULL
),
m AS (
SELECT plan_hash_value,
       SUM(elapsed_time)/SUM(executions) avg_et_secs
  FROM gv$sql
 WHERE sql_id = TRIM('&&modified_sql_id.')
   AND executions > 0
 GROUP BY
       plan_hash_value )
SELECT p.plan_hash_value,
       ROUND(m.avg_et_secs/1e6, 3) avg_et_secs
  FROM p, m
 WHERE p.plan_hash_value = m.plan_hash_value(+)   
 ORDER BY
       avg_et_secs NULLS LAST;
PRO
PRO Parameter 3:
PRO PLAN_HASH_VALUE (required)
PRO
DEF plan_hash_value = '&3';
PRO
PRO Values passed to load_sql_patch:
PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
PRO ORIGINAL_SQL_ID: "&&original_sql_id."
PRO MODIFIED_SQL_ID: "&&modified_sql_id."
PRO PLAN_HASH_VALUE: "&&plan_hash_value."
PRO
--WHENEVER SQLERROR EXIT SQL.SQLCODE;
SET TERM OFF ECHO ON;

-- trim parameters
COL original_sql_id NEW_V original_sql_id FOR A30;
COL modified_sql_id NEW_V modified_sql_id FOR A30;
COL plan_hash_value NEW_V plan_hash_value FOR A30;
SELECT TRIM('&&original_sql_id.') original_sql_id, TRIM('&&modified_sql_id.') modified_sql_id, TRIM('&&plan_hash_value.') plan_hash_value FROM DUAL;

-- open log file
SPO load_sql_patch_&&original_sql_id..log;
GET load_sql_patch.log;
.

-- get user
COL connected_user NEW_V connected_user FOR A30;
SELECT USER connected_user FROM DUAL;

VAR sql_text CLOB;
VAR other_xml CLOB;
VAR signature NUMBER;
VAR name VARCHAR2(30);

EXEC :sql_text := NULL;
EXEC :other_xml := NULL;
EXEC :signature := NULL;
EXEC :name := NULL;

-- get sql_text from memory
DECLARE
  l_sql_text VARCHAR2(32767);
BEGIN -- 10g see bug 5017909
  FOR i IN (SELECT DISTINCT piece, sql_text
              FROM gv$sqltext_with_newlines
             WHERE sql_id = TRIM('&&original_sql_id.')
             ORDER BY 1, 2)
  LOOP
    IF :sql_text IS NULL THEN
      DBMS_LOB.CREATETEMPORARY(:sql_text, TRUE);
      DBMS_LOB.OPEN(:sql_text, DBMS_LOB.LOB_READWRITE);
    END IF;
    l_sql_text := REPLACE(i.sql_text, CHR(00), ' ');
    DBMS_LOB.WRITEAPPEND(:sql_text, LENGTH(l_sql_text), l_sql_text);
  END LOOP;
  IF :sql_text IS NOT NULL THEN
    DBMS_LOB.CLOSE(:sql_text);
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('getting original sql_text from memory: '||SQLERRM);
    :sql_text := NULL;
END;
/

-- sql_text as found
SELECT :sql_text FROM DUAL;

-- check is sql_text for original sql is available
SET TERM ON;
BEGIN
  IF :sql_text IS NULL THEN
    RAISE_APPLICATION_ERROR(-20100, 'SQL_TEXT for original SQL_ID &&original_sql_id. was not found in memory (gv$sqltext_with_newlines).');
  END IF;
END;
/
SET TERM OFF;

-- get other_xml from memory
BEGIN
  FOR i IN (SELECT other_xml
              FROM gv$sql_plan
             WHERE sql_id = TRIM('&&modified_sql_id.')
               AND plan_hash_value = TO_NUMBER(TRIM('&&plan_hash_value.'))
               AND other_xml IS NOT NULL
             ORDER BY
                   child_number, id)
  LOOP
    :other_xml := i.other_xml;
    EXIT; -- 1st
  END LOOP;
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('getting modified other_xml from memory: '||SQLERRM);
    :other_xml := NULL;
END;
/

-- other_xml as found
SELECT :other_xml FROM DUAL;

-- validate other_xml
SET TERM ON;
BEGIN
  IF :other_xml IS NULL THEN
    RAISE_APPLICATION_ERROR(-20101, 'PLAN for modified SQL_ID &&modified_sql_id. and PHV &&plan_hash_value. was not found in memory (gv$sql_plan).');
  END IF;
END;
/

SET ECHO OFF;
DECLARE
  h SYS.SQLPROF_ATTR := SYS.SQLPROF_ATTR ();
  idx INTEGER := 0;
  l_pos NUMBER;
  l_hint VARCHAR2(32767);
  description VARCHAR2(500);
  output   varchar2(100);

  PROCEDURE add_hint (p_hint IN VARCHAR2)
  IS
  BEGIN
    idx := idx + 1;
    DBMS_OUTPUT.PUT_LINE(LPAD(idx, 4, '0')||' '||p_hint);
    h.EXTEND;
    h(idx) := p_hint;
  END add_hint;

BEGIN
  add_hint('BEGIN_OUTLINE_DATA');
  FOR i IN (SELECT /*+ opt_param('parallel_execution_enabled', 'false') */
                   SUBSTR(EXTRACTVALUE(VALUE(d), '/hint'), 1, 4000) hint
              FROM TABLE(XMLSEQUENCE(EXTRACT(XMLTYPE(:other_xml), '/*/outline_data/hint'))) d)
  LOOP
    l_hint := i.hint;
    WHILE NVL(LENGTH(l_hint), 0) > 0
    LOOP
      IF LENGTH(l_hint) <= 500 THEN
        add_hint(l_hint);
        l_hint := NULL;
      ELSE
        l_pos := INSTR(SUBSTR(l_hint, 1, 500), ' ', -1);
        add_hint(SUBSTR(l_hint, 1, l_pos));
        l_hint := '   '||SUBSTR(l_hint, l_pos);
      END IF;
    END LOOP;
  END LOOP;
  add_hint('END_OUTLINE_DATA');

  :signature := DBMS_SQLTUNE.SQLTEXT_TO_SIGNATURE(:sql_text);
  :name := UPPER(TRIM('&&original_sql_id.'))||'_'||TRIM('&&plan_hash_value.');
  description := UPPER('original:'||TRIM('&&original_sql_id.')||' modified:'||TRIM('&&modified_sql_id.')||' phv:'||TRIM('&&plan_hash_value.')||' signature:'||:signature||' created by load_sql_patch.sql');

  -- create custom sql patch for original sql using plan from modified sql
  
  output := SYS.DBMS_SQLTUNE_INTERNAL.I_CREATE_SQL_PROFILE(
      SQL_TEXT => :sql_text,
      PROFILE_XML => SYS.DBMS_SMB_INTERNAL.VARR_TO_HINTS_XML(h),
      NAME => :name,
	  DESCRIPTION => description,     
      CATEGORY => 'DEFAULT',
      CREATOR => 'SYS',
      VALIDATE => TRUE,
      TYPE => 'PATCH',
      FORCE_MATCH => TRUE, /* TRUE:FORCE (match even when different literals in SQL). FALSE:EXACT (similar to CURSOR_SHARING) */
      IS_PATCH => TRUE );	
	dbms_output.put_line(output);	  
END;
/

-- patch_name
COL patch_name NEW_V patch_name FOR A30;
SELECT :name patch_name FROM DUAL;

-- display details of new sql_patch
SET ECHO ON;
REM
REM SQL Patch
REM ~~~~~~~~~~~
REM ~~~~~~~~~~~
REM
SELECT signature, name, category,  status
  FROM dba_sql_patches WHERE name = :name;
SELECT description
  FROM dba_sql_patches WHERE name = :name;  
