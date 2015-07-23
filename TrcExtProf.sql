/*
# TrcExtProf.sql
#
# TrcExtProf is a sql script for analyzing raw trace file and generating a formatted output.
# This script need near zero installation all you need is the creation of an external table and that's it.(That have a serious impact on performance i will revise the approach in the next version)
# You can customize the code as you want (add new sections,metrics,join with other views ,etc) and all you need is SQL you don't need to know any other
# programing language (perl,D,etc) and that's one of the primary goal of this script. The combination of external tables + regexp queries give us a powerful tools, special thanks goes
# to nikolay savvinov for inspiring  me after reading his blog post on http://savvinov.com/2014/09/08/querying-trace-files/
#
# The analyzis done by the script are based on this key metrics :
#
# Response time = Idle wait time + non-idle Waits time + CPU time
# Self Response time = Response time - recursive statement Response time
#
#
# Usage:  @TrcExtProf.sql tracefile.trc
# Parameters : (can be adjusted in the DECLARE section of the PL/SQL block)
#
# l_min_response_time : Statement which contribute less than this threshold to the total response time will not be diplayed in the TOP SQL section
# l_min_recusive_response_time : Statement which contribute less than this threshold to the parent statement response time will not be diplayed in the RECURSIVE STATEMENT section
#
#
#
# Author : Hatem Mahmoud <h.mahmoud87@gmail.com>
# BLOG 	 : https://mahmoudhatem.wordpress.com
#
# Version TrcExtProf 1.0 BETA
# Note: this is an experimental script, use at your own risk
#
# IMPORTANT NOTES :
# - There script don't behave correctly when having errors in trace files  like 'PARSE ERROR' will be fixed soon
# - I added the materialize hint in some query do to Bug 13873885  Wrong results from RECNUM column in external table
# - The script have poor response time  will be fixed soon
#
# External table script to run :

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

*/

SET SERVEROUTPUT ON FORMAT WRAPPED
set linesize 2000;
set echo off;
set define on;
 
DECLARE

--Threshold
l_min_response_time number := 10;
l_min_recusive_response_time number := 10;


l_max_time number;
l_min_time number;
last_call_time number;
l_total_response_time number;
l_total_wait_time number;
l_total_cpu_time number;
l_total_unaccounted_for number;
nb_recursive_stat number;
nb_internal_stat number;
nb_total_stat number;
nb_distinct_stat number;
l_prev_sql varchar2(4000);
l_prev_plan varchar2(4000);
l_sum_wait_time number;
l_final_line number;

cursor c_general_info is (SELECT (MAX (REGEXP_REPLACE (text, '(.*)tim=(\S*)(.*)', '\2')) / 10E5) max_tim,
       (MIN (REGEXP_REPLACE (text, '(.*)tim=(\S*)(.*)', '\2')) / 10E5) min_tim,
       MAX (
          CASE
             WHEN text LIKE ('PARSE%dep=0%')
             THEN
                REGEXP_REPLACE (text, '(.*)tim=(\S*)(.*)', '\2') / 10E5
             WHEN text LIKE ('EXEC%dep=0%')
             THEN
                REGEXP_REPLACE (text, '(.*)tim=(\S*)(.*)', '\2') / 10E5
             WHEN text LIKE ('FETCH%dep=0%')
             THEN
                REGEXP_REPLACE (text, '(.*)tim=(\S*)(.*)', '\2') / 10E5
             WHEN text LIKE ('CLOSE%dep=0%')
             THEN
                REGEXP_REPLACE (text, '(.*)tim=(\S*)(.*)', '\2') / 10E5
          END) max_tim_db_call,
       SUM (
          CASE
             WHEN text LIKE ('PARSING%')
             THEN
                DECODE (REGEXP_REPLACE (text, '(.*)uid=(\S*)(.*)', '\2'),
                        0, 1,
                        0)
             ELSE
                0
          END) nb_internal_stat,
       SUM (
          CASE
             WHEN text LIKE ('PARSING%')
             THEN
                DECODE (INSTR (text, 'dep=0'), 0, 1, 0)
             ELSE
                0
          END) nb_recursive_stat,
         COUNT (
            DISTINCT (CASE
                         WHEN text LIKE ('PARSING%')
                         THEN
                            REGEXP_REPLACE (text,
                                            '(.*)sqlid=''(\S*)''(.*)',
                                            '\2')
                         ELSE
                            '0'
                      END))
       - 1 nb_distinct_stat,
       SUM (CASE WHEN text LIKE ('PARSING%') THEN 1 END) nb_stat,
	   max(row_num) final_line
  FROM RAWTRACEFILE
 WHERE text LIKE '%tim=%');

