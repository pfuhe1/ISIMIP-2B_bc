; based on
; gdl_routines/v2/apply_T_cor_mon.pro
; of ISIMIP Fast Track Bias Correction Code


pro app_coef_psl_tas,ipathdata,ipathcoef_prevmonth,ipathcoef_thismonth,ipathcoef_nextmonth,opath,APPLICATION_PERIOD_START,APPLICATION_PERIOD_STOP,mon,tasmin,tasmax,NUMLANDPOINTS


; restore three months of transfer function coefficients
cmrestore,ipathcoef_prevmonth
Am1=a_tas
cmrestore,ipathcoef_thismonth
A=a_tas
cmrestore,ipathcoef_nextmonth
Ap1=a_tas


; restore GCM data to be corrected
cmrestore,ipathdata
tas_e=idldata


; check for negative values in GCM data
print,'checking for negative values in input data ...'
IF (min(idldata) LT 0.0) THEN BEGIN
   print,'negative values in GCM input data !!! exiting ...'
   STOP
ENDIF
print,'... check passed'


; initialize some constants and arrays
l=n_elements(idldata[0,*])
meanthismonth_e = fltarr(NUMLANDPOINTS)
yr=APPLICATION_PERIOD_START
nyear=1L*(APPLICATION_PERIOD_STOP)-1L*(APPLICATION_PERIOD_START)+1
ind=0


FOR y=0,nyear-1 DO BEGIN
   if (mon eq 1) then nd = 28 + is_leap_proleptic_gregorian(yr + y) else nd = l/nyear
   daysthismonth = ind+findgen(nd)

   for iday=0,nd-1 do begin
      d=-0.5+(iday*1.0/(nd-1))
                                ;
                                ; Weighting factors for the previous month (dm1), the current month
                                ; (d0) and the following month (dp1) are evaluated, such that for the
                                ; first (last) day of the month the correction factors of the previous
                                ; (following) month are equally weighted , i.e. dm1=d0=0.5
                                ; (dp1=d0=0.5), and for the days in the middle of the month d0=1,
                                ; dp1=dm1=0
                                ;
      dm1=(abs(d)-d)*0.5
      d0=1-abs(d)
      dp1=(d+abs(d))*0.5
      a_iday = Am1*dm1 + A*d0 + Ap1*dp1

      for n=0L,NUMLANDPOINTS-1 do begin
         if (iday eq 0) then meanthismonth_e(n) = mean(tas_e(n,daysthismonth))
         T_res = tas_e(n,ind) - meanthismonth_e(n)
         T_corr = a_iday(n,0) + a_iday(n,1) * T_res+meanthismonth_e(n)
         if (T_corr lt tasmin) then T_corr = tasmin
         if (T_corr gt tasmax) then T_corr = tasmax
         idldata[n,ind] = T_corr
      endfor

      ind=ind+1
   endfor
endfor


cmsave,idldata,filename=opath
end
