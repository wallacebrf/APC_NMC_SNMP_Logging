#!/bin/bash
#Version 1/18/2023

#############################################
#VERIFICATIONS
#############################################
#1.) data is collected into influx properly......................................................................... VERIFIED 1/18/2023 
#2.) SNMP errors:
	#a.) bad SNMP username causes script to shutdown with email..................................................... VERIFIED 1/18/2023  
	#b.) bad SNMP authpass causes script to shutdown with email..................................................... VERIFIED 1/18/2023 
	#c.) bad SNMP privacy pass causes script to shutdown with email................................................. VERIFIED 1/18/2023 
	#d.) bad SNMP ip address causes script to shutdown with email................................................... VERIFIED 1/18/2023 
	#e.) bad SNMP port causes script to shutdown with email......................................................... VERIFIED 1/18/2023 
	#f.) error emails a through e above only are sent within the allowed time interval.............................. VERIFIED 1/18/2023 
#3.) verify that when "sendmail" is unavailable, emails are not sent, and the appropriate warnings are displayed.... VERIFIED 1/18/2023 
#4.) verify script behavior when config file is unavailable......................................................... VERIFIED 1/18/2023 
#5.) verify script behavior when config file has wrong number of arguments.......................................... VERIFIED 1/18/2023 
#6.) verify script behavior when the target device is not available / responding to pings........................... VERIFIED 1/18/2023 
  

###########################################
#USER VARIABLES
###########################################
lock_file="/volume1/web/logging/notifications/1st_floor_bedroom_APC_snmp.lock"
config_file="/volume1/web/config/config_files/config_files_local/FB_APC_config.txt"
last_time_email_sent="/volume1/web/logging/notifications/1st_floor_bedroom_APC_last_email_sent.txt"
email_contents="/volume1/web/logging/notifications/1st_floor_bedroom_APC_email_contents.txt"

#########################################################
#EMAIL SETTINGS USED IF CONFIGURATION FILE IS UNAVAILABLE, SNMP DATA IS BAD, OR IF TAGET DEVICE IS OFFLINE
#These variables will be overwritten with new corrected data if the configuration file loads properly. 
email_address="email@email.com"
from_email_address="from@email.com"
#########################################################

#####################################
#Function to send email when SNMP commands fail
#####################################
function SNMP_error_email(){
	#determine when the last time a general notification email was sent out. this will make sure we send an email only every x minutes
	current_time=$( date +%s )
	if [ -r "$last_time_email_sent" ]; then
		read email_time < $last_time_email_sent
		email_time_diff=$((( $current_time - $email_time ) / 60 ))
	else 
		echo "$current_time" > $last_time_email_sent
		email_time_diff=0
	fi

	local now=$(date +"%T")
	local mailbody="$now - ALERT APC UPS at IP $nas_url named \"$nas_name\" appears to have an issue with SNMP as it returned invalid data"
	echo "from: $from_email_address " > $email_contents
	echo "to: $email_address " >> $email_contents
	echo "subject: ALERT APC UPS at IP $nas_url named \"$nas_name\" appears to have an issue with SNMP " >> $email_contents
	echo "" >> $email_contents
	echo $mailbody >> $email_contents
			
	if [[ "$email_address" == "" || "$from_email_address" == "" ]];then
			echo -e "\n\nNo email address information is configured, Cannot send an email the UPS returned invalid SNMP data"
	else
		if [ $sendmail_installed -eq 1 ]; then	
			if [ $email_time_diff -ge 60 ]; then
				local email_response=$(sendmail -t < $email_contents  2>&1)
				if [[ "$email_response" == "" ]]; then
					echo -e "\n\nEmail Sent Successfully that the target UPS appears to have an issue with SNMP" |& tee -a $email_contents
					snmp_error=1
					current_time=$( date +%s )
					echo "$current_time" > $last_time_email_sent
					email_time_diff=0
				else
					echo -e "\n\nWARNING -- An error occurred while sending Error email. The error was: $email_response\n\n" |& tee $email_contents
				fi	
			else
				echo "Only $email_time_diff minuets have passed since the last notification, email will be sent every 60 minutes. $(( 60 - $email_time_diff )) Minutes Remaining Until Next Email"
			fi	
		else
			echo -e "\n\nERROR -- Could not send alert email that an error occurred getting SNMP data -- command \"sendmail\" is not available\n\n"
		fi
	fi
	exit 1
}

