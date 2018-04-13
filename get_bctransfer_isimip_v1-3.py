##################################
# Python script to run isimip bias correction code
# V3 updated with better checking for existing files and step 2.5
# Also works better with different obs
# Peter Uhe 13/3/2018
# 
# Assumes that the bias correction transfer coefficients for the model/variable
# have already been calculated, and applies the bias correction to other runs

import sys,os,glob,subprocess,multiprocessing
sys.path.append('/home/bridge/pu17449/src/happi_data_processing')
from get_runs import get_runs,get_bc_runs

# Create list into a string with spaces
def list_to_string(l):
	s = ''
	for item in l:
		s += item +' '
	return s

# Input parameters

var='pr'
freq='day'
obsname = 'EWEMBI'
daterange_calibrate = '1979-2013' # Default (extent of EWEMBI dataset)
expt='All-Hist'

#model='NorESM1-HAPPI'
#realization_calibrate = 'run126'

#model='CAM4-2degree'
#realization_calibrate = 'ens1000'

#model='MIROC5'
#realization_calibrate = 'run101'

#model='ECHAM6-3-LR'
# NOTE this is for v1-1 (bias correction runs) v1-0 is 2006-2015 decade
#realization_calibrate = 'run001' 

model = 'CanAM4'
# NOTE: the bias correction runs (est2) actually points to amip runs from CMIP5
# as there aren't any bias correction runs specifically for HAPPI
realization_calibrate = 'r1i1p1'
# Override default range for years available:
daterange_calibrate = '1979-2009' 

#model = 'HadAM3P'
#realization_calibrate = 'runcat1'
# Override default date range for years available
#daterange_calibrate = '1987-2013' # for HadAM3P 10 year runs

#model = 'HadAM3P-EU25'
#realization_calibrate = 'runcat1'
# Override default date range for years available
#daterange_calibrate = '1986-2013' # for HadAM3P, EU25 runs


###############################################################################
# Paths
# NOTE, these paths need to match the paths in the 'exports.settings.functions.sh' script!
sdir = '/home/bridge/pu17449/src/ISIMIP2b_bc/' 

wdir = '/export/anthropocene/array-01/pu17449/isimip_bc'
tdir = os.path.join(wdir,'isimip_processing/')
# Output of step 1
idirGCMsource = os.path.join(wdir,'happi_data_long/')
# Output of step 2+3
idirGCMdata = os.path.join(wdir,'happi_data_regrid_'+obsname)
odirGCMdata = os.path.join(wdir,'happi_data_corrected_'+obsname)
os.environ['idirGCMdata']=idirGCMdata
os.environ['odirGCMdata']=odirGCMdata

# Original location of the happi data
#datadir = os.path.join(wdir,'../happi_data/')
datadir = os.path.join(wdir,'../happi_data/')
logdir = os.path.join(wdir,'logs/')

# Not used in this script but needed for ISIMIP scripts:
idirOBSdata=os.path.join(wdir,'obs')

###############################################################################

def calc_bias_correction_coef(model,expt,var,freq,daterange_calibrate,idirGCMsource,idirGCMdata,runpath):

	arr = os.path.dirname(runpath).split('/')
	ver = arr[-4]
	est = arr[-5]
	realization = os.path.basename(runpath)
	os.environ['realization'] = realization
	print 'realization',realization
	os.environ['est'] = est
	os.environ['ver'] = ver
	print 'est,ver',est,ver

	datelong = daterange_calibrate[:4]+'0101,'+daterange_calibrate[5:]+'1231'
	datelong2=datelong.replace(',','-')

	regrid_file = os.path.join(idirGCMdata,model,var+'_'+freq+'_'+model+'_'+expt+'_'+realization+'_'+datelong2+'.nc')

	idat_files = tdir+obsname+'/idat/'+var+'_day_'+obsname+'_'+datelong2+'_??.dat'
	coef_files = tdir+model+'/'+obsname+'/coef/'+var+'_day_'+model+'_historical_'+realization_calibrate+'_'+obsname+'_'+datelong2+'_??.dat'

	##################################################################
	# 1) Select time from files and move to isimip input folder

	if os.path.isdir(runpath):
		# get input files in runpath
	 	run_files=sorted(glob.glob(runpath+'/*.nc'))
	else:
		# The runpath is the file
		run_files = [runpath]

	fname = run_files[0]
#	fstem = os.path.basename(fname)[:-20]
#	fdir = os.path.dirname(fname).replace('happi_data','happi_data_long')
	fstem = var+'_A'+freq+'_'+model+'_'+expt+'_'+est+'_'+ver+'_'+realization+'_'+datelong2+'.nc'
