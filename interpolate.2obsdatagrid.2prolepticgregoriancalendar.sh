#!/bin/bash

#SBATCH --qos=medium
#SBATCH --partition=standard
#SBATCH --account=isimip
##SBATCH --mail-user=slange@pik-potsdam.de
##SBATCH --mail-type=ALL,TIME_LIMIT
#SBATCH --output=slogs/interpolate.2obsdatagrid.2prolepticgregoriancalendar.%j
#SBATCH --error=slogs/interpolate.2obsdatagrid.2prolepticgregoriancalendar.%j



source exports.settings.functions.sh

# Flag to determine whether we interpolate to the OBS grid or not
# This must only be 0 if the grids of the model and OBS are identical
remap=1

# check input parameters
if [ ! $# -eq 5 ]
then
  echo five input parameters expected !!! exiting ... $(date)
  exit
fi

obsdataset=$1
case $obsdataset in $allowed_obs )
  echo observational dataset $obsdataset;;
*)
  echo observational dataset $obsdataset not supported !!! exiting ... $(date)
  exit;;
esac  # obsdataset

ovar=$2
case $ovar in
huss|pr|prsn|psl|rlds|rsds|tas|tasmax|tasmin|tos)
  echo variable $ovar
  ivar=$ovar
  remapweightsfileextension=;;
hurs)  # special case since hurs was mostly called rhs in CMIP5
  echo variable $ovar
  ivar=rhs
  remapweightsfileextension=;;
sfcWind)  # special case since wind fields may be defined on a staggered grid
  echo variable $ovar
  ivar=$ovar
  remapweightsfileextension=.wind;;
*)
  echo variable $ovar not supported !!! exiting ... $(date)
  exit;;
esac
[[ $ivar != $ovar ]] && cdosetname="-setname $ovar" || cdosetname=

gcm=$3
case $gcm in  # set input calendar
# GFDL-ESM2M|IPSL-CM5A-LR|MIROC5|NorESM1-M)
  CAM4-2degree|CanAM4|MIROC5|NorESM1-HAPPI|CESM-CAM5)
  echo GCM $gcm
  icalendar=365_day;;
# CMCC-CESM)
 ECHAM6-3-LR)
  echo GCM $gcm
  icalendar=standard;;
# HadGEM2-ES)
 HadAM3P|HadAM3P-EU25)
  echo GCM $gcm
  icalendar=360_day;;
*)
  echo GCM $gcm not supported !!! exiting ... $(date)
  exit;;
esac  # gcm

exp=$4
case $exp in
# piControl|historical|rcp26|rcp45|rcp60|rcp85)
 All-Hist|Plus15-Future|Plus20-Future)
  echo experiment $exp;;
*)
  echo experiment $exp not supported !!! exiting ... $(date)
  exit;;
esac

per=$5
if [[ $per =~ [0-9]{4}-[0-9]{4} ]]
then
  echo period $per
  ysp=$(cut -d '-' -f 1 <<<$per)
  yep=$(cut -d '-' -f 2 <<<$per)
else
  echo period $per has invalid format !!! exiting ... $(date)
  exit
fi  # per
echo



# set calendar and reference of output time axis
ocalendar=proleptic_gregorian
tsp=$ysp-01-01,00:00:00
timeframe=${ysp}0101-${yep}1231

# set input directory and file name
# (customize to your raw climate model output data directory and file name structures)
#idir=$idirGCMsource/$exp/$frequency/$ivar/$gcm/$realization  
#ifile=${ivar}_${frequency}_${gcm}_${exp}_${realization}_$timeframe.nc
#est=est1
#ver=v1-0
# NOTE: require 'est' and 'ver' as environment variables
domain=atmos
idir=$idirGCMsource/$gcm/$exp/$est/$ver/$frequency/$domain/$ivar/$realization
ifile=${ivar}_A${frequency}_${gcm}_${exp}_${est}_${ver}_${realization}_$timeframe.nc

# set output directory and file name
odir=$idirGCMdata/$gcm
ofile=${ovar}_${frequency}_${gcm}_${exp}_${realization}_$timeframe  # suffix is determined by shell variable ncs
[ ! -d $odir ] && mkdir -p $odir

