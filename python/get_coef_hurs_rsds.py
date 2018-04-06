#!/usr/bin/python



import numpy as np
from optparse import OptionParser
import bclib



usage = "usage: python %prog [options]"
parser = OptionParser(usage)
parser.add_option('-n', '--nrunmean', action='store', type='int', dest='n', help='window length for running mean calculations')
parser.add_option('-i', '--idvar', action='store', type='string', dest='i', help='variable name in NetCDF files')
parser.add_option('-t', '--idirtoa', action='store', type='string', dest='t', help='input directory for daily average insolation at TOA')
parser.add_option('-m', '--ipathmeans', action='store', type='string', dest='m', help='input path for rsds multi-year daily means')
parser.add_option('-v', '--ipathvar1s', action='store', type='string', dest='v', help='input path for rsds multi-year daily variances')
parser.add_option('-x', '--ipathmaxs', action='store', type='string', dest='x', help='input path for rsds multi-year daily maxima')
parser.add_option('-o', '--opath', action='store', type='string', dest='o', help='output path for smoothed rsds multi-year daily means, variances and maxima')
parser.add_option('-l', '--lupperlimitfixed', action='store_true', dest='l', help='if set, upper limit is assumed to be fixed')
parser.add_option('-u', '--upperlimit', action='store', type='float', dest='u', help='fixed upper limit')
parser.add_option('-f', '--maxfitthreshold', action='store', type='float', dest='f', help='only data from days of the year with daily average insolation at TOA greater than this value are taken into account in the rsds max curve estimation')
parser.add_option('-a', '--missval', action='store', type='float', dest='a', help='missing value used in NetCDF file that is created by this script')
(options, args) = parser.parse_args()



# get times, lats and lons
doys = np.arange(366)
lats = bclib.loadncfile(options.m, 'lat')
lons = bclib.loadncfile(options.m, 'lon')
ndoys = doys.shape[0]
nlats = lats.shape[0]
nlons = lons.shape[0]

# load annual cycles of daily means and variances
means = bclib.maskedarray2array(bclib.loadncfile(options.m, options.i), np.nan)
var1s = bclib.maskedarray2array(bclib.loadncfile(options.v, options.i), np.nan)
lmaskedinput = np.logical_or(np.isnan(means), np.isnan(var1s))

if options.l:
    halfwins = options.n/2
else:
    # load annual cycles of daily maxima
    maxs = bclib.maskedarray2array(bclib.loadncfile(options.x, options.i), np.nan)
    lmaskedinput = np.logical_or(lmaskedinput, np.isnan(maxs))
    
    # load daily average insolation at TOA
    rsdtoas = bclib.loadrsdtoas(options.t)
    halfwins = bclib.runmeanSOPhalfwins(rsdtoas, options.n/2)
    idoyfits = rsdtoas > options.f
    
    # derive rsdtoa scaling factors
    rsdtoascalings = np.empty((nlats, nlons), dtype=np.float)
    for ilat in np.arange(nlats):
        rsdtoa = rsdtoas[:,ilat]
        idoyfit = idoyfits[:,ilat]
        for ilon in np.arange(nlons):
            rsdtoascaling = np.max(maxs[idoyfit,ilat,ilon] / rsdtoa[idoyfit])
            rsdtoascalings[ilat,ilon] = rsdtoascaling if rsdtoascaling < 1. else 1.

# get estimates of daily distribution parameters to be used for bias correction
meansbc = bclib.runmean0axis_periodic(means, halfwins); del means
var1sbc = bclib.runmean0axis_periodic(var1s, halfwins); del var1s
if options.l:
    maxsbc = np.ones_like(meansbc) * options.u
else:
    maxsbc = np.empty_like(maxs)
    for ilat in np.arange(nlats):
        maxsbc[:,ilat,:] = np.outer(rsdtoas[:,ilat], rsdtoascalings[ilat,:])
    maxsbc = np.maximum(maxsbc, maxs); del maxs

# ensure var1 <= mean * (max - mean)
lvalid = meansbc > 0
maxsbc[lvalid] = np.maximum(maxsbc[lvalid], meansbc[lvalid] + var1sbc[lvalid] / meansbc[lvalid])

# get relative variances
var1srelbc = np.empty_like(maxsbc)
denominator = meansbc * (maxsbc - meansbc)
lvalid = np.logical_and(np.logical_and(meansbc > 0, meansbc < maxsbc), denominator != 0)
var1srelbc[:] = .5
var1srelbc[lvalid] = var1sbc[lvalid] / denominator[lvalid]; del var1sbc
var1srelbc[var1srelbc < 0] = 0
var1srelbc[var1srelbc > 1] = 1

# get relative means
meansrelbc = np.zeros_like(maxsbc)
lvalid = maxsbc > 0
meansrelbc[lvalid] = meansbc[lvalid] / maxsbc[lvalid]; del meansbc
meansrelbc[meansrelbc < 0] = 0
meansrelbc[meansrelbc > 1] = 1

# set np.nan to missval
meansrelbc[np.logical_or(lmaskedinput, np.isnan(meansrelbc))] = options.a
var1srelbc[np.logical_or(lmaskedinput, np.isnan(var1srelbc))] = options.a
if not options.l: maxsbc[np.logical_or(lmaskedinput, np.isnan(maxsbc))] = options.a

# save
nc = bclib.setupncobject(options.o, times=doys, lats=lats, lons=lons, time_units='days since 2000-01-01 00:00:00', zlib=True)
bclib.addvariable2ncobject(nc, 'meanrel', '1', meansrelbc, True, fillandmissval=options.a)
bclib.addvariable2ncobject(nc, 'var1rel', '1', var1srelbc, True, fillandmissval=options.a)
if not options.l: bclib.addvariable2ncobject(nc, 'max', 'W m-2', maxsbc, True, fillandmissval=options.a)
nc.close()
