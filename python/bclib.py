#!/usr/bin/python



import numpy as np
from scipy import stats as sps
from netCDF4 import Dataset
from calendar import monthrange
import os.path



def loadrsdtoas(idir, lStoN=False, nlats=360):
    """ returns rsdtoas(doy, lat)
    """
    rsdtoas = np.empty((366, nlats), dtype=np.float)
    doy0 = 0
    for month in np.arange(1, 13):
        dpm = monthrange(2000, month)[1]
        ifile = 'dlat'+str(180./nlats)+'month'+('0' if month < 10 else '')+str(month)+('.StoN' if lStoN else '.NtoS')+'.npy'
        rsdtoas[doy0:doy0+dpm,:] = np.load(idir+'/'+ifile)[:,:dpm].T
        doy0 = doy0 + dpm
    return rsdtoas



def loadncfile(path, variable):
    """ returns data saved under variable from NetCDF file path
    """
    if os.path.exists(path):
        print "loading "+path
        nc = Dataset(path, 'r')
        data = nc.variables[variable][:]
        nc.close()
        return data
    else:
        print "could not find "+path+" !!! returning None"
        return None



def replaceinncfile(path, variable, data):
    """ replaces data saved under variable in NetCDF file path with data
    """
    if os.path.exists(path):
        print "replacing data in "+path
        nc = Dataset(path, 'r+')
        nc.variables[variable][:] = data
        nc.close()
    else:
        print "could not find "+path+" !!!"



def setupncobject(path, format='NETCDF4_CLASSIC', globalatts={}, zlib=False,
                  time_calendar='proleptic_gregorian', time_units='days since 2000-01-01 00:00:00', 
                  times=None, lats=None, lons=None):
    """ opens NetCDF file, sets times, lats, lons and global attributes
        (globalatts: dictionary with keys and values)
        with compression of variables as spcified by zlib,
        returns NetCDF file object
    """
    print "setting up "+path

    nc = Dataset(path, 'w', format=format)
    nc.setncatts(globalatts)

    if times is not None:
        ncDtime = nc.createDimension('time', None)
        ncVtime = nc.createVariable('time', 'f8', ('time',), zlib)
        ncVtime.standard_name = 'time'
        ncVtime.long_name = 'time'
        ncVtime.calender = time_calendar
        ncVtime.units = time_units
        ncVtime.axis = 'T'
        ncVtime[:] = times

    if lats is not None:
        ncDlat = nc.createDimension('lat', lats.shape[0])
        ncVlat = nc.createVariable('lat', 'f4', ('lat',), zlib)
        ncVlat.standard_name = 'latitude'
        ncVlat.long_name = 'latitude'
        ncVlat.units = 'degrees_north'
        ncVlat.axis = 'Y'
        ncVlat[:] = lats

    if lons is not None:
        ncDlon = nc.createDimension('lon', lons.shape[0])
        ncVlon = nc.createVariable('lon', 'f4', ('lon',), zlib)
        ncVlon.standard_name = 'longitude'
        ncVlon.long_name = 'longitude'
        ncVlon.units = 'degrees_east'
        ncVlon.axis = 'X'
        ncVlon[:] = lons

    return nc



def addvariable2ncobject(nc, varname, varunits, varvalues, zlib=False, ltime=True, fillandmissval=None):
    """ adds variable with varname, varunits, varvalues and compression if zlib
        to NetCDF file object nc
    """
    ncV = nc.createVariable(varname, 'f4' , ('time','lat','lon',), zlib, fill_value=fillandmissval) if ltime else nc.createVariable(varname, 'f4' , ('lat','lon',), zlib, fill_value=fillandmissval)
    if fillandmissval is not None: ncV.missing_value = fillandmissval
    ncV.standard_name = varname
    ncV.units = varunits
    ncV[:] = varvalues
    return nc



def maskedarray2array(a, missval=np.nan):
    """ returns a.data with filling value replaced by missval
    """
    if type(a) == np.ma.core.MaskedArray:
        b = a.data
        b[a.mask] = missval
        return b
    else:
        return a



def extend0axis_periodic(a, n):
    """ periodically extend array a by n data points along axis 0
    """
    if a.shape[0] < n:
        raise ValueError("length of a along axis 0 is less than n")
    return np.concatenate((a[-n:], a, a[:n]), axis=0)



def runmean0axis_periodic(a, halfwin):
    """ returns the running mean of a along axis 0
        with a taken as periodic along axis 0
        and window length 2 * halfwin + 1;
        halfwin may be a scalar or an array of
        the same shape as a in its first dimensions
    """
    sa = a.shape
    da = len(sa)
    if not hasattr(halfwin, "__len__"):  # halfwin is a scalar
        halfwin = np.repeat(halfwin, sa[0])
    sh = halfwin.shape
    dh = len(sh)
    if dh > da:
        raise ValueError("halfwin has more dimensions than a")
    elif tuple(list(sa)[:dh]) != sh:
        raise ValueError("a and halfwin do not have the same shape in their first "+str(dh)+" dimensions")
    hmax = halfwin.max()
    b = extend0axis_periodic(a, hmax)
    rm = np.empty_like(a)
    for indices, h in np.ndenumerate(halfwin):
        i = indices[0]
        sliceindices = (slice(i+hmax-h, i+hmax+h+1),)+indices[1:]
        rm[indices] = b[sliceindices].mean(axis=0)
    return rm



