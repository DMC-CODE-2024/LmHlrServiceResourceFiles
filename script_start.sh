#!/bin/bash
source ~/.bash_profile

VAR=""
operator="$1"
log_level="INFO"
log_path="${LOG_HOME}/list_management_module/hlr/${operator}"
module_name="hlr_${operator}"
propertiesFile="script_${operator}.properties"
. "$propertiesFile"
build_path="${APP_HOME}/list_management_module/lm_hlr/"
build="script.sh"
build_name="lm_hlr"
script_path="${APP_HOME}/list_management_module/lm_hlr/script/"
commonConfiguration=$commonConfigurationFile
if [ ! -e "$commonConfiguration" ]
  then
    log_message "$commonConfiguration file not found ,the script is terminated."
    exit 1;
fi


source $commonConfiguration

createNewFile() {
    local inputFile="$1"
    local outputFile="$2"
#    local suffix="$3"
    header=$(head -n 1 "$inputFile")
    # Add header to the new file
    echo "${header}${fileSeparator}activation_date" > "$outputFile"
    # Read each line from the input file, add a comma and empty value for activation_date
    tail -n +2 "$inputFile" | sed "s/$/${fileSeparator}/" >> "$outputFile"
}


function mergeFiles() {

  fileName=$1
  extractedFiles=($(tar -xzvf "$fileName"))
  baseFileName=$(basename "$fileName" ".tar.gz")

    # Initialize a variable to track the total number of lines
  totalLines=0

# Iterate through the files
  for currentFile in "${extractedFiles[@]}"; do
    # Skip directories and unwanted entries
    if [ -f "$currentFile" ]; then
      # Get the line count for the current file
      currentLines=$(wc -l < "$currentFile")

      # Print the filename and line count
      echo "File: $currentFile, Line Count: $currentLines"

      # If it's the first iteration, include the header and entries
      if [ ! -e "$inputFilePath"/"$baseFileName".txt ]; then
        header=$(head -n 1 "$currentFile")
        echo "${header},activation_date" > "$inputFilePath"/"$baseFileName".txt
      fi
      # Append the content starting from the second line
      #tail -n +2 "$inputFile" | sed 's/$/,/' >> "$outputFile"
      tail -n +2 "$currentFile" | sed 's/$/,/' >> "$inputFilePath"/"$baseFileName".txt
      rm "$currentFile"
      # Update the total line count
      totalLines=$((totalLines + currentLines))
    else
      echo "Skipping directory or unwanted entry: $currentFile"
    fi
  done
  echo "Total Number of Lines in the files received: $totalLines".
  echo "Merge all the files received and created a single file with name: "$inputFilePath"/"$baseFileName".txt"
}


if [ "$operator" == "SM" ]; then
  echo "The file is for smart operator.Untar the file, merge the files and add activation date in the column."
  fileName=$(ls -Art $inputFilePath | grep $filePattern |tail -n 1)
  echo "File name is $fileName"
  outputFileName="corrected_$fileName"
  mergeFiles "$inputFilePath/$fileName"
  mv "$inputFilePath"/"$fileName" "$processedFilePath"
fi

if [ "$operator" == "CC" ]; then
  echo "The file is for Cellcard. Untar the file and activation date in the column."
  fileName=$(ls -Art $inputFilePath | grep $filePattern |tail -n 1)
  echo "$fileName"
  outputFileName="corrected_""$fileName"
  mergeFiles "$inputFilePath/$fileName"
  mv "$inputFilePath/$fileName" "$processedFilePath"
fi

if [ "$operator" == "VT" ]; then
  echo "The file is for Metfone. Adding activation date in the column."
  fileName=$(ls -Art $inputFilePath | grep $filePattern |tail -n 1)
  #fileName='20240629_VT_HLR.txt'
  echo "$fileName"
  outputFileName=new_$fileName
  createNewFile $inputFilePath/$fileName $inputFilePath/$outputFileName
  mv "$inputFilePath/$fileName" "$processedFilePath"
