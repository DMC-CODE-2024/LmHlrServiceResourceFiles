#!/bin/bash
#set -x


tar -xzvf lm_hlr_1.0.0.tar.gz >>lm_hlr_1.0.0_untar_log.txt
mkdir -p ${APP_HOME}/list_management_module/lm_hlr/

#list_management_module/lm_hlr
mv lm_hlr_1.0.0/lm_hlr_1.0.0.jar ${RELEASE_HOME}/binary/

mv lm_hlr_1.0.0/*  ${APP_HOME}/list_management_module/lm_hlr/

cd ${APP_HOME}/list_management_module/lm_hlr/

ln -sf ${RELEASE_HOME}/binary/lm_hlr_1.0.0.jar lm_hlr.jar
ln -sf ${RELEASE_HOME}/global_config/log4j2.xml log4j2.xml
chmod +x *.sh

# u02 folder create 
mkdir -p ${DATA_HOME}/cdr_input/cellcard/cc_hlr
mkdir -p ${DATA_HOME}/cdr_input/metfone/mf_hlr
mkdir -p ${DATA_HOME}/cdr_input/smart/sm_hlr
mkdir -p ${DATA_HOME}/cdr_input/seatel/st_hlr

mkdir -p ${DATA_HOME}/eirsdata/hlr/st/processed/
mkdir -p ${DATA_HOME}/eirsdata/hlr/sm/processed/
mkdir -p ${DATA_HOME}/eirsdata/hlr/cc/processed/
mkdir -p ${DATA_HOME}/eirsdata/hlr/vt/processed/

mkdir -p ${DATA_HOME}/eirsdata/hlr/st/delta/
mkdir -p ${DATA_HOME}/eirsdata/hlr/sm/delta/
mkdir -p ${DATA_HOME}/eirsdata/hlr/cc/delta/
mkdir -p ${DATA_HOME}/eirsdata/hlr/vt/delta/

#uo3 Folder create 
mkdir -p ${LOG_HOME}/list_management_module/lm_hlr/