def firstderivative_forwardbackward_absmax_periodic(a):
    """ returns the first-order accuracy forward or backward finite differences
        as approximations of the first derivative of a along axis 0,
        depending on which has the greatest absolute value 
    """
    b = extend0axis_periodic(a, 1)
    fw = b[2:] - b[1:-1]
    bw = b[1:-1] - b[:-2]
    return np.where(np.abs(fw) > np.abs(bw), fw, bw)



def runmeanSOPhalfwins(rsdtoa, halfwinmax):
    """ returns halfwins for running mean calculations for the smoothing of
        solar radiation statistics that are such that zero radiation day
        statistics are left out of the running mean calculations;
        the derivative drsdtoa of rsdtoa is used to determine the maximum 
        possible halfwins that still comply with this condition
               ^
        rsdtoa |
               |\
               | \
               |  \
             0 ----->
               0   |rsdtoa/drsdtoa|
    """
    drsdtoa = firstderivative_forwardbackward_absmax_periodic(rsdtoa)
    drsdtoa[drsdtoa == 0] = np.inf  # to get minimal halfwins where derivatives vanish
    halfwins = np.floor(np.abs(rsdtoa/drsdtoa)).astype(np.int)
    halfwins[halfwins > halfwinmax] = halfwinmax
    halfwins[halfwins < 0] = 0
    return halfwins



def pqsz(meansrel, var1srel, maxs, pqmax, e):
    """ returns p, q and scale parameters for a beta distribution fit
        as well as a boolean array that is True where maxs are zero;
        it is made sure that 0 < p, q <= pqmax and s > 0; where relative
        mean and variance estimators equal zero or one e is used for a fix
    """
    m = meansrel.copy()
    v = var1srel.copy()
    # ensure 0 < m < 1 and 0 < v < 1 to ensure p > 0 and q > 0
    m[m == 0] = e
    v[v == 0] = e
    m[m == 1] = 1 - e
    v[v == 1] = 1 - e
    # get p and q parameters
    p = m / v - m; del v
    q = p * (1. - m) / m; del m
    p[p > pqmax] = pqmax
    q[q > pqmax] = pqmax
    # keep track of originally zero maxima
    z = maxs == 0
    # get scale parameter
    s = maxs.copy()
    # ensure s > 0 to ensure well-defined beta distributions
    s[z] = e
    # this does not affect results since s is not used where maxima were zero
    return p, q, s, z

    

def biascorrectbeta(idata, meansrelu, meansrelc, var1srelu, var1srelc, maxsu, maxsc, pqmax=500, e=1e-5):
    """ returns bias-corrected idata using beta distributions to model uncorrected
        and corrected data with given relative means, variabilities and maxima;
        the beta distributions are assumed have supports of [0, maximum];
        all inputs have to be arrays[time, space dimensions] with identical shapes
    """
    if not idata.shape == meansrelu.shape == meansrelc.shape == var1srelu.shape == var1srelc.shape == maxsu.shape == maxsc.shape:
        print idata.shape, meansrelu.shape, meansrelc.shape, var1srelu.shape, var1srelc.shape, maxsu.shape, maxsc.shape
        raise ValueError("shapes of input arrays do not match !!! aborting ...")
    if np.any(idata < 0) or np.any(idata > maxsu):
        raise ValueError("found idata values outside [0,maxsu] !!! aborting ...")
    if np.any(meansrelu < 0) or np.any(meansrelu > 1):
        raise ValueError("found meansrelu values outside [0,1] !!! aborting ...")
    if np.any(meansrelc < 0) or np.any(meansrelc > 1):
        raise ValueError("found meansrelc values outside [0,1] !!! aborting ...")
    if np.any(var1srelu < 0) or np.any(var1srelu > 1):
        raise ValueError("found var1srelu values outside [0,1] !!! aborting ...")
    if np.any(var1srelc < 0) or np.any(var1srelc > 1):
        raise ValueError("found var1srelc values outside [0,1] !!! aborting ...")
    if np.any(maxsu < 0):
        raise ValueError("found negative maxsu values !!! aborting ...")
    if np.any(maxsc < 0):
        raise ValueError("found negative maxsc values !!! aborting ...")

    # get p, q and scale parameters as well as zero maximum indices
    pu, qu, su, zu = pqsz(meansrelu, var1srelu, maxsu, pqmax, e)
    pc, qc, sc, zc = pqsz(meansrelc, var1srelc, maxsc, pqmax, e)

    # prepare random p-values that are used below to turn zero into non-zero values
    rpvs = np.random.random(idata.shape)
    # make sure 0 < rpvs < 1
    rpvs[rpvs == 0] = np.nextafter(0, 1)

    # make bias correction
    du = sps.beta(pu, qu, 0, su)
    pvs = np.where(zu, rpvs, du.cdf(idata))
    dc = sps.beta(pc, qc, 0, sc)
    odata = np.where(zc, 0, dc.ppf(pvs))
    return odata
