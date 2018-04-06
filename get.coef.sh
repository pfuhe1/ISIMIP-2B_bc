#!/bin/bash

#SBATCH --qos=short
#SBATCH --partition=standard
#SBATCH --job-name=bc1p5get
#SBATCH --account=isimip
##SBATCH --mail-user=slange@pik-potsdam.de
##SBATCH --mail-type=ALL,TIME_LIMIT
#SBATCH --output=slogs/get.coef.%j
#SBATCH --error=slogs/get.coef.%j



source exports.settings.functions.sh



# check input parameters
case $# in
4)
  lobs=1;;
5)
  lobs=0;;
*)
  echo four or five input parameters expected !!! exiting ... $(date)
  exit;;
esac  # #

export obsdataset=$1
case $obsdataset in
EWEMBI|MSWEP|WFD)
  echo observational_dataset $obsdataset
  export lmonsb=1;;
Forests*|Nottingham*)
  echo observational_dataset $obsdataset
  export lmonsb=0;;
*)
  echo observational_dataset $obsdataset not supported !!! exiting ... $(date)
  exit;;
esac  # obsdataset
idirobs=$idirOBSdata/$obsdataset
tdirobsi=$tdir/$obsdataset/idat
tdirobsc=$tdir/$obsdataset/coef
export ipathBCmask=$idirobs/$obsdataset.BCmask.$ncs
exit_if_any_does_not_exist $ipathBCmask

export referenceperiod=$2
if [[ $referenceperiod =~ [0-9]{4}-[0-9]{4} ]]
then
  echo reference period $referenceperiod
  export ysreference=$(cut -d '-' -f 1 <<<$referenceperiod)
  export yereference=$(cut -d '-' -f 2 <<<$referenceperiod)
else
  echo reference period $referenceperiod has invalid format !!! exiting ... $(date)
  exit
fi  # referenceperiod
export expreference=$(get_reference_experiment $referenceperiod)

export var=$3
case $var in
hurs|psl|rlds|rsds|sfcWind|tas|tasmax|tasmin)
  echo variable $var;;
pr)
  export idlfactor=86400.
  echo variable $var;;
*)
  echo variable $var not supported !!! exiting ... $(date)
  exit;;
esac  # var

export bcmethod=$4
if [[ $bcmethod = $var ]]
then
  echo bias_correction_method $bcmethod
elif [[ $bcmethod = tas ]] && ([[ $var = tasmax ]] || [[ $var = tasmin ]])
then
  echo bias_correction_method $bcmethod ... CAUTION ... neither name nor metadata of the output file will indicate that $var was bias-corrected with a method developed for a different variable
else
  echo bias_correction_method $bcmethod not supported for variable $var !!! exiting ... $(date)
  exit
fi

if [ $lobs -eq 0 ]
then
  export gcm=$5
  case $gcm in
  GFDL-ESM2M|HadGEM2-ES|IPSL-CM5A-LR|MIROC5)
    echo GCM $gcm;;
  *)
    echo GCM $gcm not supported !!! exiting ... $(date)
    exit;;
  esac  # gcm
  idirgcm=$idirGCMdata/$gcm
  tdirgcmi=$tdir/$gcm/$obsdataset/idat
  tdirgcmc=$tdir/$gcm/$obsdataset/coef
fi  # lobs
echo



# prepare submission of slurm jobs for different months
if [ "$SLURM_JOB_ID" == "" ]
then
  export SLURM_JOB_ID=$RANDOM
  while [ -d $sdir/slogs/get.coef.$SLURM_JOB_ID.sbatched ]
  do
    export SLURM_JOB_ID=$RANDOM
  done
fi
if [ $lmonsb -eq 1 ] && [[ $bcmethod != hurs ]] && [[ $bcmethod != rsds ]]
then
  export sbatchedlogs=$sdir/slogs/get.coef.$SLURM_JOB_ID.sbatched
  export sbatchedlist=$sbatchedlogs.current
  mkdir -p $sbatchedlogs
fi



# make directories for output
mkdir -p $tdir/subscripts $tdirobsi $tdirobsc
[ $lobs -eq 0 ] && mkdir -p $tdirgcmi $tdirgcmc



# set input paths and check input file existence
if [ $lobs -eq 1 ]
then
  dataset=$obsdataset
  idir=$idirobs
  ifile=${var}_${frequency}_${obsdataset}_${ysreference}0101-${yereference}1231
else
  dataset=$gcm
  idir=$idirgcm
  ifile=${var}_${frequency}_${gcm}_${expreference}_${realization}_${ysreference}0101-${yereference}1231
  if [ ! -f $idir/$ifile.$ncs ]
  then
    idir=$tdirgcmi
    merge_reference_decades_if_necessary $var $gcm $ysreference-$yereference $idir/$ifile.$ncs $ipathBCmask
  fi
fi  # lobs
exit_if_any_does_not_exist $idir/$ifile.$ncs



