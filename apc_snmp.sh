#!/bin/bash

#create a lock file in the ramdisk directory to prevent more than one instance of this script from executing  at once
if ! mkdir /volume1/web/logging/notifications/1st_floor_bedroom_APC_snmp.lock; then
	echo "Failed to aquire lock.\n" >&2
	exit 1
fi
trap 'rm -rf /volume1/web/logging/notifications/1st_floor_bedroom_APC_snmp.lock' EXIT #remove the lockdir on exit

#Metrics to capture, set to false if you want to skip that specific set
capture_system="true" #model information, temperature, update status, 

#reading in variables from configuration file
if [ -r "/volume1/web/config/config_files/config_files_local/FB_APC_config.txt" ]; then
	#file is available and readable 
	read input_read < /volume1/web/config/config_files/config_files_local/FB_APC_config.txt
	explode=(`echo $input_read | sed 's/,/\n/g'`)
	capture_interval=${explode[0]}
	nas_url=${explode[1]}
	nas_name=${explode[2]}
	ups_group="1FB"
	influxdb_host=${explode[3]}
	influxdb_port=${explode[4]}
	influxdb_name=${explode[5]}
	influxdb_user=${explode[6]}
	influxdb_pass=${explode[7]}
	script_enable=${explode[8]}
	AuthPass1="password"
	PrivPass2="password"
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

	if [ $target_available -eq 1 ]
	then
	

		if [ $script_enable -eq 1 ]
		then

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
					#system_status=`snmpwalk -r 0 -t 1 -v 2c -c public $nas_url .1.3.6.1.4.1.318.1.1.1.3.2.5.0 -Oqv`
					system_status=`snmpwalk -v3 -l authPriv -u brian -a MD5 -A $AuthPass1 -x AES -X $PrivPass2 $nas_url:161 .1.3.6.1.4.1.318.1.1.1.3.2.5.0 -Oqv`
					
					# UPS Battery Capacity
					#battery_capacity=`snmpwalk -r 0 -t 1 -v 2c -c public $nas_url .1.3.6.1.4.1.318.1.1.1.2.2.1.0 -Oqv`
					battery_capacity=`snmpwalk -v3 -l authPriv -u brian -a MD5 -A $AuthPass1 -x AES -X $PrivPass2 $nas_url:161 .1.3.6.1.4.1.318.1.1.1.2.2.1.0 -Oqv`
					
					# UPS Battery Temperature
					#battery_temp_c=`snmpwalk -r 0 -t 1 -v 2c -c public $nas_url .1.3.6.1.4.1.318.1.1.1.2.2.2.0 -Oqv`
					battery_temp_c=`snmpwalk -v3 -l authPriv -u brian -a MD5 -A $AuthPass1 -x AES -X $PrivPass2 $nas_url:161 .1.3.6.1.4.1.318.1.1.1.2.2.2.0 -Oqv`
					
					# UPS Battery remaining Run Time
					#battery_run_time=`snmpwalk -r 0 -t 1 -v 2c -c public $nas_url .1.3.6.1.4.1.318.1.1.1.2.2.3.0 -Oqv`
					battery_run_time=`snmpwalk -v3 -l authPriv -u brian -a MD5 -A $AuthPass1 -x AES -X $PrivPass2 $nas_url:161 .1.3.6.1.4.1.318.1.1.1.2.2.3.0 -Oqv`
					
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
					#battery_replace=`snmpwalk -r 0 -t 1 -v 2c -c public $nas_url .1.3.6.1.4.1.318.1.1.1.2.2.4.0 -Oqv`
					battery_replace=`snmpwalk -v3 -l authPriv -u brian -a MD5 -A $AuthPass1 -x AES -X $PrivPass2 $nas_url:161 .1.3.6.1.4.1.318.1.1.1.2.2.4.0 -Oqv`
					
					# UPS Input Voltage
					#input_voltage=`snmpwalk -r 0 -t 1 -v 2c -c public $nas_url .1.3.6.1.4.1.318.1.1.1.3.2.1.0 -Oqv`
					input_voltage=`snmpwalk -v3 -l authPriv -u brian -a MD5 -A $AuthPass1 -x AES -X $PrivPass2 $nas_url:161 .1.3.6.1.4.1.318.1.1.1.3.2.1.0 -Oqv`
					
					# UPS Input Frequency
					#input_freq=`snmpwalk -r 0 -t 1 -v 2c -c public $nas_url .1.3.6.1.4.1.318.1.1.1.3.2.4.0 -Oqv`
					input_freq=`snmpwalk -v3 -l authPriv -u brian -a MD5 -A $AuthPass1 -x AES -X $PrivPass2 $nas_url:161 .1.3.6.1.4.1.318.1.1.1.3.2.4.0 -Oqv`
					
					# UPS Output Voltage
					#output_voltage=`snmpwalk -r 0 -t 1 -v 2c -c public $nas_url .1.3.6.1.4.1.318.1.1.1.4.2.1.0 -Oqv`
					output_voltage=`snmpwalk -v3 -l authPriv -u brian -a MD5 -A $AuthPass1 -x AES -X $PrivPass2 $nas_url:161 .1.3.6.1.4.1.318.1.1.1.4.2.1.0 -Oqv`
					
					# UPS Output Frequency
					#output_freq=`snmpwalk -r 0 -t 1 -v 2c -c public $nas_url .1.3.6.1.4.1.318.1.1.1.4.2.2.0 -Oqv`
					output_freq=`snmpwalk -v3 -l authPriv -u brian -a MD5 -A $AuthPass1 -x AES -X $PrivPass2 $nas_url:161 .1.3.6.1.4.1.318.1.1.1.4.2.2.0 -Oqv`
					
					# UPS Output Load
					#output_load=`snmpwalk -r 0 -t 1 -v 2c -c public $nas_url .1.3.6.1.4.1.318.1.1.1.4.2.3.0 -Oqv`
					output_load=`snmpwalk -v3 -l authPriv -u brian -a MD5 -A $AuthPass1 -x AES -X $PrivPass2 $nas_url:161 .1.3.6.1.4.1.318.1.1.1.4.2.3.0 -Oqv`
					
					# UPS Output Current
					#output_current=`snmpwalk -r 0 -t 1 -v 2c -c public $nas_url .1.3.6.1.4.1.318.1.1.1.4.2.4.0 -Oqv`
					output_current=`snmpwalk -v3 -l authPriv -u brian -a MD5 -A $AuthPass1 -x AES -X $PrivPass2 $nas_url:161 .1.3.6.1.4.1.318.1.1.1.4.2.4.0 -Oqv`
					
					#System details to post
					post_url=$post_url"$measurement,nas_name=$nas_name system_status=$system_status,battery_capacity=$battery_capacity,battery_temp_c=$battery_temp_c,battery_replace=$battery_replace,input_voltage=$input_voltage,input_freq=$input_freq,output_voltage=$output_voltage,output_freq=$output_freq,output_load=$output_load,output_current=$output_current,run_time_days=${array[0]},run_time_hours=${array[1]},run_time_min=${array[2]},rum_time_sec=${array[3]}
			"
				else
					echo "Skipping system capture"
				fi
				
				
				
				
				#Post to influxdb
				#if [[ -z $influxdb_user ]]; then
				#	curl -i -XPOST "http://$influxdb_host:$influxdb_port/write?db=$influxdb_name" --data-binary "$post_url"
				#else
				#	curl -i -XPOST "http://$influxdb_host:$influxdb_port/write?u=$influxdb_user&p=$influxdb_pass&db=$influxdb_name" --data-binary "$post_url"
				#fi
				curl -XPOST "http://$influxdb_host:$influxdb_port/api/v2/write?bucket=$influxdb_name&org=home" -H "Authorization: Token $influxdb_pass" --data-raw "$post_url"
				echo "$post_url"
				echo "battery run time $battery_run_time"
				
				let i=i+1
				
				echo "Capture #$i complete"
				
				#Sleeping for capture interval unless its last capture then we dont sleep
				if (( $i < $total_executions)); then
					sleep $(( $capture_interval -1))
				fi
				
			done
		else
			echo "Script Disabled"
		fi
	else
		echo "Target device at $nas_url is unavailable, skipping script"
	fi
else
	echo "Configuration file unavailable"
fi
