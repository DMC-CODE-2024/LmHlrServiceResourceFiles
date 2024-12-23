#!/bin/bash

source ~/.bash_profile

log_level="INFO"
module_name="lm_hlr"
main_name="list_management_module"
log_path="${LOG_HOME}/${main_name}/${module_name}/"

########### DO NOT CHANGE ANY CODE OR TEXT AFTER THIS LINE #########

echo "Starting process module for all operator....."

cd ./script/
## Start for cellcard operator ##
   mkdir -p  ${log_path}/cellcard
   ./script.sh cc 1>/dev/null 2>${log_path}/cellcard/${module_name}.error &

## Start for smart operator ##
   mkdir -p  ${log_path}/smart
  ./script.sh sm 1>/dev/null 2>${log_path}/smart/${module_name}.error &

## Start for seatel operator ##
    mkdir -p  ${log_path}/seatel
   ./script.sh st 1>/dev/null 2>${log_path}/seatel/${module_name}.error &

## Start for metfone operator ##
   mkdir -p  ${log_path}/metfone
  ./script.sh vt 1>/dev/null 2>${log_path}/metfone/${module_name}.error &