fi
if [ "$operator" == "ST" ]; then
  
### STARTS HERE
  $operator=ST
  nextDateTag="nextProcessingDayHLR_$operator"
  echo "Tag for next day $nextDateTag"
  nextDateToProcess=$(mysql -h$dbIp -P$dbPort $appdbName -u$dbUsername  -p${dbPassword} -se "select value from sys_param where tag='$nextDateTag'")
  echo "The next day to execute the process: $nextDateToProcess"
  currentDate=$(date +%F)
  echo "The current date: $currentDate"
  nextDateToProcessTimestamp=$(date -d "$nextDateToProcess" +%s)
  currentDateTimestamp=$(date -d "$currentDate" +%s)
  echo
  if [ -z "$nextDateToProcess" ]; then
    echo "No previous date found, will continue the process."
  elif [ "$currentDateTimestamp" -lt "$nextDateToProcessTimestamp" ]; then
   echo "Current date is earlier than the next processing date."
  #  log_message "Moving all the files, if any to processed folder"
   # mv "$inputFilePath"/* "$processedFilePath"
    echo "Terminating the script."
    exit 1
  else
    echo "Current date is greater than or equal to the next processing date. The file will be processed."
  fi
### ENDS HERE
	
  echo "The process running for Seatel."
  outputFileDeletion="$inputFilePath/hlr_full_dump_diff_del_"$operator"_$(date +%Y%m%d).csv"
  outputFileAddition="$inputFilePath/hlr_full_dump_diff_add_"$operator"_$(date +%Y%m%d).csv"
  cd $javaProcessPath
   mkdir -p ${log_path}
  java -Dlog.level=${log_level} -Dlog.path=${log_path} -Dmodule.name=${module_name}  -Dlog4j.configurationFile=file:./log4j2.xml -jar ${build_name}.jar --spring.config.location=$commonConfiguration,$javaConfiguration 0 1 2  1>/dev/null 2>/dev/null
  javaFeatureName=$javaFeatureName
  fileProcessStatusCode=$(mysql -h$dbIp -P$dbPort $auddbName -u$dbUsername -p${dbPassword} -se "select status_code from modules_audit_trail where created_on LIKE '%$(date +%F)%' and feature_name='$javaFeatureName' and module_name='HLR_Full_Dump_ST'  order by id desc limit 1");
  echo "The status code from processor after completion is = $fileProcessStatusCode"
  if [ "$fileProcessStatusCode" -eq 200 ] ;
      then
        echo "The processor completed successfully"
        mv $outputFileDeletion $deltaFileProcessedPath
        echo "Moved file ${outputFileDeletion} to $deltaFileProcessedPath."
        mv $outputFileAddition $deltaFileProcessedPath   
        echo "Moved file $outputFileAddition to $deltaFileProcessedPath."
        cd $fileScriptProcessPath
        echo "Updating Process Date"

### STARTS HERE
  $frequency=1
  differenceSeconds=$(($currentDateTimestamp - $nextDateToProcessTimestamp))
  differenceDays=$((differenceSeconds / (24 * 3600)))
  echo "Number of days between nextDateToProcess and currentDate: $differenceDays"
  daysToAdd=$(($differenceDays / $frequency + 1))

  nextTimestamp=$(($nextDateToProcessTimestamp +  $frequency * $daysToAdd * 24 * 3600))
  nextDateToProcessAgain=$(date -d "@$nextTimestamp" +%F)
  echo "Next date to process HLR file: $nextDateToProcessAgain"
  fileCopy "$fileName" "$processedFilePath" "$currentHlrCount"
  mysql -h$dbIp -P$dbPort -u$dbUsername -p${dbPassword} $appdbName <<EOFMYSQL
    update sys_param set value='$nextDateToProcessAgain' where tag='$nextDateTag'
EOFMYSQL
  echo "Seatel HLR Dump File Processor completed successfully."
### ENDS HERE
  fi
  exit 0;
fi
# Run the script now
cd "$script_path"
./script.sh $propertiesFile

