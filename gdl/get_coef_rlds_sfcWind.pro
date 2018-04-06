; based on
; gdl_routines/v2/calc_P_cor_coeff_mon.pro
; gdl_routines/v2/calc_O_cor_coeff_mon.pro
; of ISIMIP Fast Track Bias Correction Code


pro get_coef_rlds_sfcWind,ipathobs_prevmonth,ipathobs_thismonth,ipathobs_nextmonth,$
                          ipathgcm_prevmonth,ipathgcm_thismonth,ipathgcm_nextmonth,$
                          opath,CONSTRUCTION_PERIOD_START,CONSTRUCTION_PERIOD_STOP,mon,NUMLANDPOINTS,land


print,'using '+ipathgcm_thismonth+' and '+ipathobs_thismonth+' and similar files for previous and next month to get transfer function coefficients stored in ' +opath


; read OBS data
cmrestore,ipathobs_prevmonth
fullmean_obs_prevmonth = mean(idldata,DIMENSION=2)
cmrestore,ipathobs_nextmonth
fullmean_obs_nextmonth = mean(idldata,DIMENSION=2)
cmrestore,ipathobs_thismonth
fullmean_obs_thismonth = mean(idldata,DIMENSION=2)
pr_o = idldata


; read GCM data
cmrestore,ipathgcm_prevmonth
fullmean_gcm_prevmonth = mean(idldata,DIMENSION=2)
cmrestore,ipathgcm_nextmonth
fullmean_gcm_nextmonth = mean(idldata,DIMENSION=2)
cmrestore,ipathgcm_thismonth
fullmean_gcm_thismonth = mean(idldata,DIMENSION=2)
pr_e = idldata
idldata = 0


; check for negative values in input data
print,'checking for negative values in input data ...'
IF (min(pr_e) LT -1e-10) THEN BEGIN
   print,'negative values in GCM data !!! exiting ...'
   stop
ENDIF
IF (min(pr_o) LT -1e-10) THEN BEGIN
   print,'negative values in OBS data !!! exiting ...'
   stop
ENDIF
print,'... check passed'


; find start index of each year, account for leap years
ndays = n_elements(pr_o(0,*))
nyears = CONSTRUCTION_PERIOD_STOP*1L-CONSTRUCTION_PERIOD_START*1L+1
if (mon eq 1) then begin
   ndayspermonth = 28
   start_new_month = fltarr(nyears)
   leap = 0
   for ii=1,nyears-1 do begin
      syear = CONSTRUCTION_PERIOD_START*1L+ii-1
      leap = leap + is_leap_proleptic_gregorian(syear)
      start_new_month(ii) = (ii*ndayspermonth)+leap
   endfor
   ; now set ndayspermonth to 29 for climatologies computed below
   ndayspermonth = 29
endif else begin
   ndayspermonth = ndays/nyears
   start_new_month = findgen(nyears) * ndayspermonth
endelse


; get climatologies in daily resolution using piecewise linear
; interpolations that preserve the climatologies of monthly means
mean_start_obs = .5D * (fullmean_obs_prevmonth + fullmean_obs_thismonth)
fullmean_obs_prevmonth = 0
mean_end_obs = .5D * (fullmean_obs_nextmonth + fullmean_obs_thismonth)
fullmean_obs_nextmonth = 0
mean_middle_obs = 2.D * fullmean_obs_thismonth - .5D * (mean_start_obs + mean_end_obs)
ilt0 = where(mean_middle_obs lt 0)  ; avoid mean_middle_obs < 0, which can happen since mean_middle_obs is extrapolated
if (ilt0[0] ne -1) then mean_middle_obs[ilt0] = fullmean_obs_thismonth[ilt0]
fullmean_obs_thismonth = 0

mean_start_gcm = .5D * (fullmean_gcm_prevmonth + fullmean_gcm_thismonth)
fullmean_gcm_prevmonth = 0
mean_end_gcm = .5D * (fullmean_gcm_nextmonth + fullmean_gcm_thismonth)
fullmean_gcm_nextmonth = 0
mean_middle_gcm = 2.D * fullmean_gcm_thismonth - .5D * (mean_start_gcm + mean_end_gcm)
ilt0 = where(mean_middle_gcm lt 0)  ; avoid mean_middle_gcm < 0, which can happen since mean_middle_gcm is extrapolated
if (ilt0[0] ne -1) then mean_middle_gcm[ilt0] = fullmean_gcm_thismonth[ilt0]
fullmean_gcm_thismonth = 0
ilt0 = 0

climatology_obs = dblarr(NUMLANDPOINTS,ndayspermonth)
climatology_gcm = dblarr(NUMLANDPOINTS,ndayspermonth)
for iday=0,ndayspermonth-1 do begin
   d = 2.D * iday / (ndayspermonth - 1.D) - 1.D
   if (d lt 0) then begin
      climatology_obs(*,iday) = (1. + d) * mean_middle_obs - d * mean_start_obs
      climatology_gcm(*,iday) = (1. + d) * mean_middle_gcm - d * mean_start_gcm
   endif else begin
      climatology_obs(*,iday) = (1. - d) * mean_middle_obs + d * mean_end_obs
      climatology_gcm(*,iday) = (1. - d) * mean_middle_gcm + d * mean_end_gcm
   endelse
endfor
mean_start_obs = 0
mean_end_obs = 0
mean_middle_obs = 0
mean_start_gcm = 0
mean_end_gcm = 0
mean_middle_gcm = 0