BEGIN
l_prev_plan := 0;
l_prev_sql :='null';
l_total_wait_time := 0.0;
l_total_cpu_time  := 0.0;
  
 DBMS_OUTPUT.NEW_LINE;
 DBMS_OUTPUT.put_line ('===================================================================================');
 DBMS_OUTPUT.put_line ('=============================TrcExtProf V1.0 BETA==================================');
 DBMS_OUTPUT.put_line ('===================================================================================');
 DBMS_OUTPUT.put_line ('        ===================================================================        ');
 DBMS_OUTPUT.NEW_LINE;
 
 execute immediate 'ALTER TABLE RAWTRACEFILE LOCATION(''&1'') ';

 DBMS_OUTPUT.NEW_LINE;
 DBMS_OUTPUT.put_line ('*************************************************************');
 DBMS_OUTPUT.put_line ('TRACE INFO');
 DBMS_OUTPUT.put_line ('*************************************************************');
 DBMS_OUTPUT.NEW_LINE;

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
 
 DBMS_OUTPUT.NEW_LINE;
 DBMS_OUTPUT.put_line ('*************************************************************');
 DBMS_OUTPUT.put_line ('SUMMARY');
 DBMS_OUTPUT.put_line ('*************************************************************');
 DBMS_OUTPUT.NEW_LINE;
 
 open c_general_info;
 FETCH c_general_info  into l_max_time,l_min_time,last_call_time,nb_internal_stat,nb_recursive_stat,nb_distinct_stat,nb_total_stat,l_final_line;

 l_total_response_time := l_max_time - l_min_time;

  DBMS_OUTPUT.put_line(rpad('Trace file name ',43)||': &1' );
  DBMS_OUTPUT.put_line ( rpad('Total trace response time ',43)||': ' || l_total_response_time);
  DBMS_OUTPUT.put_line ( rpad('SQL statements in trace file ',43)||': ' || nb_total_stat);
  DBMS_OUTPUT.put_line ( rpad('Internal SQL statements in trace file ',43)||': ' || nb_internal_stat);
  DBMS_OUTPUT.put_line ( rpad('Unique SQL statements in trace file ',43)||': ' || nb_distinct_stat);
  DBMS_OUTPUT.put_line ( rpad('Recursive SQL statements in trace file ' ,43)||': '|| nb_recursive_stat);
       

 DBMS_OUTPUT.NEW_LINE;
 DBMS_OUTPUT.put_line ('*************************************************************');
 DBMS_OUTPUT.put_line ('DATABASE CALL STATISTICS WITH RECURSIVE STATEMENTS');
 DBMS_OUTPUT.put_line ('*************************************************************');
 DBMS_OUTPUT.NEW_LINE;
 DBMS_OUTPUT.put_line ('CALLS          |COUNT     |MISS      |CPU_TIME  |ELA_TIME  |PIO       |CR        |CUR       |NB_ROWS');
 DBMS_OUTPUT.put_line ('--------------------------------------------------------------------------------------------------------');

 FOR c_3 IN (WITH  sql_geanolgy
     AS (SELECT row_num,
                REGEXP_REPLACE (text, '(.*)tim=(\S*)(.*)', '\2') tim,
                REGEXP_REPLACE (text,
                                '(EXEC|PARSE|FETCH|CLOSE) (\S*)(.*)',
                                '\1')
                   call_name,
                TO_NUMBER (
                   CASE
                      WHEN text NOT LIKE 'CLOSE %'
                      THEN
                         REGEXP_REPLACE (text, '(.*)mis=(\S*),r=(.*)', '\2')
                      ELSE
                         '0'
                   END)
                   AS miss,
                REGEXP_REPLACE (text, '(.*) #(\d*):(.*)', '\2') AS curnum,
                CASE
                   WHEN text NOT LIKE 'CLOSE %'
                   THEN
                      REGEXP_REPLACE (text, '(.*)dep=(\S*),og(.*)', '\2')
                   ELSE
                      REGEXP_REPLACE (text, '(.*)dep=(\S*),type=(.*)', '\2')
                END
                   AS dep,
                CASE
                   WHEN (CASE
                            WHEN text NOT LIKE 'CLOSE %'
                            THEN
                               REGEXP_REPLACE (text,
                                               '(.*)dep=(\S*),og(.*)',
                                               '\2')
                            ELSE
                               REGEXP_REPLACE (text,
                                               '(.*)dep=(\S*),type=(.*)',
                                               '\2')
                         END) <
                           (LAG (
                               CASE
                                  WHEN text NOT LIKE 'CLOSE %'
                                  THEN
                                     REGEXP_REPLACE (text,
                                                     '(.*)dep=(\S*),og(.*)',
                                                     '\2')
                                  ELSE
                                     REGEXP_REPLACE (
                                        text,
                                        '(.*)dep=(\S*),type=(.*)',
                                        '\2')
                               END)
                            OVER (ORDER BY ROW_NUM))
                   THEN
                      NVL (
                         MAX (
                            row_num)
                         OVER (
                            PARTITION BY (CASE
                                             WHEN text NOT LIKE 'CLOSE %'
                                             THEN
                                                REGEXP_REPLACE (
                                                   text,
                                                   '(.*)dep=(\S*),og(.*)',
                                                   '\2')
                                             ELSE
                                                REGEXP_REPLACE (
                                                   text,
                                                   '(.*)dep=(\S*),type=(.*)',
                                                   '\2')
                                          END)
                            ORDER BY ROWNUM
                            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),
                         0)
                END
                   AS call_begin,
                  TO_NUMBER (
                     CASE
                        WHEN text NOT LIKE 'CLOSE %'
                        THEN
                           REGEXP_REPLACE (text, '(.*)c=(\S*),e=(.*)', '\2')
                        ELSE
                           REGEXP_REPLACE (text, '(.*)c=(\S*),e=(.*)', '\2')
                     END)
                / 10E5
                   cpu_time,
                  TO_NUMBER (
                     CASE
                        WHEN text NOT LIKE 'CLOSE %'
                        THEN
                           REGEXP_REPLACE (text, '(.*)e=(\S*),p=(.*)', '\2')
                        ELSE
                           REGEXP_REPLACE (text,
                                           '(.*)e=(\S*),dep=(.*)',
                                           '\2')
                     END)
                / 10E5
                   ela_time,
                TO_NUMBER (
                   CASE
                      WHEN text NOT LIKE 'CLOSE %'
                      THEN
                         REGEXP_REPLACE (text, '(.*)p=(\S*),cr=(.*)', '\2')
                      ELSE
                         '0'
                   END)
                   pio,
                TO_NUMBER (
                   CASE
                      WHEN text NOT LIKE 'CLOSE %'
                      THEN
                         REGEXP_REPLACE (text, '(.*)cr=(\S*),cu=(.*)', '\2')
                      ELSE
                         '0'
                   END)
                   Cr,
                TO_NUMBER (
                   CASE
                      WHEN text NOT LIKE 'CLOSE %'
                      THEN
                         REGEXP_REPLACE (text, '(.*)cu=(\S*),mis=(.*)', '\2')
                      ELSE
                         '0'
                   END)
                   Cur,
                TO_NUMBER (
                   CASE
                      WHEN text NOT LIKE 'CLOSE %'
                      THEN
                         REGEXP_REPLACE (text, '(.*)r=(\S*),dep=(.*)', '\2')
                      ELSE
                         '0'
                   END)
                   nb_rows
           FROM RAWTRACEFILE
          WHERE    text LIKE 'PARSE #%'
                OR text LIKE 'EXEC #%'
                OR text LIKE 'FETCH #%'
                OR text LIKE 'CLOSE #%'),
     sql_geanolgy_with_self
     AS (SELECT g.call_name,
                g.nb_rows,
                g.miss,
                CASE
                   WHEN  call_begin IS NOT NULL
                   THEN
                        g.pio
                      - (SELECT SUM (pio)
                           FROM sql_geanolgy self
                          WHERE     self.row_num < g.row_num
                                AND self.row_num > g.call_begin
                                AND self.dep = g.dep + 1)
                   ELSE
                      g.pio
                END
                   AS self_pio,
                CASE
                   WHEN call_begin IS NOT NULL
                   THEN
                        g.cr
                      - (SELECT SUM (cr)
                           FROM sql_geanolgy self
                          WHERE     self.row_num < g.row_num
                                AND self.row_num > g.call_begin
                                AND self.dep = g.dep + 1)
                   ELSE
                      g.cr
                END
                   AS self_cr,
                CASE
                   WHEN call_begin IS NOT NULL
                   THEN
                        g.cur
                      - (SELECT SUM (cur)
                           FROM sql_geanolgy self
                          WHERE     self.row_num < g.row_num
                                AND self.row_num > g.call_begin
                                AND self.dep = g.dep + 1)
                   ELSE
                      g.cur
                END
                   AS self_cur,
                CASE
                   WHEN call_begin IS NOT NULL
                   THEN
                        g.cpu_time
                      - (SELECT SUM (cpu_time)
                           FROM sql_geanolgy self
                          WHERE     self.row_num < g.row_num
                                AND self.row_num > g.call_begin
                                AND self.dep = g.dep + 1)
                   ELSE
                      g.cpu_time
                END
                   AS self_cpu_time,
                CASE
                   WHEN call_begin IS NOT NULL
                   THEN
                        g.ela_time
                      - (SELECT SUM (ela_time)
                           FROM sql_geanolgy self
                          WHERE     self.row_num < g.row_num
                                AND self.row_num > g.call_begin
                                AND self.dep = g.dep + 1)
                   ELSE
                      g.ela_time
                END
                   AS self_ela_time
           FROM sql_geanolgy g)
  SELECT call_name,
         COUNT (*) COUNT,
         SUM (self_ela_time) AS ela_time,
         SUM (self_cpu_time) AS cpu_time,
         SUM (miss) AS miss,
         SUM (self_pio) AS pio,
         SUM (self_cur) AS cur,
         SUM (self_cr) AS cr,
         SUM (nb_rows) AS nb_rows
    FROM sql_geanolgy_with_self
GROUP BY call_name        
) LOOP
    DBMS_OUTPUT.put_line ( RPAD(c_3.call_name,15) ||'|'|| RPAD(c_3.COUNT,10) ||'|'|| RPAD(c_3.miss,10)||'|'|| RPAD(c_3.cpu_time,10)||'|'|| RPAD(c_3.ela_time,10)||'|'|| RPAD(c_3.pio,10)||'|'|| RPAD(c_3.cr,10)||'|'|| RPAD(c_3.cur,10)||'|'|| RPAD(c_3.nb_rows,10));
	l_total_cpu_time := c_3.cpu_time + l_total_cpu_time ;	
END LOOP;

  
 DBMS_OUTPUT.NEW_LINE;
 DBMS_OUTPUT.put_line ('*************************************************************');
 DBMS_OUTPUT.put_line ('RESOURCE USAGE PROFILE');
 DBMS_OUTPUT.put_line ('*************************************************************');
 DBMS_OUTPUT.NEW_LINE;
 DBMS_OUTPUT.put_line ('EVENT                              |ELA_S     |MIN_ELA_S |MAX_ELA_S |AVG_ELA_S |EVENT_NB  |%Resp time');
 DBMS_OUTPUT.put_line ('--------------------------------------------------------------------------------------------------------');
  
  for c_2 in (
SELECT *
  FROM ( SELECT REGEXP_REPLACE (text, '(.*)nam=''(.*)''(.*)', '\2') event,
                   SUM (
                      TO_NUMBER (
                         REGEXP_REPLACE (text, '(.*)ela= (\S*)(.*)', '\2')))
                 / 10E5
                    ela_s,
                   MIN (
                      TO_NUMBER (
                         REGEXP_REPLACE (text, '(.*)ela= (\S*)(.*)', '\2')))
                 / 10E5
                    min_ela_s,
                   MAX (
                      TO_NUMBER (
                         REGEXP_REPLACE (text, '(.*)ela= (\S*)(.*)', '\2')))
                 / 10E5
                    max_ela_s,
                   AVG (
                      TO_NUMBER (
                         REGEXP_REPLACE (text, '(.*)ela= (\S*)(.*)', '\2')))
                 / 10E5
                    avg_ela_s,
                 COUNT (*) event_nb
            FROM RAWTRACEFILE
           WHERE text LIKE 'WAIT%'
        GROUP BY REGEXP_REPLACE (text, '(.*)nam=''(.*)''(.*)', '\2')
        ORDER BY 2 DESC)
 WHERE ROWNUM < 6) loop
 
  DBMS_OUTPUT.put_line ( rpad(c_2.event,35) ||'|'|| rpad(c_2.ela_s,10)  ||'|'||  rpad(c_2.min_ela_s,10)  ||'|'||  rpad( c_2.max_ela_s,10)  ||'|'||   rpad( c_2.avg_ela_s,10)  ||'|'||   rpad( c_2.event_nb,10)  ||'|'||rpad(round((c_2.ela_s/l_total_response_time)*100,2),10)   );
    l_total_wait_time := l_total_wait_time + c_2.ela_s;
 end loop;
 
      
 l_total_unaccounted_for :=  l_total_response_time - l_total_cpu_time - l_total_wait_time;
 DBMS_OUTPUT.put_line ( rpad('CPU',35) ||'|'|| rpad( l_total_cpu_time,10) ||'|'||  rpad( ' ',10) ||'|'||  rpad( ' ',10) ||'|'||  rpad( ' ',10) ||'|'||  rpad( ' ',10)   ||'|'||  rpad(round((l_total_cpu_time/l_total_response_time)*100,2),10) );
 DBMS_OUTPUT.put_line ( rpad('Unaccounted-for Time',35) ||'|'|| rpad( l_total_unaccounted_for,10) ||'|'||  rpad( ' ',10) ||'|'||  rpad( ' ',10) ||'|'||  rpad( ' ',10) ||'|'||  rpad( ' ',10)   ||'|'||  rpad(round((l_total_unaccounted_for/l_total_response_time)*100,2),10));
 
 DBMS_OUTPUT.NEW_LINE;
 DBMS_OUTPUT.put_line ('*************************************************************');
 DBMS_OUTPUT.put_line ('TOP SQL OVERVIEW (ONLY NON RECURSIVE STATEMENTS)');
 DBMS_OUTPUT.put_line ('*************************************************************');
 DBMS_OUTPUT.NEW_LINE;
 
 
 DBMS_OUTPUT.put_line (rpad('%TOTAL_RESPONSE_TIME',10)  ||'|'||rpad('TOTAL_RESPONSE_TIME',10)  ||'|'||rpad('E_TIME',10)  ||'|'||rpad('CPU_TIME',10) ||'|'||rpad('SELF_RESPONSE_TIME',10)   ||'|'||rpad('SELF_ELA_TIME',10)  ||'|'||rpad('SELF_CPU_TIME',10)  ||'|'||rpad('EXECS',5)  ||'|'||rpad('USER',5)  ||'|'||rpad('SQLID',10) ||'|'||rpad('PLAN_HASH',10) ||'|'||rpad('TEXT',500)  );
 DBMS_OUTPUT.put_line ('--------------------------------------------------------------------------------------------------------');

 
