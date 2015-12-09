/*
# TrcExtProf.sql
#
# TrcExtProf is a sql script for analyzing raw trace file(10046) and generating a formatted output.
# 
# You can customize the code as you want (add new sections,metrics,join with other views ,etc) and all you need is SQL you don't need to know any other
# programing language (perl,D,etc) and that's one of the primary goal of this script. The combination of external tables + sql give us a powerful tools, special thanks goes
# to nikolay savvinov for inspiring  me after reading his blog post on http://savvinov.com/2014/09/08/querying-trace-files/
#
# The analyzis done by the script are based on this key metrics :
#
# Response time = Idle wait time + non-idle Waits time + CPU time
# Self Response time = Response time - recursive statement Response time
#
#
# Usage:  @TrcExtProf.sql tracefile.trc -options
# Options : 
#
# t(threshold) : Statement which contribute less than this threshold to the total response time will not be diplayed in the TOP SQL section . Default : 10
# r(threshold) : Statement which contribute less than this threshold to the parent statement response time will not be diplayed in the RECURSIVE STATEMENT section. Default : 20
# w : Display wait event histograms.
# b : Display bind variables.
# d : Display I/O stats. 
# g : Display SQL genealogy 
#
# Example : 
# @TrcExtProf.sql tracefile.trc -t(20)r(20)wbg 
# This will display  : - All statements which contribute more than 20% of total response time
#					   - For every statements displayed list all recursive statements which contribute more than 20% of parent statement response time
#					   - Display wait event histograms
#					   - Display bind variables
#					   - Does not display I/O stats because 'd' option is not specified
#					   - Display SQL genealogy 
#
#
#
#
# Author : Hatem Mahmoud <h.mahmoud87@gmail.com>
# BLOG 	 : https://mahmoudhatem.wordpress.com
#
# Version TrcExtProf 1.1 BETA
# Note: this is an experimental script, use at your own risk
#
#
# Instalation script to run before execution  :

prompt External table creation

CREATE OR REPLACE DIRECTORY TRACEDIR AS 'Trace_file_path';

CREATE TABLE RAWTRACEFILE
 (
  row_num number,
  TEXT  VARCHAR2(4000 BYTE)                         NULL
)
ORGANIZATION EXTERNAL
  (  TYPE ORACLE_LOADER
     DEFAULT DIRECTORY TRACEDIR
     ACCESS PARAMETERS  
       ( RECORDS DELIMITED BY '\n'   fields 
     ( row_num RECNUM ,TEXT  position(1:4000)  )
       )
     LOCATION (TRACEDIR:'ORCL_2_ora_3541.trc')
  )
REJECT LIMIT 0
/

prompt Temporary table and indexes for wait events

CREATE GLOBAL TEMPORARY TABLE TRCEXTPROF_WAITS
(
  ROW_NUM  NUMBER                                   NULL,
  CURNUM   VARCHAR2(4000 BYTE)                      NULL,
  EVENT    VARCHAR2(4000 BYTE)                      NULL,
  ELA_S    NUMBER                                   NULL
)
ON COMMIT PRESERVE ROWS
RESULT_CACHE (MODE DEFAULT)
NOCACHE;


CREATE UNIQUE  INDEX  TRCEXTPROF_WAITS_IDX ON TRCEXTPROF_WAITS(ROW_NUM);

prompt Temporary table and indexes for sql geanology (PARSE,EXEC,FETCH,CLOSE)

CREATE GLOBAL TEMPORARY TABLE TRCEXTPROF_SQLGEANOLOGY
(
  ROW_NUM          NUMBER                           NULL,
  TIM              VARCHAR2(4000 BYTE)              NULL,
  CALL_NAME        VARCHAR2(5 BYTE)                 NULL,
  MISS             NUMBER                           NULL,
  CURNUM           VARCHAR2(4000 BYTE)              NULL,
  DEP              NUMBER                           NULL,
  DEP_PRE          NUMBER			                NULL,
  CALL_BEGIN       NUMBER                           NULL,
  CPU_TIME         NUMBER                           NULL,
  ELA_TIME         NUMBER                           NULL,
  PIO              NUMBER                           NULL,
  CR               NUMBER                           NULL,
  CUR              NUMBER                           NULL,
  NB_ROWS          NUMBER                           NULL,
  SELF_PIO         NUMBER                           NULL,
  SELF_CR          NUMBER                           NULL,
  SELF_CUR         NUMBER                           NULL,
  SELF_CPU_TIME    NUMBER                           NULL,
  SELF_ELA_TIME    NUMBER                           NULL,
  SELF_WAIT_ELA_S  NUMBER                           NULL  
)
ON COMMIT PRESERVE ROWS
RESULT_CACHE (MODE DEFAULT)
NOCACHE;


CREATE UNIQUE  INDEX  TRCEXTPROF_SQLGEANOLOGY_IDX ON TRCEXTPROF_SQLGEANOLOGY (DEP,ROW_NUM) compress 1;


CREATE GLOBAL TEMPORARY TABLE TRCEXTPROF_GEANOLGY_TEXT
(
  ROW_NUM          NUMBER                           NULL,
  TIM              VARCHAR2(4000 BYTE)              NULL,
  CALL_NAME        VARCHAR2(5 BYTE)                 NULL,
  MISS             NUMBER                           NULL,
  CURNUM           VARCHAR2(4000 BYTE)              NULL,
  DEP              NUMBER			                NULL,
  DEP_PRE          NUMBER			                NULL,
  CALL_BEGIN       NUMBER                           NULL,
  CPU_TIME         NUMBER                           NULL,
  ELA_TIME         NUMBER                           NULL,
  PIO              NUMBER                           NULL,
  CR               NUMBER                           NULL,
  CUR              NUMBER                           NULL,
  NB_ROWS          NUMBER                           NULL,
  SELF_PIO         NUMBER                           NULL,
  SELF_CR          NUMBER                           NULL,
  SELF_CUR         NUMBER                           NULL,
  SELF_CPU_TIME    NUMBER                           NULL,
  SELF_ELA_TIME    NUMBER                           NULL,
  SELF_WAIT_ELA_S  NUMBER                           NULL,
  ALL_WAIT_TIME    NUMBER                           NULL,
  SQLID            VARCHAR2(13 BYTE)                NULL,
  TEXT             VARCHAR2(4000 BYTE)              NULL,
  U_ID             VARCHAR2(4000 BYTE)              NULL,
  HV               VARCHAR2(10 BYTE)                NULL
)
ON COMMIT PRESERVE ROWS
RESULT_CACHE (MODE DEFAULT)
NOCACHE;


prompt Temporary table and indexes for base cursors


CREATE GLOBAL TEMPORARY TABLE TRCEXTPROF_BASE_CURSOR_TEXT
(
  ROW_NUM            NUMBER                         NULL,
  TEXT               VARCHAR2(4000 BYTE)            NULL
)
ON COMMIT PRESERVE ROWS
RESULT_CACHE (MODE DEFAULT)
NOCACHE;


CREATE UNIQUE INDEX TRCEXTPROF_BASE_CURSOR_T_IDX ON TRCEXTPROF_BASE_CURSOR_TEXT (ROW_NUM);

CREATE GLOBAL TEMPORARY TABLE TRCEXTPROF_BASE_CURSOR_INTER
(
  ROW_NUM            NUMBER                         NULL,
  CALL_NAME          VARCHAR2(17 BYTE)              NULL,
  CURNUM             VARCHAR2(4000 BYTE)            NULL,
  SQLID              VARCHAR2(13 BYTE)              NULL,
  DEP                NUMBER			                NULL,
  U_ID               VARCHAR2(4000 BYTE)            NULL,
  HV                 VARCHAR2(10 BYTE)              NULL,
  END_TEXT           NUMBER                         NULL,
  CURS_NUM_BEGIN     NUMBER                         NULL,
  PARSEIN_CURS_NEXT  NUMBER                         NULL,
  CURS_NUM_END       NUMBER                         NULL,
  TEXT               VARCHAR2(4000 BYTE)            NULL
)
ON COMMIT PRESERVE ROWS
RESULT_CACHE (MODE DEFAULT)
NOCACHE;


CREATE UNIQUE INDEX TRCEXTPROF_BASE_CURSOR_I_IDX ON TRCEXTPROF_BASE_CURSOR_INTER (call_name,curnum,ROW_NUM) compress 2;


CREATE GLOBAL TEMPORARY TABLE TRCEXTPROF_BASE_CURSOR
(
  ROW_NUM            NUMBER                         NULL,
  CALL_NAME          VARCHAR2(17 BYTE)              NULL,
  CURNUM             VARCHAR2(4000 BYTE)            NULL,
  SQLID              VARCHAR2(13 BYTE)              NULL,
  DEP                NUMBER	                        NULL,
  U_ID               VARCHAR2(4000 BYTE)            NULL,
  HV                 VARCHAR2(10 BYTE)              NULL,
  END_TEXT           NUMBER                         NULL,
  CURS_NUM_BEGIN     NUMBER                         NULL,
  PARSEIN_CURS_NEXT  NUMBER                         NULL,
  CURS_NUM_END       NUMBER                         NULL,
  TEXT               VARCHAR2(4000 BYTE)            NULL
)
ON COMMIT PRESERVE ROWS
RESULT_CACHE (MODE DEFAULT)
NOCACHE;


CREATE UNIQUE INDEX TRCEXTPROF_BASE_CURSOR_IDX ON TRCEXTPROF_BASE_CURSOR (ROW_NUM);

prompt Temporary table and indexes for plan stat

CREATE GLOBAL TEMPORARY TABLE TRCEXTPROF_STATS
(
  ROW_NUM  NUMBER                                   NULL,
  CURNUM   VARCHAR2(4000 BYTE)                      NULL,
  CNT      NUMBER                                   NULL,
  OBJN     NUMBER                                   NULL,
  O_ID     NUMBER                                   NULL,
  O_PID    NUMBER                                   NULL,
  OPERA    VARCHAR2(4000 BYTE)                      NULL
)
ON COMMIT PRESERVE ROWS
RESULT_CACHE (MODE DEFAULT)
NOCACHE;


CREATE UNIQUE  INDEX  TRCEXTPROF_STATS_IDX ON TRCEXTPROF_STATS(ROW_NUM);

prompt Temporary table and indexes for bindes

CREATE GLOBAL TEMPORARY TABLE TRCEXTPROF_BINDS
(
  ROW_NUM   NUMBER                                  NULL,
  TEXT      VARCHAR2(4000 BYTE)                     NULL,
  CUR_NUM   VARCHAR2(4000 BYTE)                     NULL,
  BIND_END  NUMBER                                  NULL
)
ON COMMIT PRESERVE ROWS
RESULT_CACHE (MODE DEFAULT)
NOCACHE;


CREATE UNIQUE  INDEX  TRCEXTPROF_BINDS_IDX ON TRCEXTPROF_BINDS (ROW_NUM);


prompt Temporary table and indexes for sql_text

CREATE GLOBAL TEMPORARY TABLE TRCEXTPROF_TEXT
(
  ROW_NUM  NUMBER                                   NULL,
  TEXT     VARCHAR2(4000 BYTE)                      NULL 
)
ON COMMIT PRESERVE ROWS
RESULT_CACHE (MODE DEFAULT)
NOCACHE;


CREATE UNIQUE INDEX TRCEXTPROF_TEXT_IDX ON TRCEXTPROF_TEXT (ROW_NUM);

*/