#	fdir = os.path.join(idirGCMsource,os.path.dirname(fname).split('happi_data_extra/')[-1])
	datadir_end = datadir.split('/')[-2]
	fdir = os.path.join(idirGCMsource,os.path.dirname(fname).split(datadir_end+'/')[-1])
	fout = os.path.join(fdir,fstem)
	if not os.path.exists(fout):
		if not os.path.exists(fdir):
			os.makedirs(fdir)

		if len(run_files)==1:
			# Hack for getting rid of negative HadAM3P pr values: (maximum of 0 and data file)
			# Need to first create the zeros data file.
			if model == 'HadAM3P' and var == 'pr':
				cmdarr = ['cdo','max',tdir+'HadAM3P_zeros_'+datelong2+'.nc','-seldate,'+datelong,fname,fout]
			else:
				cmdarr = ['cdo','seldate,'+datelong,fname,fout]
		else:
			# Note, -L flag (lock IO) is needed when using child processes with CDO with netcdf4 on BRIDGE servers
			cmdarr = ['cdo','-L','seldate,'+datelong,'-cat',list_to_string(run_files),fout]

		print cmdarr
		proc = subprocess.Popen(cmdarr, stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
		(out, err) = proc.communicate()
		ret = proc.returncode
		print out
		print 'ret',ret
		if not ret == 0:
			print 'ERROR, CDO command failed'
			return
	else:
		print 'File already exists, skipping step 1:',fout



	##################################################################
	# 2) ISIMIP script: interpolate.2obsdatagrid.2prolepticgregoriancalendar

	if not os.path.exists(regrid_file):
		flog = logdir+'/regrid_'+model+'_'+var+'_'+expt+'_'+realization+'.log'
		cmd = sdir+'/interpolate.2obsdatagrid.2prolepticgregoriancalendar.sh '+obsname+' '+var+' '+model+' '+expt+' '+daterange_calibrate
		print cmd

		proc = subprocess.Popen(cmd, stdout=open(flog,'w'),stderr=subprocess.STDOUT,shell=True)
		ret = proc.wait()
		print 'ret',ret
		if not ret == 0:
			print 'ERROR, Regridding command failed'
			print 'Log file at:',flog
			return

		if os.path.exists(regrid_file):
			print 'Finished regridding',regrid_file
		else:
			print 'Regridding finished, but output file not created:',regrid_file
			print 'Log file at:',flog
			return
	else:
		print 'File already exists, skipping step 2:',regrid_file



	##################################################################
	# 2.5) ISIMIP script: get.coef
	# IF using a new calibration period will need to run this for EWEMBI without model
	if not len(glob.glob(idat_files))==12:
	
		flog = logdir+'/get_coef_'+obsname+'_'+var+'.log'
		cmd = sdir+'/get.coef.sh '+obsname+' '+daterange_calibrate+' '+var+' '+var
		print cmd
		proc = subprocess.Popen(cmd, stdout=open(flog,'w'),stderr=subprocess.STDOUT,shell=True)
		ret = proc.wait()
	
		print 'ret',ret
		if not ret == 0:
			print 'ERROR, Creating obs idat files failed.'
			print 'Log file at:',flog
			return
		elif not len(glob.glob(idat_files))==12:
			print 'ERROR, Script completed but obs idat files not created. '
			print 'Log file at:',flog
			return

	else:
		print 'File already exists, skipping step 2.5:',idat_files


	##################################################################
	# 3) ISIMIP script: get.coef
	if not len(glob.glob(coef_files))==12:
	
		flog = logdir+'/get_coef_'+model+'_'+var+'_'+expt+'_'+realization+'.log'
	
		cmd = sdir+'/get.coef.sh '+obsname+' '+daterange_calibrate+' '+var+' '+var+' '+model
		print cmd
		proc = subprocess.Popen(cmd, stdout=open(flog,'w'),stderr=subprocess.STDOUT,shell=True)
		ret = proc.wait()
	
		print 'ret',ret
		if not ret == 0:
			print 'ERROR, Calculating bias correction coeffs failed. '
			print 'Log file at:',flog
			return
		elif not len(glob.glob(coef_files))==12:
			print 'ERROR, Script completed but coef files not created. '
			print 'Log file at:',flog
	else:
		print 'File already exists, skipping step 3:',coef_files

###########################################################################################
# Main script

# Get list of bias correction runs (based on model,freq,var)
f_runs = get_bc_runs(model,datadir,freq,var)

for runpath in f_runs:
	# Choose only one realization to use for the bias correction coefficients
	if os.path.basename(runpath)==realization_calibrate:
		calc_bias_correction_coef(model,expt,var,freq,daterange_calibrate,idirGCMsource,idirGCMdata,runpath)

##########################################################################################

# Finally do a bit of cleaning up

idat_dir = os.path.join(tdir,model,obsname,'idat')
odat_dir = os.path.join(tdir,model,obsname,'odat')

if os.path.exists(idat_dir):
	print('deleting idat dir',idat_dir)
	shutil.rmtree(idat_dir)
else:
	print('trying to delete but idat dir doesnt exist',idat_dir)
	

if os.path.exists(odat_dir):
	print('deleting odat dir',odat_dir)
	shutil.rmtree(odat_dir)
else:
	print('trying to delete but odat dir doesnt exist',odat_dir)