for c_3 in (
WITH     wait_events
     AS (SELECT /*+ materialize */
               row_num,
               REGEXP_REPLACE (text, '(.*) #(\d*):(.*)', '\2') AS curnum,       
                  TO_NUMBER (
                     REGEXP_REPLACE (text, '(.*)ela= (\S*)(.*)', '\2'))
                / 10E5
                   ela_s
           FROM RAWTRACEFILE
          WHERE text LIKE 'WAIT%'),
     base_cursor
     AS (  SELECT  row_num,
                  CASE
                     WHEN text LIKE 'CLOSE%'
                     THEN
                        'CLOSE'
                     WHEN text LIKE 'PARSING IN CURSOR%'
                     THEN
                        'PARSING IN CURSOR'
                     WHEN text LIKE 'END OF STMT%'
                     THEN
                        'END OF STMT'
                  END
                     AS call_name,
                  CASE
                     WHEN    text LIKE 'PARSING IN CURSOR %'
                          OR text LIKE 'CLOSE %'
                     THEN
                        REGEXP_REPLACE (text, '(.*)#(\d*)(.*)', '\2')
                  END
                     AS curnum,
                  CASE
                     WHEN text LIKE 'PARSING IN CURSOR %'
                     THEN
                        REGEXP_REPLACE (text, '(.*)sqlid=''(\S*)''(.*)', '\2')
                  END
                     AS sqlid,
                  CASE
                     WHEN text LIKE 'PARSING IN CURSOR %'
                     THEN
                        REGEXP_REPLACE (text, '(.*) dep=(\d*) (.*)', '\2')
                  END
                     AS dep,
                  CASE
                     WHEN text LIKE 'PARSING IN CURSOR %'
                     THEN
                        REGEXP_REPLACE (text, '(.*) uid=(\d*) (.*)', '\2')
                  END
                     AS u_id,
                  CASE
                     WHEN text LIKE 'PARSING IN CURSOR %'
                     THEN
                        REGEXP_REPLACE (text, '(.*) hv=(\d*) (.*)', '\2')
                  END
                     AS hv,
                  CASE
                     WHEN text LIKE 'PARSING IN CURSOR %'
                     THEN
                        LEAD (row_num) OVER (ORDER BY ROW_NUM)
                  END
                     AS end_text
             FROM RAWTRACEFILE
            WHERE    text LIKE 'PARSING IN CURSOR %'
                  OR text LIKE 'CLOSE%'
                  OR text LIKE 'END OF STMT%'
         ORDER BY row_num),
     base_cursor_with_limit1
     AS (  SELECT b.*,
                  CASE
                     WHEN call_name = 'PARSING IN CURSOR'
                     THEN
                        (SELECT MAX (i.row_num)
                           FROM base_cursor i
                          WHERE     i.curnum = b.curnum
                                AND i.row_num < b.row_num
                                AND i.call_name = 'CLOSE')
                  END
                     curs_num_begin,
                  CASE
                     WHEN call_name = 'PARSING IN CURSOR'
                     THEN
                        (SELECT MIN (i.row_num)
                           FROM base_cursor i
                          WHERE     i.curnum = b.curnum
                                AND i.row_num > b.row_num
                                AND i.call_name = 'PARSING IN CURSOR')
                  END
                     parsein_curs_next
             FROM base_cursor b
        ORDER BY  b.row_num  ),
     base_cursor_with_limit2
     AS (SELECT b.*,
                CASE
                   WHEN call_name = 'PARSING IN CURSOR'
                   THEN
                      (SELECT MAX (i.row_num)
                         FROM base_cursor i
                        WHERE     i.curnum = b.curnum
                              AND i.row_num >
                                     NVL2 (b.curs_num_begin,
                                           b.curs_num_begin,
                                           0)
                              AND i.row_num <
                                     NVL2 (b.parsein_curs_next,
                                           b.parsein_curs_next,
                                           l_final_line)
                              AND i.call_name = 'CLOSE')
                END
                   curs_num_end
           FROM base_cursor_with_limit1 b),
     base_cursor_with_text
     AS (   SELECT  b.*, r.text
             FROM base_cursor_with_limit2 b
                  LEFT OUTER JOIN RAWTRACEFILE r
                     ON r.row_num < b.end_text AND r.row_num > b.row_num
            WHERE b.call_name = 'PARSING IN CURSOR'
         ORDER BY b.row_num),
     sql_geanolgy
     AS (  SELECT row_num,
                  REGEXP_REPLACE (text, '(.*)tim=(\S*)(.*)', '\2') tim,
                  REGEXP_REPLACE (text,
                                  '(EXEC|PARSE|FETCH|CLOSE) (\S*)(.*)',
                                  '\1')
                     call_name,               
                  REGEXP_REPLACE (text, '(.*) #(\d*):(.*)', '\2') AS curnum,
                  CASE
                     WHEN text NOT LIKE 'CLOSE %'
                     THEN
                        REGEXP_REPLACE (text, '(.*)dep=(\S*),og(.*)', '\2')
                     ELSE
                        REGEXP_REPLACE (text, '(.*)dep=(\S*),type=(.*)', '\2')
                  END
                     AS dep,
                  LAG (
                     CASE
                        WHEN text NOT LIKE 'CLOSE %'
                        THEN
                           REGEXP_REPLACE (text, '(.*)dep=(\S*),og(.*)', '\2')
                        ELSE
                           REGEXP_REPLACE (text,
                                           '(.*)dep=(\S*),type=(.*)',
                                           '\2')
                     END)
                  OVER (ORDER BY ROW_NUM)
                     AS dep_pre,
                  CASE
                     WHEN (CASE
                              WHEN text NOT LIKE 'CLOSE %'
                              THEN
                                 REGEXP_REPLACE (text,
                                                 '(.*)dep=(\S*),og(.*)',
                                                 '\2')
                              ELSE
                                 REGEXP_REPLACE (text,
                                                 '(.*)dep=(\S*),type=(.*)',
                                                 '\2')
                           END) <
                             (LAG (
                                 CASE
                                    WHEN text NOT LIKE 'CLOSE %'
                                    THEN
                                       REGEXP_REPLACE (text,
                                                       '(.*)dep=(\S*),og(.*)',
                                                       '\2')
                                    ELSE
                                       REGEXP_REPLACE (
                                          text,
                                          '(.*)dep=(\S*),type=(.*)',
                                          '\2')
                                 END)
                              OVER (ORDER BY ROW_NUM))
                     THEN
                        NVL (
                           MAX (
                              row_num)
                           OVER (
                              PARTITION BY (CASE
                                               WHEN text NOT LIKE 'CLOSE %'
                                               THEN
                                                  REGEXP_REPLACE (
                                                     text,
                                                     '(.*)dep=(\S*),og(.*)',
                                                     '\2')
                                               ELSE
                                                  REGEXP_REPLACE (
                                                     text,
                                                     '(.*)dep=(\S*),type=(.*)',
                                                     '\2')
                                            END)
                              ORDER BY ROWNUM
                              ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),
                           0)
                     ELSE
                        NVL (
                           MAX (
                              row_num)
                           OVER (
                              PARTITION BY (REGEXP_REPLACE (text,
                                                            '(.*) #(\d*):(.*)',
                                                            '\2'))
                              ORDER BY ROWNUM
                              ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),
                           0)
                  END
                     AS call_begin,
                    TO_NUMBER (
                       CASE
                          WHEN text NOT LIKE 'CLOSE %'
                          THEN
                             REGEXP_REPLACE (text, '(.*)c=(\S*),e=(.*)', '\2')
                          ELSE
                             REGEXP_REPLACE (text, '(.*)c=(\S*),e=(.*)', '\2')
                       END)
                  / 10E5
                     cpu_time,
                    TO_NUMBER (
                       CASE
                          WHEN text NOT LIKE 'CLOSE %'
                          THEN
                             REGEXP_REPLACE (text, '(.*)e=(\S*),p=(.*)', '\2')
                          ELSE
                             REGEXP_REPLACE (text,
                                             '(.*)e=(\S*),dep=(.*)',
                                             '\2')
                       END)
                  / 10E5
                     ela_time
             FROM RAWTRACEFILE
            WHERE    text LIKE 'PARSE #%'
                  OR text LIKE 'EXEC #%'
                  OR text LIKE 'FETCH #%'
                  OR text LIKE 'CLOSE #%'
       ),
     sql_geanolgy_with_self
     AS (SELECT  g.*,
                CASE
                   WHEN dep < dep_pre
                   THEN
                        g.cpu_time
                      - (SELECT SUM (cpu_time)
                           FROM sql_geanolgy self
                          WHERE     self.row_num < g.row_num
                                AND self.row_num > g.call_begin
                                AND self.dep = g.dep + 1)
                   ELSE
                      g.cpu_time
                END
                   AS self_cpu_time,
                CASE
                   WHEN dep < dep_pre
                   THEN
                        g.ela_time
                      - (SELECT SUM (ela_time)
                           FROM sql_geanolgy self
                          WHERE     self.row_num < g.row_num
                                AND self.row_num > g.call_begin
                                AND self.dep = g.dep + 1)
                   ELSE
                      g.ela_time
                END
                   AS self_ela_time,
               case when NVL (g.call_begin, 0) < g.row_num -1 then (SELECT NVL (SUM (ela_s), 0)
                   FROM wait_events w
                  WHERE     w.row_num < g.row_num
                        AND w.row_num > NVL (g.call_begin, 0)
                        AND g.curnum = w.curnum) else 0 end
                   self_wait_ela_s
           FROM sql_geanolgy g),
     sql_geanolgy_with_text
     AS (  SELECT gs.*,
                  CASE
                     WHEN gs.dep < gs.dep_pre
                     THEN
                        (SELECT SUM (self_wait_ela_s)
                           FROM sql_geanolgy_with_self s
                          WHERE     s.row_num < gs.row_num
                                AND s.row_num > gs.call_begin)
                     ELSE
                        self_wait_ela_s
                  END
                     AS all_wait_time,
                  ct.sqlid,
                  ct.text,
                  ct.u_id,
                  ct.hv                  
             FROM sql_geanolgy_with_self gs
                  LEFT OUTER JOIN
                  base_cursor_with_text ct
                     ON     gs.row_num >
                               NVL2 (ct.curs_num_begin, ct.curs_num_begin, 0)
                        AND gs.row_num <=
                               NVL2 (ct.curs_num_end,
                                     ct.curs_num_end,
                                     l_final_line)
                        AND gs.curnum = ct.curnum
         )
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
    FROM sql_geanolgy_with_text
   WHERE dep = 0  GROUP BY sqlid,u_id,hv, text ORDER BY 1 DESC) loop 
  DBMS_OUTPUT.put_line ( rpad( ROUND((c_3.Total_response_time/l_total_response_time)*100,2),10) ||'|'|| rpad(c_3.Total_response_time,10) ||'|'|| rpad(c_3.ela_time,10)  ||'|'||  rpad(c_3.cpu_time,10) ||'|'|| rpad(c_3.self_response_time,10) ||'|'||  rpad( c_3.self_ela_time,10)  ||'|'||   rpad( c_3.self_cpu_time,10)  ||'|'||   rpad( 0||c_3.execs,5)  ||'|'|| rpad( c_3.u_id,5)  ||'|'|| rpad( c_3.sqlid,10)  ||'|'|| rpad( c_3.hv,10)  ||'|'|| rpad( c_3.text,300));
