; based on
; gdl_routines/generic/createNCDF_v2.pro
; gdl_routines/generic/idl2latlon_v1.pro
; of ISIMIP Fast Track Bias Correction Code


pro idl2nc,ipath,opath,varname,ys,ye,mon,nlat,nlon,lat0,lon0,dlat,dlon,NUMLANDPOINTS,landlat,landlon,missval
  ; restore and reshape IDL data
  cmrestore,ipath
  nt = n_elements(idldata[0,*])
  data = fltarr(nt,nlat,nlon)
  data = data * 0.0 + missval
  FOR i=0L,NUMLANDPOINTS-1 DO BEGIN
    ilat = round((landlat[i] - lat0) / dlat)
    ilon = round((landlon[i] - lon0) / dlon)
    data[*,ilat,ilon] = idldata[i,*]
  ENDFOR

  ; open new NetCDF file and fill with default values
  id = NCDF_CREATE(opath,/CLOBBER)
  NCDF_CONTROL,id,/FILL

  ; prepare absolute time axis
  nyears = ye*1L-ys*1L+1
  times = lonarr(nt)
  ind = 0
  FOR y=0,nyears-1 DO BEGIN
    if (mon eq 1) then nd = 28 + is_leap_proleptic_gregorian(ys + y) else nd = nt/nyears
    times[ind] = (ys+y)*10000L+(mon+1)*100+indgen(nd)+1
    ind = ind + nd
  ENDFOR

  ; define dimensions
  xid = NCDF_DIMDEF(id, 'lon', nlon)
  yid = NCDF_DIMDEF(id, 'lat', nlat)
  zid = NCDF_DIMDEF(id, 'time', /UNLIMITED)

  ; define variables
  lonid = NCDF_VARDEF(id, 'lon', [xid], /FLOAT)
  latid = NCDF_VARDEF(id, 'lat', [yid], /FLOAT)
  timid = NCDF_VARDEF(id, 'time', [zid], /LONG)
  varid = NCDF_VARDEF(id, varname, [xid,yid,zid], /FLOAT)
  NCDF_ATTPUT,id,varid,'_FillValue',missval
  NCDF_ATTPUT,id,varid,'missing_value',missval

  ; put NetCDF file in data mode
  NCDF_CONTROL,id,/ENDEF

  ; store data
  NCDF_VARPUT,id,lonid,lon0+dlon*findgen(nlon)
  NCDF_VARPUT,id,latid,lat0+dlat*findgen(nlat)
  NCDF_VARPUT,id,timid,times
  FOR it=0,nt-1 DO BEGIN
    FOR iy=0,nlat-1 DO BEGIN
      NCDF_VARPUT,id,varid,REFORM(data[it,iy,*]),OFFSET=[0,iy,it]
    ENDFOR
  ENDFOR

  ; close NetCDF file
  NCDF_CLOSE,id
end