WHENEVER SQLERROR EXIT SQL.SQLCODE
SET SERVEROUTPUT ON FORMAT WRAPPED
set linesize 2000;
set echo off;
set define on;
set verify off;
set feed off;


--Threshold
-- Minimum  statement response time %
var l_min_response_time number ; 
-- Minimum recursive statement response time %
var l_min_recusive_response_time number ;  


var l_max_time number;
var l_show_bind number;
var l_show_wait_hist number;
var l_show_io_stat number;
var l_show_sql_gea number;
var l_min_time number;
var last_call_time number;
var l_total_response_time number;
var l_total_wait_time number;
var l_total_cpu_time number;
var l_total_unaccounted_for number;
var nb_recursive_stat number;
var NB_INTERNAL_STAT number;
var nb_total_stat number;
var nb_distinct_stat number;
var l_prev_sql varchar2( 4000 BYTE);
var l_prev_plan varchar2(4000 BYTE);
var l_sum_wait_time number;
var l_final_line number;


PROMPT 
PROMPT ===================================================================================;
PROMPT =============================TrcExtProf V1.1 BETA==================================;
PROMPT ===================================================================================;
PROMPT ===================================================================================;
PROMPT 
PROMPT
PROMPT ----> Initializing
PROMPT

BEGIN
:l_prev_plan := 0;
:l_prev_sql :='null';
:l_total_wait_time := 0.0;
:l_total_cpu_time  := 0.0;
:l_min_response_time := 20;
:l_min_recusive_response_time := 10;
:l_show_wait_hist := 0;
:l_show_bind := 0;
:l_show_io_stat := 0;
:l_show_sql_gea := 0;
:l_final_line := 9999999999999999;

 if ('&2' like '-%w%' ) then 
    :l_show_wait_hist := 1;
	dbms_output.put_line('Display wait events histograms : Y ');
	else
	dbms_output.put_line('Display wait events histograms : N ');
 end if;
 
 if ('&2' like '-%b%' ) then 
    :l_show_bind := 1;
	dbms_output.put_line('Display bind variables : Y ');
	else
	dbms_output.put_line('Display bind variables : N ');
 end if;
 
  if ('&2' like '-%g%' ) then 
    :l_show_sql_gea := 1;
	dbms_output.put_line('Display sql geanology : Y ');
	else
	dbms_output.put_line('Display sql geanology : N ');
 end if;
  
 if ('&2' like '-%d%' ) then 
    :l_show_io_stat := 1;
	dbms_output.put_line('Display I/O stats : Y ');
	else
	dbms_output.put_line('Display I/O stats : N ');
 end if;
 
  if ('&2' like '-%t(%' ) then 
   :l_min_response_time := SUBSTR ('&2',INSTR ('&2', 't(') + 2,INSTR ('&2', ')',INSTR ('&2', 't(')) - INSTR ('&2', 't(') - 2);   
 end if;
 
  if ('&2' like '-%r(%' ) then 
   :l_min_recusive_response_time := SUBSTR ('&2',INSTR ('&2', 'r(') + 2,INSTR ('&2', ')',INSTR ('&2', 'r(')) - INSTR ('&2', 'r(') - 2);
 end if;
 
 dbms_output.put_line('Top SQL min response time : ' || :l_min_response_time || '%');
 dbms_output.put_line('Recursive SQL min response time : ' || :l_min_recusive_response_time || '%');
 
 execute immediate 'truncate table TRCEXTPROF_BINDS';
 execute immediate 'truncate table TRCEXTPROF_STATS';
 execute immediate 'truncate table TRCEXTPROF_BASE_CURSOR';
 execute immediate 'truncate table TRCEXTPROF_SQLGEANOLOGY';
 execute immediate 'truncate table TRCEXTPROF_WAITS';
 execute immediate 'TRUNCATE TABLE TRCEXTPROF_BASE_CURSOR_INTER';
 execute immediate 'TRUNCATE TABLE TRCEXTPROF_BASE_CURSOR_TEXT';
 execute immediate 'TRUNCATE TABLE TRCEXTPROF_BASE_CURSOR';
 execute immediate 'TRUNCATE TABLE TRCEXTPROF_GEANOLGY_TEXT';
 execute immediate 'ALTER TABLE RAWTRACEFILE LOCATION(''&1'') ';
 

 
 end;
 
 /
 
PROMPT
PROMPT <---- Initializing
PROMPT
PROMPT ----> LOADING DATA
PROMPT
PROMPT
PROMPT -- LOADING trcextprof_waits
PROMPT
set timing off;
begin

INSERT /*+ append */ INTO trcextprof_waits
   SELECT row_num,
          SUBSTR (text,
                  INSTR (text, '#') + 1,
                  INSTR (text, ':') - INSTR (text, '#') - 1)
             AS curnum,
          SUBSTR (text,
                  INSTR (text, 'nam=') + 5,
                  INSTR (text, 'ela=') - INSTR (text, 'nam=') - 7)
             event,
            TO_NUMBER (
               SUBSTR (
                  text,
                  INSTR (text, 'ela=') + 5,
                    INSTR (text, ' ', INSTR (text, 'ela=') + 5)
                  - INSTR (text, 'ela=')
                  - 4))
          / 10E5
             ela_s
     FROM RAWTRACEFILE
    WHERE text LIKE 'WAIT%';
		  
commit;		  

end ;
/

PROMPT
PROMPT -- LOADING trcextprof_base_cursor
PROMPT

begin



INSERT /*+ append */
      INTO  trcextprof_base_cursor_inter (row_num,
                                          call_name,
                                          curnum,
                                          sqlid,
                                          dep,
                                          u_id,
                                          hv,
                                          end_text)
   SELECT row_num,
          CASE
             WHEN text LIKE 'CLOSE%' THEN 'CLOSE'
             WHEN text LIKE 'PARSING IN CURSOR%' THEN 'PARSING IN CURSOR'
			 WHEN text LIKE 'PARSE ERROR%' THEN 'PARSE ERROR'
             WHEN text LIKE 'END OF STMT%' THEN 'END OF STMT'
          END
             AS call_name,
          CASE
             WHEN text LIKE 'PARSING IN CURSOR %'
             THEN
                SUBSTR (
                   text,
                   INSTR (text, '#') + 1,
                     INSTR (text, ' ', INSTR (text, 'len=') - 2)
                   - INSTR (text, '#')
                   - 1)
             WHEN text LIKE 'CLOSE %'
             THEN
                SUBSTR (text,
                        INSTR (text, '#') + 1,
                        INSTR (text, ':') - INSTR (text, '#') - 1)
			 WHEN text LIKE 'PARSE ERROR %'
             THEN
                SUBSTR (text,
                        INSTR (text, '#') + 1,
                        INSTR (text, ':') - INSTR (text, '#') - 1)			
          END
             AS curnum,
          CASE
             WHEN text LIKE 'PARSING IN CURSOR %'
             THEN
                SUBSTR (text, INSTR (text, 'sqlid=') + 7, 13)
		     WHEN text LIKE 'PARSE ERROR %'
             THEN
                SUBSTR (text, INSTR (text, 'err='))
          END
             AS sqlid,
          CASE
             WHEN text LIKE 'PARSING IN CURSOR %'
             THEN
                to_number(SUBSTR (text, INSTR (text, 'dep=') + 4, 1))
          END
             AS dep,
          CASE
             WHEN text LIKE 'PARSING IN CURSOR %'
             THEN
                SUBSTR (text,
                        INSTR (text, 'uid=') + 4,
                        INSTR (text, 'oct=') - INSTR (text, 'uid=') - 5)
          END
             AS u_id,
          CASE
             WHEN text LIKE 'PARSING IN CURSOR %'
             THEN
                SUBSTR (text, INSTR (text, 'hv=') + 3, 10)
          END
             AS hv,
          CASE
             WHEN text LIKE 'PARSING IN CURSOR %'
             THEN
                LEAD (row_num) OVER (ORDER BY ROW_NUM)
			 WHEN text LIKE 'PARSE ERROR %'
             THEN
                row_num + 2	
          END
             AS end_text
     FROM RAWTRACEFILE
    WHERE    text LIKE 'PARSING IN CURSOR %'
          OR text LIKE 'CLOSE%'
		  OR text LIKE 'PARSE ERROR%'
          OR text LIKE 'END OF STMT%';

