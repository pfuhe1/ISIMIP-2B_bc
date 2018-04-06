#!/bin/bash



# process input parameters
ipathobs=$1  # without month.suffix
ipathobstas=$2  # without month.suffix (only for tasmax and tasmin)
ipathgcm=$3  # without month.suffix
ipathgcmtas=$4  # without month.suffix (only for tasmax and tasmin)
opath=$5  # without month.suffix


# check input file existence (only for tasmax and tasmin)
case $bcmethod in
tasmax|tasmin)
  for month in $(seq -w 1 12)
  do
    exit_if_any_does_not_exist $ipathobstas$month.dat
    exit_if_any_does_not_exist $ipathgcmtas$month.dat
  done  # month
  [[ $bcmethod = tasmax ]] && minormax=1. || minormax=-1.
  ;;
esac  # bcmethod


# calculate transfer function coefficients for each month
for month in $(seq -w 1 12)
do
  sfile=get.coef.monthly.$month
  spath=$tdir/subscripts/$sfile.$SLURM_JOB_ID
  case $month in
  01)
    prevmonth=12
    nextmonth=02;;
  12)
    prevmonth=11
    nextmonth=01;;
  *)
    prevmonth=$(printf '%02d' $((10#$month - 1)))
    nextmonth=$(printf '%02d' $((10#$month + 1)));;
  esac  # month
  case $bcmethod in
  hurs)
    gdlprocedure=get_coef_hurs
    gdlarguments="'$ipathobs$month.dat','$ipathgcm$month.dat','$opath$month.dat'"
    ncpus=2;;
  pr)
    gdlprocedure=get_coef_pr
    gdlarguments="'$ipathobs$month.dat','$ipathgcm$month.dat','$opath$month.dat',$ysreference,$yereference,$((10#$month - 1)),NUMLANDPOINTS,land,$wetmonthreshold,$wetdaythreshold,$nwetdaysmin,$idlfactor"
    ncpus=2;;
  rlds|sfcWind)
    gdlprocedure=get_coef_rlds_sfcWind
    gdlarguments="'$ipathobs$prevmonth.dat','$ipathobs$month.dat','$ipathobs$nextmonth.dat','$ipathgcm$prevmonth.dat','$ipathgcm$month.dat','$ipathgcm$nextmonth.dat','$opath$month.dat',$ysreference,$yereference,$((10#$month - 1)),NUMLANDPOINTS,land"
    ncpus=3;;
  psl|tas)
    gdlprocedure=get_coef_psl_tas
    gdlarguments="'$ipathobs$month.dat','$ipathgcm$month.dat','$opath$month.dat',$ysreference,$yereference,$((10#$month - 1)),NUMLANDPOINTS"
    ncpus=2;;
  tasmax|tasmin)
    gdlprocedure=get_coef_tasmax_tasmin
    gdlarguments="'$ipathobs$month.dat','$ipathobstas$month.dat','$ipathgcm$month.dat','$ipathgcmtas$month.dat','$opath$month.dat',$minormax,NUMLANDPOINTS"
    ncpus=3;;
  *)
    echo bias correction method $bcmethod not supported !!! exiting ... $(date)
    exit;;
  esac  # bcmethod
  cat > $spath << EOF
#!/bin/bash

#SBATCH --workdir=$sdir
#SBATCH --qos=short
#SBATCH --partition=standard
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=$ncpus
#SBATCH --job-name=bc1p5g$month
#SBATCH --account=isimip
##SBATCH --mail-user=slange@pik-potsdam.de
##SBATCH --mail-type=ALL,TIME_LIMIT
#SBATCH --output=$sbatchedlogs/$sfile.%j
#SBATCH --error=$sbatchedlogs/$sfile.%j

echo ... calculating coefficients for month $month ...

# PFU using idl instead of GDL
# Also don't run curvefit.pro script as it is already included in idl library
idl <<GDLEOF
ipathBCmask = '$ipathBCmask'
.r $sdir/gdl/readBCmask.pro
.r $sdir/gdl/isleap.pro
.r $sdir/gdl/transferfunction.pro
.r $sdir/gdl/$gdlprocedure.pro
$gdlprocedure,$gdlarguments
exit

GDLEOF

EOF
  if [ $lmonsb -eq 1 ]
  then
    sbatchstdouterr=error
    while [[ $sbatchstdouterr = *error* ]]
    do
      sbatchstdouterr=$(sbatch $spath 2>&1)
      sbatchdate=$(date)
      sleep 2
    done  # sbatchstdouterr
    echo $sbatchstdouterr $sbatchdate
    echo $sbatchstdouterr | cut -d ' ' -f 4 >> $sbatchedlist
  else
    /bin/bash $spath
    rm $spath
  fi  # lmonsb
done  # month
