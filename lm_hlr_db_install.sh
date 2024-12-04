#!/bin/bash
. ~/.bash_profile

source ${commonConfigurationFile} 2>/dev/null

set -x
dbPassword=$(java -jar  ${pass_dypt} spring.datasource.password)

conn="mysql -h${dbIp} -P${dbPort} -u${dbUsername} -p${dbPassword} ${appdbName}"

`${conn} <<EOFMYSQL

insert IGNORE into cfg_feature_alert (alert_id, description, feature) values ('alert5201', 'The HLR file not found at the path <e> for operator <process_name>.', 'HLR_Full_Dump');

insert IGNORE into cfg_feature_alert (alert_id, description, feature) values ('alert5202', 'The java process failed with an exception for operator <e>.', 'HLR_Full_Dump');

insert IGNORE into cfg_feature_alert (alert_id, description, feature) values ('alert5203', 'The percentage of difference of records is greater than threshold <e> for operator <process_name>.', 'HLR_Full_Dump');

insert IGNORE into cfg_feature_alert (alert_id, description, feature) values ('alert5204', 'IMSI does not exist in the file <e> for operator <process_name>.', 'HLR_Full_Dump');

insert IGNORE into cfg_feature_alert (alert_id, description, feature) values ('alert5205', 'MSISDN does not exist in the file <e> for operator <process_name>.', 'HLR_Full_Dump');

insert IGNORE into cfg_feature_alert (alert_id, description, feature) values ('alert5206', 'Activation Date does not exist in the file <e> for operator <process_name>.', 'HLR_Full_Dump');

insert IGNORE into cfg_feature_alert (alert_id, description, feature) values ('alert5207', 'IMSI values does not matches the prefix configured in the file <e> for operator <process_name>.', 'HLR_Full_Dump');

insert IGNORE into cfg_feature_alert (alert_id, description, feature) values ('alert5208', 'MSISDN values does not matches the prefix configured in the file <e> for operator <process_name>.', 'HLR_Full_Dump');

insert IGNORE into cfg_feature_alert (alert_id, description, feature) values ('alert5209', 'The values for <e> are duplicate for operator <process_name>.','HLR_Full_Dump');

insert IGNORE into cfg_feature_alert (alert_id, description, feature) values ('alert5210', 'Null/Non-Numeric values exist in the file <e> for operator <process_name>.', 'HLR_Full_Dump');

insert IGNORE into cfg_feature_alert (alert_id, description, feature) values ('alert5211', 'The java process did not complete successfully for file <e> for operator <process_name>.', 'HLR_Dump_Process');

insert IGNORE into cfg_feature_alert (alert_id, description, feature) values ('alert5212', 'The path <e> does not exists on the server for operator <process_name>.', 'HLR_Full_Dump');

insert IGNORE into cfg_feature_alert (alert_id, description, feature) values ('alert5213', 'The value for retry count <e> is not an integer for operator <process_name>.', 'HLR_Full_Dump');

insert IGNORE into cfg_feature_alert (alert_id, description, feature) values ('alert5214', 'The value for batch count <e> is not an integer for operator <process_name>.', 'HLR_Full_Dump');

insert IGNORE into cfg_feature_alert (alert_id, description, feature) values ('alert 5215', 'The diff file processing for file <e> has some failed sql queries for operator <process_name>.', 'HLR_Full_Dump');



insert IGNORE into cfg_feature_alert (alert_id, description, feature) values (  "alert5001", "The values for either IMSI Prefix or MSISDN prefix is missing in database.", "Sim_Change_Dump" );

insert IGNORE into sys_param (description, tag, value, feature_name) values (  'The date on which the HLR Full Dump process should run for Smart.', 'nextProcessingDayHLR_SM', '', 'List Management' );

insert IGNORE into sys_param (description, tag, value, feature_name) values (  'The date on which the HLR Full Dump process should run for Metfone.', 'nextProcessingDayHLR_VT', '', 'List Management' );

insert IGNORE into sys_param (description, tag, value, feature_name) values (  'The date on which the HLR Full Dump process should run for Cellcard.', 'nextProcessingDayHLR_CC', '', 'List Management');

insert IGNORE into sys_param (description, tag, value, feature_name) values (  'The date on which the HLR Full Dump process should run for Seatel.', 'nextProcessingDayHLR_ST', '', 'List Management' );

insert IGNORE into sys_param (description, tag, value, feature_name) values (  'The msisdn prefixes used to validate the dump files received from operators. The values can be comma-separated in case of multiple prefixes.', 'msisdnPrefix', '855', 'List Management' );

insert IGNORE into sys_param (description, tag, value, feature_name) values ( 'The imsi prefixes used to validate the dump files received from operators. The values can be comma-separated in case of multiple prefixes.', 'imsiPrefix', '456', 'List Management' );

EOFMYSQL`

echo "********************Thank You DB Process is completed now*****************"