COMMIT;


UPDATE trcextprof_base_cursor_inter b
   SET curs_num_begin =
          CASE
             WHEN call_name = 'PARSING IN CURSOR'
             THEN
                (SELECT /*+ index(i  TRCEXTPROF_BASE_CURSOR_I_IDX) */
                       MAX (i.row_num)
                   FROM trcextprof_base_cursor_inter i
                  WHERE     i.curnum = b.curnum
                        AND i.row_num < b.row_num
                        AND i.call_name = 'CLOSE')
			WHEN call_name = 'PARSE ERROR'
             THEN
                (SELECT /*+ index(i  TRCEXTPROF_BASE_CURSOR_I_IDX) */
                       MAX (i.row_num)
                   FROM trcextprof_base_cursor_inter i
                  WHERE     i.curnum = b.curnum
                        AND i.row_num < b.row_num
                        AND i.call_name = 'CLOSE')			
          END,
       parsein_curs_next =
          CASE
             WHEN call_name = 'PARSING IN CURSOR'
             THEN
                (SELECT /*+ index(i  TRCEXTPROF_BASE_CURSOR_I_IDX) */
                       MIN (i.row_num)
                   FROM trcextprof_base_cursor_inter i
                  WHERE     i.curnum = b.curnum
                        AND i.row_num > b.row_num
                        AND ( i.call_name = 'PARSING IN CURSOR' OR i.call_name = 'PARSE ERROR') )
			 WHEN call_name = 'PARSE ERROR'
             THEN
                (SELECT /*+ index(i  TRCEXTPROF_BASE_CURSOR_I_IDX) */
                       MIN (i.row_num)
                   FROM trcextprof_base_cursor_inter i
                  WHERE     i.curnum = b.curnum
                        AND i.row_num > b.row_num
                        AND ( i.call_name = 'PARSING IN CURSOR' OR i.call_name = 'PARSE ERROR') )
          END;



UPDATE trcextprof_base_cursor_inter b
   SET curs_num_end =
          CASE
             WHEN call_name = 'PARSING IN CURSOR'
             THEN
                (SELECT /*+ index(i  TRCEXTPROF_BASE_CURSOR_I_IDX) */
                       MAX (i.row_num)
                   FROM trcextprof_base_cursor_inter i
                  WHERE     i.curnum = b.curnum
                        AND i.row_num >
                               NVL2 (b.curs_num_begin, b.curs_num_begin, 0)
                        AND i.row_num <
                               NVL2 (b.parsein_curs_next,
                                     b.parsein_curs_next,
                                     :l_final_line)
                        AND i.call_name = 'CLOSE')
			 WHEN call_name = 'PARSE ERROR'
             THEN
                (SELECT /*+ index(i  TRCEXTPROF_BASE_CURSOR_I_IDX) */
                       MAX (i.row_num)
                   FROM trcextprof_base_cursor_inter i
                  WHERE     i.curnum = b.curnum
                        AND i.row_num >
                               NVL2 (b.curs_num_begin, b.curs_num_begin, 0)
                        AND i.row_num <
                               NVL2 (b.parsein_curs_next,
                                     b.parsein_curs_next,
                                     :l_final_line)
                        AND i.call_name = 'CLOSE')			
          END;

COMMIT;

INSERT /*+ append */
      INTO  TRCEXTPROF_BASE_CURSOR_TEXT
   SELECT row_num, text
     FROM RAWTRACEFILE r
    WHERE     r.text NOT LIKE 'PARS%'
          AND r.text NOT LIKE 'CLOSE%'
          AND r.text NOT LIKE 'WAIT%'
          AND r.text NOT LIKE 'FETCH%'
          AND r.text NOT LIKE 'EXEC%'
          AND r.text NOT LIKE 'STAT%'
          AND r.text NOT LIKE 'END OF STMT%'
          AND r.text NOT LIKE '========%'
          AND r.text NOT LIKE '***%';

COMMIT;


INSERT  /*+ append  */ INTO TRCEXTPROF_BASE_CURSOR (row_num,
                                    call_name,
                                    curnum,
                                    sqlid,
                                    dep,
                                    u_id,
                                    hv,
                                    end_text,
                                    curs_num_begin,
                                    parsein_curs_next,
                                    curs_num_end,
                                    text)
SELECT  /*+
      USE_CONCAT(@"SEL$1" 8 OR_PREDICATES(1) PREDICATE_REORDERS((4 3) (5 4) (3 5)))
      OUTLINE_LEAF(@"SEL$1_2")
      OUTLINE(@"SEL$1")
      FULL(@"INS$1" "TRCEXTPROF_BASE_CURSOR"@"INS$1")
      INDEX_RS_ASC(@"SEL$1_1" "B"@"SEL$1" ("TRCEXTPROF_BASE_CURSOR_INTER"."CALL_NAME" "TRCEXTPROF_BASE_CURSOR_INTER"."CURNUM" 
              "TRCEXTPROF_BASE_CURSOR_INTER"."ROW_NUM"))
      INDEX_RS_ASC(@"SEL$1_1" "R"@"SEL$1" ("TRCEXTPROF_BASE_CURSOR_TEXT"."ROW_NUM"))
      FULL(@"SEL$1_2" "B"@"SEL$1_2")
      FULL(@"SEL$1_2" "R"@"SEL$1_2")
      LEADING(@"SEL$1_1" "B"@"SEL$1" "R"@"SEL$1")
      LEADING(@"SEL$1_2" "B"@"SEL$1_2" "R"@"SEL$1_2")
      USE_NL(@"SEL$1_1" "R"@"SEL$1")
      USE_NL(@"SEL$1_2" "R"@"SEL$1_2")   
  */
         b.row_num,
         b.call_name,
         b.curnum,
         b.sqlid,
         b.dep,
         b.u_id,
         b.hv,
         b.end_text,
         b.curs_num_begin,
         b.parsein_curs_next,
         b.curs_num_end,
         LISTAGG (text, ' ') WITHIN GROUP (ORDER BY pos ASC) as text
    FROM (SELECT b.row_num,
                 b.call_name,
                 b.curnum,
                 b.sqlid,
                 b.dep,
                 b.u_id,
                 b.hv,
                 b.end_text,
                 b.curs_num_begin,
                 b.parsein_curs_next,
                 b.curs_num_end,
                 r.text,
                 r.row_num AS pos
            FROM trcextprof_base_cursor_inter b, TRCEXTPROF_BASE_CURSOR_TEXT r
           WHERE    (    b.row_num != b.end_text - 2
                     AND r.row_num < b.end_text
                     AND r.row_num > b.row_num)
                 OR     (    b.row_num = b.end_text - 2
                         AND r.row_num = b.end_text - 1)
                    AND (   b.call_name = 'PARSING IN CURSOR'
                         OR b.call_name = 'PARSE ERROR')) b
GROUP BY b.row_num,
         b.call_name,
         b.curnum,
         b.sqlid,
         b.dep,
         b.u_id,
         b.hv,
         b.end_text,
         b.curs_num_begin,
         b.parsein_curs_next,
         b.curs_num_end;         

COMMIT;

 execute immediate 'TRUNCATE TABLE TRCEXTPROF_BASE_CURSOR_INTER';
 execute immediate 'TRUNCATE TABLE TRCEXTPROF_BASE_CURSOR_TEXT';
 
end ;
/

PROMPT
PROMPT -- LOADING trcextprof_sqlgeanology
PROMPT
		  
begin