# PFU hack to choose not to remap
# Set remap=0 when observations and model use the same grid
if [ $remap -ne 0 ]
then

	# set paths to remap weights
	remapweightsdir=$tdir/remapweights
	remapgriddesfile=$idirOBSdata/$obsdataset/$obsdataset.griddes
	remapweightsfile=$remapweightsdir/$gcm.remap$remapmethod.$obsdataset$remapweightsfileextension
	[ ! -d $remapweightsdir ] && mkdir -p $remapweightsdir

	# DEBUG
	echo infile $idir/$ifile

	# generate remap weights
	if [ $remapgriddesfile -nt $remapweightsfile.$ncs ]
	then 
	  echo generating remap weights ...
	  $cdo gen$remapmethod,$remapgriddesfile $idir/$ifile $remapweightsfile.$ncs
	fi
	echo

	# interpolate in space
	echo interpolating $ysp-$yep in space ...
	#$cdo -r setreftime,$tsp,day $cdosetname \
	#     -remap,$remapgriddesfile,$remapweightsfile.$ncs $idir/$ifile \
	#     $odir/$ofile.$ncs
	# PFU hack to allow parallel processing (rename tmp.nc tmp_$realization.nc)
	echo $odir/tmp_${ivar}_${gcm}_${exp}_${realization}.$ncs
	$cdo remap,$remapgriddesfile,$remapweightsfile.$ncs $idir/$ifile $odir/tmp_${ivar}_${gcm}_${exp}_${realization}.$ncs
	$cdo -r setreftime,$tsp,day $cdosetname $odir/tmp_${ivar}_${gcm}_${exp}_${realization}.$ncs $odir/$ofile.$ncs
	rm $odir/tmp_${ivar}_${gcm}_${exp}_${realization}.$ncs
	echo
else
	$cdo -r setreftime,$tsp,day $cdosetname $idir/$ifile $odir/$ofile.$ncs
fi

# interpolate in time
case $icalendar in
365_day|360_day)
  echo interpolating $ysp-$yep in time ...
  if [[ $icalendar = 360_day ]]; then
    # turn 360_day into 365_day calendar
    # (unfortunately this does not work with cdo setcalendar)
    # we devide the 360=72*5 days per year into six blocks with 
    # 36, 72, 72, 72, 72, 36 days worth of data per block
    # and then interpolate one day worth of data into the five gaps
    $cdo splityear $odir/$ofile.$ncs $odir/$ofile
    for year in $(seq $ysp $yep)
    do
      tsy=$year-01-01,00:00:00
      $cdo settaxis,$tsy,1day $odir/$ofile$year.$ncs $odir/$ofile$year.h.$ncs
      ncatted -a calendar,time,o,c,365_day $odir/$ofile$year.h.$ncs
      $cdo -O mergetime \
           -shifttime,0day -select,timestep=1/36 $odir/$ofile$year.h.$ncs \
           -shifttime,1day -select,timestep=37/108 $odir/$ofile$year.h.$ncs \
           -shifttime,2day -select,timestep=109/180 $odir/$ofile$year.h.$ncs \
           -shifttime,3day -select,timestep=181/252 $odir/$ofile$year.h.$ncs \
           -shifttime,4day -select,timestep=253/324 $odir/$ofile$year.h.$ncs \
           -shifttime,5day -select,timestep=325/360 $odir/$ofile$year.h.$ncs \
           $odir/$ofile$year.$ncs
      $cdo setreftime,$tsp,day \
           -inttime,$tsy,1day $odir/$ofile$year.$ncs \
           $odir/$ofile$year.h.$ncs
      mv $odir/$ofile$year.h.$ncs $odir/$ofile$year.$ncs
    done  # year
    $cdo -O mergetime $odir/$ofile????.$ncs $odir/$ofile.$ncs
    rm $odir/$ofile????.$ncs
  fi
  # turn 365_day into output calendar
  $cdo setreftime,$tsp,day \
       -inttime,$tsp,1day \
       -setcalendar,$ocalendar \
       -settaxis,$tsp,1day $odir/$ofile.$ncs \
       $odir/$ofile.h.$ncs
  # PFU add return value check as this command was often failing
  rc=$?
  if [ $rc -ne 0 ]; then
	echo 'cdo command failed'
	rm $odir/$ofile.$ncs
	rm $odir/$ofile.h.$ncs
	exit ${rc}
  fi
  mv $odir/$ofile.h.$ncs $odir/$ofile.$ncs;;
standard)
  if [[ $ysp -le 1582 ]]
  then
    echo standard and $ocalendar calendar differ before 1582-10-15 !!! please adjust script to cover that case !!! exiting ... $(date)
    exit
  else
    echo changing NetCDF calendar attribute from standard to $ocalendar
    ncatted -a calendar,time,o,c,$ocalendar $odir/$ofile.$ncs
  fi;;
$ocalendar)
  echo no time interpolation necessary;;
*)
  echo time interpolation not supported for input calendar=$icalendar !!! exiting ... $(date)
  exit;;
esac  # icalendar
