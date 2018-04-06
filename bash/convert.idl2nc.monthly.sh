#!/bin/bash



# process input parameters
ipath=$1  # without month.suffix
opath=$2  # without suffix



# set number of cpus per task (this only takes effect if lmonsb == 1)
[[ $exp = $expreference ]] && ncpus=2 || ncpus=1



# convert each monthly IDL binary file to a NetCDF file
cdopipe=
for month in $(seq -w 1 12)
do
  sfile=convert.idl2nc.monthly.$month
  spath=$tdir/subscripts/$sfile.$SLURM_JOB_ID
  cat > $spath << EOF
#!/bin/bash

#SBATCH --workdir=$sdir
#SBATCH --qos=short
#SBATCH --partition=standard
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=$ncpus
#SBATCH --job-name=bc1p5i$month
#SBATCH --account=isimip
##SBATCH --mail-user=slange@pik-potsdam.de
##SBATCH --mail-type=ALL,TIME_LIMIT
#SBATCH --output=$sbatchedlogs/$sfile.%j
#SBATCH --error=$sbatchedlogs/$sfile.%j

echo ... converting data for month $month ...

gdl <<GDLEOF
ipathBCmask = '$ipathBCmask'
.r $sdir/gdl/readBCmask.pro
.r $sdir/gdl/isleap.pro
.r $sdir/gdl/idl2nc.pro
idl2nc,'$ipath$month.dat','$ipath$month.$ncs','$var',$ysp,$yep,$((10#$month - 1)),nlat,nlon,lat0,lon0,dlat,dlon,NUMLANDPOINTS,landlat,landlon,$missval
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
  cdopipe="$cdopipe -setreftime,$yse-01-01,00:00:00,day $ipath$month.$ncs"
done  # month



# wait for monthly batch jobs to finish
if [ $lmonsb -eq 1 ]
then
  wait_for_batch_jobs_to_finish $sbatchedlist
  rm $sbatchedlist $tdir/subscripts/*.$SLURM_JOB_ID
fi



# check monthly NetCDF file existence
for month in $(seq -w 1 12); do exit_if_nt $ipath$month.dat $ipath$month.$ncs; done



# merge monthly NetCDF files
echo ... merging monthly NetCDF files into $opath.$ncs ...
$cdo -O -r mergetime $cdopipe $opath.$ncs
echo ... done ...
rm $ipath??.$ncs