; initialize transfer function coefficients
climatology_obs_over_gcm = float(climatology_obs / climatology_gcm)
a_pr = land * 0.0 + 1e+33      ; the offset fit parameter
b_pr = land * 0.0 + 1e+33      ; the slope fit parameter
tau_pr = land * 0.0 + 1e+33    ; the decay coefficient in the exponential
error_pr = land * 0.0 + 1e+33  ; the fit RMSE
extremes = fltarr(NUMLANDPOINTS,2)


; loop over all land points
for n=0L,(NUMLANDPOINTS-1) do begin
   x = pr_e(n,*)  ; GCM data
   y = pr_o(n,*)  ; OBS data

   ; this is for the shape of the annual cycle in daily resolution
   climatology_obs_shape = climatology_obs(n,*) / mean(climatology_obs(n,*))
   climatology_gcm_shape = climatology_gcm(n,*) / mean(climatology_gcm(n,*))

   ; normalize with monthly mean
   x0 = x
   y0 = y
   for mm=0,nyears-1 do begin
      startidx = start_new_month[mm]
      if (mm le (nyears-2)) then endidx = start_new_month[mm+1]-1
      if (mm eq (nyears-1)) then endidx = n_elements(x)-1
      ndaysthismonthminusone = endidx-startidx  ; necessary for february and no-leap years
      means_x = mean(x[startidx:endidx]) * climatology_gcm_shape[0:ndaysthismonthminusone]
      means_y = mean(y[startidx:endidx]) * climatology_obs_shape[0:ndaysthismonthminusone]
      x0[startidx:endidx] = float(x[startidx:endidx] / means_x)
      y0[startidx:endidx] = float(y[startidx:endidx] / means_y)
   endfor
   x0 = x0(sort(x0))
   y0 = y0(sort(y0))
   x0mean = mean(x0)
   y0mean = mean(y0)

   ; construct transfer function from normalized data
   ; use fit type that results in smaller root-mean-square error

   ; initialize fitting parameter
   a = [0.,1.,.9]
   w = replicate(1.0,ndays)
   er = 1e33

   ; fitting an exponential distribution: y=B*x*(1-exp(-x/tau))
   ; the exponential forces the fit to go to zero in the limit x-> 0
   g = curvefit(x0,y0,w,a,function_name='transferfunction',$
                status=stat,yerror=er,itmax=1000,/noderivative,$
                iter=iter,tol=1e-16,fita=[1,1,1])

   ; check if the gradient method used to fit the exponential converged
   if (stat eq 0) then er = sqrt(mean((y0 - (a(0) + a(1) * x0) * (1 - exp(-x0 / a(2))))^2))

   ; if not then try different intial values
   ; (offset and slope from linear fit)
   if (stat ne 0) then begin
      print,'warning:'
      if(stat eq 1) then print,'The computation failed. Chi-square was increasing without bounds.'
      if(stat eq 2) then print,'The computation failed to converge in ITMAX iterations.'
      print,'Trying different intialization ...'

      ; perform a linear fit
      alin = [0.,1.,1e33]
      x0m = mean(x0)
      y0m = mean(y0)
      yx0m = mean(x0 * y0)
      xx0m = mean(x0 * x0)
      divisor = x0m^2 - xx0m
      IF (divisor NE 0.0) THEN BEGIN
         alin(1) = (y0m * x0m - yx0m) / divisor
         alin(0) = y0m - alin(1) * x0m
      ENDIF ELSE BEGIN
         alin(1) = y0mean / x0mean
         alin(0) = 0
      ENDELSE

      ; new inital values for non-linear fit
      a = [alin(0),alin(1),.9]
      w = replicate(1.0,ndays)
      er = 1e33
      stat = 100
      g = curvefit(x0,y0,w,a,function_name='transferfunction',$
                   status=stat,yerror=er,itmax=1000,/noderivative,$
                   iter=iter,tol=1e-16,fita=[1,1,1])

      ; check for convergence
      if (stat eq 0) then er = sqrt(mean((y0 - (a(0) + a(1) * x0) * (1 - exp(-x0 / a(2))))^2))

      ; if second initialization also failed then use coefficients from linear fit
      if (stat ne 0) then begin
         print,'warning:'
         if (stat eq 1) then print,'The computation failed. Chi-square was increasing without bounds.'
         if (stat eq 2) then print,'The computation failed to converge in ITMAX iterations.'
         print,'Linear transfer function will be used.'
         a = alin
         er = sqrt(mean((y0 - a(0) - a(1) * x0)^2))
      endif
   endif

   if (er gt 0.05) then begin
      ; check if linear fit is better than non-linear fit
      alin = a
      x0m = mean(x0)
      y0m = mean(y0)
      yx0m = mean(x0 * y0)
      xx0m = mean(x0 * x0)
      divisor = x0m^2 - xx0m
      IF (divisor NE 0.0) THEN BEGIN
         alin(1) = (y0m * x0m - yx0m) / divisor
         alin(0) = y0m - alin(1) * x0m
      ENDIF ELSE BEGIN
         alin(1) = y0mean / x0mean
         alin(0) = 0
      ENDELSE
      er_lin = sqrt(mean((y0 - alin(0) - alin(1) * x0)^2))
      if (er_lin le er) then begin
         a = [alin(0),alin(1),1e33]
         er = er_lin
      endif
   endif

   a_pr(n) = a(0)
   b_pr(n) = a(1)
   tau_pr(n) = a(2)
   error_pr(n) = er

   extremes(n,0) = y0(0)
   extremes(n,1) = y0(ndays-1)
endfor


cmsave,filename=opath,climatology_obs_over_gcm,a_pr,b_pr,tau_pr,error_pr,extremes
end
