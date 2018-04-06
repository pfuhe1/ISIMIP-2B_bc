function is_leap_proleptic_gregorian,year
; returns 1 if year is a leap year in the
; proleptic gregorian calendar and 0 otherwise
  if (year mod 4 eq 0) then $
    if (year mod 100 eq 0) then $
      if (year mod 400 eq 0) then $
        return,1 $
      else $
        return,0 $
    else $
      return,1 $
  else $
    return,0
end