end loop;
 
 
 if (last_call_time <> l_max_time ) then 
 
 DBMS_OUTPUT.NEW_LINE;
 DBMS_OUTPUT.put_line ('-');
 DBMS_OUTPUT.put_line ('TRACE FILE NOT CORRECTLY ENDED (LAST UNKNOWN CALL)');
 DBMS_OUTPUT.put_line ('-');
 DBMS_OUTPUT.NEW_LINE;
 
 
 DBMS_OUTPUT.put_line (rpad('%TOTAL_RESPONSE_TIME',15)  ||'|'||rpad('TOTAL_RESPONSE_TIME',15)  ||'|'||rpad('RECUR_E_TIME',15)  ||'|'||rpad('RECUR_CPU_TIME',15) );
 DBMS_OUTPUT.put_line ('--------------------------------------------------------------------------------------------------------');

 
for c_4 in (
with  sql_geanolgy
     AS (   SELECT row_num,
                  REGEXP_REPLACE (text, '(.*)tim=(\S*)(.*)', '\2') tim,		  
                  REGEXP_REPLACE (text, '(.*) #(\d*):(.*)', '\2') AS curnum,
                 case  when  text NOT LIKE 'CLOSE %'    then  REGEXP_REPLACE (text, '(.*)dep=(\S*),og(.*)', '\2') else REGEXP_REPLACE (text, '(.*)dep=(\S*),type=(.*)', '\2')  end AS dep,
                 CASE
                     WHEN (  case  when  text NOT LIKE 'CLOSE %'    then  REGEXP_REPLACE (text, '(.*)dep=(\S*),og(.*)', '\2') else REGEXP_REPLACE (text, '(.*)dep=(\S*),type=(.*)', '\2')  end ) <
                             (LAG (  case  when  text NOT LIKE 'CLOSE %'    then  REGEXP_REPLACE (text, '(.*)dep=(\S*),og(.*)', '\2') else REGEXP_REPLACE (text, '(.*)dep=(\S*),type=(.*)', '\2')  end )
                              OVER (ORDER BY ROW_NUM))
                     THEN
                       NVL(MAX (
                           row_num)
                        OVER (
                           PARTITION BY  ( case  when  text NOT LIKE 'CLOSE %'    then  REGEXP_REPLACE (text, '(.*)dep=(\S*),og(.*)', '\2') else REGEXP_REPLACE (text, '(.*)dep=(\S*),type=(.*)', '\2') end )  
                           ORDER BY ROWNUM
                           ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),0)
                  END
                     AS call_begin,
                    TO_NUMBER (
                      case  when  text NOT LIKE 'CLOSE %'    then  REGEXP_REPLACE (text, '(.*)c=(\S*),e=(.*)', '\2') else REGEXP_REPLACE (text, '(.*)c=(\S*),e=(.*)', '\2')  end)
                  / 10E5
                     cpu_time,
                    TO_NUMBER (
                         case  when  text NOT LIKE 'CLOSE %'    then  REGEXP_REPLACE (text, '(.*)e=(\S*),p=(.*)', '\2') else  REGEXP_REPLACE (text, '(.*)e=(\S*),dep=(.*)', '\2')  end)
                  / 10E5
                     ela_time
             FROM RAWTRACEFILE
            WHERE    text LIKE 'PARSE #%'
                  OR text LIKE 'EXEC #%'
                  OR text LIKE 'FETCH #%' 
                  OR  text LIKE 'CLOSE #%'                  
         ORDER BY row_num),
     sql_geanolgy_with_self
     AS (SELECT g.*,                
                CASE
                   WHEN call_begin IS NOT NULL
                   THEN
                        g.cpu_time
                      - (SELECT SUM (cpu_time)
                           FROM sql_geanolgy self
                          WHERE     self.row_num < g.row_num
                                AND self.row_num > g.call_begin
                                AND self.dep = g.dep + 1)
                   ELSE
                      g.cpu_time
                END
                   AS self_cpu_time,
                CASE
                   WHEN call_begin IS NOT NULL
                   THEN
                        g.ela_time
                      - (SELECT SUM (ela_time)
                           FROM sql_geanolgy self
                          WHERE     self.row_num < g.row_num
                                AND self.row_num > g.call_begin
                                AND self.dep = g.dep + 1)
                   ELSE
                      g.ela_time
                END
                   AS self_ela_time
           FROM sql_geanolgy g)          
  SELECT    
         SUM (self_ela_time) self_ela_time,
         sum(self_cpu_time) self_cpu_time         
    FROM sql_geanolgy_with_self
	WHERE tim / 10E5 > last_call_time
) loop 
  DBMS_OUTPUT.put_line (  rpad( ROUND(((l_max_time - last_call_time)/l_total_response_time)*100,2),15) ||'|'||    rpad(l_max_time - last_call_time,15) ||'|'||     rpad( c_4.self_ela_time,15)  ||'|'||   rpad( c_4.self_cpu_time,15));
end loop;   
end if;


 DBMS_OUTPUT.NEW_LINE;
 DBMS_OUTPUT.put_line ('*************************************************************');
 DBMS_OUTPUT.put_line ('TOP SQL');
 DBMS_OUTPUT.put_line ('*************************************************************');
 DBMS_OUTPUT.NEW_LINE;


