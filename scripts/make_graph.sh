#!/bin/bash

# Author: Michael Luker
# Project: SlurmGraphing
# Version: 1.0 (Speculative Sanderling)
# Date: August 10, 2014

#Get the current date
END=$(($(date +%s)))

source CONFFILE

#Set up variables to the specified rrd file, could be for cores, jobs or partition
NAME=$1
TYPE=$2
PERI=$3
TEMP1='_group.rrd'
TEMP2='_part_queue.rrd'
TEMP3='_part_corejob.rrd'
TEMP4='_node.rrd'
CRRD="$rrd_loc/$NAME$TEMP1"
JRRD="$rrd_loc/$NAME$TEMP3"
PRRD="$rrd_loc/$NAME$TEMP2"
NRRD="$rrd_loc/$NAME$TEMP4"

#Interpret the slider value as a period of time between now and the amount given (number in seconds given by the almighty Google)
if [ "$PERI" != "manual" ]; then
	case "$PERI" in
	"hour") BEG=$(($(date +%s)-3600));;
	"day") BEG=$(($(date +%s)-86400));;
	"week") BEG=$(($(date +%s)-604800));;
	"month") BEG=$(($(date +%s)-2419200));;
	"year") BEG=$(($(date +%s)-29030400));;
	"twoyear") BEG=$(($(date +%s)-58060800));;
	esac
fi

#Make a graph of the requested type, these aren't tricky commands just very verbose
case "$TYPE" in
"cores")rrdtool graph GRAPHDIR/slurm-$NAME-$TYPE-$PERI.png -z --full-size-mode --width 500 --height 200 --start $BEG --end $END --step 60 --title "$NAME:cores:$PERI" --color CANVAS#A0A0A0 --lower-limit 0 DEF:busy=$CRRD:busy:LAST DEF:idle=$CRRD:idle:LAST DEF:offline=$CRRD:offline:LAST AREA:busy#0200B3:"Busy" STACK:idle#406D00:"Idle" STACK:offline#B30000:"Offline" >> $log_loc/graph.log >&1;; 
"corejob")rrdtool graph GRAPHDIR/slurm-$NAME-$TYPE-$PERI.png -z --full-size-mode --width 500 --height 200 --start $BEG --end $END --step 60 --title "$NAME:core/job:$PERI" --color CANVAS#A0A0A0 --lower-limit 0 DEF:r1=$JRRD:R1:LAST DEF:r2=$JRRD:R2:LAST DEF:r3=$JRRD:R3:LAST DEF:r4=$JRRD:R4:LAST DEF:r5=$JRRD:R5:LAST DEF:r6=$JRRD:R6:LAST DEF:r7=$JRRD:R7:LAST DEF:r8=$JRRD:R8:LAST DEF:r9=$JRRD:R9:LAST DEF:r10=$JRRD:R10:LAST DEF:r11=$JRRD:R11:LAST AREA:r1#B30000:"1" STACK:r2#FFFFFF:"2" STACK:r3#0A0A0A:"3-4" STACK:r4#60006B:"5-8" STACK:r5#1400B2:"9-16" STACK:r6#2F9DB1:"17-32" STACK:r7#406D00:"33-64" STACK:r8#FEFF00:"65-128" STACK:r9#A26407:"129-256" STACK:r10#49FFCC:"257-512" STACK:r11#F200CF:">512" >> $log_loc/graph.log >&2;;
"jobs")rrdtool graph GRAPHDIR/slurm-$NAME-$TYPE-$PERI.png -z --logarithmic --units=si --lower-limit 1 -r --full-size-mode --width 500 --height 200 --start $BEG --end $END --step 60 --title "$NAME:partition:$PERI" --color CANVAS#A0A0A0 DEF:queued=$PRRD:queued:LAST DEF:running=$PRRD:running:LAST AREA:queued#B30000:"Queued" STACK:running#0200B3:"Running" >> $log_loc/graph.log >&2;; 
"node")rrdtool graph GRAPHDIR/slurm-$NAME-$TYPE-$PERI.png -z -g --full-size-mode --width 250 --height 100 --start $BEG --end $END --step 60 --title "$NAME" --color CANVAS#A0A0A0 --lower-limit 0 DEF:busy=$NRRD:busy:LAST DEF:idle=$NRRD:idle:LAST DEF:offline=$NRRD:offline:LAST AREA:busy#0200B3:"Busy" STACK:idle#406D00:"Idle" STACK:offline#B30000:"Offline" >> $log_loc/graph.log >&2;; 
esac

