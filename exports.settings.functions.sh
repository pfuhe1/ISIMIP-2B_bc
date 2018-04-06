#!/bin/bash

# PFU: print date for start of script
#
date

###
### PFU hack to use idl rather than gdl, this is now done in bashrc
### 
#alias gdl='idl'
# Add path for cmsvlib
#export IDL_PATH=$IDL_PATH:/home/bridge/pu17449/src/idl/cmsvlib


###
### paths which can be changed arbitrarily
###


export wdir=/export/anthropocene/array-01/pu17449/isimip_bc # work directory
export sdir=/home/bridge/pu17449/src/ISIMIP2b_bc/ # source code directory (this script has to be in that directory)
export tdir=$wdir/isimip_processing  # temporary output directory
export idirOBSdata=$wdir/obs  # directory for observational data
export idirGCMsource=$wdir/happi_data_long  # directory containing uncorrected GCM data to be pre-processed with interpolation script

# Comment out these ones, and supply with environment variables
#export idirGCMdata=$wdir/happi_data_regrid  # directory for uncorrected GCM data
#export odirGCMdata=$wdir/happi_data_corrected  # directory for corrected GCM data


###
### parameters
###

# PFU modification, 
# Take these parameters from environment variables, not set here
# This allows them to be changed without modifying the script here
# 
# export realization=r1i1p1
# export realization=run001

# refrealization: 
# realization used for calculation of bias correction coefficients
# export refrealization=run126

# est and ver:
# specific to HAPPI, used to determine the correct file paths
# export est=est1
# export ver=v1-0

# PFU addition to allow easy addition of new observations
shopt -s extglob
allowed_obs='@(EWEMBI|EWEMBI-N96|MSWEP|WFD|EWEMBI-UK25)'
allowed_models='@(CAM4-2degree|CanAM4|MIROC5|NorESM1-HAPPI|CESM-CAM5|ECHAM6-3-LR|HadAM3P|HadAM3P-EU25)'


export frequency=day
export historicalextensionpathway=rcp85  # for bias correction
export ysdecadeoffset=1  # decade start year offset from 0
export remapmethod=con  # for GCMinput pre-processing (con is preferred over con2 because con2 may remap non-negative to negative values)
export dailymaxhuss=1.  # kg kg-1
export dailymaxpr=.00462963  # kg m-2 s-1 (equivalent to 400 mm/day)
export dailymaxpsl=120000.  # Pa
export dailymaxrlds=1000.  # W m-2
export dailymaxsfcWind=75.  # m s-1
export dailymaxtas=333.15  # K (equivalent to +60 degC)
export dailyminpsl=80000.  # Pa
export dailymintas=183.15  # K (equivalent to -90 degC)
export wetmonthreshold=0.01  # mm/day
export wetdaythreshold=0.1  # mm/day
export nwetdaysmin=80  # number of wet days required for transfer function fitting
export nrunmeanhursrsds=25  # window length in days for running mean calculation of hurs and rsds bias correction parameters
export rsdsmaxfitthreshold=50.  # W m-2
export correctionfactormaxnonneg=10.
export correctionfactormaxtasminmax=3.
export missval=1e20
# PFU hack to serialize IO in cdo
#export cdo="cdo -f nc4c -z zip"
export cdo="cdo -L -f nc4c -z zip"
export ncs="nc"
export CDO_FILE_SUFFIX=.$ncs
export GDL_PATH=$GDL_PATH:$sdir/gdl



###
### functions
###



function get_interpolation_method_label {
  # $1 CDO identifier of interpolation method
  # returns string describing this interpolation method
 
  case $1 in
  bil)
    echo bilinear
    return 0;;
  con)
    echo first-order conservative
    return 0;;
  con2)
    echo second-order conservative
    return 0;;
  *)
    echo ERROR !!! interpolation method $1 not supported
    return 1;;
  esac  # 1
}
export -f get_interpolation_method_label