INSERT /*+ append  */
      INTO  trcextprof_sqlgeanology (row_num,
                                     tim,
                                     call_name,
                                     miss,
                                     curnum,
                                     dep,
                                     dep_pre,
                                     call_begin,
                                     cpu_time,
                                     ela_time,
                                     pio,
                                     cr,
                                     cur,
                                     nb_rows)
   WITH sql_geanolgy
        AS (  SELECT row_num,
                     SUBSTR (text, INSTR (text, 'tim=') + 4) tim,
                     CASE
                        WHEN text LIKE ('FETCH #%') THEN 'FETCH'
                        WHEN text LIKE ('PARSE #%') THEN 'PARSE'
                        WHEN text LIKE ('EXEC #%') THEN 'EXEC'
                        WHEN text LIKE ('CLOSE #%') THEN 'CLOSE'
                     END
                        call_name,
                     TO_NUMBER (
                        NVL (
                           SUBSTR (
                              text,
                              INSTR (text, 'mis=') + 4,
                              INSTR (text, ',r=') - INSTR (text, 'mis=') - 4),
                           0))
                        AS miss,
                     SUBSTR (text,
                             INSTR (text, '#') + 1,
                             INSTR (text, ':') - INSTR (text, '#') - 1)
                        AS curnum,
                     to_number(SUBSTR (
                        text,
                        INSTR (text, 'dep=') + 4,
                          INSTR (text, ',', (INSTR (text, 'dep=')))
                        - INSTR (text, 'dep=')
                        - 4))
                        AS dep,
                     to_number(LAG (
                        SUBSTR (
                           text,
                           INSTR (text, 'dep=') + 4,
                             INSTR (text, ',', (INSTR (text, 'dep=')))
                           - INSTR (text, 'dep=')
                           - 4))
                     OVER (ORDER BY ROW_NUM))
                        AS dep_pre,
                     CASE
                        WHEN (SUBSTR (
                                 text,
                                 INSTR (text, 'dep=') + 4,
                                   INSTR (text, ',', (INSTR (text, 'dep=')))
                                 - INSTR (text, 'dep=')
                                 - 4) <
                                 (LAG (
                                     SUBSTR (
                                        text,
                                        INSTR (text, 'dep=') + 4,
                                          INSTR (text,
                                                 ',',
                                                 (INSTR (text, 'dep=')))
                                        - INSTR (text, 'dep=')
                                        - 4))
                                  OVER (ORDER BY ROW_NUM)))
                        THEN
                           NVL (
                              MAX (
                                 row_num)
                              OVER (
                                 PARTITION BY (SUBSTR (
                                                  text,
                                                  INSTR (text, 'dep=') + 4,
                                                    INSTR (
                                                       text,
                                                       ',',
                                                       (INSTR (text, 'dep=')))
                                                  - INSTR (text, 'dep=')
                                                  - 4))
                                 ORDER BY ROWNUM
                                 ROWS BETWEEN UNBOUNDED PRECEDING
                                      AND     1 PRECEDING),
                              0)
                        ELSE
                           NVL (
                              MAX (
                                 row_num)
                              OVER (
                                 PARTITION BY (SUBSTR (
                                                  text,
                                                  INSTR (text, '#') + 1,
                                                    INSTR (text, ':')
                                                  - INSTR (text, '#')
                                                  - 1))
                                 ORDER BY ROWNUM
                                 ROWS BETWEEN UNBOUNDED PRECEDING
                                      AND     1 PRECEDING),
                              0)
                     END
                        AS call_begin,
                       TO_NUMBER (
                          SUBSTR (text,
                                  INSTR (text, 'c=') + 2,
                                  INSTR (text, ',e=') - INSTR (text, 'c=') - 2))
                     / 10E5
                        cpu_time,
                       TO_NUMBER (
                          SUBSTR (
                             text,
                             INSTR (text, 'e=') + 2,
                               INSTR (text, ',', INSTR (text, 'e='))
                             - INSTR (text, 'e=')
                             - 2))
                     / 10E5
                        ela_time,
                     TO_NUMBER (
                        NVL (
                           SUBSTR (
                              text,
                              INSTR (text, 'p=') + 2,
                              INSTR (text, ',cr') - INSTR (text, 'p=') - 2),
                           0))
                        pio,
                     TO_NUMBER (
                        NVL (
                           SUBSTR (
                              text,
                              INSTR (text, 'cr=') + 3,
                              INSTR (text, ',cu') - INSTR (text, 'cr=') - 3),
                           0))
                        Cr,
                     TO_NUMBER (
                        NVL (
                           SUBSTR (
                              text,
                              INSTR (text, 'cu=') + 3,
                              INSTR (text, ',mis=') - INSTR (text, 'cu=') - 3),
                           0))
                        Cur,
                     TO_NUMBER (
                        CASE
                           WHEN text NOT LIKE 'CLOSE %'
                           THEN
                              NVL (
                                 SUBSTR (
                                    text,
                                    INSTR (text, ',r=') + 3,
                                      INSTR (text, ',dep=')
                                    - INSTR (text, ',r=')
                                    - 3),
                                 0)
                           ELSE
                              '0'
                        END)
                        nb_rows
                FROM RAWTRACEFILE
               WHERE    text LIKE 'PARSE #%'
                     OR text LIKE 'EXEC #%'
                     OR text LIKE 'FETCH #%'
                     OR text LIKE 'CLOSE #%'
            ORDER BY row_num)
   SELECT row_num,
          tim,
          call_name,
          miss,
          curnum,
          dep,
          dep_pre,
          call_begin,
          cpu_time,
          ela_time,
          pio,
          cr,
          cur,
          nb_rows
     FROM sql_geanolgy;


COMMIT;


UPDATE trcextprof_sqlgeanology g
   SET  self_wait_ela_s =  CASE
             WHEN NVL (g.call_begin, 0) < g.row_num - 1
             THEN
                (SELECT NVL (SUM (ela_s), 0)
                   FROM trcextprof_waits w
                  WHERE     w.row_num < g.row_num
                        AND w.row_num > NVL (g.call_begin, 0)
                        AND g.curnum = w.curnum)
             ELSE
                0
          END;
            
COMMIT;

INSERT /*+ append */  INTO TRCEXTPROF_GEANOLGY_TEXT
   WITH wait_events AS (SELECT * FROM trcextprof_waits)
   SELECT g.row_num,
                                     g.tim,
                                     g.call_name,
                                     miss,
                                     g.curnum,
                                     g.dep,
                                     g.dep_pre,
                                     call_begin,
                                     cpu_time,
                                     ela_time,
                                     pio,
                                     cr,
                                     cur,
                                     nb_rows,           
          CASE
             WHEN g.dep < g.dep_pre and g.call_name != 'CLOSE'
             THEN
                  g.pio
                - (SELECT SUM (pio)
                     FROM trcextprof_sqlgeanology self
                    WHERE     self.row_num < g.row_num
                          AND self.row_num > g.call_begin
                          AND self.dep = g.dep + 1)
             ELSE
                g.pio
          END as self_pio,   
          CASE
             WHEN g.dep < g.dep_pre and g.call_name != 'CLOSE'
             THEN
                  g.cr
                - (SELECT SUM (cr)
                     FROM trcextprof_sqlgeanology self
                    WHERE     self.row_num < g.row_num
                          AND self.row_num > g.call_begin
                          AND self.dep = g.dep + 1)
             ELSE
                g.cr
          END as self_cr,  
          CASE
             WHEN g.dep < g.dep_pre and g.call_name != 'CLOSE'
             THEN
                  g.cur
                - (SELECT SUM (cur)
                     FROM trcextprof_sqlgeanology self
                    WHERE     self.row_num < g.row_num
                          AND self.row_num > g.call_begin
                          AND self.dep = g.dep + 1)
             ELSE
                g.cur
          END as self_cur,  
          CASE
             WHEN g.dep < g.dep_pre
             THEN
                  g.cpu_time
                - (SELECT SUM (cpu_time)
                     FROM trcextprof_sqlgeanology self
                    WHERE     self.row_num < g.row_num
                          AND self.row_num > g.call_begin
                          AND self.dep = g.dep + 1)
             ELSE
                g.cpu_time
          END as self_cpu_time,    
          CASE
             WHEN g.dep < g.dep_pre
             THEN
                  g.ela_time
                - (SELECT SUM (ela_time)
                     FROM trcextprof_sqlgeanology self
                    WHERE     self.row_num < g.row_num
                          AND self.row_num > g.call_begin
                          AND self.dep = g.dep + 1)
             ELSE
                g.ela_time
          END as self_ela_time,   
		  g.self_wait_ela_s,
          CASE
             WHEN g.dep < g.dep_pre
             THEN
                (SELECT SUM (self_wait_ela_s)
                   FROM trcextprof_sqlgeanology s
                  WHERE     s.row_num < g.row_num
                        AND s.row_num > g.call_begin
                        AND s.dep > g.dep )  + self_wait_ela_s
             ELSE
                self_wait_ela_s
          END as ALL_WAIT_TIME,
          ct.sqlid,
          ct.text,
          ct.u_id,
          ct.hv
     FROM trcextprof_sqlgeanology g
          LEFT OUTER JOIN
          trcextprof_base_cursor ct
             ON     g.row_num >
                       NVL2 (ct.curs_num_begin, ct.curs_num_begin, 0)
                AND g.row_num <=
                       NVL2 (ct.curs_num_end,
                             ct.curs_num_end,
                              :l_final_line)
                AND g.curnum = ct.curnum;
     
commit;


