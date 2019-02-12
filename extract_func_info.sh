gdb oracle <<<"disas $1 " |  awk --non-decimal-data '/(mov|pushq).*\$0x[[:alnum:]]{6,8}(,|$)/{gsub(/[$,]/," ");print "x/1s " $4}' | sort -u  |  gdb oracle | grep "(gdb)" | grep -v "out of bounds"
