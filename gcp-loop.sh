#!/bin/bash

# Capture all CLI output
#exec &> deploy-log.txt

# Move to local directory
cd "${0%/*}"

# Initiate log file
logfile="deploy-log.txt"

# Does what it says on the tin
source creds.txt

# Cron runs every minute, so do this process 28 times, with a 2 second pause, to cover just under a minute of execution
for number in {1..28}
do

# Query databse for jobs which are ready
results=$(mysql -N -u $DBUSER -p$OURPASS -D gcp-autocloud -e "SELECT JOB FROM jobs WHERE STATUS = 'Ready';") >> $logfile

# Make jobs list from database the stdin
set -- $results

# Take first job
uid=$1

if [ "$uid" != "" ]
	then
	# There are jobs ready!
	echo "Job(s) ready" >> $logfile

	# Start the clock
	start=$(date)
    	lstart=$(date +%s)
	
	# Set job to deploying status
	$(mysql -u $DBUSER -p$OURPASS -D gcp-autocloud -e "UPDATE jobs SET STATUS = 'Deploying' WHERE JOB = '$uid';")

	# Get job attributes
	resgrp=$(mysql -N -u $DBUSER -p$OURPASS -D gcp-autocloud -e "SELECT RESGRP FROM jobs WHERE JOB = '$uid';") >> $logfile
	message=$(mysql -N -u $DBUSER -p$OURPASS -D gcp-autocloud -e "SELECT MESSAGE FROM jobs WHERE JOB = '$uid';") >> $logfile
	phone=$(mysql -N -u $DBUSER -p$OURPASS -D gcp-autocloud -e "SELECT PHONE FROM jobs WHERE JOB = '$uid';") >> $logfile
	email=$(mysql -N -u $DBUSER -p$OURPASS -D gcp-autocloud -e "SELECT EMAIL FROM jobs WHERE JOB = '$uid';") >> $logfile
	nickname=$(mysql -N -u $DBUSER -p$OURPASS -D gcp-autocloud -e "SELECT NICKNAME FROM jobs WHERE JOB = '$uid';") >> $logfile
	se=$(mysql -N -u $DBUSER -p$OURPASS -D gcp-autocloud -e "SELECT SE FROM jobs WHERE JOB = '$uid';") >> $logfile
	subnet=$(mysql -N -u $DBUSER -p$OURPASS -D gcp-autocloud -e "SELECT ID FROM subnetid WHERE NAME = 'here';") >> $logfile
	
	#read -n1 -r -p "Press any key to continue..." key

	# Make sure the subnet is incremented ready for next job, wrapping around 254 as required
	if [ "$subnet" -ge 254 ]
		then
			newsubnet=0
		else
			newsubnet=$((subnet+1))
	fi
	
	#read -n1 -r -p "Press any key to continue..." key

	# Write back the next subnet to the database
	$(mysql -u $DBUSER -p$OURPASS -D gcp-autocloud -e "UPDATE subnetid SET ID = '$newsubnet' WHERE NAME = 'here';") >> $logfile

	#read -n1 -r -p "Press any key to continue..." key

	# Attribute manipulation as required
	nickname=${nickname//[[:space:]]/}
	nick_lower="${nickname,,}"

	# Log the inputs
	echo $resgrp >> $logfile
	echo $message >> $logfile
	echo $phone >> $logfile
	echo $email >> $logfile
	echo $nickname >> $logfile
	echo $subnet >> $logfile
	echo $newsubnet >> $logfile

	#read -n1 -r -p "Press any key to continue..." key

    # Send SMS
	#curl -X POST https://textbelt.com/text --data-urlencode phone=$phone --data-urlencode message="Hi $nickname, starting your deployment now..." -d key=$SMS >> $logfile
	# Send admin email
	curl -s --user 'api:'"$MAILGUN"'' https://api.mailgun.net/v3/demo.panw.co.uk/messages -F from='Palo Alto Networks <demo@demo.panw.co.uk>' -F to=jholland@paloaltonetworks.com -F subject='GCP HackLab Cloud Automation Demo Used by Someone - Started' -F html=' '"$message_txt"' '

	#read -n1 -r -p "Press any key to continue..." key

	# Copy source bootstrap file to working file
	cp bootstrap-orig.xml bootstrap.xml >> $logfile
	cp gcp_compute-orig gcp_compute.tf >> $logfile
	cp gcp_outputs-orig gcp_outputs.tf >> $logfile
	cp init-cfg-orig.txt init-cfg.txt >> $logfile

	# Insert MOTD, login banner, hostname
	sed -i "s/OLD-MSG-MOTD-HERE/$message/g" bootstrap.xml >> $logfile
	sed -i "s/OLD-MSG-LOGIN-HERE/$message/g" bootstrap.xml >> $logfile
	sed -i "s/gcp-fw/fw-$nickname-$subnet/g" init-cfg.txt >> $logfile
	sed -i "s/VM-FW1/fw-$uid-$nick_lower/g" gcp_compute.tf >> $logfile
	sed -i "s/KALI-VM1/kali-$uid-$nick_lower/g" gcp_compute.tf >> $logfile
	sed -i "s/LIN-VM1/linux-$uid-$nick_lower/g" gcp_compute.tf >> $logfile
	sed -i "s/DB-VM1/db-$uid-$nick_lower/g" gcp_compute.tf >> $logfile

	# Insert subnet octet, ensures unique subnets/IPs/names for components
	sed -i "s/xxyyzz/$subnet/g" bootstrap.xml >> $logfile
	sed -i "s/xxyyzz/$subnet/g" gcp_compute.tf >> $logfile
	sed -i "s/xxyyzz/$subnet/g" gcp_outputs.tf >> $logfile

	# Auth to GCP, set runtime variables
	gcloud auth activate-service-account --key-file=gcp_compute_key_svc_auto-hack-cloud.json
	gcloud config set project auto-hack-cloud

	# Upload bootstrap.xml and init-gfc bootstrap files - will overwrite already present file(s)
	gsutil cp bootstrap.xml gs://bootstrap-bucket/config/
	gsutil cp init-cfg.txt gs://bootstrap-bucket/config/
	
	#read -n1 -r -p "Press any key to continue..." key
	
	# Deploy via Terraform, in new directory for new Terraform state
	mkdir $uid
	cp *.tf $uid/
	cd $uid
	whoami >> $logfile
	pwd >> $logfile
	echo $PATH >> $logfile
	/usr/local/bin/terraform init >> ../$logfile
	/usr/local/bin/terraform apply --auto-approve >> ../$logfile
	cd ..
	deployed=$(date)
	
	# Timers
	ldeployed=$(date +%s)
	deploytime=$((ldeployed - lstart))
	deployminutes=$((deploytime / 60))
	deployseconds=$((deploytime % 60))
	deploytimedesc="$deployminutes minutes and $deployseconds seconds"

	# Set job to bootstrapping
    $(mysql -u $DBUSER -p$OURPASS -D gcp-autocloud -e "UPDATE jobs SET STATUS = 'Bootstrapping' WHERE JOB = '$uid';")
	$(mysql -u $DBUSER -p$OURPASS -D gcp-autocloud -e "UPDATE jobs SET DEPLOYTIME = '$deploytimedesc' WHERE JOB = '$uid';")

	# Find the public mgmt IP after deployment, and create a URL to test if the VM-Series is up yet
	#ip=`az network public-ip list --resource-group $resgrp | grep ipAddress | head -1 | awk '{match($0,/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/); ip = substr($0,RSTART,RLENGTH); print ip}'`
	#untrustip=`az network public-ip list --resource-group $resgrp | grep ipAddress | head -2 | tail -1 | awk '{match($0,/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/); ip = substr($0,RSTART,RLENGTH); print ip}'`
	#ip=`gcloud compute addresses list --filter="name=('mgmt-pip-'$subnet'')" | grep pip | awk '{match($0,/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/); ip = substr($0,RSTART,RLENGTH); print ip}'`
	#untrustip=`gcloud compute addresses list --filter="name=('outside-pip-'$subnet'')" | grep pip | awk '{match($0,/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/); ip = substr($0,RSTART,RLENGTH); print ip}'`
	ip=`gcloud compute instances list | grep fw- | grep $uid | awk -F"[ ,]+" '{print $8}'`
	untrustip=`gcloud compute instances list | grep fw- | grep $uid | awk -F"[ ,]+" '{print $9}'`
	kaliip=`gcloud compute instances list | grep kali | grep $uid | awk '{print $5}'`
	echo "fw-mgmt: ${ip}" >> $logfile
	echo "fw-ext: ${untrustip}" >> $logfile
	echo "kali: ${kaliip}" >> $logfile
	
	# Add IPs to database
	$(mysql -u $DBUSER -p$OURPASS -D gcp-autocloud -e "UPDATE jobs SET MGMTIP = '$ip' WHERE JOB = '$uid';")
	$(mysql -u $DBUSER -p$OURPASS -D gcp-autocloud -e "UPDATE jobs SET UNTRUSTIP = '$untrustip' WHERE JOB = '$uid';")
	$(mysql -u $DBUSER -p$OURPASS -D gcp-autocloud -e "UPDATE jobs SET KALIIP = '$kaliip' WHERE JOB = '$uid';")
	
	# Wait for VM-Series to be up (i.e. HTTP code not 000) before opening browser
	url="https://"$ip
	while [ `curl --write-out "%{http_code}\n" -m 2 -k --silent --output /dev/null $url` -eq 000 ]
	do
		echo "Waiting for firewall mgmt GUI page to be up..."
		sleep 5s
	done

	#read -n1 -r -p "Press any key to continue..." key

	# Timers
	lboot=$(date +%s)
	boottime=$((lboot - ldeployed))
	bootminutes=$((boottime / 60))
	bootseconds=$((boottime % 60))
	bootdesc="$bootminutes minutes and $bootseconds seconds"

	# Set job to configuring
	$(mysql -u $DBUSER -p$OURPASS -D gcp-autocloud -e "UPDATE jobs SET STATUS = 'Configuring' WHERE JOB = '$uid';")
	$(mysql -u $DBUSER -p$OURPASS -D gcp-autocloud -e "UPDATE jobs SET BOOTTIME = '$bootdesc' WHERE JOB = '$uid';")

	# Using BYOL means adding a licence auth code to the bootstrap folder, which incurs a reboot, so add wait time for this, and re-do the check for the firewall to be up
	sleep 120s
	while [ `curl --write-out "%{http_code}\n" -m 2 -k --silent --output /dev/null $url` -eq 000 ]
	do
		echo "Waiting for firewall mgmt GUI page to be up again after reboot incurred when applying auth code..."
		sleep 5s
	done

	#read -n1 -r -p "Press any key to continue..." key
	
	# Get new firewall's XML key
	#xmlresp=$(curl -k -X GET 'https://'$ip'/api/?type=keygen&user=panadmin&password='$OURPASS)
	#fwkey=$(sed -ne '/key/{s/.*<key>\(.*\)<\/key>.*/\1/p;q;}' <<< "$xmlresp")
	
	# Get new firewall's serial number
	#sysinfo=$(curl -k -X GET 'https://'$ip'/api/?type=op&cmd=<show><system><info></info></system></show>&key='$fwkey)
	#serial=$(sed -ne '/serial/{s/.*<serial>\(.*\)<\/serial>.*/\1/p;q;}' <<< "$sysinfo")	
	#echo "fw-api-key: ${fwkey}" >> $logfile
	#echo "fw-serial: ${serial}" >> $logfile

	# Stop the clock
	finish=$(date)
	
	# Record timings
	echo "Start     $start"
	echo "Deployed  $deployed"
	echo "Finished  $finish"
	
	#read -n1 -r -p "Press any key to continue..." key

	# Send SMS
    curl -X POST https://textbelt.com/text --data-urlencode phone=$phone --data-urlencode message="Hi $nickname, your deployment is done. Here's your firewall: $url Login with username user and password '"$USERPASS"'" -d key=$SMS >> $logfile
	
	# Send email
	#message_txt=$'Hi '"$nickname"',  Thanks for using the cloud automation demo. Your firewall was deployed to '"$url"' Login with username user and password '"$USERPASS"'     Kind regards, Palo Alto Networks      (Please contact '"$se"' for more information)'
	demourl="http://autocloud.panw.co.uk/autocloud-frontend/status.php?uid="$uid
	message_txt=$'Hi '"$nickname"',<br><br>Thanks for using the cloud automation demo. Your firewall was deployed to '"$url"' Login with username user and password '"$USERPASS"'<br>The demo website can be accessed at '"$demourl"'<br><br>Kind regards,<br>Palo Alto Networks<br><br>(Please contact '"$se"' for more information)'
	curl -s --user 'api:'"$MAILGUN"'' https://api.mailgun.net/v3/demo.panw.co.uk/messages -F from='Palo Alto Networks <demo@demo.panw.co.uk>' -F to=$email -F subject='Cloud Automation Demo - Palo Alto Networks' -F html=' '"$message_txt"' '
	curl -s --user 'api:'"$MAILGUN"'' https://api.mailgun.net/v3/demo.panw.co.uk/messages -F from='Palo Alto Networks <demo@demo.panw.co.uk>' -F to=jholland@paloaltonetworks.com -F subject='GCP HackLab Cloud Automation Demo Used by Someone - Completed' -F html=' '"$message_txt"' '
	
	# Timers
    	ldone=$(date +%s)
    	donetime=$((ldone - lboot))
    	doneminutes=$((donetime / 60))
    	doneseconds=$((donetime % 60))
    	if [ "$doneminutes" == "" ]
    	then
		donedesc="$doneseconds seconds"
	else
		donedesc="$doneminutes minutes and $doneseconds seconds"	
	fi
	$(mysql -u $DBUSER -p$OURPASS -D gcp-autocloud -e "UPDATE jobs SET DONETIME = '$donedesc' WHERE JOB = '$uid';")

	totaltime=$((ldone - lstart))
    	totalminutes=$((totaltime / 60))
    	totalseconds=$((totaltime % 60))
    	totaldesc="$totalminutes minutes and $totalseconds seconds"
	$(mysql -u $DBUSER -p$OURPASS -D gcp-autocloud -e "UPDATE jobs SET TOTALTIME = '$totaldesc' WHERE JOB = '$uid';")

	# Set job to done
	$(mysql -u $DBUSER -p$OURPASS -D gcp-autocloud -e "UPDATE jobs SET STATUS = 'Done' WHERE JOB = '$uid';")

	# Commit to Panorama after VM-series has fully attached etc
	#sleep 120s
	#curl -k -X GET 'https://demomatic-rama.panw.co.uk/api/?type=commit&cmd=<commit><description>Post-bootstrap</description></commit>&key=$RAMAKEY'
	
else	
	# There were no jobs ready, paus for 2 seconds before FOR loop kicks in again
	echo "No jobs ready" >> $logfile
	sleep 2s
fi

# End of for loop as we've done about a minute of checking for jobs, so exit script ready for next cron to initiate
done
exit 0