execute immediate 'truncate table trcextprof_sqlgeanology';
	
end ;
/
PROMPT
PROMPT -- LOADING trcextprof_stats
PROMPT

begin	
	
INSERT  /*+ append */ INTO trcextprof_stats
   SELECT r.row_num,
          SUBSTR (r.text,
                  INSTR (r.text, '#') + 1,
                  INSTR (r.text, 'id=') - INSTR (r.text, '#') - 2)
             curnum,
          TO_NUMBER (
             SUBSTR (r.text,
                     INSTR (r.text, 'cnt=') + 4,
                     INSTR (r.text, 'pid=') - INSTR (r.text, 'cnt=') - 5))
             cnt,
          TO_NUMBER (
             SUBSTR (r.text,
                     INSTR (r.text, 'obj=') + 4,
                     INSTR (r.text, 'op=') - INSTR (r.text, 'obj=') - 5))
             objn,
          TO_NUMBER (
             SUBSTR (r.text,
                     INSTR (r.text, 'id=') + 3,
                     INSTR (r.text, 'cnt=') - INSTR (r.text, 'id=') - 4))
             o_id,
          TO_NUMBER (
             SUBSTR (r.text,
                     INSTR (r.text, 'pid=') + 4,
                     INSTR (r.text, 'pos=') - INSTR (r.text, 'pid=') - 5))
             o_pid,
          SUBSTR (r.text,
                  INSTR (r.text, 'op=') + 4,
                  INSTR (r.text, ')') - INSTR (r.text, 'op=') - 4)
             opera
     FROM RAWTRACEFILE r
    WHERE r.text LIKE 'STAT%';		
commit;

	
end ;

/

PROMPT
PROMPT -- LOADING trcextprof_binds
PROMPT

begin	

if (:l_show_bind = 1 ) then
insert /*+ append */ into TRCEXTPROF_BINDS
 SELECT row_num,
                   text,
                     CASE
                      WHEN text LIKE 'BIND%'
                      THEN
                         SUBSTR (text,
                                 INSTR (text, '#') + 1,
                                 INSTR (text, ':') - INSTR (text, '#') - 1)
                   END as cur_num,
                 CASE
                      WHEN CASE
                      WHEN text LIKE 'BIND%'
                      THEN
                         SUBSTR (text,
                                 INSTR (text, '#') + 1,
                                 INSTR (text, ':') - INSTR (text, '#') - 1)
                   END IS NOT NULL
                      THEN
                        nvl( LAG (row_num) OVER  (  partition by substr(text,1,5) ORDER BY ROW_NUM desc  ), to_number(:l_final_line))
                   END
                      AS bind_end     
              FROM RAWTRACEFILE
             WHERE    text LIKE 'BIND%'
                   OR text LIKE ' Bind#%'
                   OR text LIKE '  value=%' order by row_num ;                       
commit;                       
else
 dbms_output.put_line('Binds option not specified');
end if;
end;

/
set timing off;
PROMPT
PROMPT <---- DATA LOADED
PROMPT
PROMPT *************************************************************
PROMPT TRACE INFO
PROMPT *************************************************************
PROMPT

begin

   FOR c_0 IN (SELECT *
	  FROM RAWTRACEFILE
	 WHERE    text LIKE '*** SESSION ID%'
		   OR text LIKE '*** CLIENT ID%'
		   OR text LIKE '*** SERVICE NAME%'
		   OR text LIKE '*** MODULE NAME%'
		   OR text LIKE '*** ACTION NAME%')
   LOOP
      DBMS_OUTPUT.put_line (c_0.text);
   END LOOP;
 
end;

/

PROMPT
PROMPT *************************************************************
PROMPT SUMMARY
PROMPT *************************************************************
PROMPT


declare

cursor c_general_info is (     
SELECT MAX (tim),
       MIN (tim - ela),
       MAX (max_tim_db_call),
       SUM (NB_INTERNAL_STAT),
       SUM (nb_recursive_stat),
       COUNT (DISTINCT nb_distinct_stat) - 1,
       SUM (DECODE (nb_distinct_stat, '0', 0, 1)),
       MAX (row_num) final_line
  FROM (SELECT   (CASE
                     WHEN text LIKE 'PARSING IN CURSOR%'
                     THEN
                        SUBSTR (
                           text,
                           INSTR (text, 'tim=') + 4,
                           INSTR (text, 'hv=') - INSTR (text, 'tim=') - 5)
                     WHEN text LIKE 'PARSE ERROR%'
                     THEN
                        SUBSTR (
                           text,
                           INSTR (text, 'tim=') + 4,
                           INSTR (text, 'err=') - INSTR (text, 'tim=') - 5)   
                     ELSE
                        SUBSTR (text, INSTR (text, 'tim=') + 4)
                  END)
               / 10E5
                  AS tim,
                  (CASE
                     WHEN text LIKE 'WAIT%'
                     THEN
                         TO_NUMBER (
						   SUBSTR (
							  text,
							  INSTR (text, 'ela=') + 5,
								INSTR (text, ' ', INSTR (text, 'ela=') + 5)
							  - INSTR (text, 'ela=')
							  - 4))
                     WHEN text LIKE 'PARSE ERROR%'
                     THEN
                        0 
					 WHEN text LIKE 'PARSING IN CURSOR%'
                     THEN
                        0 
					 WHEN text LIKE 'ERROR%'
                     THEN
                        0 	
                     ELSE
                         TO_NUMBER (
                          SUBSTR (
                             text,
                             INSTR (text, 'e=') + 2,
                               INSTR (text, ',', INSTR (text, 'e='))
                             - INSTR (text, 'e=')
                             - 2))

                  END)
               / 10E5
                  AS ela,  
               CASE
                  WHEN row_num LIKE
                          MAX (
                             CASE
                                WHEN text LIKE ('PARSE #%') THEN row_num
                                WHEN text LIKE ('EXEC #%') THEN row_num
                                WHEN text LIKE ('FETCH #%') THEN row_num
                                WHEN text LIKE ('CLOSE #%') THEN row_num
                             END)
                          OVER ()
                  THEN
                     SUBSTR (text, INSTR (text, 'tim=') + 4) / 10E5
               END
                  AS max_tim_db_call,
               CASE
                  WHEN text LIKE ('PARSING%')
                  THEN
                     DECODE (
                        SUBSTR (
                           text,
                           INSTR (text, 'uid=') + 4,
                           INSTR (text, 'oct=') - INSTR (text, 'uid=') - 5),
                        0, 1,
                        0)
                  ELSE
                     0
               END
                  NB_INTERNAL_STAT,
               CASE
                  WHEN text LIKE ('PARSING%')
                  THEN
                     DECODE (INSTR (text, 'dep=0'), 0, 1, 0)
                  ELSE
                     0
               END
                  nb_recursive_stat,
               CASE
                  WHEN text LIKE ('PARSING%')
                  THEN
                     SUBSTR (text, INSTR (text, 'sqlid=') + 6)
                  ELSE
                     '0'
               END
                  nb_distinct_stat,
               row_num
          FROM RAWTRACEFILE
         WHERE text LIKE '%tim=%'));

begin 

 open c_general_info; 
 FETCH c_general_info  into :l_max_time,:l_min_time,:last_call_time,:NB_INTERNAL_STAT,:nb_recursive_stat,:nb_distinct_stat,:nb_total_stat,:l_final_line;

 :l_total_response_time := :l_max_time - :l_min_time;

  DBMS_OUTPUT.put_line(rpad('Trace file name ',43)||': &1' );
  DBMS_OUTPUT.put_line ( rpad('Total trace response time ',43)||': ' || :l_total_response_time);
  DBMS_OUTPUT.put_line ( rpad('SQL statements in trace file ',43)||': ' || :nb_total_stat);
  DBMS_OUTPUT.put_line ( rpad('Internal SQL statements in trace file ',43)||': ' || :NB_INTERNAL_STAT);
  DBMS_OUTPUT.put_line ( rpad('Unique SQL statements in trace file ',43)||': ' || :nb_distinct_stat);
  DBMS_OUTPUT.put_line ( rpad('Recursive SQL statements in trace file ' ,43)||': '|| :nb_recursive_stat);
    
end;
/

PROMPT
PROMPT *************************************************************
PROMPT DATABASE CALL STATISTICS WITH RECURSIVE STATEMENTS
PROMPT *************************************************************
PROMPT

begin	
 
 DBMS_OUTPUT.put_line ('CALLS          |COUNT     |MISS      |RESP_TIME |CPU_TIME  |ELA_TIME  |PIO       |CR        |CUR       |NB_ROWS');
 DBMS_OUTPUT.put_line ('--------------------------------------------------------------------------------------------------------');

 FOR c_3 IN (
  SELECT call_name,
         COUNT (*) COUNT,
		  SUM (self_wait_ela_s + self_cpu_time) AS resp_time,
         SUM (self_ela_time) AS ela_time,
         SUM (self_cpu_time) AS cpu_time,
         SUM (miss) AS miss,
         SUM (self_pio) AS pio,
         SUM (self_cur) AS cur,
         SUM (self_cr) AS cr,
         SUM (nb_rows) AS nb_rows
    FROM TRCEXTPROF_GEANOLGY_TEXT
GROUP BY call_name     
) LOOP
    DBMS_OUTPUT.put_line ( RPAD(c_3.call_name,15) ||'|'|| RPAD(c_3.COUNT,10) ||'|'|| RPAD(c_3.miss,10)||'|'|| RPAD(c_3.resp_time,10)||'|'||RPAD(c_3.cpu_time,10)||'|'|| RPAD(c_3.ela_time,10)||'|'|| RPAD(c_3.pio,10)||'|'|| RPAD(c_3.cr,10)||'|'|| RPAD(c_3.cur,10)||'|'|| RPAD(c_3.nb_rows,10));
	:l_total_cpu_time := c_3.cpu_time + :l_total_cpu_time ;	
