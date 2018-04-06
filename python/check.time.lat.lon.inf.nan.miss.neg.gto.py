#!/usr/bin/python


import numpy as np
from netCDF4 import Dataset
from optparse import OptionParser


usage = "usage: python %prog [options]"
parser = OptionParser(usage)
parser.add_option('-o', '--check_greaterthan100', action='store_true', dest='o', help='flag to include check for values > 100')
parser.add_option('-n', '--check_negative', action='store_true', dest='n', help='flag to include check for negative values')
parser.add_option('-s', '--start_time', action='store', type='int', dest='s', help='start time to be checked')
parser.add_option('-e', '--end_time', action='store', type='int', dest='e', help='end time to be checked')
parser.add_option('-v', '--variable', action='store', type='string', dest='v', help='variable to be checked')
parser.add_option('-f', '--file', action='store', type='string', dest='f', help='path to file to be checked')
(options, args) = parser.parse_args()


nc = Dataset(options.f, 'r')

times = nc.variables["time"][:]
lats = nc.variables["lat"][:]
lons = nc.variables["lon"][:]
datao = nc.variables[options.v]

ctime = np.any(times != np.arange(options.s, options.e+1))
clat = np.any(lats != np.arange(89.75, -90., step=-.5))
clon = np.any(lons != np.arange(-179.75, 180., step=.5))

cinf = False
cnan = False
cmiss = False
cneg = False
cgto = False
for i in xrange(times.size):
    data = datao[i]
    if type(data) == np.ma.core.MaskedArray:
        cmiss = cmiss or np.any(data.mask)
        data = data.data
    cinf = cinf or np.any(np.isinf(data))
    cnan = cnan or np.any(np.isnan(data))
    if options.n:
        cneg = cneg or np.any(data[np.logical_not(np.isnan(data))] < 0)
    if options.o:
        cgto = cgto or np.any(data[np.logical_not(np.isnan(data))] > 100)

nc.close()


checksum = 0
if ctime: checksum += 10000000
if clat:  checksum += 1000000
if clon:  checksum += 100000
if cinf:  checksum += 10000
if cnan:  checksum += 1000
if cmiss: checksum += 100
if cneg:  checksum += 10
if cgto:  checksum += 1
print '%0.8d' % checksum