function get_piControl_period_in {
  # $1 GCM name
  # returns "yearstart-yearend" of raw piControl input data
 
  case $1 in
  GFDL-ESM2M)  # last years
    local ys=0062
    local ny=439;;
  HadGEM2-ES)  # first years
    local ys=1860
    local ny=320;;
  IPSL-CM5A-LR)  # last years
    local ys=3260
    local ny=440;;
  MIROC5)  # first years
    local ys=2100
    local ny=570;;
  *)
    echo ERROR !!! experiment $1 not supported
    return 1;;
  esac  # 1
  local ye=$(printf %04d $((10#$ys+10#$ny-1)))
  echo $ys-$ye
  return 0
}
export -f get_piControl_period_in



function get_experiment_period {
  # $1 CMIP5 experiment name
  # $2 GCM name
  # returns "yearstart-yearend" of that experiment as used for bias correction
 
  case $2 in
  IPSL-CM5A-LR)
    local ye26=2299
    local ye45=2299
    local ye85=2299;;
  HadGEM2-ES|MIROC5)
    local ye26=2299
    local ye45=2099
    local ye85=2099;;
  *)
    local ye26=2099
    local ye45=2099
    local ye85=2099;;
  esac  # 2
  case $1 in
  All-Hist)
	local ys=1950; local ye=2017;;
  Plus15-Future|Plus20-Future)
	local ys=2090; local ye=2120;;
  piControl)
    local ys=1661; local ye=$ye26;;
  historical)
    local ys=1861; local ye=2005;;
  rcp26)
    local ys=2006; local ye=$ye26;;
  rcp45)
    local ys=2006; local ye=$ye45;;
  rcp60)
    local ys=2006; local ye=2099;;
  rcp85)
    local ys=2006; local ye=$ye85;;
  *)
    echo ERROR !!! experiment $1 not supported
    return 1;;
  esac  # 1
  echo $ys-$ye
  return 0
}
export -f get_experiment_period



function get_first_year_of_decade_containing {
  # $1 year to contain
  # $2 decade start year offset from 0
  # returns the first year of the decade with offset $2 containing $1

  if [[ $2 = [0-9] ]]
  then
    local ysd=$(expr $1 - $1 % 10 + $2)
    [ $ysd -gt $1 ] && ysd=$(expr $ysd - 10)
    echo $ysd
    return 0
  else
    echo ERROR !!! second argument has to be a one-digit number
    return 1
  fi
}
export -f get_first_year_of_decade_containing



function get_experiment_decades {
  # $1 CMIP5 experiment name
  # $2 GCM name
  # returns list of decades in the form
  # "yearstartfirstdecade-yearendfirstdecade yearstartseconddecade-yearendseconddecade ..."
  # for the given experiment-GCM combination
 
  local period=$(get_experiment_period $1 $2)
  local ys=$(cut -d '-' -f 1 <<<$period)
  local ye=$(cut -d '-' -f 2 <<<$period)
  local ysds=$(get_first_year_of_decade_containing $ys $ysdecadeoffset)
  local ysde=$(get_first_year_of_decade_containing $ye $ysdecadeoffset)

  local decades=
  local ysd
  for ysd in $(seq $ysds 10 $ysde)
  do
    local yed=$(( $ysd + 9 ))
    [ $ysd -lt $ys ] && ysd=$ys
    [ $yed -gt $ye ] && yed=$ye
    decades="$decades $ysd-$yed"
  done  # ysd

  echo $decades
  return 0
}
export -f get_experiment_decades



function is_leap_proleptic_gregorian {
  # $1 year
  # returns 1 if $1 is a leap year and 0 otherwise

  local il=0
  if (( ( $1 / 4 * 4 ) == $1 ))
  then
    if (( ( $1 / 100 * 100 ) == $1 ))
    then
      if (( ( $1 / 400 * 400 ) == $1 ))
      then
        il=1
      fi
    else
      il=1
    fi
  fi
  echo $il
  return 0
}
export -f is_leap_proleptic_gregorian



