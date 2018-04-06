# ISIMIP2b Bias-Correction Code



## General Notes
This is the code base used for the bias correction of GCM data in ISIMIP2b. It is based on the bias correction code developed in the ISIMIP fast track, see
https://github.com/ISI-MIP/BC

For a comprehensive description of the methods and datasets used for bias correction in ISIMIP2b see Frieler et al. (2017; http://dx.doi.org/10.5194/gmd-10-4321-2017) and Lange (2017; https://doi.org/10.5194/esd-2017-81)

The following variables (short name in brackets) can be bias-corrected with this code
- Near-Surface Relative Humidity             (hurs)
- Near-Surface Specific Humidity             (huss)
- Precipitation                              (pr)
- Snowfall Flux                              (prsn)
- Surface Air Pressure                       (ps)
- Sea Level Pressure                         (psl)
- Surface Downwelling Longwave Radiation     (rlds)
- Surface Downwelling Shortwave Radiation    (rsds)
- Near-Surface Wind Speed                    (sfcWind)
- Near-Surface Air Temperature               (tas)
- Daily Maximum Near-Surface Air Temperature (tasmax)
- Daily Minimum Near-Surface Air Temperature (tasmin)



## Bias-Correction Workflow
In ISIMIP2b, the bias correction of GCM data was done in four steps, which are reflected by the different scripts which can be found in the root directory of this repository
1. Use `interpolate.2obsdatagrid.2prolepticgregoriancalendar.sh` to interpolate raw GCM data in time and space to the proleptic gregorian calendar and to the grid of the observational reference dataset used for bias correction
2. Use `get.coef.sh` to compute bias correction coefficients using simulated and observed data from the reference period
3. Use `app.coef.sh` to apply these coefficients for a bias correction of interpolated GCM data from any period
4. Use `check.time.lat.lon.inf.nan.miss.neg.gto.sh` to check output files for improper time, latitude or longitude axes, infs, nans, missing or out-of-range values

In addition, there is the script `exports.settings.functions.sh` which can be used to customize all data directory paths. All five scripts are described in more detail in the following

### 0. `exports.settings.functions.sh`
- This script contains various functions used by the other bash scripts
- It can be used to modify some bias-correction parameter values
- Most importantly, it can be used to set the following data directory paths
- `idirGCMsource` for the raw GCM data to be interpolated in time and space
- `idirGCMdata` for the interpolated GCM data to be bias-corrected
  - has to contain one subdirectory per GCM containing one file per variable and decade; ISIMIP2b path example: `$idirGCMdata/IPSL-CM5A-LR/hurs_day_IPSL-CM5A-LR_rcp26_r1i1p1_20110101-20201231.nc4`
  - please note that the input files have to use the proleptic gregorian calendar and have to have the same horizontal resolution as the observational data
- `idirOBSdata` for the observational data used to compute all bias correction coefficients
  - has to contain one subdirectory per observational dataset containing one file per variable covering the entire reference period; ISIMIP2b path example: `$idirOBSdata/EWEMBI/hurs_day_EWEMBI_19790101-20131231.nc4`
  - for each observational dataset there has to be a NetCDF file which defines the set of grid cells where data shall be bias-corrected (`BCmask = 1`) and where not (`BCmask = 0`); this NetCDF file has to contain the dimensions `lat`, `lon` and the variables `lat(lat)`, `lon(lon)`, `BCmask(lat,lon)`; ISIMIP2b path example: `$idirOBSdata/EWEMBI/EWEMBI.BCmask.nc4`
  - please note that the reference period can only contain whole years worth of data and that at least one of those years needs to be a leap year in the proleptic gregorian calendar
- `odirGCMdata` for the bias-corrected GCM data
  - the bias correction scripts will create one subdirectory per GCM containing one subdirectory per observational dataset to store one output file per input file; ISIMIP2b path example: `$odirGCMdata/IPSL-CM5A-LR/EWEMBI/hurs_day_IPSL-CM5A-LR_rcp26_r1i1p1_EWEMBI_20110101-20201231.nc4`
- `tdir` for temporary output
  - please mind that some temporary output is not removed automatically

### 1. `interpolate.2obsdatagrid.2prolepticgregoriancalendar.sh`
- This script can be used to pre-process raw GCM data from `idirGCMsource` to `idirGCMdata` and has the input parameters
  ```
  $1 ... observational dataset (e.g., EWEMBI)
  $2 ... variable (hurs, huss, pr, prsn, psl, rlds, rsds, sfcWind, tas, tasmax, tasmin)
  $3 ... GCM (GFDL-ESM2M, HadGEM2-ES, IPSL-CM5A-LR, MIROC5)
  $4 ... CMIP5 experiment (piControl historical rcp26 rcp60)
  $5 ... period (e.g., 2011-2020)
  ```
- Please note that running this script requires a file describing the grid of the observational data, which can be obtained using `cdo griddes`; ISIMIP2b command example: `cdo griddes $idirOBSdata/EWEMBI/EWEMBI.BCmask.nc4 > $idirOBSdata/EWEMBI/EWEMBI.griddes`

### 2. `get.coef.sh`
- This script can be used to compute bias correction coefficients using simulated and observed data from the reference period
- In order to obtain these coefficients for a particular observational dataset-variable-GCM combination, the script first needs to be run with the input parameters
  ```
  $1 ... observational dataset (e.g., EWEMBI)
  $2 ... reference period (e.g., 1979-2013)
  $3 ... variable (hurs, pr, psl, rlds, rsds, sfcWind, tas, tasmax, tasmin)
  $4 ... bias-correction method (hurs, pr, psl, rlds, rsds, sfcWind, tas, tasmax, tasmin)
  ```
  and then again with
  ```
  $1 ... observational dataset (e.g., EWEMBI)
  $2 ... reference period (e.g., 1979-2013)
  $3 ... variable (hurs, pr, psl, rlds, rsds, sfcWind, tas, tasmax, tasmin)
  $4 ... bias-correction method (hurs, pr, psl, rlds, rsds, sfcWind, tas, tasmax, tasmin)
  $5 ... GCM (GFDL-ESM2M, HadGEM2-ES, IPSL-CM5A-LR, MIROC5)
  ```
- Please note that
  - bias correction coefficients for tasmax and tasmin can only be computed after those for tas have been computed
  - `python/get_TOA_daily_mean_insolation_climatology.py` has to be run once before rsds bias correction coefficients can be computed; ISIMIP2b usage example: `python get_TOA_daily_mean_insolation_climatology.py -d 0.5`
  - the shell variable `lmonsb` determines if calculations that may be carried out in parallel for different calendar months are actually carried out in parallel (via SLURM batch job submissions; `lmonsb = 1`) or sequentially (within the running instance of the script; `lmonsb = 0`); currently, the value of `lmonsb` is set depending on the observational dataset; this also holds for `app.coef.sh`, see below
  - any bias correction of a variable using a method that was not developed for that variable is strongly discouraged; in the current code version this is prohibited with the exception of tasmax and tasmin which may be bias-corrected with the method developed for tas; this also holds for `app.coef.sh`, see below

### 3. `app.coef.sh`
- Once you have computed bias correction coefficients for a specific variable-GCM combination you can use this script to bias-correct corresponding GCM data from any time period
- The script has the input parameters
  ```
  $1 ... observational dataset (e.g., EWEMBI)
  $2 ... reference period (e.g., 1979-2013)
  $3 ... variable (hurs, huss, pr, prsn, ps, psl, rlds, rsds, sfcWind, tas, tasmax, tasmin)
  $4 ... bias-correction method (hurs, huss, pr, prsn, ps, psl, rlds, rsds, sfcWind, tas, tasmax, tasmin)
  $5 ... GCM (GFDL-ESM2M, HadGEM2-ES, IPSL-CM5A-LR, MIROC5)
  $6 ... CMIP5 experiment (piControl historical rcp26 rcp60)
  $7 ... application period (e.g., 2011-2020)
  ```
- Please note that the bias correction of
  - tasmax and tasmin requires bias-corrected tas data
  - huss requires bias-corrected hurs, ps and tas data
  - prsn requires bias-corrected pr data
  - ps requires bias-corrected psl and surface elevation data; the latter need to be consistent with the observational data, stored in the `$idirOBSdata` directory, have the variable name `orog` and the unit `meters above sea level`; ISIMIP2b path example: `$idirOBSdata/EWEMBI/orog_EWEMBI.nc4`

### 4. `check.time.lat.lon.inf.nan.miss.neg.gto.sh`
- This script checks the files in `odirGCMdata` for improper time, latitude and longitude axes, infs, nans, missing values, hurs values outside [0%, 100%] and negative huss, pr, prsn, ps, psl, rlds, rsds, sfcWind, tas, tasmax or tasmin values
- Look through the output of this script to see if all quality checks have been passed
- The script is a wrapper for `python/check.time.lat.lon.inf.nan.miss.neg.gto.py` and has the input parameters
  ```
  $1 ... observational dataset (e.g., EWEMBI)
  $2 ... variable (hurs, huss, pr, prsn, ps, psl, rlds, rsds, sfcWind, tas, tasmax, tasmin)
  $3 ... GCM (GFDL-ESM2M, HadGEM2-ES, IPSL-CM5A-LR, MIROC5)
  $4 ... CMIP5 experiment (piControl historical rcp26 rcp60)
  $5 ... application period (e.g., 2011-2020)
  ```



## Software Requirements
The code was written for a Linux environment with computing jobs managed by the workload manager Slurm. All shell scripts are to be interpreted by Bash. CDO and ncatted from NCO are frequently used for data pre- and post-processing. The actual bias correction is done by Python and GDL routines. The following software versions were used on the PIK high-performance cluster to prepare the ISIMIP2b climate input data.

### SLURM 15.08.4
- http://slurm.schedmd.com/

### NCO 4.5.0
- http://nco.sourceforge.net/
- only needed for ncatted

### CDO 1.7.0
- https://code.zmaw.de/projects/cdo/
- with support of compressed NetCDF4 file format

### Python 2.7.11
- https://www.python.org/
- required packages: numpy, scipy, netCDF4, calendar, optparse, os

### GDL 0.9.7
- http://sourceforge.net/projects/gnudatalanguage/
- compile from source with the following cmake options
```
-DUDUNITS=ON
-DWXWIDGETS=OFF
-DMAGICK=OFF
-DGRAPHICSMAGICK=OFF
-DEIGEN3=OFF
-DPSLIB=OFF
-DOLDPLPLOT=OFF
```
- required package: cmsvlib
- additionally required is the IDL routine `curvefit.pro`
