#Extact events that are checked in a specified core oracle function
#Example : ./event_extractor.sh kslwtectx

gdb oracle <<< "disas $1" | awk --non-decimal-data '/mov .*,%edi$/{gsub(/[$,]/," ");a=$4}/EventRdbmsErr/{printf "dbkdChkEventRdbmsErr %d\n", a}' | sort -u
gdb oracle <<<"disas $1" | awk --non-decimal-data '/mov .*,%.*cx$/{gsub(/[$,]/," ");a=$4}/mov .*\$.*,%.*dx$/{gsub(/[$,]/," ");b=$4; if (b < 10999 && b > 10000) {c=$4 } }/mov .*\$[0-9a-zA-Z]*,%eax$/{gsub(/[$,]/," "); if ($4 < 10999 && $4 > 10000) {c=$4 }}/dbgdChkEventIntV/{if(b == 18219009 ) {  if ( a != 33882161 ) { printf "dbgdChkEventIntV EDX:%x ECX:%x \n", b,a; } else { printf "dbgdChkEventIntV EDX:%x ECX:%x KST_EVENT:%d \n", b,a,c; }} else {  printf "dbgdChkEventIntV EDX:%x \n", b ;   }  }' | sort -u

