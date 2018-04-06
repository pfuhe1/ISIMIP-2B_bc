#!/usr/bin/python



import numpy as np
from optparse import OptionParser
import bclib



usage = "usage: python %prog [options]"
parser = OptionParser(usage)
parser.add_option('-v', '--idvar', action='store', type='string', dest='v', help='variable name in NetCDF files')
parser.add_option('-b', '--ipathBCmask', action='store', type='string', dest='b', help='input path to NetCDF file containing spatial mask for bias correction')
parser.add_option('-i', '--ipathdata', action='store', type='string', dest='i', help='input path for one year of daily rsds data to be corrected')
parser.add_option('-u', '--ipathcoefuncorrected', action='store', type='string', dest='u', help='input path for smoothed uncorrected rsds multi-year daily means, variances and maxima')
parser.add_option('-c', '--ipathcoefcorrected', action='store', type='string', dest='c', help='input path for smoothed corrected rsds multi-year daily means, variances and maxima')
parser.add_option('-o', '--opathdata', action='store', type='string', dest='o', help='output path for corrected one year of daily rsds data')
parser.add_option('-l', '--lupperlimitfixed', action='store_true', dest='l', help='if set, upper limit is assumed to be fixed')
parser.add_option('-m', '--upperlimit', action='store', type='float', dest='m', help='fixed upper limit')
parser.add_option('-a', '--missval', action='store', type='float', dest='a', help='missing value for masked locations in output NetCDF file')
(options, args) = parser.parse_args()



# load spatial mask for bias correction
BCmask = np.bool8(bclib.loadncfile(options.b, 'BCmask'))



# load distribution parameters
meansrelu = bclib.maskedarray2array(bclib.loadncfile(options.u, 'meanrel'), np.nan)[:,BCmask]
meansrelc = bclib.maskedarray2array(bclib.loadncfile(options.c, 'meanrel'), np.nan)[:,BCmask]
var1srelu = bclib.maskedarray2array(bclib.loadncfile(options.u, 'var1rel'), np.nan)[:,BCmask]
var1srelc = bclib.maskedarray2array(bclib.loadncfile(options.c, 'var1rel'), np.nan)[:,BCmask]
if options.l:
    maxsu = np.ones_like(meansrelu) * options.m
    maxsc = maxsu.copy()
else:
    maxsu = bclib.maskedarray2array(bclib.loadncfile(options.u, 'max'), np.nan)[:,BCmask]
    maxsc = bclib.maskedarray2array(bclib.loadncfile(options.c, 'max'), np.nan)[:,BCmask]



# correct yearwise, treat leap and non-leap years properly
idata = bclib.maskedarray2array(bclib.loadncfile(options.i, options.v), np.nan)
ll = idata.shape[0] - 365
if not ll:
    meansrelu = np.delete(meansrelu, 59, axis=0)
    meansrelc = np.delete(meansrelc, 59, axis=0)
    var1srelu = np.delete(var1srelu, 59, axis=0)
    var1srelc = np.delete(var1srelc, 59, axis=0)
    maxsu = np.delete(maxsu, 59, axis=0)
    maxsc = np.delete(maxsc, 59, axis=0)
elif ll != 1:
    raise ValueError('length of '+options.v+' array in '+options.i+' along axis 0 is neither 365 nor 366 !!! aborting ...')
idatamasked = idata[:,BCmask]
odatamasked = bclib.biascorrectbeta(idatamasked, meansrelu, meansrelc, var1srelu, var1srelc, maxsu, maxsc); del idatamasked
odata = idata
odata[:,BCmask] = odatamasked; del odatamasked
odata[:,np.logical_not(BCmask)] = options.a
bclib.replaceinncfile(options.o, options.v, odata)