END LOOP;

end;

/

PROMPT
PROMPT *************************************************************
PROMPT RESOURCE USAGE PROFILE
PROMPT *************************************************************
PROMPT

begin

 DBMS_OUTPUT.put_line ('EVENT                              |ELA_S     |MIN_ELA_S |MAX_ELA_S |AVG_ELA_S |EVENT_NB  |%Resp time');
 DBMS_OUTPUT.put_line ('--------------------------------------------------------------------------------------------------------');
  
  for c_2 in (
  SELECT *
  FROM ( SELECT    EVENT event,
                   SUM (ELA_S)  ela_s,
                   MIN (ELA_S)  min_ela_s,
                   MAX (ELA_S)  max_ela_s,
                   AVG (ELA_S)  avg_ela_s,
                 COUNT (*) event_nb
            FROM trcextprof_waits           
        GROUP BY EVENT
        ORDER BY 2 DESC)
 WHERE ROWNUM < 6) loop   
  DBMS_OUTPUT.put_line ( rpad(c_2.event,35) ||'|'|| rpad(c_2.ela_s,10)  ||'|'||  rpad(c_2.min_ela_s,10)  ||'|'||  rpad( c_2.max_ela_s,10)  ||'|'||   rpad( c_2.avg_ela_s,10)  ||'|'||   rpad( c_2.event_nb,10)  ||'|'||rpad(round((c_2.ela_s/:l_total_response_time)*100,2),10)   );
    :l_total_wait_time := :l_total_wait_time + c_2.ela_s;
	
	if ( :l_show_wait_hist = 1 ) then 
	
	DBMS_OUTPUT.put_line ('--------------------------------------------------------------------------------------------------------');
	DBMS_OUTPUT.put_line ( '    |'||rpad('Buket *Time is in ms',35) ||'|'|| rpad('Low_value',10)  ||'|'||  rpad('High_value',10)  ||'|'||  rpad('Num_Waits',10)  ||'|'||   rpad('Wait_Time',10));
	DBMS_OUTPUT.put_line ('--------------------------------------------------------------------------------------------------------');
	for c_3 in (
    SELECT buket,
         MIN (ELA_MS) low_value,
         MAX (ELA_MS) high_value,
         COUNT (*) AS Num_Waits,
         SUM (ELA_MS) AS Wait_Time
    FROM (SELECT CASE
                    WHEN ELA_S < 0.001 THEN '0    -> 1'
                    WHEN ELA_S < 0.002 THEN '1    -> 2'
                    WHEN ELA_S < 0.004 THEN '2    -> 4'
                    WHEN ELA_S < 0.008 THEN '4    -> 8'
                    WHEN ELA_S < 0.016 THEN '8    -> 16'
                    WHEN ELA_S < 0.032 THEN '16   -> 32'
                    WHEN ELA_S < 0.064 THEN '32   -> 64'
                    WHEN ELA_S < 0.128 THEN '64   -> 128'
                    WHEN ELA_S < 0.256 THEN '128  -> 256'
                    WHEN ELA_S < 0.512 THEN '256  -> 512'
                    WHEN ELA_S < 1.024 THEN '512  -> 1024'
                    WHEN ELA_S < 2.048 THEN '1024 ->  2048'
                    WHEN ELA_S < 4.096 THEN '2048 -> 4096'
                    WHEN ELA_S < 8.192 THEN '4096 -> 8192'
                    ELSE  '8192 > '
                 END
                    AS buket,
                    ELA_S,
                 ELA_S * 1000 AS ELA_MS
            FROM trcextprof_waits
           WHERE event = c_2.event)
GROUP BY buket
ORDER BY to_number(substr(buket,1,instr(buket,'->') -1 ))) loop
	
	 DBMS_OUTPUT.put_line ( '    |'||rpad(c_3.buket,35) ||'|'|| rpad(c_3.low_value,10)  ||'|'||  rpad(c_3.high_value,10)  ||'|'||  rpad( c_3.Num_Waits,10)  ||'|'||   rpad( c_3.Wait_Time,10));
end loop;
 DBMS_OUTPUT.put_line ('--------------------------------------------------------------------------------------------------------');	
 
 end if;
 end loop;
 
      
 :l_total_unaccounted_for :=  :l_total_response_time - :l_total_cpu_time - :l_total_wait_time;
 DBMS_OUTPUT.put_line ( rpad('CPU',35) ||'|'|| rpad( :l_total_cpu_time,10) ||'|'||  rpad( ' ',10) ||'|'||  rpad( ' ',10) ||'|'||  rpad( ' ',10) ||'|'||  rpad( ' ',10)   ||'|'||  rpad(round((:l_total_cpu_time/:l_total_response_time)*100,2),10) );
 DBMS_OUTPUT.put_line ( rpad('Unaccounted-for Time',35) ||'|'|| rpad( :l_total_unaccounted_for,10) ||'|'||  rpad( ' ',10) ||'|'||  rpad( ' ',10) ||'|'||  rpad( ' ',10) ||'|'||  rpad( ' ',10)   ||'|'||  rpad(round((:l_total_unaccounted_for/:l_total_response_time)*100,2),10));
end;
/


PROMPT
PROMPT *************************************************************
PROMPT Hot I/O Blocks
PROMPT *************************************************************
PROMPT


begin


if ( :l_show_io_stat = 1 ) then

