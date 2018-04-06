; based on
; gdl_routines/v2/apply_T_cor_mon.pro
; of ISIMIP Fast Track Bias Correction Code


pro app_coef_tasmax_tasmin,ipathtasminmax_uncorrected,ipathtas_uncorrected,ipathtas_corrected,ipathcoef_prevmonth,ipathcoef_thismonth,ipathcoef_nextmonth,opath,APPLICATION_PERIOD_START,APPLICATION_PERIOD_STOP,mon,minormax,correctionfactormax,minmaxval,NUMLANDPOINTS


; restore and limit three months of transfer function coefficients
cmrestore,ipathcoef_prevmonth
overthresh=where(a_td gt correctionfactormax)
if (overthresh(0) ne -1) then a_td[overthresh] = correctionfactormax
adm1=a_td
cmrestore,ipathcoef_thismonth
overthresh=where(a_td gt correctionfactormax)
if (overthresh(0) ne -1) then a_td[overthresh] = correctionfactormax
ad=a_td
cmrestore,ipathcoef_nextmonth
overthresh=where(a_td gt correctionfactormax)
if (overthresh(0) ne -1) then a_td[overthresh] = correctionfactormax
adp1=a_td


; restore corrected GCM tas data
cmrestore,ipathtas_corrected
print,'checking for negative values in input data ...'
IF (min(idldata) LT 0.0) THEN BEGIN
   print,'negative values in corrected GCM tas data !!! exiting ...'
   STOP
ENDIF
tas_c=idldata


; restore uncorrected GCM tas data
cmrestore,ipathtas_uncorrected
IF (min(idldata) LT 0.0) THEN BEGIN
   print,'negative values in uncorrected GCM tas data !!! exiting ...'
   STOP
ENDIF
tas_e=idldata


; restore uncorrected GCM tasmax/tasmin data
cmrestore,ipathtasminmax_uncorrected
IF (min(idldata) LT 0.0) THEN BEGIN
   print,'negative values in uncorrected GCM tasmax/tasmin data !!! exiting ...'
   STOP
ENDIF
print,'... check passed'
tminmax_minus_tas_e = idldata - tas_e
tas_e=0
print,'checking for tas exceeding tasmax or tasmin exceeding tas ...'
IF (min(minormax*tminmax_minus_tas_e) LT 0.0) THEN BEGIN
   print,'tasmax/tasmin </> tas in GCM data !!! exiting ...'
   STOP
ENDIF
print,'... check passed'


; initialize some constants and arrays
l=n_elements(idldata[0,*])
yr=APPLICATION_PERIOD_START
nyear=1L*(APPLICATION_PERIOD_STOP)-1L*(APPLICATION_PERIOD_START)+1
ind = 0


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
                                ; dp1=dm1=0.
                                ;
      dm1=(abs(d)-d)*0.5
      d0=1-abs(d)
      dp1=(d+abs(d))*0.5
      ad_iday = adm1*dm1 + ad*d0 + adp1*dp1

      for n=0L,NUMLANDPOINTS-1 do begin
         tasminmax = ad_iday[n] * tminmax_minus_tas_e[n,ind] + tas_c[n,ind]
;         tasminmax = tminmax_minus_tas_e[n,ind] + tas_c[n,ind]
         if ((minormax * (tasminmax - minmaxval)) gt 0) then tasminmax = minmaxval  ; make sure minimum/maximum temperatures do not fall below/exceed minmaxval
         idldata[n,ind] = tasminmax
      endfor

      ind=ind+1
   endfor
endfor


cmsave,idldata,filename=opath
end
