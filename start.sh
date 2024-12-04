#!/bin/bash
set -x
module_name="lm_hlr"
main_module="list_management" #keep it empty "" if there is no main module 
log_level="INFO" # INFO, DEBUG, ERROR

########### DO NOT CHANGE ANY CODE OR TEXT AFTER THIS LINE #########

. ~/.bash_profile

 if [ "${main_module}" == "" ]
  then
     build_path="${APP_HOME}/${module_name}_module"
     log_path="${LOG_HOME}/${module_name}_module"
  else
     if [ "${main_module}" == "utility" ] || [ "${main_module}" == "api_service" ] || [ "${main_module}" == "gui" ]
     then
       build_path="${APP_HOME}/${main_module}/${module_name}"
       log_path="${LOG_HOME}/${main_module}/${module_name}"
     else
       build_path="${APP_HOME}/${main_module}_module/${module_name}"
       log_path="${LOG_HOME}/${main_module}_module/${module_name}"
     fi
  fi

cd ${build_path}/script

  echo "Starting process module for all operator....."


## Start for cellcard operator ##
  ./start.sh CC

## Start for smart operator ##
  ./start.sh SM

## Start for seatel operator ##
  ./start.sh ST

## Start for metfone operator ##
  ./start.sh VT