for c_4 in (
WITH wait_events
     AS (SELECT    /*+ materialize */
               row_num,
                REGEXP_REPLACE (text, '(.*) #(\d*):(.*)', '\2') AS curnum,            
                  TO_NUMBER (
                     REGEXP_REPLACE (text, '(.*)ela= (\S*)(.*)', '\2'))
                / 10E5
                   ela_s
           FROM  RAWTRACEFILE
          WHERE text LIKE 'WAIT%'),
     base_cursor
     AS (  SELECT row_num,
                  CASE
                     WHEN text LIKE 'CLOSE%'
                     THEN
                        'CLOSE'
                     WHEN text LIKE 'PARSING IN CURSOR%'
                     THEN
                        'PARSING IN CURSOR'
                     WHEN text LIKE 'END OF STMT%'
                     THEN
                        'END OF STMT'
                  END
                     AS call_name,
                  CASE
                     WHEN    text LIKE 'PARSING IN CURSOR %'
                          OR text LIKE 'CLOSE %'
                     THEN
                        REGEXP_REPLACE (text, '(.*)#(\d*)(.*)', '\2')
                  END
                     AS curnum,
                  CASE
                     WHEN text LIKE 'PARSING IN CURSOR %'
                     THEN
                        REGEXP_REPLACE (text, '(.*)sqlid=''(\S*)''(.*)', '\2')
                  END
                     AS sqlid,
                  CASE
                     WHEN text LIKE 'PARSING IN CURSOR %'
                     THEN
                        REGEXP_REPLACE (text, '(.*) dep=(\d*) (.*)', '\2')
                  END
                     AS dep,
                  CASE
                     WHEN text LIKE 'PARSING IN CURSOR %'
                     THEN
                        REGEXP_REPLACE (text, '(.*) uid=(\d*) (.*)', '\2')
                  END
                     AS u_id,             
                  CASE
                     WHEN text LIKE 'PARSING IN CURSOR %'
                     THEN
                        REGEXP_REPLACE (text, '(.*) hv=(\d*) (.*)', '\2')
                  END
                     AS hv,
                  CASE
                     WHEN text LIKE 'PARSING IN CURSOR %'
                     THEN
                        LEAD (row_num) OVER (ORDER BY ROW_NUM)
                  END
                     AS end_text
             FROM RAWTRACEFILE
            WHERE    text LIKE 'PARSING IN CURSOR %'
                  OR text LIKE 'CLOSE%'
                  OR text LIKE 'END OF STMT%'
         ORDER BY row_num),
     base_cursor_with_limit1
     AS (  SELECT b.*,
                  CASE
                     WHEN call_name = 'PARSING IN CURSOR'
                     THEN
                        (SELECT MAX (i.row_num)
                           FROM base_cursor i
                          WHERE     i.curnum = b.curnum
                                AND i.row_num < b.row_num
                                AND i.call_name = 'CLOSE')
                  END
                     curs_num_begin,
                  CASE
                     WHEN call_name = 'PARSING IN CURSOR'
                     THEN
                        (SELECT MIN (i.row_num)
                           FROM base_cursor i
                          WHERE     i.curnum = b.curnum
                                AND i.row_num > b.row_num
                                AND i.call_name = 'PARSING IN CURSOR')
                  END
                     parsein_curs_next
             FROM base_cursor b
         ORDER BY b.row_num),
     base_cursor_with_limit2
     AS (SELECT b.*,
                CASE
                   WHEN call_name = 'PARSING IN CURSOR'
                   THEN
                      (SELECT MAX (i.row_num)
                         FROM base_cursor i
                        WHERE     i.curnum = b.curnum
                              AND i.row_num >
                                     NVL2 (b.curs_num_begin,
                                           b.curs_num_begin,
                                           0)
                              AND i.row_num <
                                     NVL2 (b.parsein_curs_next,
                                           b.parsein_curs_next,
                                           l_final_line)
                              AND i.call_name = 'CLOSE')
                END
                   curs_num_end
           FROM base_cursor_with_limit1 b),
     base_cursor_with_text
     AS (  SELECT b.*, r.text
             FROM base_cursor_with_limit2 b
                  LEFT OUTER JOIN RAWTRACEFILE r
                     ON r.row_num < b.end_text AND r.row_num > b.row_num
            WHERE b.call_name = 'PARSING IN CURSOR'
         ORDER BY b.row_num),
     sql_geanolgy
     AS (  SELECT row_num,
                  REGEXP_REPLACE (text, '(.*)tim=(\S*)(.*)', '\2') tim,
                  REGEXP_REPLACE (text,
                                  '(EXEC|PARSE|FETCH|CLOSE) (\S*)(.*)',
                                  '\1')
                     call_name,
                  TO_NUMBER (
                     CASE
                        WHEN text NOT LIKE 'CLOSE %'
                        THEN
                           REGEXP_REPLACE (text, '(.*)mis=(\S*),r=(.*)', '\2')
                        ELSE
                           '0'
                     END)
                     AS miss,
                  REGEXP_REPLACE (text, '(.*) #(\d*):(.*)', '\2') AS curnum,
                  CASE
                     WHEN text NOT LIKE 'CLOSE %'
                     THEN
                        REGEXP_REPLACE (text, '(.*)dep=(\S*),og(.*)', '\2')
                     ELSE
                        REGEXP_REPLACE (text, '(.*)dep=(\S*),type=(.*)', '\2')
                  END
                     AS dep,
                  LAG (
                     CASE
                        WHEN text NOT LIKE 'CLOSE %'
                        THEN
                           REGEXP_REPLACE (text, '(.*)dep=(\S*),og(.*)', '\2')
                        ELSE
                           REGEXP_REPLACE (text,
                                           '(.*)dep=(\S*),type=(.*)',
                                           '\2')
                     END)
                  OVER (ORDER BY ROW_NUM)
                     AS dep_pre,
                  CASE
                     WHEN (CASE
                              WHEN text NOT LIKE 'CLOSE %'
                              THEN
                                 REGEXP_REPLACE (text,
                                                 '(.*)dep=(\S*),og(.*)',
                                                 '\2')
                              ELSE
                                 REGEXP_REPLACE (text,
                                                 '(.*)dep=(\S*),type=(.*)',
                                                 '\2')
                           END) <
                             (LAG (
                                 CASE
                                    WHEN text NOT LIKE 'CLOSE %'
                                    THEN
                                       REGEXP_REPLACE (text,
                                                       '(.*)dep=(\S*),og(.*)',
                                                       '\2')
                                    ELSE
                                       REGEXP_REPLACE (
                                          text,
                                          '(.*)dep=(\S*),type=(.*)',
                                          '\2')
                                 END)
                              OVER (ORDER BY ROW_NUM))
                     THEN
                        NVL (
                           MAX (
                              row_num)
                           OVER (
                              PARTITION BY (CASE
                                               WHEN text NOT LIKE 'CLOSE %'
                                               THEN
                                                  REGEXP_REPLACE (
                                                     text,
                                                     '(.*)dep=(\S*),og(.*)',
                                                     '\2')
                                               ELSE
                                                  REGEXP_REPLACE (
                                                     text,
                                                     '(.*)dep=(\S*),type=(.*)',
                                                     '\2')
                                            END)
                              ORDER BY ROWNUM
                              ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),
                           0)
                     ELSE
                        NVL (
                           MAX (
                              row_num)
                           OVER (
                              PARTITION BY (REGEXP_REPLACE (text,
                                                            '(.*) #(\d*):(.*)',
                                                            '\2'))
                              ORDER BY ROWNUM
                              ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),
                           0)
                  END
                     AS call_begin,
                    TO_NUMBER (
                       CASE
                          WHEN text NOT LIKE 'CLOSE %'
                          THEN
                             REGEXP_REPLACE (text, '(.*)c=(\S*),e=(.*)', '\2')
                          ELSE
                             REGEXP_REPLACE (text, '(.*)c=(\S*),e=(.*)', '\2')
                       END)
                  / 10E5
                     cpu_time,
                    TO_NUMBER (
                       CASE
                          WHEN text NOT LIKE 'CLOSE %'
                          THEN
                             REGEXP_REPLACE (text, '(.*)e=(\S*),p=(.*)', '\2')
                          ELSE
                             REGEXP_REPLACE (text,
                                             '(.*)e=(\S*),dep=(.*)',
                                             '\2')
                       END)
                  / 10E5
                     ela_time,
                  TO_NUMBER (
                     CASE
                        WHEN text NOT LIKE 'CLOSE %'
                        THEN
                           REGEXP_REPLACE (text, '(.*)p=(\S*),cr=(.*)', '\2')
                        ELSE
                           '0'
                     END)
                     pio,
                  TO_NUMBER (
                     CASE
                        WHEN text NOT LIKE 'CLOSE %'
                        THEN
                           REGEXP_REPLACE (text, '(.*)cr=(\S*),cu=(.*)', '\2')
                        ELSE
                           '0'
                     END)
                     Cr,
                  TO_NUMBER (
                     CASE
                        WHEN text NOT LIKE 'CLOSE %'
                        THEN
                           REGEXP_REPLACE (text, '(.*)cu=(\S*),mis=(.*)', '\2')
                        ELSE
                           '0'
                     END)
                     Cur,
                  TO_NUMBER (
                     CASE
                        WHEN text NOT LIKE 'CLOSE %'
                        THEN
                           REGEXP_REPLACE (text, '(.*)r=(\S*),dep=(.*)', '\2')
                        ELSE
                           '0'
                     END)
                     nb_rows
             FROM RAWTRACEFILE
            WHERE    text LIKE 'PARSE #%'
                  OR text LIKE 'EXEC #%'
                  OR text LIKE 'FETCH #%'
                  OR text LIKE 'CLOSE #%'
         ORDER BY row_num),
     sql_geanolgy_with_self
     AS (SELECT g.*,
                CASE
                   WHEN dep < dep_pre
                   THEN
                        g.pio
                      - (SELECT SUM (pio)
                           FROM sql_geanolgy self
                          WHERE     self.row_num < g.row_num
                                AND self.row_num > g.call_begin
                                AND self.dep = g.dep + 1)
                   ELSE
                      g.pio
                END
                   AS self_pio,
                CASE
                   WHEN dep < dep_pre
                   THEN
                        g.cr
                      - (SELECT SUM (cr)
                           FROM sql_geanolgy self
                          WHERE     self.row_num < g.row_num
                                AND self.row_num > g.call_begin
                                AND self.dep = g.dep + 1)
                   ELSE
                      g.cr
                END
                   AS self_cr,
                CASE
                   WHEN dep < dep_pre
                   THEN
                        g.cur
                      - (SELECT SUM (cur)
                           FROM sql_geanolgy self
                          WHERE     self.row_num < g.row_num
                                AND self.row_num > g.call_begin
                                AND self.dep = g.dep + 1)
                   ELSE
                      g.cur
                END
                   AS self_cur,
                CASE
                   WHEN dep < dep_pre
                   THEN
                        g.cpu_time
                      - (SELECT SUM (cpu_time)
                           FROM sql_geanolgy self
                          WHERE     self.row_num < g.row_num
                                AND self.row_num > g.call_begin
                                AND self.dep = g.dep + 1)
                   ELSE
                      g.cpu_time
                END
                   AS self_cpu_time,
                CASE
                   WHEN dep < dep_pre
                   THEN
                        g.ela_time
                      - (SELECT SUM (ela_time)
                           FROM sql_geanolgy self
                          WHERE     self.row_num < g.row_num
                                AND self.row_num > g.call_begin
                                AND self.dep = g.dep + 1)
                   ELSE
                      g.ela_time
                END
                   AS self_ela_time,
                case when NVL (g.call_begin, 0) < g.row_num -1 then (SELECT NVL (SUM (ela_s), 0)
                   FROM wait_events w
                  WHERE     w.row_num < g.row_num
                        AND w.row_num > NVL (g.call_begin, 0)
                        AND g.curnum = w.curnum) else 0 end
                   self_wait_ela_s
           FROM sql_geanolgy g),
     sql_geanolgy_with_text
     AS (  SELECT gs.*,
                  CASE
                     WHEN gs.dep < gs.dep_pre
                     THEN
                        (SELECT SUM (self_wait_ela_s)
                           FROM sql_geanolgy_with_self s
                          WHERE     s.row_num < gs.row_num
                                AND s.row_num > gs.call_begin)
                     ELSE
                        self_wait_ela_s
                  END
                     AS all_wait_time,
                  ct.sqlid,
                  ct.text,
                  ct.u_id,
                  ct.hv
             FROM sql_geanolgy_with_self gs
                  LEFT OUTER JOIN
                  base_cursor_with_text ct
                     ON     gs.row_num >
                               NVL2 (ct.curs_num_begin, ct.curs_num_begin, 0)
                        AND gs.row_num <=
                               NVL2 (ct.curs_num_end,
                                     ct.curs_num_end,
                                     l_final_line)
                        AND gs.curnum = ct.curnum
        ),
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
             FROM sql_geanolgy_with_text
         GROUP BY sqlid,
                  u_id,
                  text,
                  hv,
                  dep,
                  call_name ),top_sql_with_global_time as (
  SELECT SUM (top.Total_response_time) OVER (PARTITION BY sqlid, u_id, hv,dep)
            AS golbal_response_time,
         SUM (top.self_response_time) OVER (PARTITION BY sqlid, u_id, hv,dep)
            AS global_self_response_time,
         SUM (top.self_wait_time) OVER (PARTITION BY sqlid, u_id, hv,dep)
            AS global_self_wait_time,
         top.*
    FROM top_sql_1 top 
ORDER BY 1 DESC,
         sqlid,
         UID,
         hv,
         dep,
         call_name DESC) select * from top_sql_with_global_time     where golbal_response_time >  l_total_response_time/l_min_response_time) loop  

		 if ( l_prev_sql!= (c_4.sqlid || c_4.hv || c_4.dep || c_4.u_id )) then
			  
			  l_prev_sql := c_4.sqlid || c_4.hv || c_4.dep || c_4.u_id;
			 
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
	for row_s in (WITH base_cursor
     AS (  SELECT row_num,
                  CASE
                     WHEN text LIKE 'CLOSE%'
                     THEN
                        'CLOSE'
                     WHEN text LIKE 'PARSING IN CURSOR%'
                     THEN
                        'PARSING IN CURSOR'
                     WHEN text LIKE 'END OF STMT%'
                     THEN
                        'END OF STMT'
                  END
                     AS call_name,
                  CASE
                     WHEN    text LIKE 'PARSING IN CURSOR %'
                          OR text LIKE 'CLOSE %'
                     THEN
                        REGEXP_REPLACE (text, '(.*)#(\d*)(.*)', '\2')
                  END
                     AS curnum,
                  CASE
                     WHEN text LIKE 'PARSING IN CURSOR %'
                     THEN
                        REGEXP_REPLACE (text, '(.*)sqlid=''(\S*)''(.*)', '\2')
                  END
                     AS sqlid,
                  CASE
                     WHEN text LIKE 'PARSING IN CURSOR %'
                     THEN
                        REGEXP_REPLACE (text, '(.*) dep=(\d*) (.*)', '\2')
                  END
                     AS dep,
                  CASE
                     WHEN text LIKE 'PARSING IN CURSOR %'
                     THEN
                        REGEXP_REPLACE (text, '(.*) uid=(\d*) (.*)', '\2')
                  END
                     AS u_id,                
                  CASE
                     WHEN text LIKE 'PARSING IN CURSOR %'
                     THEN
                        REGEXP_REPLACE (text, '(.*) hv=(\d*) (.*)', '\2')
                  END
                     AS hv
             FROM RAWTRACEFILE
            WHERE    text LIKE 'PARSING IN CURSOR %'
                  OR text LIKE 'CLOSE%'
                  OR text LIKE 'END OF STMT%'
         ORDER BY row_num),
     base_cursor_with_limit1
     AS (  SELECT b.*,
                  CASE
                     WHEN call_name = 'PARSING IN CURSOR'
                     THEN
                        (SELECT MAX (i.row_num)
                           FROM base_cursor i
                          WHERE     i.curnum = b.curnum
                                AND i.row_num < b.row_num
                                AND i.call_name = 'CLOSE')
                  END
                     curs_num_begin,
                  CASE
                     WHEN call_name = 'PARSING IN CURSOR'
                     THEN
                        (SELECT MIN (i.row_num)
                           FROM base_cursor i
                          WHERE     i.curnum = b.curnum
                                AND i.row_num > b.row_num
                                AND i.call_name = 'PARSING IN CURSOR')
                  END
                     parsein_curs_next
             FROM base_cursor b
         ORDER BY b.row_num),
     base_cursor_with_limit2
     AS (SELECT b.*,
                CASE
                   WHEN call_name = 'PARSING IN CURSOR'
                   THEN
                      (SELECT MAX (i.row_num)
                         FROM base_cursor i
                        WHERE     i.curnum = b.curnum
                              AND i.row_num >
                                     NVL2 (b.curs_num_begin,
                                           b.curs_num_begin,
                                           0)
                              AND i.row_num <
                                     NVL2 (b.parsein_curs_next,
                                           b.parsein_curs_next,
                                           l_final_line)
                              AND i.call_name = 'CLOSE')
                END
                   curs_num_end
           FROM base_cursor_with_limit1 b
          WHERE call_name = 'PARSING IN CURSOR'),
     rowsources
     AS (SELECT b.row_num ident,
                r.row_num,
                REGEXP_REPLACE (text, '(.*)#(\d*)(.*)', '\2') curnum,
                TO_NUMBER (
                   REGEXP_REPLACE (text, '(.*) cnt=(\d*) (.*)', '\2'))
                   cnt,
                TO_NUMBER (
                   REGEXP_REPLACE (text, '(.*) obj=(\d*) (.*)', '\2'))
                   objn,
                TO_NUMBER (REGEXP_REPLACE (text, '(.*) id=(\d*) (.*)', '\2'))
                   o_id,
                TO_NUMBER (
                   REGEXP_REPLACE (text, '(.*) pid=(\d*) (.*)', '\2'))
                   o_pid,
                REGEXP_REPLACE (text, '(.*) op=''(.*)''(.*)', '\2') opera
           FROM RAWTRACEFILE r, base_cursor_with_limit2 b
          WHERE     r.text LIKE 'STAT%'
                AND REGEXP_REPLACE (r.text, '(.*)#(\d*)(.*)', '\2') =
                       b.curnum
                AND r.row_num > NVL (b.curs_num_begin, 0)
                AND r.row_num < NVL (b.curs_num_end, l_final_line)
                AND b.sqlid = c_4.sqlid and b.u_id = c_4.u_id and b.hv = c_4.hv and b.dep = c_4.dep )
    SELECT ident, cnt, (LPAD ('  ', LEVEL - 1) || r.opera) rowsource_op,objn
      FROM rowsources r
CONNECT BY PRIOR o_id = o_pid AND PRIOR ident = ident
START WITH o_id = 1
  ORDER BY ident,o_id)    loop
  
 
  if( l_prev_plan != row_s.ident) 
   then 
	DBMS_OUTPUT.NEW_LINE; 
	DBMS_OUTPUT.put_line (rpad('ROWS',10)  ||'|'||rpad('OPERATION',15));
    DBMS_OUTPUT.put_line ('--------------------------------------------------------------------------------------------------------');
  end if;
  
  DBMS_OUTPUT.put_line (RPAD(row_s.cnt,10) ||'|'|| row_s.rowsource_op || ' (objn : '|| row_s.objn ||')');
  l_prev_plan := row_s.ident ;
  
  end loop;

  
  --Display bind variables
  
  
  if ( c_4.text like '%:%' ) then
  
  DBMS_OUTPUT.NEW_LINE; 
  DBMS_OUTPUT.put_line (rpad('Bind Variables',20) );
  DBMS_OUTPUT.put_line ('--------------------');
  DBMS_OUTPUT.NEW_LINE; 
  
  for c_bind in (
	WITH base_cursor
     AS (  SELECT row_num,
                  CASE
                     WHEN text LIKE 'CLOSE%'
                     THEN
                        'CLOSE'
                     WHEN text LIKE 'PARSING IN CURSOR%'
                     THEN
                        'PARSING IN CURSOR'
                     WHEN text LIKE 'END OF STMT%'
                     THEN
                        'END OF STMT'
                  END
                     AS call_name,
                  CASE
                     WHEN    text LIKE 'PARSING IN CURSOR %'
                          OR text LIKE 'CLOSE %'
                     THEN
                        REGEXP_REPLACE (text, '(.*)#(\d*)(.*)', '\2')
                  END
                     AS curnum,
                  CASE
                     WHEN text LIKE 'PARSING IN CURSOR %'
                     THEN
                        REGEXP_REPLACE (text, '(.*)sqlid=''(\S*)''(.*)', '\2')
                  END
                     AS sqlid,
                  CASE
                     WHEN text LIKE 'PARSING IN CURSOR %'
                     THEN
                        REGEXP_REPLACE (text, '(.*) dep=(\d*) (.*)', '\2')
                  END
                     AS dep,
                  CASE
                     WHEN text LIKE 'PARSING IN CURSOR %'
                     THEN
                        REGEXP_REPLACE (text, '(.*) uid=(\d*) (.*)', '\2')
                  END
                     AS u_id,
                  CASE
                     WHEN text LIKE 'PARSING IN CURSOR %'
                     THEN
                        REGEXP_REPLACE (text, '(.*) hv=(\d*) (.*)', '\2')
                  END
                     AS hv
             FROM RAWTRACEFILE
            WHERE    text LIKE 'PARSING IN CURSOR %'
                  OR text LIKE 'CLOSE%'
                  OR text LIKE 'END OF STMT%'
         ORDER BY row_num),
     base_cursor_with_limit1
     AS (  SELECT b.*,
                  CASE
                     WHEN call_name = 'PARSING IN CURSOR'
                     THEN
                        (SELECT MAX (i.row_num)
                           FROM base_cursor i
                          WHERE     i.curnum = b.curnum
                                AND i.row_num < b.row_num
                                AND i.call_name = 'CLOSE')
                  END
                     curs_num_begin,
                  CASE
                     WHEN call_name = 'PARSING IN CURSOR'
                     THEN
                        (SELECT MIN (i.row_num)
                           FROM base_cursor i
                          WHERE     i.curnum = b.curnum
                                AND i.row_num > b.row_num
                                AND i.call_name = 'PARSING IN CURSOR')
                  END
                     parsein_curs_next
             FROM base_cursor b
         ORDER BY b.row_num),
     base_cursor_with_limit2
     AS (SELECT b.*,
                CASE
                   WHEN call_name = 'PARSING IN CURSOR'
                   THEN
                      (SELECT MAX (i.row_num)
                         FROM base_cursor i
                        WHERE     i.curnum = b.curnum
                              AND i.row_num >
                                     NVL2 (b.curs_num_begin,
                                           b.curs_num_begin,
                                           0)
                              AND i.row_num <
                                     NVL2 (b.parsein_curs_next,
                                           b.parsein_curs_next,
                                           l_final_line)
                              AND i.call_name = 'CLOSE')
                END
                   curs_num_end
           FROM base_cursor_with_limit1 b
          WHERE call_name = 'PARSING IN CURSOR'),
     binds
     AS (SELECT row_num,
                text,
                CASE
                   WHEN text LIKE 'BIND%'
                   THEN
                      REGEXP_REPLACE (text, '(.*) #(\d*):(.*)', '\2')
                END
                   AS curnum
           FROM RAWTRACEFILE
          WHERE    text LIKE 'BIND%'
                OR text LIKE ' Bind#%'
                OR text LIKE '  value=%'),
     binds_with_curnum
     AS (SELECT b.row_num,
                b.text,
                CASE
                   WHEN curnum IS NULL
                   THEN
                      LAG (curnum) IGNORE NULLS OVER (ORDER BY ROWNUM)
                END
                   AS par_cur
           FROM binds b)
SELECT bind.row_num,bind.text
  FROM binds_with_curnum bind, base_cursor_with_limit2 b
 WHERE     b.curnum = bind.par_cur
       AND bind.row_num < NVL (b.curs_num_end, l_final_line)
       AND bind.row_num > NVL (b.curs_num_begin, 0)  AND b.sqlid = c_4.sqlid  and b.u_id = c_4.u_id and b.hv = c_4.hv and b.dep = c_4.dep order by bind.row_num) loop
	   
	   DBMS_OUTPUT.put_line (c_bind.text);
	   
	   end loop;
 end if;	   
  
  
  --Display self wait events
  
  l_sum_wait_time := 0.0;
  DBMS_OUTPUT.NEW_LINE; 
  DBMS_OUTPUT.put_line (rpad('EVENT NAME',30)||'|'||rpad('ELAPSED TIME',30) );
  DBMS_OUTPUT.put_line ('--------------------------------------------------');  
  
	for c_wait in (WITH wait_events
     AS (SELECT /*+ materialize */
               row_num,
                REGEXP_REPLACE (text, '(.*) #(\d*):(.*)', '\2') AS curnum,
                REGEXP_REPLACE (text, '(.*)nam=''(.*)''(.*)', '\2') event,
                  TO_NUMBER (
                     REGEXP_REPLACE (text, '(.*)ela= (\S*)(.*)', '\2'))
                / 10E5
                   ela_s
           FROM RAWTRACEFILE
          WHERE text LIKE 'WAIT%'),
      base_cursor
     AS (  SELECT row_num,
                  CASE
                     WHEN text LIKE 'CLOSE%'
                     THEN
                        'CLOSE'
                     WHEN text LIKE 'PARSING IN CURSOR%'
                     THEN
                        'PARSING IN CURSOR'
                     WHEN text LIKE 'END OF STMT%'
                     THEN
                        'END OF STMT'
                  END
                     AS call_name,
                  CASE
                     WHEN    text LIKE 'PARSING IN CURSOR %'
                          OR text LIKE 'CLOSE %'
                     THEN
                        REGEXP_REPLACE (text, '(.*)#(\d*)(.*)', '\2')
                  END
                     AS curnum,
                  CASE
                     WHEN text LIKE 'PARSING IN CURSOR %'
                     THEN
                        REGEXP_REPLACE (text, '(.*)sqlid=''(\S*)''(.*)', '\2')
                  END
                     AS sqlid,
                  CASE
                     WHEN text LIKE 'PARSING IN CURSOR %'
                     THEN
                        REGEXP_REPLACE (text, '(.*) dep=(\d*) (.*)', '\2')
                  END
                     AS dep,
                  CASE
                     WHEN text LIKE 'PARSING IN CURSOR %'
                     THEN
                        REGEXP_REPLACE (text, '(.*) uid=(\d*) (.*)', '\2')
                  END
                     AS u_id,
                  CASE
                     WHEN text LIKE 'PARSING IN CURSOR %'
                     THEN
                        REGEXP_REPLACE (text, '(.*) hv=(\d*) (.*)', '\2')
                  END
                     AS hv
             FROM RAWTRACEFILE
            WHERE    text LIKE 'PARSING IN CURSOR %'
                  OR text LIKE 'CLOSE%'
                  OR text LIKE 'END OF STMT%'
         ORDER BY row_num),
     base_cursor_with_limit1
     AS (  SELECT b.*,
                  CASE
                     WHEN call_name = 'PARSING IN CURSOR'
                     THEN
                        (SELECT MAX (i.row_num)
                           FROM base_cursor i
                          WHERE     i.curnum = b.curnum
                                AND i.row_num < b.row_num
                                AND i.call_name = 'CLOSE')
                  END
                     curs_num_begin,
                  CASE
                     WHEN call_name = 'PARSING IN CURSOR'
                     THEN
                        (SELECT MIN (i.row_num)
                           FROM base_cursor i
                          WHERE     i.curnum = b.curnum
                                AND i.row_num > b.row_num
                                AND i.call_name = 'PARSING IN CURSOR')
                  END
                     parsein_curs_next
             FROM base_cursor b
         ORDER BY b.row_num),
     base_cursor_with_limit2
     AS (SELECT b.*,
                CASE
                   WHEN call_name = 'PARSING IN CURSOR'
                   THEN
                      (SELECT MAX (i.row_num)
                         FROM base_cursor i
                        WHERE     i.curnum = b.curnum
                              AND i.row_num >
                                     NVL2 (b.curs_num_begin,
                                           b.curs_num_begin,
                                           0)
                              AND i.row_num <
                                     NVL2 (b.parsein_curs_next,
                                           b.parsein_curs_next,
                                           l_final_line)
                              AND i.call_name = 'CLOSE')
                END
                   curs_num_end
           FROM base_cursor_with_limit1 b
          WHERE call_name = 'PARSING IN CURSOR')
	SELECT w.event event_name,sum(ela_s) ela
	FROM wait_events w, base_cursor_with_limit2 b
	WHERE     b.curnum = w.curnum
       AND w.row_num < NVL (b.curs_num_end, l_final_line)
       AND w.row_num > NVL (b.curs_num_begin, 0)   AND b.sqlid = c_4.sqlid and b.u_id = c_4.u_id and b.hv = c_4.hv and b.dep = c_4.dep    group by event order by 2 desc) loop
	   
	   dbms_output.put_line(rpad(c_wait.event_name,30) ||'|' ||c_wait.ela);
	   l_sum_wait_time := l_sum_wait_time + c_wait.ela;
 end loop;
	   
			  DBMS_OUTPUT.put_line ('--------------------------------------------------');  
			  DBMS_OUTPUT.put_line (rpad('TOTAL',30) ||'|' || l_sum_wait_time);
			  if (l_sum_wait_time !=  c_4.global_self_wait_time ) then
				DBMS_OUTPUT.put_line (rpad('WAIT TIME NOT ASSIGNED TO ANY DB CALL',38) ||'|' || (l_sum_wait_time - c_4.global_self_wait_time));
			  end if;
			  
			  
  if (((c_4.global_self_response_time/c_4.golbal_response_time)*100 )< (100 - l_min_recusive_response_time) ) then 		  
    --Display recursive statement			  
	DBMS_OUTPUT.new_line;
	DBMS_OUTPUT.new_line;
    DBMS_OUTPUT.put_line ('RECURSIVE STATEMENTS');
	DBMS_OUTPUT.put_line ('--------------------------------------------------'); 
	DBMS_OUTPUT.put_line (rpad('SQLID',20) ||'|'|| 'RESPONSE TIME');
	DBMS_OUTPUT.put_line ('--------------------------------------------------'); 
	
	for c_recur in (
WITH wait_events
     AS (SELECT /*+ materialize */
               row_num,
                REGEXP_REPLACE (text, '(.*) #(\d*):(.*)', '\2') AS curnum,              
                  TO_NUMBER (
                     REGEXP_REPLACE (text, '(.*)ela= (\S*)(.*)', '\2'))
                / 10E5
                   ela_s
           FROM RAWTRACEFILE
          WHERE text LIKE 'WAIT%'),
     base_cursor
     AS (  SELECT row_num,
                  CASE
                     WHEN text LIKE 'CLOSE%'
                     THEN
                        'CLOSE'
                     WHEN text LIKE 'PARSING IN CURSOR%'
                     THEN
                        'PARSING IN CURSOR'
                     WHEN text LIKE 'END OF STMT%'
                     THEN
                        'END OF STMT'
                  END
                     AS call_name,
                  CASE
                     WHEN    text LIKE 'PARSING IN CURSOR %'
                          OR text LIKE 'CLOSE %'
                     THEN
                        REGEXP_REPLACE (text, '(.*)#(\d*)(.*)', '\2')
                  END
                     AS curnum,
                  CASE
                     WHEN text LIKE 'PARSING IN CURSOR %'
                     THEN
                        REGEXP_REPLACE (text, '(.*)sqlid=''(\S*)''(.*)', '\2')
                  END
                     AS sqlid,
                  CASE
                     WHEN text LIKE 'PARSING IN CURSOR %'
                     THEN
                        REGEXP_REPLACE (text, '(.*) dep=(\d*) (.*)', '\2')
                  END
                     AS dep,
                  CASE
                     WHEN text LIKE 'PARSING IN CURSOR %'
                     THEN
                        REGEXP_REPLACE (text, '(.*) uid=(\d*) (.*)', '\2')
                  END
                     AS u_id,                 
                  CASE
                     WHEN text LIKE 'PARSING IN CURSOR %'
                     THEN
                        REGEXP_REPLACE (text, '(.*) hv=(\d*) (.*)', '\2')
                  END
                     AS hv
             FROM RAWTRACEFILE
            WHERE    text LIKE 'PARSING IN CURSOR %'
                  OR text LIKE 'CLOSE%'
                  OR text LIKE 'END OF STMT%'
         ORDER BY row_num),
     base_cursor_with_limit1
     AS (  SELECT b.*,
                  CASE
                     WHEN call_name = 'PARSING IN CURSOR'
                     THEN
                        (SELECT MAX (i.row_num)
                           FROM base_cursor i
                          WHERE     i.curnum = b.curnum
                                AND i.row_num < b.row_num
                                AND i.call_name = 'CLOSE')
                  END
                     curs_num_begin,
                  CASE
                     WHEN call_name = 'PARSING IN CURSOR'
                     THEN
                        (SELECT MIN (i.row_num)
                           FROM base_cursor i
                          WHERE     i.curnum = b.curnum
                                AND i.row_num > b.row_num
                                AND i.call_name = 'PARSING IN CURSOR')
                  END
                     parsein_curs_next
             FROM base_cursor b
         ORDER BY b.row_num),
     base_cursor_with_limit2
     AS (SELECT b.*,
                CASE
                   WHEN call_name = 'PARSING IN CURSOR'
                   THEN
                      (SELECT MAX (i.row_num)
                         FROM base_cursor i
                        WHERE     i.curnum = b.curnum
                              AND i.row_num >
                                     NVL2 (b.curs_num_begin,
                                           b.curs_num_begin,
                                           0)
                              AND i.row_num <
                                     NVL2 (b.parsein_curs_next,
                                           b.parsein_curs_next,
                                           l_final_line)
                              AND i.call_name = 'CLOSE')
                END
                   curs_num_end
           FROM base_cursor_with_limit1 b
          WHERE b.call_name = 'PARSING IN CURSOR'),
     sql_geanolgy
     AS (  SELECT row_num,
                  REGEXP_REPLACE (text, '(.*)tim=(\S*)(.*)', '\2') tim,                  
                    TO_NUMBER (
                       CASE
                          WHEN text NOT LIKE 'CLOSE %'
                          THEN
                             REGEXP_REPLACE (text, '(.*)c=(\S*),e=(.*)', '\2')
                          ELSE
                             REGEXP_REPLACE (text, '(.*)c=(\S*),e=(.*)', '\2')
                       END)
                  / 10E5
                     cpu_time,
                  REGEXP_REPLACE (text, '(.*) #(\d*):(.*)', '\2') AS curnum,
                  CASE
                     WHEN text NOT LIKE 'CLOSE %'
                     THEN
                        REGEXP_REPLACE (text, '(.*)dep=(\S*),og(.*)', '\2')
                     ELSE
                        REGEXP_REPLACE (text, '(.*)dep=(\S*),type=(.*)', '\2')
                  END
                     AS dep,
                  LAG (
                     CASE
                        WHEN text NOT LIKE 'CLOSE %'
                        THEN
                           REGEXP_REPLACE (text, '(.*)dep=(\S*),og(.*)', '\2')
                        ELSE
                           REGEXP_REPLACE (text,
                                           '(.*)dep=(\S*),type=(.*)',
                                           '\2')
                     END)
                  OVER (ORDER BY ROW_NUM)
                     AS dep_pre,
                  CASE
                     WHEN (CASE
                              WHEN text NOT LIKE 'CLOSE %'
                              THEN
                                 REGEXP_REPLACE (text,
                                                 '(.*)dep=(\S*),og(.*)',
                                                 '\2')
                              ELSE
                                 REGEXP_REPLACE (text,
                                                 '(.*)dep=(\S*),type=(.*)',
                                                 '\2')
                           END) <
                             (LAG (
                                 CASE
                                    WHEN text NOT LIKE 'CLOSE %'
                                    THEN
                                       REGEXP_REPLACE (text,
                                                       '(.*)dep=(\S*),og(.*)',
                                                       '\2')
                                    ELSE
                                       REGEXP_REPLACE (
                                          text,
                                          '(.*)dep=(\S*),type=(.*)',
                                          '\2')
                                 END)
                              OVER (ORDER BY ROW_NUM))
                     THEN
                        NVL (
                           MAX (
                              row_num)
                           OVER (
                              PARTITION BY (CASE
                                               WHEN text NOT LIKE 'CLOSE %'
                                               THEN
                                                  REGEXP_REPLACE (
                                                     text,
                                                     '(.*)dep=(\S*),og(.*)',
                                                     '\2')
                                               ELSE
                                                  REGEXP_REPLACE (
                                                     text,
                                                     '(.*)dep=(\S*),type=(.*)',
                                                     '\2')
                                            END)
                              ORDER BY ROWNUM
                              ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),
                           0)
                     ELSE
                        NVL (
                           MAX (
                              row_num)
                           OVER (
                              PARTITION BY (REGEXP_REPLACE (text,
                                                            '(.*) #(\d*):(.*)',
                                                            '\2'))
                              ORDER BY ROWNUM
                              ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),
                           0)
                  END
                     AS call_begin
             FROM RAWTRACEFILE
            WHERE    text LIKE 'PARSE #%'
                  OR text LIKE 'EXEC #%'
                  OR text LIKE 'FETCH #%'
                  OR text LIKE 'CLOSE #%'
         ORDER BY row_num),
     sql_geanolgy_with_self
     AS (SELECT g.*,
                (case when NVL (g.call_begin, 0) < g.row_num -1 then (SELECT NVL (SUM (ela_s), 0)
                   FROM wait_events w
                  WHERE     w.row_num < g.row_num
                        AND w.row_num > NVL (g.call_begin, 0)
                        AND g.curnum = w.curnum) else 0 end
                 )
                   self_wait_ela_s
           FROM sql_geanolgy g),
     sql_geanolgy_with_text
     AS (  SELECT gs.*,
                  CASE
                     WHEN gs.dep < gs.dep_pre
                     THEN
                        (SELECT SUM (self_wait_ela_s)
                           FROM sql_geanolgy_with_self s
                          WHERE     s.row_num < gs.row_num
                                AND s.row_num > gs.call_begin)
                     ELSE
                        self_wait_ela_s
                  END
                     AS all_wait_time,
                  ct.sqlid,
                  ct.u_id,
                  ct.hv
             FROM sql_geanolgy_with_self gs
                  LEFT OUTER JOIN
                  base_cursor_with_limit2 ct
                     ON     gs.row_num >
                               NVL2 (ct.curs_num_begin, ct.curs_num_begin, 0)
                        AND gs.row_num <=
                               NVL2 (ct.curs_num_end,
                                     ct.curs_num_end,
                                     l_final_line)
                        AND gs.curnum = ct.curnum
            WHERE gs.dep <> 0
         ORDER BY gs.row_num),
     sql_geanolgy_with_text_2
     AS (SELECT gs.*,
                ct.sqlid,
                ct.u_id,
                ct.hv
           FROM sql_geanolgy gs
                LEFT OUTER JOIN
                base_cursor_with_limit2 ct
                   ON     gs.row_num >
                             NVL2 (ct.curs_num_begin, ct.curs_num_begin, 0)
                      AND gs.row_num <=
                             NVL2 (ct.curs_num_end,
                                   ct.curs_num_end,
                                   l_final_line)
                      AND gs.curnum = ct.curnum),
     recursive_statement
     AS (SELECT s1.*
           FROM sql_geanolgy_with_text_2 s2, sql_geanolgy_with_text s1
          WHERE     s2.sqlid = c_4.sqlid and s2.u_id = c_4.u_id and s2.hv = c_4.hv and s2.dep = c_4.dep 
                AND s2.dep < s2.dep_pre
                AND s1.row_num > s2.call_begin
                AND s1.row_num < s2.row_num
                AND s1.dep = s2.dep + 1)
  SELECT sqlid, SUM (all_wait_time + cpu_time) total_response_time
    FROM recursive_statement
GROUP BY sqlid
ORDER BY 2 DESC) loop