DBMS_OUTPUT.put_line ( rpad('File#',10) ||'|'|| rpad('Block#',10)  ||'|'||  rpad('Obj#',10)  ||'|'||  rpad('Times_waited',12)  ||'|'||   rpad('Wait_time_s',12)||'|'||   rpad('Max_wait_time_s',12));
DBMS_OUTPUT.put_line ('------------------------------------------------------------------------');	
for c_1 in (
WITH sequential_read
     AS (SELECT   TO_NUMBER (
                     SUBSTR (
                        text,
                        INSTR (text, 'ela=') + 5,
                          INSTR (text, ' ', INSTR (text, 'ela=') + 5)
                        - INSTR (text, 'ela=')
                        - 4))
                / 10E5
                   ela_s,
                SUBSTR (text,
                        INSTR (text, 'file#=') + 6,
                        INSTR (text, 'block#=') - INSTR (text, 'file#=') - 7)
                   AS file#,
                SUBSTR (
                   text,
                   INSTR (text, 'block#=') + 7,
                   INSTR (text, 'blocks=') - INSTR (text, 'block#=') - 8)
                   AS block#,
                SUBSTR (text,
                        INSTR (text, 'obj#=') + 5,
                        INSTR (text, 'tim=') - INSTR (text, 'obj#=') - 6)
                   AS obj#
           FROM RAWTRACEFILE
          WHERE text LIKE '%db file sequential read%'),
     hot_io_blocks
     AS (  SELECT file#,
                  block#,
                  obj#,
                  COUNT (*) AS times_waited,
                  SUM (ela_s) AS wait_time_s,
                  MAX (ela_s) max_wait_time_s
             FROM sequential_read
         GROUP BY file#, block#, obj#
         ORDER BY WAIT_TIME_S DESC)
SELECT *
  FROM hot_io_blocks
 WHERE ROWNUM < 6 ) loop
 
  DBMS_OUTPUT.put_line ( rpad(c_1.file#,10) ||'|'|| rpad(c_1.block#,10)  ||'|'||  rpad(c_1.obj#,10)  ||'|'||  rpad( c_1.times_waited,12)  ||'|'||   rpad( c_1.wait_time_s,12)||'|'||   rpad( c_1.max_wait_time_s,12));
 
 end loop;
 
 else
 
 DBMS_OUTPUT.put_line (' * Option ''d'' not specified to display Hot I/O Blocks');

 end if;

end;

/



PROMPT
PROMPT *************************************************************
PROMPT SQL GEANOLOGY
PROMPT *************************************************************
PROMPT


begin


if ( :l_show_sql_gea = 1 ) then

DBMS_OUTPUT.put_line (rpad('%Self_time',10) ||'|'|| rpad('Self_time',10) ||'|'|| rpad('Recur_time',10)  ||'|'||  rpad('Exec_count',10)  ||'|'||  rpad('sqlid',12)  ||'|'||   rpad('hv',12)||'|'||   rpad('u_id',6));
DBMS_OUTPUT.put_line ('------------------------------------------------------------------------');	
for c_1 in (
WITH sql_gea1
     AS (SELECT row_num r,
                curnum,
                CASE WHEN dep < dep_pre THEN CALL_BEGIN ELSE row_num END b,
                u_id,
                dep,
                dep_pre,
                RPAD ('.', dep, '.') || '' || text text,
                sqlid,
                hv,
                (ALL_WAIT_TIME + CPU_TIME) all_response,
                (SELF_WAIT_ELA_S + SELF_CPU_TIME) self_response,
                DECODE (call_name, 'EXEC', 1, 0) AS is_exec
           FROM TRCEXTPROF_GEANOLGY_TEXT),
     sql_gea2
     AS (    SELECT ROWNUM row_num2, co.*, CONNECT_BY_ROOT text par
               FROM sql_gea1 co
         START WITH dep = 0
         CONNECT BY PRIOR dep = dep - 1 AND PRIOR b < r AND PRIOR r > r)
  SELECT SUM (self_response) self_response_time,
         SUM (all_response) - SUM (self_response) recursive_response_time,
         SUM (is_exec) exec_count,
         sqlid,
         u_id,
         text,
         hv,
         dep
    FROM sql_gea2
GROUP BY sqlid,
         u_id,
         text,
         hv,
         dep,
         par
ORDER BY MIN (row_num2) ) loop
 
  DBMS_OUTPUT.put_line ( rpad(  ROUND(((c_1.self_response_time) /  :l_total_response_time ) *100,2),10) ||'|'||rpad(c_1.self_response_time,10) ||'|'|| rpad(c_1.recursive_response_time,10)  ||'|'||  rpad(c_1.exec_count,10)  ||'|'||  rpad( c_1.sqlid,12)  ||'|'||   rpad( c_1.hv,12)||'|'||   rpad( c_1.u_id,6) ||'|'|| c_1.text);
 
 end loop;
 
 else
 
 DBMS_OUTPUT.put_line (' * Option ''g'' not specified to display SQL geanology');

 end if;

end;

/

PROMPT
PROMPT *************************************************************
PROMPT TOP SQL OVERVIEW (ONLY NON RECURSIVE STATEMENTS)
PROMPT *************************************************************
PROMPT

begin
 
 DBMS_OUTPUT.put_line (rpad('%TOTAL_RESPONSE_TIME',10)  ||'|'||rpad('TOTAL_RESPONSE_TIME',10)  ||'|'||rpad('E_TIME',10)  ||'|'||rpad('CPU_TIME',10) ||'|'||rpad('SELF_RESPONSE_TIME',10)   ||'|'||rpad('SELF_ELA_TIME',10)  ||'|'||rpad('SELF_CPU_TIME',10)  ||'|'||rpad('EXECS',5)  ||'|'||rpad('USER',5)  ||'|'||rpad('SQLID',10) ||'|'||rpad('PLAN_HASH',10) ||'|'||rpad('TEXT',500)  );
 DBMS_OUTPUT.put_line ('--------------------------------------------------------------------------------------------------------');

for c_3 in (
WITH wait_events
     AS (SELECT * from trcextprof_waits)     
	SELECT 
         SUM (all_wait_time + cpu_time) Total_response_time,
         SUM (self_wait_ela_s + self_cpu_time) Self_response_time,
         SUM (ela_time) ela_time,
         sum(cpu_time) cpu_time,
         SUM (self_ela_time) self_ela_time,
         sum(self_cpu_time) self_cpu_time,
         SUM (DECODE (call_name, 'EXEC', 1)) execs,
         u_id ,
         sqlid,
         hv,
         text
    FROM TRCEXTPROF_GEANOLGY_TEXT
   WHERE dep = 0  GROUP BY sqlid,u_id,hv, text ORDER BY 1 DESC) loop 
  DBMS_OUTPUT.put_line ( rpad( ROUND((c_3.Total_response_time/:l_total_response_time)*100,2),10) ||'|'|| rpad(c_3.Total_response_time,10) ||'|'|| rpad(c_3.ela_time,10)  ||'|'||  rpad(c_3.cpu_time,10) ||'|'|| rpad(c_3.self_response_time,10) ||'|'||  rpad( c_3.self_ela_time,10)  ||'|'||   rpad( c_3.self_cpu_time,10)  ||'|'||   rpad( 0||c_3.execs,5)  ||'|'|| rpad( c_3.u_id,5)  ||'|'|| rpad( c_3.sqlid,10)  ||'|'|| rpad( c_3.hv,10)  ||'|'|| rpad( c_3.text,300));
end loop;
 
 
 if (:last_call_time <> :l_max_time ) then 
 
 DBMS_OUTPUT.NEW_LINE;
 DBMS_OUTPUT.put_line ('-');
 DBMS_OUTPUT.put_line ('TRACE FILE NOT CORRECTLY ENDED (LAST UNKNOWN CALL)');
 DBMS_OUTPUT.put_line ('-');
 DBMS_OUTPUT.NEW_LINE;
 
 
 DBMS_OUTPUT.put_line (rpad('%TOTAL_RESPONSE_TIME',15)  ||'|'||rpad('TOTAL_RESPONSE_TIME',15)  ||'|'||rpad('RECUR_E_TIME',15)  ||'|'||rpad('RECUR_CPU_TIME',15) );
 DBMS_OUTPUT.put_line ('--------------------------------------------------------------------------------------------------------');

 
for c_4 in (        
  SELECT    
         SUM (self_ela_time) self_ela_time,
         sum(self_cpu_time) self_cpu_time         
    FROM TRCEXTPROF_GEANOLGY_TEXT
	WHERE tim / 10E5 > :last_call_time
) loop 
  DBMS_OUTPUT.put_line (  rpad( ROUND(((:l_max_time - :last_call_time)/:l_total_response_time)*100,2),15) ||'|'||    rpad(:l_max_time - :last_call_time,15) ||'|'||     rpad( c_4.self_ela_time,15)  ||'|'||   rpad( c_4.self_cpu_time,15));
end loop;   
end if;
end;
/

PROMPT
PROMPT *************************************************************
PROMPT TOP SQL
PROMPT *************************************************************
PROMPT

begin

for c_4 in (
WITH 
     top_sql_1
     AS (  SELECT call_name,
                  COUNT (*) COUNT,
                  SUM (all_wait_time + cpu_time ) Total_response_time,
                  SUM (self_wait_ela_s + self_cpu_time ) self_response_time,
                  SUM (self_wait_ela_s) self_wait_time,
                  SUM (miss) miss,
                  SUM (ela_time) ela_time,
                  SUM (cpu_time) cpu_time,
                  SUM (cur) cur,
                  SUM (cr) cr,
                  SUM (pio) pio,
                  SUM (self_ela_time) self_ela_time,
                  SUM (self_cpu_time) self_cpu_time,
                  SUM (self_cur) self_cur,
                  SUM (self_cr) self_cr,
                  SUM (self_pio) self_pio,
                  SUM (nb_rows) nb_rows,
                  u_id u_id,
                  sqlid,
                  dep,
                  hv,
                  text
             FROM TRCEXTPROF_GEANOLGY_TEXT
         GROUP BY sqlid,
                  u_id,
                  text,
                  hv,
                  dep,
                  call_name ),top_sql_with_global_time as (
  SELECT SUM (top.Total_response_time) OVER (PARTITION BY sqlid, u_id, hv,dep,text)
            AS golbal_response_time,
         SUM (top.self_response_time) OVER (PARTITION BY sqlid, u_id, hv,dep,text)
            AS global_self_response_time,
         SUM (top.self_wait_time) OVER (PARTITION BY sqlid, u_id, hv,dep,text)
            AS global_self_wait_time,
         top.*
    FROM top_sql_1 top 
ORDER BY 1 DESC,
         sqlid,
         UID,
         hv,
         dep,
         call_name DESC) select * from top_sql_with_global_time     where golbal_response_time >  :l_total_response_time*(:l_min_response_time/100)) loop  

		 if ( :l_prev_sql!= (c_4.sqlid || c_4.hv || c_4.dep || c_4.u_id || c_4.text )) then
			  
			  :l_prev_sql := c_4.sqlid || c_4.hv || c_4.dep || c_4.u_id || c_4.text;
			 
			  DBMS_OUTPUT.NEW_LINE;
			  DBMS_OUTPUT.NEW_LINE;
			  DBMS_OUTPUT.put_line('+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++');
			  DBMS_OUTPUT.NEW_LINE;
			  DBMS_OUTPUT.put_line (rpad('SQL ID',20)||' '||c_4.sqlid);
			  DBMS_OUTPUT.put_line (rpad('PLAN HASH',20)||' '||c_4.hv);
			  DBMS_OUTPUT.put_line (rpad('PARSING USER',20)||' '||c_4.u_id);
			  DBMS_OUTPUT.put_line (rpad('DEP',20)||' '||c_4.dep);
			  DBMS_OUTPUT.put_line (rpad('TOTAL RESPONSE TIME',20)||' '||c_4.golbal_response_time);
			  DBMS_OUTPUT.put_line (rpad('SELF RESPONSE TIME',20) ||' '||c_4.global_self_response_time||'  ('|| ROUND((c_4.global_self_response_time/c_4.golbal_response_time)*100,2) || '%)');
			  DBMS_OUTPUT.put_line (rpad('TEXT',20)||' '||c_4.text);			  
			  DBMS_OUTPUT.NEW_LINE; 
			
	--Display all execution plans		  
	for row_s in (WITH  rowsources
     AS (SELECT b.row_num ident,
                r.row_num,
                 r.curnum,
                   r.cnt,   
                   r.objn,               
                   r.o_id,                   
                   r.o_pid,
                   r.opera
           FROM trcextprof_stats r, trcextprof_base_cursor b
          WHERE     r.curnum = b.curnum
                AND r.row_num > NVL (b.curs_num_begin, 0)
                AND r.row_num < NVL (b.curs_num_end, :l_final_line)
                AND b.sqlid = c_4.sqlid and b.u_id = c_4.u_id and b.hv = c_4.hv and b.dep = c_4.dep AND b.text= c_4.text )
    SELECT ident, cnt, (LPAD ('  ', LEVEL - 1) || r.opera) rowsource_op,objn
      FROM rowsources r
CONNECT BY PRIOR o_id = o_pid AND PRIOR ident = ident
START WITH o_id = 1
  ORDER BY ident,o_id)    loop
  
 
  if( :l_prev_plan != row_s.ident) 
   then 
	DBMS_OUTPUT.NEW_LINE; 
	DBMS_OUTPUT.put_line (rpad('ROWS',10)  ||'|'||rpad('OPERATION',15));
    DBMS_OUTPUT.put_line ('--------------------------------------------------------------------------------------------------------');
  end if;
  
  DBMS_OUTPUT.put_line (RPAD(row_s.cnt,10) ||'|'|| row_s.rowsource_op || ' (objn : '|| row_s.objn ||')');
  :l_prev_plan := row_s.ident ;
  
  end loop;

  
  --Display bind variables
  
if (:l_show_bind = 1 ) then
  if ( c_4.text like '%:%' ) then
  
  DBMS_OUTPUT.NEW_LINE; 
  DBMS_OUTPUT.put_line (rpad('Bind Variables',20) );
  DBMS_OUTPUT.put_line ('--------------------');
  DBMS_OUTPUT.NEW_LINE; 
  
  for c_bind in (
with bind_boundary as (
SELECT bind.row_num,nvl(bind.bind_end,:l_final_line) bind_end
  FROM trcextprof_binds bind, trcextprof_base_cursor b
 WHERE     b.curnum = bind.cur_num
       AND bind.row_num < NVL (b.curs_num_end, :l_final_line) 
       AND bind.row_num > NVL (b.curs_num_begin, 0)  AND b.sqlid = c_4.sqlid  and b.u_id = c_4.u_id and b.hv = c_4.hv and b.dep = c_4.dep  AND b.text= c_4.text ) 
 select      a.text  from  trcextprof_binds a, bind_boundary b where a.row_num between b.row_num and b.bind_end and rownum < 200) loop
	   
	   DBMS_OUTPUT.put_line (c_bind.text);
	   
	   end loop;
 end if;	   
end if;
  
  
  --Display self wait events
  
  :l_sum_wait_time := 0.0;
  DBMS_OUTPUT.NEW_LINE; 
  DBMS_OUTPUT.put_line (rpad('EVENT NAME',30)||'|'||rpad('ELAPSED TIME',30) );
  DBMS_OUTPUT.put_line ('--------------------------------------------------');  
  
	for c_wait in (
	SELECT w.event event_name,sum(ela_s) ela
	FROM trcextprof_waits w, trcextprof_base_cursor b
	WHERE     b.curnum = w.curnum
       AND w.row_num < NVL (b.curs_num_end, :l_final_line)
       AND w.row_num > NVL (b.curs_num_begin, 0)   AND b.sqlid = c_4.sqlid and b.u_id = c_4.u_id and b.hv = c_4.hv and b.dep = c_4.dep AND b.text= c_4.text    group by event order by 2 desc) loop
	   
	   dbms_output.put_line(rpad(c_wait.event_name,30) ||'|' ||c_wait.ela);
	   :l_sum_wait_time := :l_sum_wait_time + c_wait.ela;
 end loop;
	   
			  DBMS_OUTPUT.put_line ('--------------------------------------------------');  
			  DBMS_OUTPUT.put_line (rpad('TOTAL',30) ||'|' || :l_sum_wait_time);
			  if (:l_sum_wait_time !=  c_4.global_self_wait_time ) then
				DBMS_OUTPUT.put_line (rpad('WAIT TIME NOT ASSIGNED TO ANY DB CALL',38) ||'|' || (:l_sum_wait_time - c_4.global_self_wait_time));
			  end if;
			  
			  
  if ( ((  (c_4.golbal_response_time - c_4.global_self_response_time ) /c_4.golbal_response_time)*100 ) > :l_min_recusive_response_time ) then 			  
  
    --Display recursive statement			  
	DBMS_OUTPUT.new_line;
	DBMS_OUTPUT.new_line;
    DBMS_OUTPUT.put_line ('RECURSIVE STATEMENTS');
	DBMS_OUTPUT.put_line ('--------------------------------------------------'); 
	DBMS_OUTPUT.put_line (rpad('SQLID',20) ||'|'|| 'RESPONSE TIME');
	DBMS_OUTPUT.put_line ('--------------------------------------------------'); 
	
	for c_recur in (
WITH recursive_statement
     AS (SELECT s1.*
           FROM TRCEXTPROF_GEANOLGY_TEXT s2, TRCEXTPROF_GEANOLGY_TEXT s1
          WHERE     s2.sqlid = c_4.sqlid and s2.u_id = c_4.u_id and s2.hv = c_4.hv and s2.dep = c_4.dep  AND s2.text= c_4.text  
                AND s2.dep < s2.dep_pre
                AND s1.row_num > s2.call_begin
                AND s1.row_num < s2.row_num
                AND s1.dep = s2.dep + 1)
  SELECT sqlid,text,u_id ,SUM (all_wait_time + cpu_time) total_response_time
    FROM recursive_statement
GROUP BY sqlid,text,u_id
ORDER BY 2 DESC) loop

dbms_output.put_line(rpad(c_recur.sqlid,14)|| case  when c_recur.u_id = 0 then '(SYS) ' else '      ' end ||'|'|| rpad(c_recur.total_response_time,10) ||'  ('||rpad( ROUND((c_recur.total_response_time/c_4.golbal_response_time)*100,2),6) || '%)' ||' | ' || c_recur.text );

end loop;	

else 

if ((c_4.global_self_response_time/c_4.golbal_response_time)*100 != 100 )
then 
 DBMS_OUTPUT.NEW_LINE;
 DBMS_OUTPUT.NEW_LINE;
 DBMS_OUTPUT.put_line ('----------');
 DBMS_OUTPUT.put_line ('Recursive statements consume less than '|| :l_min_recusive_response_time ||' of response time');
 
end if;

end if;	  
			  DBMS_OUTPUT.NEW_LINE; 
			  DBMS_OUTPUT.NEW_LINE; 
			  DBMS_OUTPUT.put_line (RPAD('CALLS',15)||'|'||RPAD('COUNT',10)||'|'||RPAD('MISS',5)||'|'||RPAD('RESP_TIME',10)||'|'||RPAD('CPU_TIME',10)||'|'||RPAD('ELA_TIME',10)||'|'||RPAD('PIO',5)||'|'||RPAD('CR',5)||'|'||RPAD('CUR',5)||'|'||RPAD('S_RESP_TIME',11)||'|'||RPAD('S_CPU_TIME',10)||'|'||RPAD('S_ELA_TIME',9)||'|'||RPAD('S_PIO',6)||'|'||RPAD('S_CR',6)||'|'||RPAD('S_CUR',6)||'|'||RPAD('NB_ROWS',10));
			  DBMS_OUTPUT.put_line ('------------------------------------------------------------------------------------------------------------------------------------------------------');
  
	  
			  
		  end if;
		  
		  DBMS_OUTPUT.put_line ( RPAD(c_4.call_name,15) ||'|'|| RPAD(c_4.COUNT,10) ||'|'|| RPAD(c_4.miss,5)||'|'|| RPAD(c_4.total_response_time,10)||'|'|| RPAD(c_4.cpu_time,10)||'|'|| RPAD(c_4.ela_time,10)||'|'|| RPAD(c_4.pio,5)||'|'|| RPAD(c_4.cr,5)||'|'|| RPAD(c_4.cur,5)||'|'|| RPAD(c_4.self_response_time,11)||'|'|| RPAD(c_4.self_cpu_time,13)||'|'|| RPAD(c_4.self_ela_time,9)||'|'|| RPAD(c_4.self_pio,6)||'|'|| RPAD(c_4.self_cr,6)||'|'|| RPAD(c_4.self_cur,6)||'|'||RPAD(c_4.nb_rows,10));
		  
		 
end loop;		 
		 
		 
execute immediate 'truncate table TRCEXTPROF_BINDS';
execute immediate 'truncate table TRCEXTPROF_STATS';
execute immediate 'truncate table TRCEXTPROF_BASE_CURSOR';
execute immediate 'truncate table TRCEXTPROF_SQLGEANOLOGY';
execute immediate 'truncate table TRCEXTPROF_WAITS';	
execute immediate 'truncate table TRCEXTPROF_GEANOLGY_TEXT';
 
END;

/

