#!/bin/bash


# Initialise logging
logfile="gcp-clearup-log.txt"
exec &>> $logfile
now="$(date)"
printf "\n*** Clearing up GCP Running Instances on `date` ***\n\n" >> $logfile


# Ensure we're in the right place in GCP
gcloud config set project auto-hack-cloud
gcloud config set compute/zone europe-west2-b


# Take note of all the VMs currently present
printf "\nCurrent list of VM instances:\n" >> $logfile
gcloud compute instances list >> $logfile


# Cycle through all running VMs...
for vm in `gcloud compute instances list | grep RUNNING | awk '{print $1}'`; do
	printf "\nGoing to shut down $vm\n" >> $logfile
	#...and shut them down
	gcloud compute instances stop $vm
done


# Take another note of all the VMs, to compare against before the shutdown commands
printf "\nUpdated list of VM instances:\n" >> $logfile
gcloud compute instances list >> $logfile
printf "\n\n\n\n" >> $logfile