#create a lock file in the ramdisk directory to prevent more than one instance of this script from executing  at once
if ! mkdir $lock_file; then
	echo "Failed to acquire lock.\n" >&2
	exit 1
fi
trap 'rm -rf $lock_file' EXIT #remove the lockdir on exit

#verify MailPlus Server package is installed and running as the "sendmail" command is not installed in synology by default. the MailPlus Server package is required
install_check=$(/usr/syno/bin/synopkg list | grep MailPlus-Server)
	if [ "$install_check" = "" ];then
	echo "WARNING!  ----   MailPlus Server NOT is installed, cannot send email notifications"
	sendmail_installed=0
else
	#echo "MailPlus Server is installed, verify it is running and not stopped"
	status=$(/usr/syno/bin/synopkg is_onoff "MailPlus-Server")
	if [ "$status" = "package MailPlus-Server is turned on" ]; then
		sendmail_installed=1
	else
		sendmail_installed=0
		echo "WARNING!  ----   MailPlus Server NOT is running, cannot send email notifications"
	fi
fi

#Metrics to capture, set to false if you want to skip that specific set
capture_system="true" #model information, temperature, update status, 

#reading in variables from configuration file
if [ -r "$config_file" ]; then
	#file is available and readable 
	read input_read < $config_file
	explode=(`echo $input_read | sed 's/,/\n/g'`)
	
	#verify the correct number of configuration parameters are in the configuration file
	if [[ ! ${#explode[@]} == 14 ]]; then
		echo "WARNING - the configuration file is incorrect or corrupted. It should have 14 parameters, it currently has ${#explode[@]} parameters."
		exit 1
	fi
	
	capture_interval=${explode[0]}
	nas_url=${explode[1]}
	nas_name=${explode[2]}
	ups_group=""
	influxdb_host=${explode[3]}
	influxdb_port=${explode[4]}
	influxdb_name=${explode[5]}
	influxdb_user=${explode[6]}
	influxdb_pass=${explode[7]}
	script_enable=${explode[8]}
	AuthPass1=${explode[9]}
	PrivPass2=${explode[10]}
	snmp_user=${explode[11]}
	snmp_privacy_protocol=${explode[12]}
	snmp_auth_protocol=${explode[13]}
	target_available=0
	
	
	#let's make sure the target for SNMP walking is available on the network 
	ping -c1 $nas_url > /dev/null
	if [ $? -eq 0 ]
	then
			target_available=1 #network coms are good
	else
		#ping failed
		#since the ping failed, let's do just one more ping juts in case
		ping -c1 $nas_url > /dev/null
		if [ $? -eq 0 ]
		then
			target_available=1 #network coms are good
		else
			target_available=0 #network coms appear to be down, stop script
		fi
	fi

	if [ $target_available -eq 1 ]; then
		if [ $script_enable -eq 1 ]; then

			#loop the script 
			total_executions=$(( 60 / $capture_interval))
			echo "Capturing $total_executions times"
			i=0
			while [ $i -lt $total_executions ]; do
				
				#Create empty URL
				post_url=

				#GETTING VARIOUS SYSTEM INFORMATION
				if (${capture_system,,} = "true"); then
					
					measurement="apc_system"
					
					#UPS Reason for last transfer,  1  No events, 2  High line voltage, 3  Brownout, 4  Loss of mains power, 5  Small temporary power drop, 6  Large temporary power drop, 7  Small spike, 8  Large spike, 9  UPS self test, 10  Excessive input voltage fluctuation
					#collect the first SNMP data point and make sure it is valid or exit the script
					if [ "$snmp_user" = "" ];then
						echo "SNMP Username is BLANK, please configure the SNMP settings"
						SNMP_error_email #send notification email that the switch appears to have issues with SNMP
					else
						if [ "$AuthPass1" = "" ];then
							echo "SNMP Authentication Password is BLANK, please configure the SNMP settings"
							SNMP_error_email #send notification email that the switch appears to have issues with SNMP
						else
							if [ "$PrivPass2" = "" ];then
								echo "SNMP Privacy Password is BLANK, please configure the SNMP settings"
								SNMP_error_email #send notification email that the switch appears to have issues with SNMP
							else
								system_status=$(snmpwalk -v3 -r 1 -l authPriv -u $snmp_user -a $snmp_auth_protocol -A $AuthPass1 -x $snmp_privacy_protocol -X $PrivPass2 $nas_url:161 .1.3.6.1.4.1.318.1.1.1.3.2.5.0 -Oqv 2>&1)
								
								#since $system_status is the first time we have performed a SNMP request to the switch, let's make sure we did not receive any errors that could be caused by things like bad passwords, bad username, incorrect auth or privacy types etc
								#if we receive an error now, then something is wrong with the SNMP settings and this script will not be able to function so we should exit out of it. 
								#different errors and responses can be received from the UPS network management card when SNMP fails
	
								#1.) wrong username --> "Authentication failed for"
								#2.) wrong authentication/privacy protocol/password --> "Timeout: No Response from"
								#3.) too short of auth/privacy password --> "Error: passphrase chosen is below the length requirements"
								#4.) wrong IP/Port --> "snmpwalk: Timeout"
								#5.) bad IOD --> "No Such Instance currently exists at this OID"
								#6.) result is blank

									
								if [[ "$system_status" == "Authentication failed for"* ]]; then 
									echo -e "\n\n WARNING -- the SNMP username appears to be incorrect. Exiting Script"
									SNMP_error_email
								fi
								
								if [[ "$system_status" == "Timeout: No Response from"* ]]; then 
									echo -e "\n\n WARNING -- the SNMP authentication/privacy protocol/password appears to be incorrect. Exiting Script"
									SNMP_error_email
								fi
								
								if [[ "$system_status" == "Error: passphrase chosen is below the length requirements"* ]]; then 
									echo -e "\n\n WARNING -- the SNMP auth/privacy password are too short. Exiting Script"
									SNMP_error_email
								fi
								
								if [[ "$system_status" == "snmpwalk: Timeout"* ]]; then 
									echo -e "\n\n WARNING --  the SNMP IP address or port appear to be incorrect. Exiting Script"
									SNMP_error_email
								fi
								
								if [[ "$system_status" == "No Such Instance currently exists at this OID"* ]]; then 
									echo -e "\n\n WARNING --  the SNMP IOD appears to be incorrect. Exiting Script"
									SNMP_error_email
								fi
								
								if [[ "$system_status" == "" ]]; then 
									echo -e "\n\n WARNING --  the SNMP data received was blank. Exiting Script"
									SNMP_error_email
								fi
							fi
						fi
					fi

					# UPS Battery Capacity
					battery_capacity=`snmpwalk -v3 -r 1 -l authPriv -u $snmp_user -a $snmp_auth_protocol -A $AuthPass1 -x $snmp_privacy_protocol -X $PrivPass2 $nas_url:161 .1.3.6.1.4.1.318.1.1.1.2.2.1.0 -Oqv`
					
					# UPS Battery Temperature
					battery_temp_c=`snmpwalk -v3 -r 1 -l authPriv -u $snmp_user -a $snmp_auth_protocol -A $AuthPass1 -x $snmp_privacy_protocol -X $PrivPass2 $nas_url:161 .1.3.6.1.4.1.318.1.1.1.2.2.2.0 -Oqv`
					
					# UPS Battery remaining Run Time
					battery_run_time=`snmpwalk -v3 -r 1 -l authPriv -u $snmp_user -a $snmp_auth_protocol -A $AuthPass1 -x $snmp_privacy_protocol -X $PrivPass2 $nas_url:161 .1.3.6.1.4.1.318.1.1.1.2.2.3.0 -Oqv`
					
					#split the run time from a string to individual numbers
					delimiter=":"
					s=$battery_run_time$delimiter
					array=();
					while [[ $s ]]; do
						array+=( "${s%%"$delimiter"*}" );
						s=${s#*"$delimiter"};
					done;
					#declare -p array    #([0]=days [1]=hours [2]=minutes [3]=seconds
					
					
					# UPS Battery Replace If result = 2 then battery needs replacing (1 = ok)
					battery_replace=`snmpwalk -v3 -r 1 -l authPriv -u $snmp_user -a $snmp_auth_protocol -A $AuthPass1 -x $snmp_privacy_protocol -X $PrivPass2 $nas_url:161 .1.3.6.1.4.1.318.1.1.1.2.2.4.0 -Oqv`
					
					# UPS Input Voltage
					input_voltage=`snmpwalk -v3 -r 1 -l authPriv -u $snmp_user -a $snmp_auth_protocol -A $AuthPass1 -x $snmp_privacy_protocol -X $PrivPass2 $nas_url:161 .1.3.6.1.4.1.318.1.1.1.3.2.1.0 -Oqv`
					
					# UPS Input Frequency
					input_freq=`snmpwalk -v3 -r 1 -l authPriv -u $snmp_user -a $snmp_auth_protocol -A $AuthPass1 -x $snmp_privacy_protocol -X $PrivPass2 $nas_url:161 .1.3.6.1.4.1.318.1.1.1.3.2.4.0 -Oqv`
					
					# UPS Output Voltage
					output_voltage=`snmpwalk -v3 -r 1 -l authPriv -u $snmp_user -a $snmp_auth_protocol -A $AuthPass1 -x $snmp_privacy_protocol -X $PrivPass2 $nas_url:161 .1.3.6.1.4.1.318.1.1.1.4.2.1.0 -Oqv`
					
					# UPS Output Frequency
					output_freq=`snmpwalk -v3 -r 1 -l authPriv -u $snmp_user -a $snmp_auth_protocol -A $AuthPass1 -x $snmp_privacy_protocol -X $PrivPass2 $nas_url:161 .1.3.6.1.4.1.318.1.1.1.4.2.2.0 -Oqv`
					
					# UPS Output Load
					output_load=`snmpwalk -v3 -r 1 -l authPriv -u $snmp_user -a $snmp_auth_protocol -A $AuthPass1 -x $snmp_privacy_protocol -X $PrivPass2 $nas_url:161 .1.3.6.1.4.1.318.1.1.1.4.2.3.0 -Oqv`
					
					# UPS Output Current
					output_current=`snmpwalk -v3 -r 1 -l authPriv -u $snmp_user -a $snmp_auth_protocol -A $AuthPass1 -x $snmp_privacy_protocol -X $PrivPass2 $nas_url:161 .1.3.6.1.4.1.318.1.1.1.4.2.4.0 -Oqv`
					

					# ups self-test diagnostics results
					#ok(1)
					#failed(2)
					#invalidTest(3)
					#testInProgress(4)
					self_test_result=`snmpwalk -v3 -r 1 -l authPriv -u $snmp_user -a $snmp_auth_protocol -A $AuthPass1 -x $snmp_privacy_protocol -X $PrivPass2 $nas_url:161 1.3.6.1.4.1.318.1.1.1.7.2.3.0 -Oqv`
					
					# ups self-test last diagnostics date
					self_test_date=`snmpwalk -v3 -r 1 -l authPriv -u $snmp_user -a $snmp_auth_protocol -A $AuthPass1 -x $snmp_privacy_protocol -X $PrivPass2 $nas_url:161 1.3.6.1.4.1.318.1.1.1.7.2.4.0 -Oqv`
					
					# ups adv test calibration results
					#ok(1)
					#invalidCalibration(2)
					#calibrationInProgress(3)
					#refused(4)
					#aborted(5)
					#pending(6)
					#unknown(7)
					calibration_results=`snmpwalk -v3 -r 1 -l authPriv -u $snmp_user -a $snmp_auth_protocol -A $AuthPass1 -x $snmp_privacy_protocol -X $PrivPass2 $nas_url:161 1.3.6.1.4.1.318.1.1.1.7.2.6.0 -Oqv`
					
					# ups adv test calibration date
					calibration_date=`snmpwalk -v3 -r 1 -l authPriv -u $snmp_user -a $snmp_auth_protocol -A $AuthPass1 -x $snmp_privacy_protocol -X $PrivPass2 $nas_url:161 1.3.6.1.4.1.318.1.1.1.7.2.7.0 -Oqv`
					
					# ups basic battery status
					#unknown(1)
					#batteryNormal(2)
					#batteryLow(3)
					#batteryInFaultCondition(4)
					battery_status=`snmpwalk -v3 -r 1 -l authPriv -u $snmp_user -a $snmp_auth_protocol -A $AuthPass1 -x $snmp_privacy_protocol -X $PrivPass2 $nas_url:161 1.3.6.1.4.1.318.1.1.1.2.1.1.0 -Oqv`
					
					# ups adv battery actual voltage
					battery_voltage=`snmpwalk -v3 -r 1 -l authPriv -u $snmp_user -a $snmp_auth_protocol -A $AuthPass1 -x $snmp_privacy_protocol -X $PrivPass2 $nas_url:161 1.3.6.1.4.1.318.1.1.1.2.2.8.0 -Oqv`
					
					# ups basic battery last replace date
					battery_last_replace_date=`snmpwalk -v3 -r 1 -l authPriv -u $snmp_user -a $snmp_auth_protocol -A $AuthPass1 -x $snmp_privacy_protocol -X $PrivPass2 $nas_url:161 1.3.6.1.4.1.318.1.1.1.2.1.3.0 -Oqv`
					
					# ups adv battery recommended replace date
					battery_recommended_replace_date=`snmpwalk -v3 -r 1 -l authPriv -u $snmp_user -a $snmp_auth_protocol -A $AuthPass1 -x $snmp_privacy_protocol -X $PrivPass2 $nas_url:161 1.3.6.1.4.1.318.1.1.1.2.2.21.0 -Oqv`
					
					# uio sensor status temperature degf
					IO_temp_f=`snmpwalk -v3 -r 1 -l authPriv -u $snmp_user -a $snmp_auth_protocol -A $AuthPass1 -x $snmp_privacy_protocol -X $PrivPass2 $nas_url:161 1.3.6.1.4.1.318.1.1.25.1.2.1.5 -Oqv`
					
					# uio sensor status humidity
					IO_humidity=`snmpwalk -v3 -r 1 -l authPriv -u $snmp_user -a $snmp_auth_protocol -A $AuthPass1 -x $snmp_privacy_protocol -X $PrivPass2 $nas_url:161 1.3.6.1.4.1.318.1.1.25.1.2.1.7 -Oqv`
					
					#System details to post
					post_url=$post_url"$measurement,nas_name=$nas_name system_status=$system_status,battery_capacity=$battery_capacity,battery_temp_c=$battery_temp_c,battery_replace=$battery_replace,input_voltage=$input_voltage,input_freq=$input_freq,output_voltage=$output_voltage,output_freq=$output_freq,output_load=$output_load,output_current=$output_current,run_time_days=${array[0]},run_time_hours=${array[1]},run_time_min=${array[2]},rum_time_sec=${array[3]},self_test_result=$self_test_result,self_test_date=$self_test_date,calibration_results=$calibration_results,calibration_date=$calibration_date,battery_status=$battery_status,battery_voltage=$battery_voltage,battery_last_replace_date=$battery_last_replace_date,battery_recommended_replace_date=$battery_recommended_replace_date,IO_temp_f=$IO_temp_f,IO_humidity=$IO_humidity
			"
				else
					echo "Skipping system capture"
				fi
				
				#Post to influxdb
				curl -XPOST "http://$influxdb_host:$influxdb_port/api/v2/write?bucket=$influxdb_name&org=home" -H "Authorization: Token $influxdb_pass" --data-raw "$post_url"
				
				let i=i+1
				
				echo "Capture #$i complete"
				
				#Sleeping for capture interval unless its last capture then we don't sleep
				if (( $i < $total_executions)); then
					sleep $(( $capture_interval -1))
				fi
				
			done
		else
			echo "Script Disabled"
		fi
	else
		#determine when the last time a general notification email was sent out. this will make sure we send an email only every x minutes
		current_time=$( date +%s )
		if [ -r "$last_time_email_sent" ]; then
			read email_time < $last_time_email_sent
			email_time_diff=$((( $current_time - $email_time ) / 60 ))
		else 
			echo "$current_time" > $last_time_email_sent
			email_time_diff=0
		fi
	
		echo "Target device at $nas_url is unavailable, skipping script"
		now=$(date +"%T")
		if [ $email_time_diff -ge 60 ]; then
			#send an email indicating script config file is missing and script will not run
			mailbody="$now - Warning UPS SNMP Monitoring Failed for device IP $nas_url - Target is Unavailable "
			echo "from: $from_email_address " > $email_contents
			echo "to: $email_address " >> $email_contents
			echo "subject: Warning UPS SNMP Monitoring Failed for device IP $nas_url - Target is Unavailable " >> $email_contents
			echo "" >> $email_contents
			echo $mailbody >> $email_contents
			
			if [[ "$email_address" == "" || "$from_email_address" == "" ]];then
				echo -e "\n\nNo email address information is configured, Cannot send an email indicating Target is Unavailable and script will not run"
			else
				if [ $sendmail_installed -eq 1 ]; then
					email_response=$(sendmail -t < $email_contents  2>&1)
					if [[ "$email_response" == "" ]]; then
						echo -e "\nEmail Sent Successfully indicating Target is Unavailable and script will not run" |& tee -a $email_contents
						current_time=$( date +%s )
						echo "$current_time" > $last_time_email_sent
						email_time_diff=0
					else
						echo -e "\n\nWARNING -- An error occurred while sending email. The error was: $email_response\n\n" |& tee $email_contents
					fi	
				else
					echo "Unable to send email, \"sendmail\" command is unavailable"
				fi
			fi
		else
			echo -e "\n\nAnother email notification will be sent in $(( 60 - $email_time_diff)) Minutes"
		fi
		exit 1
	fi
else
	#determine when the last time a general notification email was sent out. this will make sure we send an email only every x minutes
	current_time=$( date +%s )
	if [ -r "$last_time_email_sent" ]; then
		read email_time < $last_time_email_sent
		email_time_diff=$((( $current_time - $email_time ) / 60 ))
	else 
		echo "$current_time" > $last_time_email_sent
		email_time_diff=0
	fi
	
	now=$(date +"%T")
	echo "Configuration file for script \"${0##*/}\" is missing, skipping script and will send alert email every 60 minuets"
	if [ $email_time_diff -ge 60 ]; then
		#send an email indicating script config file is missing and script will not run
		mailbody="$now - Warning UPS Monitoring Failed for script \"${0##*/}\" - Configuration file is missing "
		echo "from: $from_email_address " > $email_contents
		echo "to: $email_address " >> $email_contents
		echo "subject: Warning UPS Monitoring Failed for script \"${0##*/}\" - Configuration file is missing " >> $email_contents
		echo "" >> $email_contents
		echo $mailbody >> $email_contents
		
		if [[ "$email_address" == "" || "$from_email_address" == "" ]];then
			echo -e "\n\nNo email address information is configured, Cannot send an email indicating script \"${0##*/}\" config file is missing and script will not run"
		else
			if [ $sendmail_installed -eq 1 ]; then
				email_response=$(sendmail -t < $email_contents  2>&1)
				if [[ "$email_response" == "" ]]; then
					echo -e "\nEmail Sent Successfully indicating script \"${0##*/}\" config file is missing and script will not run" |& tee -a $email_contents
					current_time=$( date +%s )
					echo "$current_time" > $last_time_email_sent
					email_time_diff=0
				else
					echo -e "\n\nWARNING -- An error occurred while sending email. The error was: $email_response\n\n" |& tee $email_contents
				fi	
			else
				echo "Unable to send email, \"sendmail\" command is unavailable"
			fi
		fi
	else
		echo -e "\n\nAnother email notification will be sent in $(( 60 - $email_time_diff)) Minutes"
	fi
	exit 1
fi
