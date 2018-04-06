; analogous to readWFDgridspecs.pro
; of ISIMIP Fast Track Bias Correction Code

id = NCDF_OPEN(ipathBCmask)
NCDF_VARGET,id,'BCmask',BCmask
NCDF_VARGET,id,'lat',lat
NCDF_VARGET,id,'lon',lon
NCDF_CLOSE,id

nlat = long(n_elements(lat))
nlon = long(n_elements(lon))
lat0 = float(lat[0])
lon0 = float(lon[0])
dlat = float(lat[1] - lat[0])
dlon = float(lon[1] - lon[0])

land = where(BCmask GT 0, NUMLANDPOINTS)
ilandlat = land / nlon
ilandlon = land - ilandlat * nlon
landlat = float(lat[ilandlat])
landlon = float(lon[ilandlon])

end
