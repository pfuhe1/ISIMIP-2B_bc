#!/bin/bash



# process input parameters
ipathdata=$1  # without month.suffix
ipathtasu=$2  # without month.suffix (only for tasmax and tasmin)
ipathtasc=$3  # without month.suffix (only for tasmax and tasmin)
ipathcoef=$4  # without month.suffix
opath=$5  # without month.suffix


# check input file existence (only for tasmax and tasmin)
case $bcmethod in
tasmax|tasmin)
  for month in $(seq -w 1 12)
  do
    exit_if_any_does_not_exist $ipathtasu$month.dat
    exit_if_any_does_not_exist $ipathtasc$month.dat
  done  # month
  case $bcmethod in
  tasmax)
    minormax=1.
    minmaxval=$dailymax;;
  *)
    minormax=-1.
    minmaxval=$dailymin;;
  esac  # bcmethod
  ;;
esac  # bcmethod


# set number of cpus per task (this only takes effect if lmonsb == 1)
[[ $exp = $expreference ]] && ncpus=4 || ncpus=1


# apply transfer function coefficients for each month
for month in $(seq -w 1 12)
do
  sfile=app.coef.monthly.$month
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
    gdlprocedure=app_coef_hurs
    gdlarguments="'$ipathdata$prevmonth.dat','$ipathdata$month.dat','$ipathdata$nextmonth.dat','$ipathcoef$prevmonth.dat','$ipathcoef$month.dat','$ipathcoef$nextmonth.dat','$opath$month.dat',$ysp,$yep,$((10#$month - 1)),NUMLANDPOINTS";;
  pr)
    gdlprocedure=app_coef_pr
    gdlarguments="'$ipathdata$month.dat','$ipathcoef$month.dat','$opath$month.dat',$ysp,$yep,$((10#$month - 1)),NUMLANDPOINTS,$correctionfactormaxnonneg,$dailymax,$idlfactor";;
  rlds|sfcWind)
    gdlprocedure=app_coef_rlds_sfcWind
    gdlarguments="'$ipathdata$prevmonth.dat','$ipathdata$month.dat','$ipathdata$nextmonth.dat','$ipathcoef$month.dat','$opath$month.dat',$ysp,$yep,$((10#$month - 1)),NUMLANDPOINTS,$correctionfactormaxnonneg,$dailymax";;
  psl|tas)
    gdlprocedure=app_coef_psl_tas
    gdlarguments="'$ipathdata$month.dat','$ipathcoef$prevmonth.dat','$ipathcoef$month.dat','$ipathcoef$nextmonth.dat','$opath$month.dat',$ysp,$yep,$((10#$month - 1)),$dailymin,$dailymax,NUMLANDPOINTS";;
  tasmax|tasmin)
    gdlprocedure=app_coef_tasmax_tasmin
    gdlarguments="'$ipathdata$month.dat','$ipathtasu$month.dat','$ipathtasc$month.dat','$ipathcoef$prevmonth.dat','$ipathcoef$month.dat','$ipathcoef$nextmonth.dat','$opath$month.dat',$ysp,$yep,$((10#$month - 1)),$minormax,$correctionfactormaxtasminmax,$minmaxval,NUMLANDPOINTS";;
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
#SBATCH --job-name=bc1p5a$month
#SBATCH --account=isimip
##SBATCH --mail-user=slange@pik-potsdam.de
##SBATCH --mail-type=ALL,TIME_LIMIT
#SBATCH --output=$sbatchedlogs/$sfile.%j
#SBATCH --error=$sbatchedlogs/$sfile.%j

echo ... applying coefficients for month $month ...

# PFU using idl instead of gdl
idl <<GDLEOF
ipathBCmask = '$ipathBCmask'
.r $sdir/gdl/readBCmask.pro
.r $sdir/gdl/isleap.pro
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
