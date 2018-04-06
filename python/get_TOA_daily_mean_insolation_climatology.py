#!/usr/bin/python


import numpy as np
from calendar import monthrange
from optparse import OptionParser


usage = "usage: python %prog [options]"
parser = OptionParser(usage)
parser.add_option('-d', '--dlat', action='store', type='float', dest='d', help='latitudinal resolution at which the TOA daily mean insolation climatology shall be computed [deg]')
(options, args) = parser.parse_args()


# constants
S0 = 1360.8  # solar constant [W/m^2]
e = 0.0167086  # eccentricity of the Earth's orbit around the Sun
ndpy = 365.25  # number of days per year
omega = 2 * np.pi / ndpy  # average angular velocity of the Earth [rad/day]
dmin = np.deg2rad(-23.4392811)  # minimum declination of the Sun [rad]
days = np.arange(365 * 4 + 1)  # days of four years including one leap day
lats = np.deg2rad(np.arange(90 - .5 * options.d, -90, step=-options.d))  # latitudes
nlats = lats.shape[0]
lats = lats.reshape(1, nlats)


# get four-year cycle of ...
thetaP = omega * (days - 2)  # approximate angle relative to perihelion
thetaS = omega * (days + 10)  # approximate angle relative to December solstice
S = S0 * np.square(1 + e * np.cos(thetaP + 2 * e * np.sin(thetaP)))  # TSI
sind = np.sin(dmin) * np.cos(thetaS + 2 * e * np.sin(thetaP))  # sinus of the declination of the Sun
cosd = np.sqrt(1 - np.square(sind))  # cosinus of the declination of the Sun
tand = sind / cosd  # tangens of the declination of the Sun


# get the solar hour of the sunset as a function of latitude and declination of the Sun
cosh0 = -np.outer(np.tan(lats), tand)
cosh0[cosh0 > 1] = 1
cosh0[cosh0 < -1] = -1
h0 = np.arccos(cosh0)


# get the daily average insolation at TOA as a function of latitude and declination of the Sun over four years including one leap year
q4 = (h0 * np.outer(np.sin(lats), sind * S) + np.sin(h0) * np.outer(np.cos(lats), cosd * S)) / np.pi


# get the average annual cycle of q4
q29 = np.zeros((nlats,   1), dtype=q4.dtype)  # February 29
q1c = np.zeros((nlats, 365), dtype=q4.dtype)  # any other day
for i in np.arange(4):  # average over four cases: leap day in year 1, 2, 3 and 4
    q29 = q29 + q4[:,365*i+59].reshape(nlats, 1)
    q4noleap = np.delete(q4, 365*i+59, 1).reshape(nlats, 4, 365)
    q1c = q1c + q4noleap.mean(axis=1)
q1 = np.concatenate((q1c[:,:59], q29, q1c[:,59:]), axis=1) / 4.


# save q1 monthly and for different orientations of latitude axis
savedir = './TOA_daily_mean_insolation_climatology/'
savefilenameprefix = 'dlat'+str(options.d)+'month'
day0 = 0
for m in np.arange(1, 13):
    dpm = monthrange(2000, m)[1]
    ofilem = savedir+savefilenameprefix+('0' if m<10 else '')+str(m)
    ofile = ofilem+'.NtoS.npy'
    print 'saving '+ofile+' ...'
    np.save(ofile, q1[:,day0:day0+dpm])
    ofile = ofilem+'.StoN.npy'
    print 'saving '+ofile+' ...'
    np.save(ofile, q1[::-1,day0:day0+dpm])
    day0 = day0 + dpm
print "done"