function get_halfdegree_lonlatbox {
  # $1 longitude
  # $2 latitude
  # returns lonmin,lonmax,latmin,latmax of the 0.5-degree regular grid cell 
  # that contains longitude, latitude

  local nlon=$(bc<<<"$1 / .5")
  if [[ ${1:0:1} = - ]]  # longitude negative?
  then
    local lonbounds=$(bc<<<"($nlon - 1) * .5"),$(bc<<<"$nlon * .5")
  else
    local lonbounds=$(bc<<<"$nlon * .5"),$(bc<<<"($nlon + 1) * .5")
  fi

  local nlat=$(bc<<<"$2 / .5")
  if [[ ${2:0:1} = - ]]  # latitude negative?
  then
    local latbounds=$(bc<<<"($nlat - 1) * .5"),$(bc<<<"$nlat * .5")
  else
    local latbounds=$(bc<<<"$nlat * .5"),$(bc<<<"($nlat + 1) * .5")
  fi

  echo $lonbounds,$latbounds
  return 0
}
export -f get_halfdegree_lonlatbox



function get_day_difference {
  # $1 first date yyyymmdd
  # $2 second date yyyymmdd
  # returns number of days that have to be added to get from $2 to $1
  # i.e. $1 - $2 on an absolute daily time axis 

  echo $(( ($(date -ud $1 +%s) - $(date -ud $2 +%s)) / 86400 ))
  return 0
}
export -f get_day_difference



function get_merge_reference_decades_ipaths {
  # $1 input path prefix
  # $2 reference period in the form ysreference-yereference
  # returns the paths to decadal NetCDF files that need to be merged in order
  # to get one NetCDF file that covers the whole reference period

#  local yeh=$(cut -d '-' -f 2 <<<$(get_experiment_period historical))
#  local yeh=$(cut -d '-' -f 2 <<<$(get_experiment_period All-Hist))
#  local yse=$(cut -d '-' -f 1 <<<$(get_experiment_period $historicalextensionpathway))
  local ysreference=$(cut -d '-' -f 1 <<<$2)
  local yereference=$(cut -d '-' -f 2 <<<$2)
#  local ysds=$(get_first_year_of_decade_containing $ysreference $ysdecadeoffset)
#  local ysde=$(get_first_year_of_decade_containing $yereference $ysdecadeoffset)
#  local ipaths=
#  local ysd
#  for ysd in $(seq $ysds 10 $ysde)
#  do
#    local yed=$(( $ysd + 9 ))
#    # PFU hack to restrict file names to valid periods
#	ysd=$(($ysd>$ysreference?$ysd:$ysreference)) # Greater of ysd and ysreference
#	yed=$(($yed<$yereference?$yed:$yereference)) # Lesser of yed and yereference
#    if [ $yed -le $yeh ]
#    then
#      ipaths="$ipaths ${1}All-Hist_${realization}_${ysd}0101-${yed}1231.$ncs"
#    elif [ $ysd -ge $yse ]
#    then
#      ipaths="$ipaths $1${historicalextensionpathway}_${realization}_${ysd}0101-${yed}1231.$ncs"
#    elif [ $yereference -le $yeh ]
#    then
#      ipaths="$ipaths ${1}All-Hist_${realization}_${ysd}0101-${yeh}1231.$ncs"
#    else
#      ipaths="$ipaths ${1}historical_${realization}_${ysd}0101-${yeh}1231.$ncs $1${historicalextensionpathway}_${realization}_${yse}0101-${yed}1231.$ncs"
#    fi
#  done  # ysd
  ipaths=${1}All-Hist_${realization}_${ysreference}0101-${yereference}1231.$ncs
  echo $ipaths
  return 0
}
export -f get_merge_reference_decades_ipaths