dbms_output.put_line(rpad(c_recur.sqlid,20) ||'|'|| c_recur.total_response_time ||'  ('|| ROUND((c_recur.total_response_time/c_4.golbal_response_time)*100,2) || '%)');

end loop;	

else 

if ((c_4.global_self_response_time/c_4.golbal_response_time)*100 != 100 )
then 
 DBMS_OUTPUT.NEW_LINE;
 DBMS_OUTPUT.NEW_LINE;
 DBMS_OUTPUT.put_line ('----------');
 DBMS_OUTPUT.put_line ('Recursive statements consume less than 10% of response time');
 
end if;

end if;	  
			  DBMS_OUTPUT.NEW_LINE; 
			  DBMS_OUTPUT.NEW_LINE; 
			  DBMS_OUTPUT.put_line ('CALLS          |COUNT     |MISS |RESP_TIME |CPU_TIME  |ELA_TIME  |PIO  |CR   |CUR  |S_RESP_TIME|S_CPU_TIME|S_ELA_TIME  |S_PIO |S_CR  |S_CUR |NB_ROWS');
			  DBMS_OUTPUT.put_line ('------------------------------------------------------------------------------------------------------------------------------------------------------');
  
	  
			  
		  end if;
		  
		  DBMS_OUTPUT.put_line ( RPAD(c_4.call_name,15) ||'|'|| RPAD(c_4.COUNT,10) ||'|'|| RPAD(c_4.miss,5)||'|'|| RPAD(c_4.total_response_time,10)||'|'|| RPAD(c_4.cpu_time,10)||'|'|| RPAD(c_4.ela_time,10)||'|'|| RPAD(c_4.pio,5)||'|'|| RPAD(c_4.cr,5)||'|'|| RPAD(c_4.cur,5)||'|'|| RPAD(c_4.self_response_time,11)||'|'|| RPAD(c_4.self_cpu_time,13)||'|'|| RPAD(c_4.self_ela_time,9)||'|'|| RPAD(c_4.self_pio,6)||'|'|| RPAD(c_4.self_cr,6)||'|'|| RPAD(c_4.self_cur,6)||'|'||RPAD(c_4.nb_rows,10));
		  
		 
end loop;		 
		 
 
END;

/
