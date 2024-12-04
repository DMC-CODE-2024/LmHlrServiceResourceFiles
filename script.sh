#!/bin/bash

  # utility functions
set -x

  # function to log messages
  log_message() {
    # Get the current date and timestamp
    datetime=$(date +"%Y-%m-%d %H:%M:%S.%3N")
    # Get the line number of the caller
    lineno=$(caller | awk '{print $1}')
    # Print the log message with date, timestamp, and line number
    echo "$datetime [Line $lineno] $1"
  }

function fileCopy() {
      sourceFileName=$1
      sourceFilePath=$2
      count=$3
      IFS=',' read -ra destPaths <<< "$destinationPath"
      IFS=',' read -ra destServers <<< "$destinationServer"

      # Construct the JSON body string with dynamic array of destinations
      jsonBody=$(cat <<EOF
      {
        "appName": "HLR Full Dump",
        "destination": [
EOF
      )

      # Iterate over each destination path and server name
      for ((i=0; i<${#destPaths[@]}; i++)); do
        # Construct the destination object
        destination="{\"destFilePath\": \"${destPaths[$i]}\", \"destServerName\": \"${destServers[$i]}\"}"
        # Add the destination object to the JSON body string
        jsonBody+="    $destination"
        if [ $i -lt $((${#destPaths[@]} - 1)) ]; then
          jsonBody+=","
        fi
        jsonBody+=$'\n' # Add newline for readability
      done

      # Complete the JSON body string
      jsonBody+="  ],
        \"remarks\": \"\",
        \"serverName\": \"$serverName\",
        \"sourceFileName\": \"$sourceFileName\",
        \"sourceFilePath\": \"$sourceFilePath\",
        \"sourceServerName\": \"$sourceServerName\",
        \"txnId\": \"\"
      }"

      # Send the request with curl

      response=$(curl -X POST \
        "$fileCopyApi" \
        -H 'Content-Type: application/json' \
        -d "$jsonBody" \
        2>/dev/null)

      message=$(echo "$response" | jq -r '.message')

      # Check if the message is "Success"
      if [ "$message" = "Success" ]; then
        log_message "The file copy request was successful"
      else
        log_message "The file copy request failed. Error message: $message"
        log_message "Making an entry in list_file_mgmt table"
        for ((i=0; i<${#destPaths[@]}; i++)); do
          # Construct the destination object
          mysql -h$dbIp -P$dbPort $appdbName -u$dbUsername -p${dbPassword} << EOFMYSQL
              insert into list_file_mgmt (created_on, modified_on, file_name, file_path, source_server, list_type, operator_name, file_type, file_state,
	      record_count, copy_status, destination_path, destination_server) values (NOW(), NOW(), "$sourceFileName", "$sourceFilePath",
              "$serverName", "OTHERS","ALL","1", 1, "$count", 0, "${destPaths[$i]}", "${destServers[$i]}");
EOFMYSQL
        done

      fi
    }

  # function to raise alert

  function generateAlert() {
    id=$1
    echo "Raising alert for alert id $id"
    curlOutput=$(curl -s ""$curlUrl"/"$id"")
    if [ $? -ne 0 ]; then
      log_message "Error: Alert not raised due to some error."
    else
      log_message "Alert was raised successfully."
    fi
  }

  function generateAlertUsingUrl() {
    alertId=$1
    alertMessage=$2
    alertProcess=$3
    alertUrl=$4
    curlOutput=$(curl --header "Content-Type: application/json"   --request POST   --data '{"alertId":"'$alertId'",
    "alertMessage":"'"$alertMessage"'", "userId": "0", "alertProcess": "'"$alertProcess"'"}' "$alertUrl")
    echo $curlOutput
  }


  # function to update entry in modules audit trail
  function updateAuditEntry() {
    errMsg=$1
    executionStartTime=$2
    moduleName=$3
    featureName=$4
    echo $errMsg $executionStartTime $moduleName $featureName
  #  echo $executionStartTime
    executionFinishTime=$(date +%s.%N);
    executionTime=$(echo "$executionFinishTime - $executionStartTime" | bc)
    secondDivision=1000
    finalExecutionTime=`echo "$executionTime * $secondDivision" | bc`
  #  echo $finalExecutionTime
#    echo $dbIp $dbPort $dbUsername $dbPassword $auddbName
    mysqlOutput=$(mysql -h$dbIp -P$dbPort -u$dbUsername -p${dbPassword} $auddbName -se "update modules_audit_trail set status_code='501',status='FAIL',error_message='$errMsg',execution_time='$finalExecutionTime',modified_on=CURRENT_TIMESTAMP where module_name='$moduleName' and feature_name='$featureName' order by id desc limit 1")
    log_message "Updating the modules_audit_trail entry for error $errMsg"
  }

  # function to execute any mysql query


  # function that validates the configuration values

  function validatePath() {
    path=$1
    echo $path
    alertId=$2
    featureName=$3
    moduleName=$4
    if [ ! -e "$path" ] || [ ! -d "$path" ]; then
      log_message "$path not exists. Terminating the process."
      updateAuditEntry 'The path '$path' does not exists on the server.' $executionStartTime $moduleName $featureName
      generateAlertUsingUrl $alertId $path $operator $alertUrl
      exit 3;
    fi
  }

  # function to check if file size is still increasing (using sleep method)

  function checkFileUploadComplete() {
      fullFileName=$1
      initialFileSize=$(wc -c <"$fullFileName")
      sleep $initialTimer
      currentFileSize=$(wc -c <"$fullFileName")
      log_message
      while [ $currentFileSize -ne $initialFileSize ]
      do
        log_message "File $fullFileName is still uploading. Will check again in next $finalTimer seconds."
        initialFileSize=$currentFileSize
        sleep $finalTimer
      done
      log_message "File "$fullFileName" uploading completed. Now will process the file for further steps."
      return 1;
    }

  function getHeaderColumnNumber() {
    fullFileName=$1
    headers=$2
    columnName=$3
    fileSeparator=$4
    columnNumber=$(echo "$headers" | awk -v target="$columnName" -v fileSeparator="${fileSeparator}" 'BEGIN {IGNORECASE=1; FS=fileSeparator} {
      for(i = 1; i<= NF; i++) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i);
        if(tolower($i) == tolower(target)) {
          print i
          exit
        }
      }
    }')
    echo "$columnNumber"
  }

  function checkPrefixInFile() {
    dbValues=$1
    fullFileName=$2
    columnNumber=$3
    fileSeparator=$4
    error_found=0
    echo "$fullFileName $dbValues $fileSeparator $columnNumber"
    IFS=',' read -ra values <<< "$dbValues"
  #  echo "${values[*]}"
  #  # Read the CSV file, extract the second column, and check if it starts with any value from the array
    awk -F $fileSeparator -v columnNumber="${columnNumber}" -v values="${dbValues}" -v fileSeparator="${fileSeparator}" '
    BEGIN {
      # Split the values string into an array
      split(values, lookup, ",")
    }
NR == 1 { next }
    {
        # Extract the second column value
        column_value=$(columnNumber)

        # Flag to track if any matching prefix is found
        found_match = 0

        # Loop through the values array
        for (i in lookup) {
          # Check if the column value starts with any value from the array
#          print "\""column_value"\" \""lookup[i]"\" "
  #        print index(column_value, lookup[i])
          if (index(column_value, lookup[i]) == 1) {
            found_match = 1
#            print "Match found"
            break
          }
        }

        # If no matching prefix is found, print an error
        if (!found_match) {
          print "Error: Value \"" column_value "\" in column " col_number " does not start with any expected prefix"
          error_found = 1
        }
    }
    END {
        # Print status based on error flag
        if (error_found) {
          print "Some values did not match the prefix condition"
          exit 1
        } else {
          print "All values matched the prefix condition"
          exit 0
        }
    }' "$fullFileName"

  }

  function nullValueValidation() {
    fileSeparator=$1
    fullFileName=$2
    imsiColumnNumber=$3
    msisdnColumnNumber=$4
    log_message "$fullFileName $fileSeparator"
    awk -v FS="$fileSeparator" -v imsi="$imsiColumnNumber" -v msisdn="$msisdnColumnNumber" '
    function is_numeric(value) {
      return (value ~ /^[0-9]+$/);
    }

    NR > 1 {
      if (!(is_numeric($imsi) && is_numeric($msisdn))) {
        failed_entries[NR] = $0;
      }
    }

    END {
      failed_entries_size = length(failed_entries)
      #print path
      if (failed_entries_size > 0) {
        # Raise alert
        print "Records found with null or non-numeric."
        exit 1;
      } else {
        print "No records found with null or non-numeric."
        exit 0;
      }
    }' "$fullFileName"
  }



  # starting of the script
  source ~/.bash_profile   2>/dev/null
  . $1
  executionStartTime=$(date +%s.%N)

  commonConfiguration=$commonConfigurationFile

  #source $HLRScriptConfiguration

  if [ ! -e "$commonConfiguration" ]
    then
      log_message "$commonConfiguration file not found ,the script is terminated."
      exit 1;
  fi

  source $commonConfiguration
function get_value() 
{
  key=$1
  grep "^$key=" "$commonConfigurationFile" | cut -d'=' -f2
}

log_level="INFO"
log_path="${LOG_HOME}/list_management_module/hlr/${operator}"
module_name="hlr_${operator}"
echo ""   

alertUrl=$(get_value "eirs.alert.url");

  log_message "The server host name is: $serverName"

  # Reading password from the config file.
  log_message "Retrieving password for database connection."
  dbPassword=$(java -jar ${pass_dypt} spring.datasource.password)

  if [ -z "$dbIp" ] || [ -z "$dbPort" ] || [ -z "$dbUsername" ] || [ -z "$dbPassword" ] ;
    then
      log_message "DB details missing, the script is terminated."
      exit 1;
  fi

  # check to execute script for today or not
  moduleName='HLR_Full_Dump_'$operator''
  featureName='HLR_Full_Dump_Manager'
#  previousStatus=$(mysql -h$dbIp -P$dbPort $auddbName -u$dbUsername  -p${dbPassword} -se "select count(*) from
#  modules_audit_trail where feature_name='$moduleName' order by created_on desc limit 1")

  nextDateTag="nextProcessingDayHLR_$operator"
  log_message "Tag for next day $nextDateTag"
  nextDateToProcess=$(mysql -h$dbIp -P$dbPort $appdbName -u$dbUsername  -p${dbPassword} -se "select value from sys_param where tag='$nextDateTag'")
  log_message "The next day to execute the process: $nextDateToProcess"
  currentDate=$(date +%F)
  log_message "The current date: $currentDate"

  nextDateToProcessTimestamp=$(date -d "$nextDateToProcess" +%s)
  currentDateTimestamp=$(date -d "$currentDate" +%s)
  echo
  if [ -z "$nextDateToProcess" ]; then
    log_message "No previous date found, will continue the process."
  elif [ "$currentDateTimestamp" -lt "$nextDateToProcessTimestamp" ]; then
    log_message "Current date is earlier than the next processing date."
    log_message "Moving all the files, if any to processed folder"
    mv "$inputFilePath"/* "$processedFilePath"
    log_message "Terminating the script."
    exit 1
  else
    log_message "Current date is greater than or equal to the next processing date. The file will be processed."
  fi

  #insert into modules_audit_trail for starting of the process
  mysql -h$dbIp -P$dbPort -u$dbUsername -p${dbPassword} $auddbName <<EOFMYSQL
      insert into modules_audit_trail (status_code,status,error_message,feature_name,server_name,execution_time,module_name)
      values(201,'INITIAL','NA','$featureName','$serverName',0,'$moduleName');
EOFMYSQL

  #previousStatus=$(mysql -h$dbIp -P$dbPort $appdbName -u$dbUsername  -p${dbPassword} -se "select count(*) from ")
  imsiPrefix=$(mysql -h$dbIp -P$dbPort $appdbName -u$dbUsername  -p${dbPassword} -se "select value from sys_param where tag='imsiPrefix'")
  msisdnPrefix=$(mysql -h$dbIp -P$dbPort $appdbName -u$dbUsername  -p${dbPassword} -se "select value from sys_param where tag='msisdnPrefix'")

  if [ -z "$imsiPrefix" ] || [ -z "$msisdnPrefix" ] ;
    then
      log_message "The values for either IMSI Prefix or MSISDN prefix is missing in database."
      updateAuditEntry 'The values for either IMSI Prefix or MSISDN prefix is missing in database.' $executionStartTime $moduleName $featureName
      generateAlertUsingUrl 'alert5001' '' '' $alertUrl
      log_message "Terminating the process."
      exit 3;
  fi

  # call functions to validate the path
  # alerts can be same. Change the parameter for the alert

  validatePath $inputFilePath 'alert5212' $featureName $moduleName
  validatePath $processedFilePath 'alert5212' $featureName $moduleName
  validatePath $deltaFileProcessedPath 'alert5212' $featureName $moduleName
#  validatePath $deltaFilePath 'alert5212' $featureName $moduleName
  validatePath $javaProcessPath 'alert5212' $featureName $moduleName
  validatePath $scriptProcessPath 'alert5212' $featureName $moduleName

  cd $scriptProcessPath
  operatorFilePattern="$filePattern"
  fileCount=$(find "$inputFilePath" -type f -name "*${operatorFilePattern}*" | wc -l)

  if [ "$fileCount" -eq 0 ]; then
      log_message "No files found matching the pattern '$operatorFilePattern'."
      updateAuditEntry 'The HLR file not found at the path '$inputFilePath'.' $executionStartTime $moduleName $featureName
      generateAlertUsingUrl 'alert5201' $inputFilePath $operator $alertUrl
      log_message 'Exiting from the process.'
      exit 2;
  elif [ "$fileCount" -eq 1 ]; then
      log_message "One file found matching the pattern '$operatorFilePattern'."
  else
      log_message "Multiple files with the pattern '$operatorFilePattern' present. Picking the latest file for processing."
  fi

  fileName=$(ls -Art $inputFilePath | grep $operatorFilePattern |tail -n 1)
  log_message 'The latest file is '$fileName''.
  fullFileName="$inputFilePath/$fileName"
  checkFileUploadComplete $fullFileName
  previousProcessedFileName=$(mysql -h$dbIp -P$dbPort $auddbName -u$dbUsername  -p${dbPassword} -se "select info from modules_audit_trail where status_code=200 and feature_name='$featureName' and module_name='$moduleName' order by id desc limit 1")
  #echo $previousProcessedFileName;
  fullPreviousProcessedFileName="$processedFilePath/$previousProcessedFileName"
#  echo $fullPreviousProcessedFileName
  if [ -z "$previousProcessedFileName" ]; then
    log_message "No previous processed file in the system. Taking this file as fresh."
  else
    log_message "Previous file exists. Compare the difference of records from current file and previous file."
    currentFileRecordCount=$(wc -l <"$fullFileName")
    previousFileRecordCount=$(wc -l <"$fullPreviousProcessedFileName")
    log_message "The current file records counts is $currentFileRecordCount and previous file records counts is $previousFileRecordCount"
    differenceRecords=$(expr $currentFileRecordCount - $previousFileRecordCount)
    differenceRecords=${differenceRecords#-}
    log_message "The difference of records is $differenceRecords"
    #percentDifference=$(expr $differenceRecords / $previousFileRecordCount)
    percentDifference=$(($differenceRecords * 100 / $previousFileRecordCount))
#    echo $currentFileRecordCount $previousFileRecordCount $differenceRecords $percentDifference
    log_message "The percentage of difference of records between new file and previous file is $percentDifference".
    if (( $(echo "$percentDifference > $recordDiffPercent" | bc -l) )); then
      log_message 'The percentage of difference of records is greater than threshold '$recordDiffPercent''
      updateAuditEntry 'The percentage of difference of records is greater than threshold '$recordDiffPercent'.' $executionStartTime $moduleName $featureName
      #copyFileToCorruptFolder $baseFileName.txt
      generateAlertUsingUrl 'alert5203' $recordDiffPercent $operator $alertUrl
      exit 2
    fi
  fi

  if [ ! -z "$previousProcessedFileName" ] && [ ! -f "$fullPreviousProcessedFileName" ]; then
  log_message "The previous file "$previousProcessedFileName" does not exists at the path $processedFilePath"
      updateAuditEntry 'The previous processed file '$previousProcessedFileName' is not present on the path '$processedFilePath'.' $executionStartTime $moduleName $featureName
      generateAlertUsingUrl 'alert5316' $fullPreviousProcessedFileName $operator $alertUrl
      exit 1;
  fi

  imsiHeaderValue=$imsiHeader
  msisdnHeaderValue=$msisdnHeader
  activationDateHeaderValue=$activationDateHeader
  headers=$(head -n 1 "$fullFileName" | tr -d '[:space:]')
  log_message "Headers of the file '$fileName' are '$headers'".
  log_message "The file separator is $fileSeparator"

  #getHeaderColumnNumber $fullFileName $headers $imsiHeaderValue $fileSeparator
  imsiColumnNumber=$(getHeaderColumnNumber $fullFileName $headers $imsiHeaderValue $fileSeparator)
  #getHeaderColumnNumber $fullFileName $headers $msisdnHeaderValue $fileSeparator
  msisdnColumnNumber=$(getHeaderColumnNumber $fullFileName $headers $msisdnHeaderValue $fileSeparator)
 # getHeaderColumnNumber $fullFileName $headers $activationDateHeaderValue $fileSeparator
  activationDateColumnNumber=$(getHeaderColumnNumber $fullFileName $headers $activationDateHeaderValue $fileSeparator)

  log_message 'The IMSI column number in the file '$fileName' is '$imsiColumnNumber''
  log_message 'The MSISDN column number in the file '$fileName' is '$msisdnColumnNumber''
  log_message 'The activation date column number in the file '$fileName' is '$activationDateColumnNumber''

  if [ -z "$imsiColumnNumber" ] ;
    then
      log_message "IMSI does not exist in the file '$fileName'."
      updateAuditEntry 'IMSI does not exist in the file '$fileName'.' $executionStartTime $moduleName $featureName
      #copyFileToCorruptFolder $baseFileName.txt
      generateAlertUsingUrl 'alert5204' $fileName $operator $alertUrl
      exit 1;
    else
      log_message "IMSI exists in the file '$fileName'."
  fi

  if [ -z "$msisdnColumnNumber" ] ;
    then
      log_message "MSISDN does not exist in the file '$fileName'."
      updateAuditEntry 'MSISDN does not exist in the file '$fileName'.' $executionStartTime $moduleName $featureName
      #copyFileToCorruptFolder $baseFileName.txt
      generateAlertUsingUrl 'alert5205' $fileName $operator $alertUrl
      exit 1;
    else
      log_message "MSISDN exists in the file '$fileName'."
  fi

  if [ -z "$activationDateColumnNumber" ] ;
    then
      log_message "Activation date does not exist in the file '$fileName'."
      updateAuditEntry 'Activation does not exist in the file '$fileName'.' $executionStartTime $moduleName $featureName
      #copyFileToCorruptFolder $baseFileName.txt
      generateAlertUsingUrl 'alert5206' $fileName $operator $alertUrl
      exit 1;
    else
      log_message "Activation date exists in the file '$fileName'."
  fi

  # check for no alphanumeric and null values. We would skip the first line of the file considering it as header of the
    # file.
  nullValueValidation $fileSeparator $fullFileName $imsiColumnNumber $msisdnColumnNumber
  nullValueValidationOutput=$?
  log_message "Output from null/non-numeric checking of values is $nullValueValidationOutput"
  if [ "$nullValueValidationOutput" -eq 1 ]; then
    log_message "Null/Non-Numeric values exist in the file '$fileName'";
    updateAuditEntry 'Null/Non-Numeric values exist in the file '$fileName'.' $executionStartTime $moduleName $featureName
    generateAlertUsingUrl 'alert5210' $fileName $operator $alertUrl
    exit 2;
  fi

  # checking if the imsi starts with the prefix present in the DB sys_param or not
  checkPrefixInFile $imsiPrefix $fullFileName $imsiColumnNumber $fileSeparator
  imsiPrefixCheckOutput=$?
  log_message "Output from prefix checking of IMSI is $imsiPrefixCheckOutput"
  if [ "$imsiPrefixCheckOutput" -eq 1 ]; then
    log_message "The file contains IMSI that does not starts with $imsiPrefix.";
    updateAuditEntry 'IMSI values does not matches the prefix configured.' $executionStartTime $moduleName $featureName
    generateAlertUsingUrl 'alert5207' $fileName $operator $alertUrl
    exit 2;
  fi
  # checking if the imsi starts with the prefix present in the DB sys_param or not
  checkPrefixInFile $msisdnPrefix $fullFileName $msisdnColumnNumber $fileSeparator
  msisdnPrefixCheckOutput=$?
  log_message "Output from prefix checking of MSISDN is $msisdnPrefixCheckOutput"
  if [ "$msisdnPrefixCheckOutput" -eq 1 ]; then
    log_message "The file contains MSISDN that does not starts with $msisdnPrefix.";
    updateAuditEntry 'MSISDN values does not matches the prefix configured.' $executionStartTime $moduleName $featureName
    generateAlertUsingUrl 'alert5208' $fileName $operator $alertUrl
    exit 2;
  fi

  #checking imsi unique in dump
  numberOfUniqueImsi=$(cut -d "$fileSeparator" -f"$imsiColumnNumber" "$fullFileName" | sort | uniq | wc -l);
  log_message "Number of unique IMSI in the file '$fileName' are $numberOfUniqueImsi"
  currentFileRecordCount=$(wc -l <"$fullFileName")
  if [ "$numberOfUniqueImsi" != "$currentFileRecordCount" ] ;
    then
      log_message "IMSI is duplicate in the file '$fileName'";
      #raise alert
      updateAuditEntry 'IMSI values are duplicate in the file '$fileName'.' $executionStartTime $moduleName $featureName

      #copyFileToCorruptFolder $baseFileName.txt
      generateAlertUsingUrl 'alert5209' 'IMSI in file '$fileName'' $operator $alertUrl
      exit 2
  fi

  #checking msisdn unique in dump
    numberOfUniqueImsi=$(cut -d "$fileSeparator" -f"$msisdnColumnNumber" "$fullFileName" | sort | uniq | wc -l);
    log_message "Number of unique MSISDN in the file '$fileName' are $numberOfUniqueImsi"
    currentFileRecordCount=$(wc -l <"$fullFileName")
    if [ "$numberOfUniqueImsi" != "$currentFileRecordCount" ] ;
      then
        log_message "MSISDN is duplicate in the file '$fileName'";
        #raise alert
        updateAuditEntry 'MSISDN values are duplicate in the file '$fileName'.' $executionStartTime $moduleName $featureName

        #copyFileToCorruptFolder $baseFileName.txt
        generateAlertUsingUrl 'alert5209' 'MSISDN in file '$fileName'' $operator $alertUrl
        exit 2
    fi

  # check pair of imsi and msisdn is unique in the file
  numberOfUniqueImsiMsisdnPair=$(cut -d "$fileSeparator" -f"$imsiColumnNumber,$msisdnColumnNumber" "$fullFileName" | sort | uniq | wc -l);
  log_message "Number of unique IMSI and MSISDN pairs in the file $fileName are $numberOfUniqueImsiMsisdnPair."
  currentFileRecordCount=$(wc -l <"$fullFileName")
  log_message "The total number of records in file $currentFileRecordCount"
  if [ "$numberOfUniqueImsiMsisdnPair" != "$currentFileRecordCount" ] ;
    then
      log_message "Pair of IMSI and MSISDN is duplicate in the file '$fileName'";
      #raise alert
      updateAuditEntry 'Pair of IMSI and MSISDN values are duplicate in the file '$fileName'.' $executionStartTime $moduleName $featureName

      #copyFileToCorruptFolder $baseFileName.txt
      generateAlertUsingUrl 'alert5209' 'pair of MSISDN and IMSI in file '$fileName'' $operator $alertUrl
      exit 2
  fi

  # creating a temp file for further processing. This would only contains IMSI,MSISDN and activation date from the file.
  log_message "Creating temp file with only IMSI, MSISDN and activation date without headers."
  tempFile="$inputFilePath/tempFile.csv"

> $tempFile
t=$(awk -v FS="$fileSeparator" -v var1="$imsiColumnNumber" -v var2="$msisdnColumnNumber" -v var3="$activationDateColumnNumber" -v tempFile="$tempFile" '
    BEGIN {
        #print "File separator: \"" fileSep "\""
        #print "IMSI column number: " var1
        #print "MSISDN column number: " var2
        #print "Activation Date column number: " var3
    }
    NR > 1 {
        #print "Processing line " NR ": " $0
        #print "File separator inside awk: \"" fileSep "\""
        gsub(/^[ \t]+|[ \t]+$/, "", $var1);
        gsub(/^[ \t]+|[ \t]+$/, "", $var2);
        gsub(/^[ \t]+|[ \t]+$/, "", $var3);
        #print "Extracted values: " $var1, $var2, $var3
        if ($var1 != "" && $var2 != "") print $var1 FS $var2 FS $var3 >> tempFile
    }
' "$fullFileName")


 # cat "$tempFile"
  log_message "The temp file created successfully"

  sortedTempFile="$inputFilePath/sortedTempFile.csv"
  log_message "Sorting the temp file for creating diff files."
  sorted=$(sort "$tempFile" > "$sortedTempFile")
  log_message "The sorted temp file created successfully."

  outputFileDeletion="$deltaFilePath/hlr_full_dump_diff_del_"$operator"_$(date +%Y%m%d).csv"
  outputFileAddition="$deltaFilePath/hlr_full_dump_diff_add_"$operator"_$(date +%Y%m%d).csv"
  > "$outputFileDeletion"
  > "$outputFileAddition"
  log_message "Previous processed file name $fullPreviousProcessedFileName"
  #creating diff file
    if [ -f "$fullPreviousProcessedFileName" ];
	then
        #taking diff
        start_time=$(date +%s%3N)
        #diff_output=$(diff "$processedFile" "$tempFile" | grep '>' | cut -c 3-)
        diffOutputDeletion=$(diff -B --changed-group-format='%<' --unchanged-group-format='' "$fullPreviousProcessedFileName" "$sortedTempFile")
        diffOutputAddition=$(diff -B --changed-group-format='%>' --unchanged-group-format='' "$fullPreviousProcessedFileName" "$sortedTempFile")
        #echo "$headers" > "$output_file"
        echo "$diffOutputDeletion" > "$outputFileDeletion"
        echo "$diffOutputAddition" >  "$outputFileAddition"
        end_time=$(date +%s%3N)  # Get end time in milliseconds
        execution_time=$((end_time - start_time))
        log_message "Diff file creation execution time: $execution_time ms"
     else
        log_message "Processed File is empty copying the temp file to delta files."
        cp "$sortedTempFile" "$outputFileAddition"
  fi

  initialHlrCount=$(mysql -h$dbIp -P$dbPort $appdbName -u$dbUsername -p${dbPassword} -se "select count(*) from app.active_msisdn_list where operator='$operator'")
  log_message "The active_msisdn_list table count before execution $initialHlrCount"
  deleteCount=$(wc -l <"$outputFileDeletion")
  insertCount=$(wc -l <"$outputFileAddition")
  log_message "The total count in delete diff file $deleteCount".
  log_message "The total count in insert diff file $insertCount"
  start_time=$(date +%s%3N)
  cd $javaProcessPath
  mkdir -p ${log_path}
  java -Dlog.level=${log_level} -Dlog.path=${log_path} -Dmodule.name=${module_name} -Dlog4j.configurationFile=file:./log4j2.xml -jar lm_hlr.jar --spring.config.location=$commonConfiguration,$javaConfiguration 0 1 2  1>/dev/null 2>/dev/null
  jarStatusCode=$?
  end_time=$(date +%s%3N)
  execution_time=$((end_time-start_time))
  log_message "The java ava process took time for execution: $execution_time ms"
  javaFeatureName=$javaFeatureName
  fileProcessStatusCode=$(mysql -h$dbIp -P$dbPort $auddbName -u$dbUsername -p${dbPassword} -se "select status_code from modules_audit_trail where created_on LIKE '%$(date +%F)%' and feature_name='$javaFeatureName' and module_name='$moduleName'  order by id desc limit 1");
  log_message "The status code from processor after completion is = $fileProcessStatusCode"

  if [ "$fileProcessStatusCode" -eq 200 ] ;
      then
        log_message "The processor completed successfully"
        log_message "Move the $sortedTempFile to $processedFilePath"
        mv 	${sortedTempFile} ${processedFilePath}/${fileName}
        log_message "Remove the $sortedTempFile to $processedFilePath"
        rm ${inputFilePath}/${fileName} ${tempFile}
        mv $outputFileDeletion $deltaFileProcessedPath
        log_message "Moved file ${outputFileDeletion} to $deltaFileProcessedPath."
        mv $outputFileAddition $deltaFileProcessedPath
        log_message "Moved file $outputFileAddition to $deltaFileProcessedPath."
        log_message "Move the remaining files to $processedFilePath"
        mv ${inputFilePath}/* ${processedFilePath}
        cd $fileScriptProcessPath

     else
        log_message "The status of processor execution is not equal to 200."
        executionFinishTime=$(date +%s.%N);
        ExecutionTime=$(echo "$executionFinishTime - $executionStartTime" | bc)
        secondDivision=1000
        finalExecutionTime=`echo "$ExecutionTime * $secondDivision" | bc`
        updateAuditEntry 'The java process did not complete successfully for file '$fileName'.' $executionStartTime $moduleName $featureName
        generateAlertUsingUrl 'alert5211' $fileName $operator $alertUrl
        exit 1
  fi

  #8. Success entry in audit table.
  executionFinishTime=$(date +%s.%N);
  ExecutionTime=$(echo "$executionFinishTime - $executionStartTime" | bc)
  secondDivision=1000
  finalExecutionTime=`echo "$ExecutionTime * $secondDivision" | bc`

#  expectedHlrCount=$(( $initialHlrCount + $insertCount - $deleteCount))
#  currentHlrCount=$(mysql -h$dbIp -P$dbPort $appdbName -u$dbUsername -p$dbPassword -se "select count(*) from active_msisdn_list where operator='$operator'")
#  failureCount=$(($expectedHlrCount - $currentHlrCount))
#  failureCount=${failureCount#-}
#  log_message "Expected Count $expectedHlrCount"
#  log_message "current count $currentHlrCount"
#  log_message "$failureCount failure count"
#  if [ "$currentHlrCount" -ne "$expectedHlrCount" ]; then
#    log_message "There is some error while updating the HLR table."
#    #generateAlertUsingUrl 'alert5213' $fileName $operator $alertUrl
#  fi

#  log_message "Total number of record deleted=$deleteCount"
#  log_message "Total number of record inserted=$insertCount"
#  log_message "Total number of records failed=$failureCount"

   # logic for calculating the next date for processing of the
   # The tag value for nextDateTag contains the date when the process should execute. So when the process completes this
    #value needs to be updated with next processing date depending upon the frequency set.
    # First we try to calculate the the difference of days between current date and value nextDateTag.
  #  It can be 0,1,2 or any value or it can be greater than the frequency defined (worst case)
  # So we need to accordingly add days to current value of nextDateTag to calculate the next processing date.

  differenceSeconds=$(($currentDateTimestamp - $nextDateToProcessTimestamp))
  differenceDays=$((differenceSeconds / (24 * 3600)))
  log_message "Number of days between nextDateToProcess and currentDate: $differenceDays"
  daysToAdd=$(($differenceDays / $frequency + 1))

  nextTimestamp=$(($nextDateToProcessTimestamp +  $frequency * $daysToAdd * 24 * 3600))

  nextDateToProcessAgain=$(date -d "@$nextTimestamp" +%F)
  log_message "Next date to process HLR file: $nextDateToProcessAgain"
  fileCopy "$fileName" "$processedFilePath" "$currentHlrCount"
  mysql -h$dbIp -P$dbPort -u$dbUsername -p${dbPassword} $appdbName <<EOFMYSQL
    update sys_param set value='$nextDateToProcessAgain' where tag='$nextDateTag'
EOFMYSQL

  mysql -h$dbIp -P$dbPort -u$dbUsername -p${dbPassword} $auddbName <<EOFMYSQL
    update modules_audit_trail set status_code='200',status='SUCCESS',info='$fileName',count='$insertCount',execution_time='$finalExecutionTime',count2='$deleteCount',modified_on=CURRENT_TIMESTAMP where module_name='$moduleName' and feature_name='$featureName' order by id desc limit 1;
EOFMYSQL
  log_message "HLR Dump File Processor completed successfully."
  exit 0;
