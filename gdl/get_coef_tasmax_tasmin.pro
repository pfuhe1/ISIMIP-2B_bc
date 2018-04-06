; based on
; gdl_routines/v2/calc_T_cor_coeff_mon.pro
; of ISIMIP Fast Track Bias Correction Code


pro get_coef_tasmax_tasmin,ipathobs,ipathobstas,ipathgcm,ipathgcmtas,opath,minormax,NUMLANDPOINTS


print,'using '+ipathgcm+', '+ipathgcmtas+' and '+ipathobs+', '+ipathobstas+' to get transfer function coefficients stored in ' +opath


; read OBS data
cmrestore,ipathobs
tminmax_o=idldata
cmrestore,ipathobstas
print,'checking for negative values in input data ...'
IF (min(tminmax_o) LT 0.0) THEN BEGIN
   print,'negative values in OBS tasmax/tasmin data !!! exiting ...'
   STOP
ENDIF
IF (min(idldata) LT 0.0) THEN BEGIN
   print,'negative values in OBS tas data !!! exiting ...'
   STOP
ENDIF
tminmax_minus_tas_o = tminmax_o - idldata
tminmax_o=0


; read GCM data
cmrestore,ipathgcm
tminmax_e=idldata
cmrestore,ipathgcmtas
IF (min(tminmax_e) LT 0.0) THEN BEGIN
   print,'negative values in GCM tasmax/tasmin data !!! exiting ...'
   STOP
ENDIF
IF (min(idldata) LT 0.0) THEN BEGIN
   print,'negative values in GCM tas data !!! exiting ...'
   STOP
ENDIF
print,'... check passed'
tminmax_minus_tas_e = tminmax_e - idldata
tminmax_e=0
idldata=0


; check for tasmin above tas and tasmax below tas
print,'checking for tas exceeding tasmax or tasmin exceeding tas ...'
IF (min(minormax*tminmax_minus_tas_o) LT 0.0) THEN BEGIN
   print,'tasmax/tasmin </> tas in OBS data !!! exiting ...'
   STOP
ENDIF
IF (min(minormax*tminmax_minus_tas_e) LT 0.0) THEN BEGIN
   print,'tasmax/tasmin </> tas in GCM data !!! exiting ...'
   STOP
ENDIF
print,'... check passed'


a_td = mean(tminmax_minus_tas_o,DIMENSION=2) / mean(tminmax_minus_tas_e,DIMENSION=2)


cmsave,a_td,filename=opath
end