function get_merge_reference_decades_cdopipe {
  # $1 input path prefix
  # $2 reference period in the form ysreference-yereference
  # $3 (optional) path to NetCDF file that is used to mask files before they are merged
  # returns the cdo pipe to be put after cdo mergetime to get a NetCDF file
  # covering the whole reference period from decadal input NetCDF files

  local ipaths=$(get_merge_reference_decades_ipaths $1 $2)
  local ysreference=$(cut -d '-' -f 1 <<<$2)
  local yereference=$(cut -d '-' -f 2 <<<$2)
  [ $# -eq 3 ] && local cdomask="-ifthen $3" || local cdomask=

  local cdopipe=
  local ipath
  for ipath in $ipaths; do cdopipe="$cdopipe $cdomask -selyear,$ysreference/$yereference $ipath"; done
  echo $cdopipe
  return 0
}
export -f get_merge_reference_decades_cdopipe



function get_merge_rcp_decades_cdopipe {
  # $1 input path prefix
  # $2 start year
  # $3 end year
  # $4 rcp
  # $5 gcm
  # returns the cdo pipe to be put after cdo mergetime to get a NetCDF file
  # covering $2--$3 of the given rcp from decadal input NetCDF files

  local ysr=$(cut -d '-' -f 1 <<<$(get_experiment_period $4 $5))
  local yer=$(cut -d '-' -f 2 <<<$(get_experiment_period $4 $5))
  local ysds=$(get_first_year_of_decade_containing $2 $ysdecadeoffset)
  local ysde=$(get_first_year_of_decade_containing $3 $ysdecadeoffset)
  local cdopipe=
  local ysd
  for ysd in $(seq $ysds 10 $ysde)
  do
    local yed=$(( $ysd + 9 ))
    [ $ysd -lt $ysr ] && ysd=$ysr
    [ $yed -gt $yer ] && yed=$yer
    local selyearpipe="$1${ysd}0101-${yed}1231.$ncs"
    [ $ysd -lt $2 ] && selyearpipe="-selyear,$2/$yed $selyearpipe"
    [ $yed -gt $3 ] && selyearpipe="-selyear,$ysd/$3 $selyearpipe"
    cdopipe="$cdopipe $selyearpipe"
  done  # ysd
  echo $cdopipe
  return 0
}
export -f get_merge_rcp_decades_cdopipe



function wait_for_batch_jobs_to_finish {
  # this function can handle input in the following two forms
  # $1 path to file with list of slurm job IDs
  # $1 ... $n slurm job IDs
  # waits until none of the slurm jobs in the given list are running any more

  # process arguments
  local badformaterrormessage="recieved neither a list of slurm job IDs nor a path to a file with such a list !!! exiting ... $(date)"
  case $# in
  0)
    echo no arguments recieved !!! exiting ... $(date)
    exit;;
  1)
    if [[ $1 =~ ^[0-9]+$ ]]
    then
      echo -n "... waiting for batch job to finish ... "
      local sjobids=$1
    elif [ -s $1 ]
    then
      local arg; for arg in $(cat $1); do if [[ ! $arg =~ ^[0-9]+$ ]]; then echo $badformaterrormessage; exit; fi; done
      echo -n "... waiting for batch jobs to finish ... "
      local sjobids=$(cat $1 | tr '\n' ',' | sed 's/,$//')
    else
      echo $badformaterrormessage
      exit
    fi;;
  *)
    local arg; for arg in $@; do if [[ ! $arg =~ ^[0-9]+$ ]]; then echo $badformaterrormessage; exit; fi; done
    echo -n "... waiting for batch jobs to finish ... "
    local sjobids=$(sed 's/ /,/g'<<<$@)
  esac

  # do the waiting
  local squeueouterr=$(squeue --format="%i" -j$sjobids 2>&1)
  until [[ $squeueouterr = JOBID ]] || [[ $squeueouterr = "slurm_load_jobs error: Invalid job id specified" ]]
  do
    sleep 32
    squeueouterr=$(squeue --format="%i" -j$sjobids 2>&1)
  done  # squeueouterr
  echo done ...

  return 0
}
export -f wait_for_batch_jobs_to_finish



