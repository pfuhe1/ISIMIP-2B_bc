; based on
; gdl_routines/generic/ncdf2idl.pro
; of ISIMIP Fast Track Bias Correction Code


pro nc2idl,ipath,opath,varname,NUMLANDPOINTS,land
  ; read data from NetCDF file
  id = NCDF_OPEN(ipath)
  NCDF_VARGET,id,varname,ncdfdata
  NCDF_CLOSE,id
  print,'converting '+ipath+' to '+opath

  ; l is the number of timesteps
  ; mind that NCDF_VARGET turns [time,lat,lon] NetCDF arrays into [lon,lat,time] IDL arrays
  l = n_elements(ncdfdata[0,0,*])

  ; flatten the spatial dimensions and only save land points
  ; land is an index array for land grid cells
  idldata = fltarr(NUMLANDPOINTS,l)
  for i=0L,l-1L do begin
     dum = reform(ncdfdata[*,*,i])
     idldata[*,i] = dum[land]
  endfor
  ncdfdata=0

  cmsave,idldata,filename=opath
end
