#!/bin/bash

#Read the .conf file
source ./sgraphing.conf


## Segmented List Parsing ##
############################
function parseList(){
	#Get a function to call and list to parse
	func=$1
	shift
	list=("$@")
	
	#Check if the list is long enough to segment
	total_length="${#list[@]}"
	if [ "$total_length" -gt "64" ] && [ "$(nproc)" -gt "1" ]; then
		segs=$max_segs
	else
		segs=1
	fi
	
	#Get the length and remainder for the segments to use
	remainder=$(($total_length%$segs))
	seg_length=$((total_length/$segs))
	
	#Call the function sent and send which segment this is, its length & remainder, and the list
	for segment in $(seq "0" $((segs-1))); do
		if [[ "$segment" -eq "7" ]]; then
			$func $segment $seg_length $remainder "${list[@]}" &
		else
			$func $segment $seg_length "0" "${list[@]}" &
		fi
	done
	
	#Return how many segments were used so results can be put back together
	echo "$segs"
}

## Getting Node Information ##
##############################
configuredNode() {
	#Check the target node agains the list of configured nodes
	target=$1
	for item in "${nodelist[@]}"; do 
		if [[ $target == $item ]]; then 
			return 1;
		fi; 
	done
	return 0
}
function parseNode() {
	#Get arguments sent from the parseList function
	segment=$1
	seg_length=$2
	remainder=$3
	#Make sure above arguments don't show up in the list
	shift
	shift
	shift
	list=("$@")

	#Calculate the starting and ending points of the segment
	start=$(($segment*$seg_length))
	end=$(($segment*$seg_length+$seg_length+$remainder-1))

	#Clear (or create) the file where results will be put
	> /tmp/parseNode.$segment

	#Look at items between start and end, make sure it's configured then
	#  print it to the outfile for reconstruction later
	for index in `seq $start $end`; do
		item=$(echo ${list[$index]})
		item=($(echo ${item//,/ }))
		name=$(echo ${item[0]} | cut -f2 -d '=')
		alloc=$(echo ${item[3]} | cut -f2 -d '=')
		tot=$(echo ${item[5]} | cut -f2 -d '=')
		state=$(echo ${item[17]} | cut -f2 -d '=')
		configuredNode "$name"
		if [[ $? == 1 ]]; then
			echo "$name,$alloc,$tot,$state" >> /tmp/parseNode.$segment
		fi
	done
}
function get_node_info() {
	#Call scontrol to get current node info, remove spaces (newline will
	# not be affected) to group each node into 1 item in a list for speedup
	#output=$($slurm_bin/scontrol show node -o | sed 's/ /,/g')
	
	# At home, need to read file instead of calling scontrol
	#output=(`cat ./large_node_info.txt`)
	output=(`cat ./nodeInfo.txt`)
	
	#Concurrently parse output to remove uneeded info
	segs=$(parseList "parseNode" "${output[@]}")
	
	#Wait for parsing to complete
	wait
	
	#Combine results and return them
	for x in $(seq 0 $((segs-1))); do
		if [[ -a "/tmp/parseNode.$x" ]]; then
			temp=($(cat /tmp/parseNode.$x))
			combined=("${combined[@]}" "${temp[@]}")
		fi
	done
	echo "${combined[@]}"
}

## Getting Job Information ##
#############################
function get_job_info() {
	#Call squeue with some arguments to only get info needed
	#output=(`$slurm_bin/squeue -h -o '%P,%t,%C'`)
	
	#output=(`cat ./large_job_info.txt`)
	#output=(`cat ./medium_job_info.txt`)
	output=(`cat ./jobInfo.txt`)
	#output=(`cat ./small_job_info.txt`)
	
	echo ${output[@]}
}

## RRD Update Functions ##
##########################
function totalNodeSeg() {
	#Same beginning as other functions used in parseList
	segment=$1
	seg_length=$2
	remainder=$3
	#Make sure above arguments don't show up in the list
	shift
	shift
	shift
	list=("$@")

	start=$(($segment*$seg_length))
	end=$(($segment*$seg_length+$seg_length+$remainder-1))

	> /tmp/totalNodeSeg.$segment

	busy=0
	idle=0
	down=0

	#For each item find busy, idle, down cores and add them up
	for index in `seq $start $end`; do
		item=($(echo ${list[$index]} | sed 's/,/ /g'))
		name=$(echo ${item[0]})
		alloc=$(echo ${item[1]})
		tot=$(echo ${item[2]})
		state=$(echo ${item[3]})
		
		busy=$((busy+alloc))
		
		if [ "$state" == "ALLOCATED" ] || [ "$state" == "IDLE" ] || [ "$state" == "MIXED" ]; then
			temp=$((tot-alloc))
			idle=$((idle+temp))
		else
			temp=$((tot-alloc))
			down=$((down+temp))
		fi
		
	done
	
	echo "$busy-$idle-$down" > /tmp/totalNodeSeg.$segment
}
function node_total() {
	#Get the node info
	array=("$@")
	
	totBusy=0
	totIdle=0
	totDown=0
	
	#Parse the node info to get total busy, idle, and down cores
	segs=$(parseList "totalNodeSeg" "${array[@]}")
	wait
	
	#Construct results
	for x in $(seq 0 $((segs-1))); do
		if [[ -a "/tmp/totalNodeSeg.$x" ]]; then
			temp=($(cat /tmp/totalNodeSeg.$x | sed 's/-/ /g'))
			t_b="${temp[0]}"
			t_i="${temp[1]}"
			t_d="${temp[2]}"
			totBusy=$((totBusy+t_b))
			totIdle=$((totIdle+t_i))
			totDown=$((totDown+t_d))
		fi
	done

	#Set where some logging output goes to
	case "$log_level" in
	0)
	  verbose_logging=/dev/null
	  minimal_logging=/dev/null
	;;
	1)
	  verbose_logging=/dev/null
	  minimal_logging=$log_loc/all_total_cpu.log 2>&1
	;;
	2) 
	  verbose_logging=$log_loc/all_total_cpu.log 2>&1
	  minimal_logging=$log_loc/all_total_cpu.log 2>&1
	;;
	esac
	
	#Update and Report
	echo "`date +%s`-$totBusy-$totIdle-$totDown" #>> $verbose_logging
#	rrdtool update $rrd_loc/all_group.rrd -t busy:idle:offline `date +%s`:$totAlloc:$totIdle:$totDown >> $minimal_logging &
}
function groupNodeSeg() {
	#parseList beginning
	segment=$1
	seg_length=$2
	remainder=$3
	#Make sure above arguments don't show up in the list
	shift
	shift
	shift
	list=("$@")

	#Find start and end points for this segment, then clear the out file
	start=$(($segment*$seg_length))
	end=$(($segment*$seg_length+$seg_length+$remainder-1))

	> /tmp/groupNodeSeg.$segment
	
	busy=0
	idle=0
	down=0
	
	#Set up a dictionary for each group to have 3 variables available
	declare -A dictionary
	for grp in "${grouplist[@]}"; do		
		dictionary["$grp-b"]=0
		dictionary["$grp-i"]=0
		dictionary["$grp-d"]=0
	done

	#For each item find busy, idle, down cores, and add them up
	for index in `seq $start $end`; do
		item=($(echo ${list[$index]} | sed 's/,/ /g'))
		name=$(echo ${item[0]})
		alloc=$(echo ${item[1]})
		tot=$(echo ${item[2]})
		state=$(echo ${item[3]})
		
		busy=$alloc
		
		if [ "$state" == "ALLOCATED" ] || [ "$state" == "IDLE" ] || [ "$state" == "MIXED" ]; then
			temp=$((tot-alloc))
			idle=$temp
		else
			temp=$((tot-alloc))
			down=$temp
		fi
		
		#Find which group this node belongs to and add to busy-idle-down
		
		# This part may need to be modified later to be more abstract
		
		#Remove any numbers and special characters from the name to get a group name
		grp=$(echo $name | sed 's/[0-9!@#$%^&*)(_+=-].*//g')
		
		#Check to see if it's a group that's configured
		contains() {
			t1=$1
			shift
			l=("$@")
			for i in ${l[@]}; do
				if 
			done
			#[[ ${l[@]} =~ $t1 ]] && echo "true" || echo "false"
		}
		
		inGroup=$(contains $grp ${grouplist[@]})
		
		#If it's configured add it to the proper place in the dictionary
		if [[ "$inGroup" == "true" ]]; then
			dictionary["$grp-b"]=$((dictionary[$T_busy]+busy))
			dictionary["$grp-i"]=$((dictionary[$T_idle]+idle))
			dictionary["$grp-d"]=$((dictionary[$T_down]+down))
		fi
	done

	#Write the results of each group to a temp file
	for grp in "${grouplist[@]}"; do		
		echo "$group-${dictionary[$grp-b]}-${dictionary[$grp-i]}-${dictionary[$grp-d]}" >> /tmp/groupNodeSeg.$segment
	done
}
function node_group() {
	#Get node info
	array=("$@")

	#Parse node info to get group breakdown of data
	segs=$(parseList "groupNodeSeg" "${array[@]}")
	wait

	#Set up the dictionary to put results in
	declare -A dictionary
	for grp in "${grouplist[@]}"; do		
		dictionary["$grp-b"]=0
		dictionary["$grp-i"]=0
		dictionary["$grp-d"]=0
	done

	#Read in results line by line, chop it up and store in dictionary
	for x in $(seq 0 $((segs-1))); do
		temp=(`cat /tmp/groupNodeSeg.$x`)
		for line in "${temp[@]}"; do
			items=(`echo $line | sed 's/-/ /g'`)
			grp=${items[0]}
			busy=${items[1]}
			idle=${items[2]}
			down=${items[3]}

			dictionary["$grp-b"]=$((dictionary["$grp-b"]+busy))
			dictionary["$grp-i"]=$((dictionary["$grp-i"]+idle))
			dictionary["$grp-d"]=$((dictionary["$grp-d"]+down))
		done
	done

	#Set log output
	for grp in "${grouplist[@]}"; do
		case "$log_level" in
		0)
		  verbose_logging=/dev/null
		  minimal_logging=/dev/null
		;;
		1)
		  verbose_logging=/dev/null
		  minimal_logging=$log_loc/"$group"_group.log
		;;
		2) 
		  verbose_logging=$log_loc/"$group"_group.log 2>&1
		  minimal_logging=$log_loc/"$group"_group.log 2>&1
		;;
		esac
		
		#Update and Report
		echo "`date +%s`-${dictionary[$grp-b]}-${dictionary[$grp-i]}-${dictionary[$grp-d]}" #>> $verbose_logging
		#rrdtool update $rrd_loc/"$group"_group.rrd -t busy:idle:offline `date +%s`:${dictionary[$T_busy]}:${dictionary[$T_idle]}:${dictionary[$T_down]} >> $minimal_logging &
	done
}
function node_indiv() {
	#parseList beginning, without regular parseList function name
	segment=$1
	seg_length=$2
	remainder=$3
	#Make sure above arguments don't show up in the list
	shift
	shift
	shift
	list=("$@")
	
	start=$(($segment*$seg_length))
	end=$(($segment*$seg_length+$seg_length+$remainder-1))
	
	#For each node all that's needed is to chop up the input line and store it in its RRD file
	for index in $(seq $start $end); do
		node="${list[$index]}"
		nodeName=$(echo $node | cut -f1 -d ',')
		nodeAlloc=$(echo $node | cut -f2 -d ',')
		nodeIdle=$(echo $node | cut -f3 -d ',')
		nodeDown=$(echo $node | cut -f4 -d ',')

		case "$log_level" in
		0)
		  verbose_logging=/dev/null
		  minimal_logging=/dev/null
		;;
		1)
		  verbose_logging=/dev/null
		  minimal_logging=$log_loc/$nodeName_node.log
		;;
		2) 
		  verbose_logging=$log_loc/"$nodeName"_node.log 2>&1
		  minimal_logging=$log_loc/"$nodeName"_node.log 2>&1
		;;
		esac
		
		echo "`date +%s`-$nodeAlloc-$nodeIdle-$nodeDown" #>> $verbose_logging
		#rrdtool update $rrd_loc/"$nodeName"_node.rrd -t busy:idle:offline `date +%s`:$nodeAlloc:$nodeIdle:$nodeDown >> $minimal_logging &
	done
}
function totalPartSeg() {
	#parseList beginning
	segment=$1
	seg_length=$2
	remainder=$3
	#Make sure above arguments don't show up in the list
	shift
	shift
	shift
	array=("$@")
	
	start=$(($segment*$seg_length))
	end=$(($segment*$seg_length+$seg_length+$remainder-1))

	totQueued=0
	totRunning=0
	r1=0
	r2=0
	r3_4=0
	r5_8=0
	r9_16=0
	r17_32=0
	r33_64=0
	r65_128=0
	r129_256=0
	r257_512=0
	rGT512=0
	
	#Look at each job, check its state, and if it's turned on add to the proper corejob category
	for index in $(seq $start $end); do
		jobState=$(echo "${array[$index]}" | cut -f2 -d ',')
		case "$jobState" in
			"PD") totQueued=$(($totQueued + 1));;
			"R") totRunning=$(($totRunning + 1));;
		esac

		if [[ "$corejob_graphing" == "true" ]] && [[ $jobState == "R" ]]; then
			jobCores=$(echo  "${array[$index]}" | cut -f3 -d ',')
			if [[ $jobCores == 1 ]]; then r1=$(($r1 + 1)); fi
			if [[ $jobCores == 2 ]]; then r2=$(($r2 + 2)); fi
			if [[ $jobCores -ge 3 && $jobCores -le 4 ]]; then r3_4=$(($r3_4 + $jobCores)); fi
			if [[ $jobCores -ge 5 && $jobCores -le 8 ]]; then r5_8=$(($r5_8 + $jobCores)); fi
			if [[ $jobCores -ge 9 && $jobCores -le 16 ]]; then r9_16=$(($r9_16 + $jobCores)); fi
			if [[ $jobCores -ge 17 && $jobCores -le 32 ]]; then r17_32=$(($r17_32 + $jobCores)); fi
			if [[ $jobCores -ge 33 && $jobCores -le 64 ]]; then r33_64=$(($r33_64 + $jobCores)); fi
			if [[ $jobCores -ge 65 && $jobCores -le 128 ]]; then r65_128=$(($r65_128 + $jobCores)); fi
			if [[ $jobCores -ge 129 && $jobCores -le 256 ]]; then r129_256=$(($r129_256 + $jobCores)); fi
			if [[ $jobCores -ge 257 && $jobCores -le 512 ]]; then r257_512=$(($r257_512 + $jobCores)); fi
			if [[ $jobCores -gt 512 ]]; then rGT512=$(($rGT512 + $jobCores)); fi		
		fi
	done

	#Write to segment
	echo "$totQueued-$totRunning-$r1-$r2-$r3_4-$r5_8-$r9_16-$r17_32-$r33_64-$r65_128-$r129_256-$r257_512-$rGT512" > /tmp/totalPartSeg.$segment
}
function part_total() {
	#Get job info
	array=("$@")

	#Parse job info
	segs=$(parseList "totalPartSeg" "${array[@]}")
	wait
	
	#Reconstruct results
	for segment in $(seq "0" $(($segs-1))); do
		loc=/tmp/totalPartSeg.$segment
		t_q="$(cat $loc | cut -f1 -d '-')"
		t_r="$(cat $loc | cut -f2 -d '-')"
		totQueued=$(($totQueued+$t_q))
		totRunning=$(($totRunning+$t_r))
		
		if [[ "$corejob_graphing" == "true" ]]; then
			t_r1="$(cat $loc | cut -f3 -d '-')"
			t_r2="$(cat $loc | cut -f4 -d '-')"
			t_r3_4="$(cat $loc | cut -f5 -d '-')"
			t_r5_8="$(cat $loc | cut -f6 -d '-')"
			t_r9_16="$(cat $loc | cut -f7 -d '-')"
			t_r17_32="$(cat $loc | cut -f8 -d '-')"
			t_r33_64="$(cat $loc | cut -f9 -d '-')"
			t_r65_128="$(cat $loc | cut -f10 -d '-')"
			t_r129_256="$(cat $loc | cut -f11 -d '-')"
			t_r257_512="$(cat $loc | cut -f12 -d '-')"
			t_rGT512="$(cat $loc | cut -f13 -d '-')"
			r1=$(($r1+$t_r1))
			r2=$(($r2+$t_r2)) 
			r3_4=$(($r3+$t_r3_4))
			r5_8=$(($r5_8+$t_r5_8))
			r9_16=$(($r9_16+$t_r9_16))
			r17_32=$(($r17_32+$t_r17_32))
			r33_64=$(($r33_64+$t_r33_64))
			r65_128=$(($r65_128+$t_r65_128))
			r129_256=$(($r129_256+$t_r129_256))
			r257_512=$(($r257_512+$t_r257_512))
			rGT512=$(($rGT512+$t_rGT512))
		fi
	done

	#Set log output location
	case "$log_level" in
		0)
		  verbose_logging=/dev/null
		  minimal_logging=/dev/null
		;;
		1)
		  verbose_logging=/dev/null
		  minimal_logging=$log_loc/all_part.log
		;;
		2) 
		  verbose_logging=$log_loc/all_part.log 2>&1
		  minimal_logging=$log_loc/all_part.log 2>&1
		;;
	esac

	#Update and report based on what's being tracked
	if [[ "$corejob_graphing" == "true" ]]; then
		  echo "`date +%s`-$totQueued-$totRunning-$r1-$r2-$r3_4-$r5_8-$r9_16-$r17_32-$r33_64-$r65_128-$r129_256-$r257_512-$rGT512" #>> $verbose_logging
