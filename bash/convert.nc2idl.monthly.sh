#!/bin/bash



# process input parameters
idir=$1
odir=$2
ifile=$3  # without suffix
ofile=$4  # without suffix
ncpus=$5



# split multi-year ifile into months
echo ... splitting $idir/$ifile.$ncs into months ...
mfile=${ifile}_
cdo -f nc splitmon $idir/$ifile.$ncs $odir/$mfile
for month in $(seq -w 1 12); do exit_if_nt $idir/$ifile.$ncs $odir/$mfile$month.$ncs; done
echo ... done ...



# convert each monthly NetCDF file to an IDL binary file
for month in $(seq -w 1 12)
do
  sfile=convert.nc2idl.monthly.$month
  spath=$tdir/subscripts/$sfile.$SLURM_JOB_ID
  cat > $spath << EOF
#!/bin/bash

#SBATCH --workdir=$sdir
#SBATCH --qos=short
#SBATCH --partition=standard
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=$ncpus
#SBATCH --job-name=bc1p5n$month
#SBATCH --account=isimip
##SBATCH --mail-user=slange@pik-potsdam.de
##SBATCH --mail-type=ALL,TIME_LIMIT
#SBATCH --output=$sbatchedlogs/$sfile.%j
#SBATCH --error=$sbatchedlogs/$sfile.%j

echo ... converting data for month $month ...

# PFU using idl instead of gdl
idl <<GDLEOF
ipathBCmask = '$ipathBCmask'
.r $sdir/gdl/readBCmask.pro
.r $sdir/gdl/nc2idl.pro
nc2idl,'$odir/$mfile$month.$ncs','$odir/$ofile$month.dat','$var',NUMLANDPOINTS,land
exit

GDLEOF
rm $odir/$mfile$month.$ncs

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
