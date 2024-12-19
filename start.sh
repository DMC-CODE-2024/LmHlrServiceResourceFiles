#!/bin/bash

. ~/.bash_profile

module_name="lm_hlr"
main_module="list_management" #keep it empty "" if there is no main module 
log_level="INFO" # INFO, DEBUG, ERROR

########### DO NOT CHANGE ANY CODE OR TEXT AFTER THIS LINE #########

## Start for cellcard operator ##
  ./start.sh CC

## Start for smart operator ##
  ./start.sh SM

## Start for seatel operator ##
  ./start.sh ST

## Start for metfone operator ##
  ./start.sh VT