function submit_wait_check_loop {
  # $1 ... $n sbatch options (with leading hyphen)
  # $n+1 path to shell script (first argument without leading hyphen)
  # $n+2 ... $n+1+m shell script arguments

  local errormessages="\!\!\!\|permission denied\|no such file or directory\|segmentation fault\|hdf error"
  local nerrormessages=1
  local nloopmax=5
  local iloop=0

  # extract path to shell script from list of input arguments
  local spath; for spath in $@; do [[ ${spath:0:1} != - ]] && break; done

  while [ $nerrormessages -gt 0 ] && [ $iloop -lt $nloopmax ]
  do
    [ $iloop -gt 0 ] && echo " resubmitting ..."

    # keep submitting until successfull
    local sbatchouterr=$(sbatch $@ 2>&1)
    while [[ $sbatchouterr = *error* ]]
    do
      sleep 16
      sbatchouterr=$(sbatch $@ 2>&1)
    done
    echo $sbatchouterr on $(date)
    local sjobid=$(echo $sbatchouterr | cut -d ' ' -f 4)
    local slogfile=slogs/$(basename ${spath%sh})$sjobid

    # wait until slurm job is done
    wait_for_batch_jobs_to_finish $sjobid

    # check log file for error messages
    local nerrormessages=$(tr [:upper:] [:lower:] < $slogfile | grep -c "$errormessages")
    case $nerrormessages in
    0)
      echo -n;;
    1)
      echo -n ... 1 error message found in log file $slogfile ...;;
    *)
      echo -n ... $nerrormessages error messages found in log file $slogfile ...;;
    esac  # nerrormessages
    iloop=$(($iloop + 1))
  done

  if [ $nerrormessages -gt 0 ] && [ $iloop -eq $nloopmax ]
  then
    echo
    echo tried $nloopmax times to sbatch $@ without success !!! exiting ... $(date)
    exit 111
  else
    echo ... no error messages found in log file $slogfile

    # return error code based on checksum
    local checksum=$(tail -n 1 $slogfile | rev | cut -d ' ' -f 1 | rev)
    [[ $checksum =~ ^0+$ ]] && return 0 || return 1
  fi
}
export -f submit_wait_check_loop



function get_cdoexpr_huss_Weedon2010style {
  # returns the cdo expression that calculates specific humidity from
  # relative humidity, air pressure and temperature using the equations of
  # Buck (1981) Journal of Applied Meteorology 20, 1527-1532,
  # doi:10.1175/1520-0450(1981)020<1527:NEFCVP>2.0.CO;2 as described in
  # Weedon et al. (2010) WATCH Technical Report 22,
  # url:www.eu-watch.org/publications/technical-reports

  local shum=$1  # name of specific humidity [kg/kg]
  local rhum=$2  # name of relative humidity [1]
  local pres=$3  # name of air pressure [mb]
  local temp=$4  # name of temperature [degC]
  
  # ratio of the specific gas constants of dry air and water vapor after Weedon2010
  local RdoRv=0.62198
  
  # constants for calculation of saturation water vapor pressure over water and ice after Weedon2010, i.e.,
  # using Buck1981 curves e_w4, e_i3 and f_w4, f_i4
  local aw=6.1121   # [mb]
  local ai=6.1115   # [mb]
  local bw=18.729
  local bi=23.036
  local cw=257.87   # [degC]
  local ci=279.82   # [degC]
  local dw=227.3    # [degC]
  local di=333.7    # [degC]
  local xw=7.2e-4
  local xi=2.2e-4
  local yw=3.20e-6
  local yi=3.83e-6
  local zw=5.9e-10
  local zi=6.4e-10
  
  # prepare usage of different parameter values above and below 0 degC
  local a="(($temp>0)?$aw:$ai)"
  local b="(($temp>0)?$bw:$bi)"
  local c="(($temp>0)?$cw:$ci)"
  local d="(($temp>0)?$dw:$di)"
  local x="(($temp>0)?$xw:$xi)"
  local y="(($temp>0)?$yw:$yi)"
  local z="(($temp>0)?$zw:$zi)"
  
  # saturation water vapor pressure part of the equation
  local saturationpurewatervaporpressure="$a*exp(($b-$temp/$d)*$temp/($temp+$c))"
  local enhancementfactor="1.0+$x+$pres*($y+$z*$temp^2)"
  local saturationwatervaporpressure="($saturationpurewatervaporpressure)*($enhancementfactor)"
  
  # saturation water vapor pressure -> saturation specific humidity -> specific humidity
  echo "$shum=$rhum*$RdoRv/($pres/($saturationwatervaporpressure)+$RdoRv-1.0);"
  return 0
}
export -f get_cdoexpr_huss_Weedon2010style



