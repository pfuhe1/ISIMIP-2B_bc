; based on
; gdl_routines/v2/calc_T_cor_coeff_mon.pro
; of ISIMIP Fast Track Bias Correction Code


pro get_coef_psl_tas,ipathobs,ipathgcm,opath,CONSTRUCTION_PERIOD_START,CONSTRUCTION_PERIOD_STOP,mon,NUMLANDPOINTS


print,'using '+ipathgcm+' and '+ipathobs+' to get transfer function coefficients stored in ' +opath


; read OBS data
cmrestore,ipathobs
tas_o=idldata


; read GCM data
cmrestore,ipathgcm
tas_e=idldata


; check for negative values in input data
print,'checking for negative values in input data ...'
IF (min(tas_e) LT 0.0) THEN BEGIN
   print,'negative values in GCM data !!! exiting ...'
   STOP
ENDIF
IF (min(tas_o) LT 0.0) THEN BEGIN
   print,'negative values in OBS data !!! exiting ...'
   STOP
ENDIF
print,'... check passed'


; initialize some constants and arrays
construction_period_length = CONSTRUCTION_PERIOD_STOP*1L-CONSTRUCTION_PERIOD_START*1L+1
l=n_elements(tas_e[0,*])
monlength = l / construction_period_length
idldata=0
tas_e_res = fltarr(l)
tas_o_res = fltarr(l)
a_tas=fltarr(NUMLANDPOINTS,2)


; find start index of each year, account for leap years
start_new_month = findgen(construction_period_length)*monlength
if (mon eq 1) then begin
   monthlength=28
   leap=0
   for ii=1,construction_period_length-1 do begin
      syear = CONSTRUCTION_PERIOD_START*1L+ii-1
      leap = leap + is_leap_proleptic_gregorian(syear)
      start_new_month(ii) = (ii*monthlength)+leap
   endfor
endif


; loop over all land points
for n=0L,(NUMLANDPOINTS-1) do begin
   if ((n mod 1000) eq 0) then print,n

   for mm=0,construction_period_length-1 do begin
      startidx = start_new_month[mm]
      if (mm le (construction_period_length-2)) then endidx = start_new_month[mm+1]-1
      if (mm eq (construction_period_length-1)) then endidx = l-1
      tas_e_res[startidx:endidx] = tas_e[n,startidx:endidx]-mean(tas_e[n,startidx:endidx])
      tas_o_res[startidx:endidx] = tas_o[n,startidx:endidx]-mean(tas_o[n,startidx:endidx])
   endfor

   ; reorder residuals of tas
   y=reform(tas_o_res(sort(tas_o_res)))  ; obs
   x=reform(tas_e_res(sort(tas_e_res)))  ; gcm

   xm=mean(x)
   ym=mean(y)
   yxm=mean(x*y)
   xxm=mean(x*x)
   divisor=xxm-xm*xm
   IF (divisor NE 0.0 AND xm NE 0.0) THEN BEGIN
      a=[ym+(ym*xm-yxm)/divisor*xm,-(ym*xm-yxm)/divisor]
   ENDIF ELSE BEGIN
      a=[ym-xm,1]
   ENDELSE
   IF (a(0) GT 50000.0 or a(0) LT -50000.0 or a(1) GT 5000.0 or a(1) LT -5000.0) THEN BEGIN
      a=[0,1]
   ENDIF

   a_tas(n,0)=mean(tas_o[n,*])-mean(tas_e[n,*])
   a_tas(n,1)=a(1)
endfor


cmsave,a_tas,filename=opath
end
