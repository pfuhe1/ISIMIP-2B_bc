##################################
# Python script to run isimip bias correction code
# V3 updated with better checking for existing files and step 2.5
# Also works better with different obs
# EU25 version allows for determining date range from single year HadAM3P runs
# Peter Uhe 6/4/2018
# 
# Assumes that the bias correction transfer coefficients for the model/variable
# have already been calculated, and applies the bias correction to other runs

import sys,os,glob,subprocess
import multiprocessing
#import multiprocessing.dummy
sys.path.append('/home/bridge/pu17449/src/happi_data_processing')
from get_runs import get_runs

# Create list into a string with spaces
def list_to_string(l):
	s = ''
	for item in l:
		s += item +' '
	return s

# Input parameters
var='tas'
freq='day'
obsname = 'EWEMBI-UK25'

#model='NorESM1-HAPPI'
#daterange_calibrate = '1979-2013'
#realization_calibrate = 'run126'

#model='CAM4-2degree'
#daterange_calibrate = '1979-2013'
#realization_calibrate = 'ens1000'

#model = 'HadAM3P'
#daterange_calibrate = '1987-2013'
#realization_calibrate = 'runcat1'

model = 'HadAM3P-EU25'
daterange_calibrate = '1986-2013'
realization_calibrate = 'runcat1'

expt='All-Hist'
#daterange_app = '2006-2015'

#expt='Plus15-Future'
#daterange_app='2106-2115'
#daterange_app = '2090-2099'

# Multithreading
numthreads=1

###############################################################################
# Paths
# NOTE, these paths need to match the paths in the 'exports.settings.functions.sh' script!
sdir = '/home/bridge/pu17449/src/ISIMIP2b_bc/' 

wdir = '/export/anthropocene/array-01/pu17449/isimip_bc'
tdir = os.path.join(wdir,'isimip_processing/')
# Output of step 1
idirGCMsource = os.path.join(wdir,'happi_data_long/')
# Output of step 2 (Note needs observation in directory name to be unique)
idirGCMdata = os.path.join(wdir,'happi_data_regrid_'+obsname)
os.environ['idirGCMdata']=idirGCMdata
# Output of step 3
odirGCMdata = os.path.join(wdir,'happi_data_corrected')
os.environ['odirGCMdata']=odirGCMdata

# Original location of the happi data
datadir = os.path.join(wdir,'../happi_data_extra/')
logdir = os.path.join(wdir,'logs/')

# Not used in this script but needed for ISIMIP scripts:
idirOBSdata=os.path.join(wdir,'obs')

################################################################################

def bias_correct_run(model,expt,var,freq,daterange_calibrate,daterange_app,idirGCMsource,idirGCMdata,odirGCMdata,runpath):

	arr = os.path.dirname(runpath).split('/')
	ver = arr[-4]
	est = arr[-5]
	realization = os.path.basename(runpath)

	print 'Setting environment variables for ISIMIP scripts:'
	print 'realization:',realization
	print 'refrealization:',realization_calibrate
	print 'est:',est
	print 'ver:',ver

	os.environ['realization'] = realization
	os.environ['refrealization'] = realization_calibrate
	os.environ['est'] = est
	os.environ['ver'] = ver

	datelong = daterange_app[:4]+'0101,'+daterange_app[5:]+'1231'
	datelong2=datelong.replace(',','-')

	regrid_file = os.path.join(idirGCMdata,model,var+'_'+freq+'_'+model+'_'+expt+'_'+realization+'_'+datelong2+'.nc')

	final_file = os.path.join(odirGCMdata,model,obsname,var+'_'+freq+'_'+model+'_'+expt+'_'+realization+'_'+obsname+'_'+datelong2+'.nc')

	if os.path.exists(final_file):
		print 'Bias corrected file already exists, skipping:',final_file
		return

	##################################################################
	# 1) Select time from files and move to isimip input folder

	if os.path.isdir(runpath):
		# get input files in runpath
	 	run_files=sorted(glob.glob(runpath+'/*.nc'))
	else:
		# The runpath is the file
		run_files = [runpath]

	fname = run_files[0]
	#fstem = os.path.basename(fname)[:-20]
#	fdir = os.path.dirname(fname).replace('happi_data','happi_data_long')
	fstem = var+'_A'+freq+'_'+model+'_'+expt+'_'+est+'_'+ver+'_'+realization+'_'+datelong2+'.nc'
	datadir_end = datadir.split('/')[-2]
	fdir = os.path.join(idirGCMsource,os.path.dirname(fname).split(datadir_end+'/')[-1])
	fout = os.path.join(fdir,fstem)
	if not os.path.exists(fout):
		if not os.path.exists(fdir):
			os.makedirs(fdir)

		if len(run_files)==1:
			cmdarr = ['cdo','seldate,'+datelong,fname,fout]
		else:
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
		flog = wdir+'/logs/regrid_'+model+'_'+var+'_'+expt+'_'+realization+'.log'
		cmd = sdir+'/interpolate.2obsdatagrid.2prolepticgregoriancalendar.sh '+obsname+' '+var+' '+model+' '+expt+' '+daterange_app
		print cmd
		#os.system(cmd)
		#cmdarr = ['./interpolate.2obsdatagrid.2prolepticgregoriancalendar.sh', obsname,var,model,expt,daterange_app]
		#print cmdarr

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
	# 3) ISIMIP script: app.coef
	flog = wdir+'/logs/bc_'+model+'_'+var+'_'+expt+'_'+realization+'.log'
	cmd = sdir+'/app.coef.sh '+obsname+' '+daterange_calibrate+' '+var+' '+var+' '+model+' '+expt+' '+daterange_app
	print cmd
	#os.system(cmd)
	#cmdarr = ['./app.coef.sh',obsname,daterange_calibrate,var,var,model,expt,daterange_app]
	#print cmdarr
	#proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,stderr=subprocess.STDOUT,env={'realization':realization},shell=True,executable='/bin/bash')
	proc = subprocess.Popen(cmd, stdout=open(flog,'w'),stderr=subprocess.STDOUT,shell=True)
	ret = proc.wait()
	
	print 'ret',ret
	if not ret == 0:
		print 'ERROR, Applying bias correction failed. '
		print 'Log file at:',flog
		return

	if os.path.exists(final_file):
		print 'Bias corrected file successfully created:',final_file
	else:
		print 'Script finished but bias corrected file not created:',final_file
		print 'Log file at:',flog


###########################################################################################
# Main script

# Call script by Pete to get paths of runs
f_runs = get_runs(model,expt,datadir,freq,var)

# Create pool of processes to process runs in parallel. 
#
pool = multiprocessing.Pool(processes=numthreads)	

# Loop over runs
#for runpath in f_runs:[:100]# (Limit to 100)
for runpath in f_runs:
	# HACK for EU25 runs to determine date range of files
	fname = glob.glob(runpath+'/*.nc')[0]
	#print fname
	daterange_app = fname[-18:-13]+fname[-10:-6]
	print 'daterange',fname[-18:-13]+fname[-10:-6]
	pool.apply_async(bias_correct_run, (model,expt,var,freq,daterange_calibrate,daterange_app,idirGCMsource,idirGCMdata,odirGCMdata,runpath))

	#bias_correct_run(model,expt,var,freq,daterange_calibrate,daterange_app,idirGCMsource,idirGCMdata,odirGCMdata,runpath)

# Finish up
pool.close()
pool.join()	