case $bcmethod in
hurs|rsds)
  [ $lobs -eq 1 ] && odir=$tdirobsc || odir=$tdirgcmc
  ofile=$ifile

  # get multi-year daily means, variances (and maxima)
  case $bcmethod in
  hurs)
    echo "clamping $var input values in [0,100] ..."
    $cdo setmisstoc,0 -ifthen -gtc,0 $idir/$ifile.$ncs $idir/$ifile.$ncs $odir/$ifile.unlimited.$ncs
    exit_if_nt $idir/$ifile.$ncs $odir/$ifile.unlimited.$ncs
    $cdo setmisstoc,100 -ifthen -ltc,100 $odir/$ifile.unlimited.$ncs $odir/$ifile.unlimited.$ncs $odir/$ifile.limited.$ncs
    exit_if_nt $odir/$ifile.unlimited.$ncs $odir/$ifile.limited.$ncs
    rm $odir/$ifile.unlimited.$ncs
    echo ... clamping done
    echo

    ipath=$odir/$ifile.limited
    stats="mean var1"
    echo computing multi-year daily $dataset means and variances ...;;
  rsds)
    ipath=$idir/$ifile
    stats="mean var1 max"
    echo computing multi-year daily $dataset means, variances and maxima ...;;
  esac  # bcmethod
  for stat in $stats
  do
    $cdo yday$stat -ifthen $ipathBCmask $ipath.$ncs $odir/$ifile.yday$stat.$ncs
    exit_if_nt $ipath.$ncs $odir/$ifile.yday$stat.$ncs
  done  # stat
  echo ... computing done
  echo

  # get smoothed multi-year daily means, variances (and maxima)
  case $bcmethod in
  hurs)
    rm $ipath.$ncs
    get_coef_hurs_rsds_special_args="-l -u 100."
    echo smoothing multi-year daily $dataset means and variances ...;;
  rsds)
    get_coef_hurs_rsds_special_args="-f $rsdsmaxfitthreshold -t $sdir/python/TOA_daily_mean_insolation_climatology -x $odir/$ifile.ydaymax.$ncs"
    echo smoothing multi-year daily $dataset means, variances and maxima ...;;
  esac  # bcmethod
  python $sdir/python/get_coef_hurs_rsds.py $get_coef_hurs_rsds_special_args \
         -a $missval \
         -i $var \
         -n $nrunmeanhursrsds \
         -m $odir/$ifile.ydaymean.$ncs \
         -v $odir/$ifile.ydayvar1.$ncs \
         -o $odir/$ofile.$ncs
  for stat in $stats; do exit_if_nt $odir/$ifile.yday$stat.$ncs $odir/$ofile.$ncs; done
  for stat in $stats; do rm $odir/$ifile.yday$stat.$ncs; done
  echo ... smoothing done
  ;;
*)
  # convert NetCDF to IDL binary files
  sfile=convert.nc2idl.monthly
  [ $lobs -eq 1 ] && odir=$tdirobsi || odir=$tdirgcmi

  echo converting reference-period NetCDF file to monthly IDL binary files ...
  $sdir/bash/$sfile.sh $idir $odir $ifile ${ifile}_ 2
  if [ $lmonsb -eq 1 ]
  then
    wait_for_batch_jobs_to_finish $sbatchedlist
    rm $sbatchedlist $tdir/subscripts/*.$SLURM_JOB_ID
  fi
  for month in $(seq -w 1 12); do exit_if_nt $idir/$ifile.$ncs $odir/${ifile}_$month.dat; done
  echo ... converting done
  
  # calculate transfer function coefficients
  if [ $lobs -eq 0 ]
  then
    echo
    echo computing transfer function coefficients ...
    sfile=get.coef.monthly
    ifixobs=_${frequency}_${obsdataset}_${ysreference}0101-${yereference}1231_
    ifixgcm=_${frequency}_${gcm}_${expreference}_${realization}_${ysreference}0101-${yereference}1231_
    ofixgcm=_${frequency}_${gcm}_${expreference}_${realization}_${obsdataset}_${ysreference}0101-${yereference}1231_
    ipathobs=$tdirobsi/$var$ifixobs
    ipathgcm=$tdirgcmi/$var$ifixgcm
    ipathobstas=$tdirobsi/tas$ifixobs  # for tasmin and tasmax
    ipathgcmtas=$tdirgcmi/tas$ifixgcm  # for tasmin and tasmax
    opath=$tdirgcmc/$var$ofixgcm

    # check input file existence
    for month in $(seq -w 1 12)
    do
      exit_if_any_does_not_exist $ipathobs$month.dat
      exit_if_any_does_not_exist $ipathgcm$month.dat
    done  # month

    # calculate coefficients
    $sdir/bash/$sfile.sh $ipathobs $ipathobstas $ipathgcm $ipathgcmtas $opath
    if [ $lmonsb -eq 1 ]
    then
      wait_for_batch_jobs_to_finish $sbatchedlist
      rm $sbatchedlist $tdir/subscripts/*.$SLURM_JOB_ID
    fi

    # check output file existence
    for month in $(seq -w 1 12)
    do
      exit_if_nt $ipathobs$month.dat $opath$month.dat
      exit_if_nt $ipathgcm$month.dat $opath$month.dat
    done  # month
    echo ... computing done
  fi  # lobs
  ;;
esac  # bcmethod
