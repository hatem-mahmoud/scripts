/*
* Script from http://www.jlcomp.demon.co.uk/faq/bitwise.html
* Author's name: Connor McDonald
*/


CREATE OR REPLACE package bitops2 is

function bitand(p_dec1 number, p_dec2 number) return varchar2 ;
function bitor(p_dec1 number, p_dec2 number) return varchar2 ;
function bitxor(p_dec1 number, p_dec2 number) return varchar2 ;

end;
/


CREATE OR REPLACE package body bitops2 is

function raw_ascii(p_dec number) return raw is
  v_result varchar2(1999);
  v_tmp1   number := p_dec;
begin
  loop
    v_result := chr(mod(v_tmp1,256)) || v_result ;
    v_tmp1 := trunc(v_tmp1/256);
    exit when v_tmp1 = 0;
  end loop;
  return utl_raw.cast_to_raw(v_result);
end;

function ascii_raw(p_raw varchar2) return number is
  v_result number := 0;
begin
  for i in 1 .. length(p_raw) loop
    v_result := v_result * 256 + ascii(substr(p_raw,i,1));
  end loop;
  return v_result;
end;

function bitand(p_dec1 number, p_dec2 number) return varchar2 is
begin
  return
   ascii_raw(
     utl_raw.cast_to_varchar2(
       utl_raw.bit_and(
         raw_ascii(p_dec1),
         raw_ascii(p_dec2)
       )
     )
   );
end;

function bitor(p_dec1 number, p_dec2 number) return varchar2 is
begin
  return
   ascii_raw(
     utl_raw.cast_to_varchar2(
       utl_raw.bit_or(
         raw_ascii(p_dec1),
         raw_ascii(p_dec2)
       )
     )
   );
end;

function bitxor(p_dec1 number, p_dec2 number) return varchar2 is
begin
  return
   ascii_raw(
     utl_raw.cast_to_varchar2(
       utl_raw.bit_xor(
         raw_ascii(p_dec1),
         raw_ascii(p_dec2)
       )
     )
   );
end;

end;
/