function get_reference_period {
  # $1 name of observational dataset
  # returns ysreference-yereference
 
  echo $(grep $1 $idirOBSdata/referenceperiod.txt | cut -d ' ' -f 2)
  return 0
}
export -f get_reference_period



function get_reference_experiment {
  # $1 reference period in the form ysreference-yereference
  # returns historical or historical-$historicalextensionpathway
  # depending on whether yereference exceeds yehistorical

  local yereference=$(cut -d '-' -f 2 <<<$1)
#  local yehistorical=$(get_experiment_period historical foo | cut -d '-' -f 2)
  local yehistorical=$(get_experiment_period All-Hist foo | cut -d '-' -f 2)
  [ $yereference -gt $yehistorical ] && echo historical-$historicalextensionpathway || echo historical
  return 0
}
export -f get_reference_experiment



function exit_if_nt {
  # $1 path1
  # $2 path2
  # exits with error message if path1 -nt path2

  if [ ! -e $2 ]
  then
    echo $2 does not exist !!! exiting ... $(date)
    exit
  elif [ $1 -nt $2 ]
  then
    echo $1 is newer than $2 !!! exiting ... $(date)
    exit
  fi
  return 0
}
export -f exit_if_nt



function exit_if_any_does_not_exist {
  # $1 ... $n paths (also works with wildcards)
  # exits with error message if any path does not exist

  local lexit=0
  local path
  for path in "$@"
  do
    if [ ! -e $path ]
    then
      echo $path does not exist !!!
      lexit=1
    fi
  done  # path
  if [ $lexit -eq 1 ]
  then
    echo exiting ... $(date)
    exit
  fi
  return 0
}
export -f exit_if_any_does_not_exist



function merge_reference_decades_if_necessary {
  # $1 variable
  # $2 GCM
  # $3 reference period in the form ysreference-yereference
  # $4 path to output file
  # $5 (optional) path to NetCDF file that is used to mask files before they are merged

  local ipaths=$(get_merge_reference_decades_ipaths $idirGCMdata/$2/${1}_${frequency}_${2}_ $3)
  exit_if_any_does_not_exist $ipaths
  # PFU HACK
#  local lmerge=0; local ipath; for ipath in $ipaths; do [ $ipath -nt $4 ] && lmerge=1; done
#  if [ $lmerge -eq 1 ]
  if [ "${#ipaths[@]}" -gt 1 ]
  then
    echo merging decadal NetCDF input files to $4 ...
    local cdopipe=$(get_merge_reference_decades_cdopipe $idirGCMdata/$2/${1}_${frequency}_${2}_ $3 $5)
    $cdo -O mergetime $cdopipe $4
    echo ... merging done
    echo
  else
	echo only one input file, copying: $ipaths $4
    cp $ipaths $4
  fi
  return 0
}
export merge_reference_decades_if_necessary
