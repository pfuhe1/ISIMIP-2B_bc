; based on
; gdl_routines/v2/apply_P_cor_mon.pro
; gdl_routines/v2/apply_O_cor_mon.pro
; of ISIMIP Fast Track Bias Correction Code


pro app_coef_rlds_sfcWind,ipathdata_prevmonth,ipathdata_thismonth,ipathdata_nextmonth,ipathcoef,opath,$
                          APPLICATION_PERIOD_START,APPLICATION_PERIOD_STOP,mon,NUMLANDPOINTS,mr_thresh,abs_thresh


; restore transfer function coefficients
cmrestore,ipathcoef


; restore GCM data to be corrected
cmrestore,ipathdata_prevmonth
fullmean_gcm_prevmonth = mean(idldata,DIMENSION=2)
cmrestore,ipathdata_nextmonth
fullmean_gcm_nextmonth = mean(idldata,DIMENSION=2)
cmrestore,ipathdata_thismonth
fullmean_gcm_thismonth = mean(idldata,DIMENSION=2)
idata = idldata
idldata = 0
odata = idata


; check for negative values in GCM data
print,'checking for negative values in input data ...'
IF (min(idata) LT -1e-10) THEN BEGIN
   print,'negative values in GCM input data !!! exiting ...'
   STOP
ENDIF
print,'... check passed'


; get climatologies in daily resolution
; using piecewise linear interpolations that preserve the monthly means
ndays = n_elements(odata[0,*])
nyears = 1L*(APPLICATION_PERIOD_STOP) - 1L*(APPLICATION_PERIOD_START) + 1
if (mon eq 1) then ndayspermonth = 29 else ndayspermonth = ndays/nyears

mean_start_gcm = .5D * (fullmean_gcm_prevmonth + fullmean_gcm_thismonth)
fullmean_gcm_prevmonth = 0
mean_end_gcm = .5D * (fullmean_gcm_nextmonth + fullmean_gcm_thismonth)
fullmean_gcm_nextmonth = 0
mean_middle_gcm = 2.D * fullmean_gcm_thismonth - .5D * (mean_start_gcm + mean_end_gcm)
ilt0 = where(mean_middle_gcm lt 0)  ; avoid mean_middle_gcm < 0, which can happen since mean_middle_gcm is extrapolated
if (ilt0[0] ne -1) then mean_middle_gcm[ilt0] = fullmean_gcm_thismonth[ilt0]
fullmean_gcm_thismonth = 0
ilt0 = 0

climatology_gcm = dblarr(NUMLANDPOINTS,ndayspermonth)
for iday=0,ndayspermonth-1 do begin
   d = 2.D * iday / (ndayspermonth - 1.D) - 1.D
   if (d lt 0) then begin
      climatology_gcm(*,iday) = (1. + d) * mean_middle_gcm - d * mean_start_gcm
   endif else begin
      climatology_gcm(*,iday) = (1. - d) * mean_middle_gcm + d * mean_end_gcm
   endelse
endfor
mean_start_gcm = 0
mean_end_gcm = 0
mean_middle_gcm = 0


; get shape of climatologies
climatology_gcm_shape = dblarr(NUMLANDPOINTS,ndayspermonth)
for n=0L,(NUMLANDPOINTS-1) do begin
   climatology_gcm_shape(n,*) = climatology_gcm(n,*) / mean(climatology_gcm(n,*))
endfor


; limit mean correction ratios
overthresh = where(climatology_obs_over_gcm gt mr_thresh)
if (overthresh(0) ne -1) then climatology_obs_over_gcm[overthresh] = 1.D * mr_thresh
overthresh = where(climatology_obs_over_gcm lt 1. / mr_thresh)
if (overthresh(0) ne -1) then climatology_obs_over_gcm[overthresh] = 1.D / mr_thresh


ind = 0  ; a counter for the days
FOR y=0,nyears-1 DO BEGIN
   print,APPLICATION_PERIOD_START+y

   if (mon eq 1) then nd = 28 + is_leap_proleptic_gregorian(APPLICATION_PERIOD_START + y) else nd = ndayspermonth
   daysthismonth = ind + lindgen(nd)
   meansthismonth = mean(idata[*,daysthismonth],DIMENSION=2,/DOUBLE)

   for iday=0,nd-1 do begin
      for n=0L,NUMLANDPOINTS-1 do begin
         ; normalize
         x0 = float(idata[n,ind] / (meansthismonth[n] * climatology_gcm_shape[n,iday]))

         ; check for too high decay coefficient
         IF ((tau_pr(n) GT 1e32) and (tau_pr(n) NE 1e33)) THEN BEGIN
            print,'exponent too extreme !!! stopping ...'
            stop
         ENDIF
         
         ; use linear or non-linear transfer function depending on value of tau_pr
         y0 = a_pr(n) + b_pr(n) * x0
         if (tau_pr(n) ne 1e33) then y0 = y0 * (1 - exp(-x0 / tau_pr(n)))

         ; avoid too extreme variability
         lowerlimit = 0.7 * extremes[n,0]
         if (y0 lt lowerlimit) then y0 = lowerlimit
         upperlimit = 1.3 * extremes[n,1]
         if (y0 gt upperlimit) then y0 = upperlimit

         ; avoid negative values
         if (y0 lt 0) then y0 = 0
         odata(n,ind) = y0

         ; at the last day of the month rescale all daily values of the month to adjust the monthly mean
         if (iday eq (nd-1)) then begin
            ; from left to right:
            ; ensure that the monthly mean of the transformed normalized data is 1
            ; restore the uncorrected monthly mean
            ; correct the monthly mean
            odata[n,daysthismonth] = float((odata[n,daysthismonth] / mean(odata[n,daysthismonth],/DOUBLE)) * (meansthismonth[n] * climatology_gcm_shape[n,lindgen(nd)]) * climatology_obs_over_gcm[n,lindgen(nd)])
         endif
      endfor

      ind = ind + 1
   endfor
ENDFOR


; cap unphysically high values
idata = 0
overthresh = where(odata gt abs_thresh)
if (overthresh(0) ne -1) then odata(overthresh) = abs_thresh
overthresh = 0


idldata = odata
odata = 0
cmsave,filename=opath,idldata
end