#		  rrdtool update $rrd_loc/all_part_corejob.rrd -t R1:R2:R3:R4:R5:R6:R7:R8:R9:R10:R11 `date +%s`:$r1:$r2:$r3_4:$r5_8:$r9_16:$r17_32:$r33_64:$r65_128:$r129_256:$r257_512:$rGT512 >> $minimal_logging &
#		  rrdtool update $rrd_loc/all_part_queue.rrd -t queued:running `date +%s`:$totQueued:$totRunning >> $minimal_logging &

	else
		  echo "`date +%s`-$totQueued-$totRunning" #>> $verbose_logging
#		  rrdtool update $rrd_loc/all_part_queue.rrd -t queued:running `date +%s`:$totQueued:$totRunning >> $minimal_logging &
	fi
}
function indivPartSeg() {
	#parseList beginning
	segment=$1
	seg_length=$2
	remainder=$3
	#Make sure above arguments don't show up in the list
	shift
	shift
	shift
	array=("$@")
	
	start=$(($segment*$seg_length))
	end=$(($segment*$seg_length+$seg_length+$remainder-1))
	
	> /tmp/indivPartSeg.$segment
	
	r1=0
	r2=0
	r3_4=0
	r5_8=0
	r9_16=0
	r17_32=0
	r33_64=0
	r65_128=0
	r129_256=0
	r257_512=0
	rGT512=0
	
	#Set up a dictionary for each partition
	declare -A dictionary
	for part in "${partitionlist[@]}"; do
		dictionary["$part-q"]=0
		dictionary["$part-r"]=0
		if [[ $corejob_graphing == "true" ]]; then
			dictionary["$part-1"]=0
			dictionary["$part-2"]=0
			dictionary["$part-3"]=0
			dictionary["$part-4"]=0
			dictionary["$part-5"]=0
			dictionary["$part-6"]=0
			dictionary["$part-7"]=0
			dictionary["$part-8"]=0
			dictionary["$part-9"]=0
			dictionary["$part-10"]=0
			dictionary["$part-11"]=0
		fi
	done
	
	#For each job add to the partition it's in
	for index in $(seq $start $end); do
		part=$(echo "${array[$index]}" | cut -f1 -d ',')
		
		#Might re-write this to be like other similar sections
		inPart="false"
		for item in ${partitionlist[@]}; do
			if [[ "$part" == "$item" ]]; then 
				inPart="true"
				break
			fi
		done
		
		if [[ "$inPart" == "false" ]]; then break; fi
		
		jobState=$(echo "${array[$index]}" | cut -f2 -d ',')
		case "$jobState" in
			"PD") dictionary["$part-q"]=$((dictionary["$part-q"]+1));;
			"R") dictionary["$part-r"]=$((dictionary["$part-r"]+1));;
		esac

		if [[ "$corejob_graphing" == "true" ]] && [[ "$jobState" == "R" ]]; then
			jobCores=$(echo  "${array[$index]}" | cut -f3 -d ',')
			if [[ $jobCores == 1 ]]; then dictionary["$part-1"]=$((dictionary["$part-1"]+1)); fi
			if [[ $jobCores == 2 ]]; then dictionary["$part-2"]=$((dictionary["$part-2"]+2)); fi
			if [[ $jobCores -ge 3 && $jobCores -le 4 ]]; then dictionary["$part-3"]=$((dictionary["$part-3"]+$jobCores)); fi
			if [[ $jobCores -ge 5 && $jobCores -le 8 ]]; then dictionary["$part-4"]=$((dictionary["$part-4"]+$jobCores)); fi
			if [[ $jobCores -ge 9 && $jobCores -le 16 ]]; then dictionary["$part-5"]=$((dictionary["$part-5"]+$jobCores)); fi
			if [[ $jobCores -ge 17 && $jobCores -le 32 ]]; then dictionary["$part-6"]=$((dictionary["$part-6"]+$jobCores)); fi
			if [[ $jobCores -ge 33 && $jobCores -le 64 ]]; then dictionary["$part-7"]=$((dictionary["$part-7"]+$jobCores)); fi
			if [[ $jobCores -ge 65 && $jobCores -le 128 ]]; then dictionary["$part-8"]=$((dictionary["$part-8"]+$jobCores)); fi
			if [[ $jobCores -ge 129 && $jobCores -le 256 ]]; then dictionary["$part-9"]=$((dictionary["$part-9"]+$jobCores)); fi
			if [[ $jobCores -ge 257 && $jobCores -le 512 ]]; then dictionary["$part-10"]=$((dictionary["$part-10"]+$jobCores)); fi
			if [[ $jobCores -gt 512 ]]; then dictionary["$part-11"]=$((dictionary["$part-11"]+$jobCores)); fi
		fi
	done

	for p in "${partitionlist[@]}"; do
		if [[ "$corejob_graphing" == "true" ]]; then
			echo "$p-${dictionary[$p-q]}-${dictionary[$p-r]}-${dictionary[$p-1]}-${dictionary[$p-2]}-${dictionary[$p-3]}-${dictionary[$p-4]}-${dictionary[$p-5]}-${dictionary[$p-6]}-${dictionary[$p-7]}-${dictionary[$p-8]}-${dictionary[$p-9]}-${dictionary[$p-10]}-${dictionary[$p-11]}" >> /tmp/indivPartSeg.$segment
		else
			echo "$p-${dictionary[$p-q]}-${dictionary[$p-r]}" >> /tmp/indivPartSeg.$segment
		fi
	done
}
function part_indiv() {
	#Get job info
	array=("$@")
	
	#Parse job info
	segs=$(parseList "indivPartSeg" "${array[@]}")
	wait
	
	#Create dictionary for each partition
	declare -A dictionary
	for part in "${partitionlist[@]}"; do
		dictionary["$part-q"]=0
		dictionary["$part-r"]=0
		if [[ $corejob_graphing == "true" ]]; then
			dictionary["$part-1"]=0
			dictionary["$part-2"]=0
			dictionary["$part-3"]=0
			dictionary["$part-4"]=0
			dictionary["$part-5"]=0
			dictionary["$part-6"]=0
			dictionary["$part-7"]=0
			dictionary["$part-8"]=0
			dictionary["$part-9"]=0
			dictionary["$part-10"]=0
			dictionary["$part-11"]=0
		fi
	done
	
	#Reconstruct results
	for x in $(seq 0 $((segs-1))); do
		temp=(`cat /tmp/indivPartSeg.$x`)
		for line in "${temp[@]}"; do
			part=$(echo $line | cut -f1 -d '-')
			t_q=$(echo $line | cut -f2 -d '-')
			t_r=$(echo $line | cut -f3 -d '-')
			dictionary["$part-q"]=$((dictionary["$part-q"]+t_q))
			dictionary["$part-r"]=$((dictionary["$part-r"]+t_r))
			
			if [[ "$corejob_graphing" == "true" ]]; then
				t_1=$(echo $line | cut -f4 -d '-')
				t_2=$(echo $line | cut -f5 -d '-')
				t_3=$(echo $line | cut -f6 -d '-')
				t_4=$(echo $line | cut -f7 -d '-')
				t_5=$(echo $line | cut -f8 -d '-')
				t_6=$(echo $line | cut -f9 -d '-')
				t_7=$(echo $line | cut -f10 -d '-')
				t_8=$(echo $line | cut -f11 -d '-')
				t_9=$(echo $line | cut -f12 -d '-')
				t_10=$(echo $line | cut -f13 -d '-')
				t_11=$(echo $line | cut -f14 -d '-')
				dictionary["$part-1"]=$((dictionary["$part-1"]+t_1))
				dictionary["$part-2"]=$((dictionary["$part-2"]+t_2))
				dictionary["$part-3"]=$((dictionary["$part-3"]+t_3))
				dictionary["$part-4"]=$((dictionary["$part-4"]+t_4))
				dictionary["$part-5"]=$((dictionary["$part-5"]+t_5))
				dictionary["$part-6"]=$((dictionary["$part-6"]+t_6))
				dictionary["$part-7"]=$((dictionary["$part-7"]+t_7))
				dictionary["$part-8"]=$((dictionary["$part-8"]+t_8))
				dictionary["$part-9"]=$((dictionary["$part-9"]+t_9))
				dictionary["$part-10"]=$((dictionary["$part-10"]+t_10))
				dictionary["$part-11"]=$((dictionary["$part-11"]+t_11))
			fi
			
		done
	done

	#Update RRD file for each partition
	for part in ${partitionlist[@]}; do
		case "$log_level" in
			0)
			  verbose_logging=/dev/null
			  minimal_logging=/dev/null
			;;
			1)
			  verbose_logging=/dev/null
			  minimal_logging=$log_loc/all_part.log
			;;
			2) 
			  verbose_logging=$log_loc/"$part"_part.log 2>&1
			  minimal_logging=$log_loc/"$part"_part.log 2>&1
			;;
		esac

		if [[ "$corejob_graphing" == "true" ]]; then
			  echo `date +%s`-${dictionary["$part-q"]}-${dictionary["$part-r"]}-${dictionary["$part-1"]}-${dictionary["$part-2"]}-${dictionary["$part-3"]}-${dictionary["$part-4"]}-${dictionary["$part-5"]}-${dictionary["$part-6"]}-${dictionary["$part-7"]}-${dictionary["$part-8"]}-${dictionary["$part-9"]}-${dictionary["$part-10"]}-${dictionary["$part-11"]} #>> $verbose_logging
			  #rrdtool update $rrd_loc/"$part"_part_corejob.rrd -t R1:R2:R3:R4:R5:R6:R7:R8:R9:R10:R11 `date +%s`:$r1:$r2:$r3_4:$r5_8:$r9_16:$r17_32:$r33_64:$r65_128:$r129_256:$r257_512:$rGT512 >> $minimal_logging &
			  #rrdtool update $rrd_loc/"$part"_part_queue.rrd -t queued:running `date +%s`:$totQueued:$totRunning >> $minimal_logging &
		else
			  echo `date +%s`-${dictionary[$part-q]}-${dictionary[$part-r]} #>> $verbose_logging
			  #rrdtool update $rrd_loc/"$part"_part_queue.rrd -t queued:running `date +%s`:$totQueued:$totRunning >> $minimal_logging &
		fi
	done
}

## Main Program Commands ##
###########################
#Get the information on the nodes and jobs
if [ "$node_totaling" == "true" ] || [ $group_graphing == "true" ] || [ $node_graphing == "true" ]; then
	node_info=($(get_node_info))
fi
if [ "$part_totaling" == "true" ] || [ $partition_graphing == "true" ]; then
	job_info=($(get_job_info))
fi

#Check what's configured to update and call the functions needed as background processes
if [[ "$node_totaling" == "true" ]]; then
		node_total "${node_info[@]}" &
fi

if [[ "$part_totaling" == "true" ]]; then
		part_total "${job_info[@]}" &
fi

if [[ "$group_graphing" == "true" ]]; then
		node_group "${node_info[@]}" &
fi

if [[ "$node_graphing" == "true" ]]; then
		#No data dependency, doesn't need a host function to run, returned # of segments can be thrown out
		parseList "node_indiv" "${node_info[@]}" >/dev/null &
fi

if [[ "$partition_graphing" == "true" ]]; then
	part_indiv "${job_info[@]}" &
fi

wait
