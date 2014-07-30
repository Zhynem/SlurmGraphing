#!/bin/bash

#Read the .conf file
source ./sgraphing.conf

#-------------------------------------
#------ Concurrent List Parsing ------
#-------------------------------------
function parseList(){
	#Get a function to call and list of things to call it on
	func=$1
	shift
	list=("$@")
	
	#Make sure we can make use of concurrent parsing
	total_length="${#list[@]}"
	if [ "$total_length" -gt "64" ] && [ "$(nproc)" -gt "1" ]; then
		segs=$max_segs
	else
		segs=1
	fi
	
	#Check to see how evenly it splits
	remainder=$(($total_length%$segs))
	seg_length=$((total_length/$segs))
	
	#Start concurrent parsing, call the function and send some arguments
	for segment in $(seq "0" $((segs-1))); do
		if [[ "$segment" -eq "7" ]]; then
			$func $segment $seg_length $remainder "${list[@]}" &
		else
			$func $segment $seg_length "0" "${list[@]}" &
		fi
	done
	
	echo "$segs"
}

#-------------------------------------
#------ Getting Node Information -----
#-------------------------------------
configuredNode() {
	#Get a target node and check it against the list of configured nodes
	target=$1
	for item in "${nodelist[@]}"; do 
		if [[ $target == $item ]]; then 
			return 1;
		fi; 
	done
	return 0
}
function parseNode() {
	#Find out what segment we are, the length to look at, and if there's
	#  a remainder we have
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
	output=(`cat ./large_node_info.txt`)
	#output=(`cat ./nodeInfo.txt`)
	
	#len=$((${#output[@]}-1))
	#Try to concurrently parse the list for best speed
	segs=$(parseList "parseNode" "${output[@]}")
	
	#Wait until it finished before reconstructing the list
	wait
	
	for x in $(seq 0 $((segs-1))); do
		if [[ -a "/tmp/parseNode.$x" ]]; then
			temp=($(cat /tmp/parseNode.$x))
			combined=("${combined[@]}" "${temp[@]}")
		fi
	done
	echo "${combined[@]}"
}

#--------------------------------------
#------  Getting Job Information  -----
#--------------------------------------
function get_job_info() {
	#output=(`$slurm_bin/squeue -h -o '%P,%t,%C'`)
	#output=(`cat ./large_job_info.txt`)
	output=(`cat ./medium_job_info.txt`)
	#output=(`cat ./jobInfo.txt`)
	echo ${output[@]}
}

#--------------------------------------
#-------- RRD Update Functions --------
#--------------------------------------
function totalNodeSeg() {
	#Find out what segment we are, the length to look at, and if there's
	#  a remainder we have
	segment=$1
	seg_length=$2
	remainder=$3
	#Make sure above arguments don't show up in the list
	shift
	shift
	shift
	list=("$@")

	busy=0
	idle=0
	down=0

	#Find start and end points for this segment, then clear the out file
	start=$(($segment*$seg_length))
	end=$(($segment*$seg_length+$seg_length+$remainder-1))

	> /tmp/totalNodeSeg.$segment

	#For each item find busy, idle, down cores, add them up and send them
	#  to a temp file
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
	#Get the node info array and init some variables
	array=("$@")
	totBusy=0
	totIdle=0
	totDown=0
	
	#Parse the node info list to get total numbers of busy, idle, and offline
	segs=$(parseList "totalNodeSeg" "${array[@]}")
	
	wait
	
	#Get info from all segments after they've finished and add them up
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

	#Determine where to log to
	case "$log_level" in
	0)
	  verbose_logging=/dev/null
	  minimal_logging=/dev/null
	;;
	1)
	  verbose_logging=/dev/null
	  minimal_logging=$log_loc/all_total_cpu.log
	;;
	2) 
	  verbose_logging=$log_loc/all_total_cpu.log 2>&1
	  minimal_logging=$log_loc/all_total_cpu.log 2>&1
	;;
	esac
	
	#Update and Report
	echo "`date +%s`-$totBusy-$totIdle-$totDown" >> $verbose_logging
#	rrdtool update $rrd_loc/all_group.rrd -t busy:idle:offline `date +%s`:$totAlloc:$totIdle:$totDown >> $minimal_logging &
}
function groupNodeSeg() {
	#Find out what segment we are, the length to look at, and if there's
	#  a remainder we have
	segment=$1
	seg_length=$2
	remainder=$3
	#Make sure above arguments don't show up in the list
	shift
	shift
	shift
	list=("$@")

	busy=0
	idle=0
	down=0

	#Find start and end points for this segment, then clear the out file
	start=$(($segment*$seg_length))
	end=$(($segment*$seg_length+$seg_length+$remainder-1))

	> /tmp/groupNodeSeg.$segment

	#Set up a dictionary for each group to have 3 variables available
	declare -A dictionary
	for group in "${grouplist[@]}"; do
		temp="-b"
		T_busy=$group$temp
		temp="-i"
		T_idle=$group$temp
		temp="-d"
		T_down=$group$temp
		
		dictionary[$T_busy]=0
		dictionary[$T_idle]=0
		dictionary[$T_down]=0
	done

	#For each item find busy, idle, down cores, add them up and send them
	#  to a temp file
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
		
		#Remove any numbers and special characters from the name to get
		#  a group
		grp=$(echo $name | sed 's/[0-9!@#$%^&*)(_+=-].*//g')
		
		#Check to see if it's a group that's configured
		contains() {
			t1=$1
			shift
			l=("$@")
			[[ ${l[@]} =~ $t1 ]] && echo "true" || echo "false"
		}
		
		inGroup=$(contains $grp ${grouplist[@]})
		
		#If it's configured add it to the proper place in the dictionary
		if [[ "$inGroup" == "true" ]]; then
			temp="-b"
			T_busy=$grp$temp
			temp="-i"
			T_idle=$grp$temp
			temp="-d"
			T_down=$grp$temp
			
			dictionary[$T_busy]=$((dictionary[$T_busy]+busy))
			dictionary[$T_idle]=$((dictionary[$T_idle]+idle))
			dictionary[$T_down]=$((dictionary[$T_down]+down))
		fi
		
	done

	#Write the results of each group to a temp file
	for group in "${grouplist[@]}"; do
		temp="-b"
		T_busy=$group$temp
		temp="-i"
		T_idle=$group$temp
		temp="-d"
		T_down=$group$temp
		
		echo "$group-${dictionary[$T_busy]}-${dictionary[$T_idle]}-${dictionary[$T_down]}" >> /tmp/groupNodeSeg.$segment
	done
}
function node_group() {
	array=("$@")

	segs=$(parseList "groupNodeSeg" "${array[@]}")
	wait

	#Set up the dictionary to put results in
	declare -A dictionary
	for group in "${grouplist[@]}"; do
		temp="-b"
		T_busy=$group$temp
		temp="-i"
		T_idle=$group$temp
		temp="-d"
		T_down=$group$temp
		
		dictionary[$T_busy]=0
		dictionary[$T_idle]=0
		dictionary[$T_down]=0
	done

	#Open each file and read each line in, chop and disperse results
	#  to the dictionary
	for x in $(seq 0 $((segs-1))); do
		temp=(`cat /tmp/groupNodeSeg.$x`)
		for line in "${temp[@]}"; do
			items=(`echo $line | sed 's/-/ /g'`)
			group=${items[0]}
			busy=${items[1]}
			idle=${items[2]}
			down=${items[3]}

			temp="-b"
			T_busy=$group$temp
			temp="-i"
			T_idle=$group$temp
			temp="-d"
			T_down=$group$temp

			dictionary[$T_busy]=$((dictionary[$T_busy]+busy))
			dictionary[$T_idle]=$((dictionary[$T_idle]+idle))
			dictionary[$T_down]=$((dictionary[$T_down]+down))
		done
	done

	#Determine where to log to
	for group in "${grouplist[@]}"; do
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
		
		temp="-b"
		T_busy=$group$temp
		temp="-i"
		T_idle=$group$temp
		temp="-d"
		T_down=$group$temp
		
		#Update and Report
		echo "`date +%s`-${dictionary[$T_busy]}-${dictionary[$T_idle]}-${dictionary[$T_down]}" >> $verbose_logging
		#rrdtool update $rrd_loc/"$group"_group.rrd -t busy:idle:offline `date +%s`:${dictionary[$T_busy]}:${dictionary[$T_idle]}:${dictionary[$T_down]} >> $minimal_logging &
	done
}
function node_indiv() {
	#Find out what segment we are, the length to look at, and if there's
	#  a remainder we have
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
		
		echo "`date +%s`-$nodeAlloc-$nodeIdle-$nodeDown" >> $verbose_logging
		#rrdtool update $rrd_loc/"$nodeName"_node.rrd -t busy:idle:offline `date +%s`:$nodeAlloc:$nodeIdle:$nodeDown >> $minimal_logging &
	done
}
function totalPartSeg() {
	#Find out what segment we are, the length to look at, and if there's
	#  a remainder we have
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

	echo "$totQueued-$totRunning-$r1-$r2-$r3_4-$r5_8-$r9_16-$r17_32-$r33_64-$r65_128-$r129_256-$r257_512-$rGT512" > /tmp/totalPartSeg.$segment
}
function part_total() {
	#Send the array through the parser, reconstruct the temp files,
	#  then report and update
	array=("$@")

	segs=$(parseList "totalPartSeg" "${array[@]}")

	wait
	
	for segment in $(seq "0" $(($segs-1))); do
		loc=/tmp/totalPartSeg.$segment
		t_q="$(cat $loc | cut -f1 -d '-')"
		t_r="$(cat $loc | cut -f2 -d '-')"
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
		totQueued=$(($totQueued+$t_q))
		totRunning=$(($totRunning+$t_r))
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
	done

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

	if [[ "$corejob_graphing" == "true" ]]; then
		  echo "`date +%s`-$totQueued-$totRunning-$r1-$r2-$r3_4-$r5_8-$r9_16-$r17_32-$r33_64-$r65_128-$r129_256-$r257_512-$rGT512" >> $verbose_logging
#		  rrdtool update $rrd_loc/all_part_corejob.rrd -t R1:R2:R3:R4:R5:R6:R7:R8:R9:R10:R11 `date +%s`:$r1:$r2:$r3_4:$r5_8:$r9_16:$r17_32:$r33_64:$r65_128:$r129_256:$r257_512:$rGT512 >> $minimal_logging &
#		  rrdtool update $rrd_loc/all_part_queue.rrd -t queued:running `date +%s`:$totQueued:$totRunning >> $minimal_logging &

	else
		  echo "`date +%s`-$totQueued-$totRunning" >> $verbose_logging
#		  rrdtool update $rrd_loc/all_part_queue.rrd -t queued:running `date +%s`:$totQueued:$totRunning >> $minimal_logging &
	fi
}
function indivPartSeg() {
	#Find out what segment we are, the length to look at, and if there's
	#  a remainder we have
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
	
	> /tmp/indivPartSeg.$segment
	
	for index in $(seq $start $end); do
		partition=$(echo "${array[$index]}" | cut -f1 -d ',')
		if [[ $inPart == "false" ]]; then break; fi
		
		jobState=$(echo "${array[$index]}" | cut -f2 -d ',')
		case "$jobState" in
			"PD") dictionary["$partition-q"]=$((dictionary["$partition-q"]+1));;
			"R") dictionary["$partition-r"]=$((dictionary["$partition-r"]+1));;
		esac

		if [[ "$corejob_graphing" == "true" ]] && [[ $jobState == "R" ]]; then
			jobCores=$(echo  "${array[$index]}" | cut -f3 -d ',')
			if [[ $jobCores == 1 ]]; then r1=1; fi
			if [[ $jobCores == 2 ]]; then r2=2; fi
			if [[ $jobCores -ge 3 && $jobCores -le 4 ]]; then r3_4=$jobCores; fi
			if [[ $jobCores -ge 5 && $jobCores -le 8 ]]; then r5_8=$jobCores; fi
			if [[ $jobCores -ge 9 && $jobCores -le 16 ]]; then r9_16=$jobCores; fi
			if [[ $jobCores -ge 17 && $jobCores -le 32 ]]; then r17_32=$jobCores; fi
			if [[ $jobCores -ge 33 && $jobCores -le 64 ]]; then r33_64=$jobCores; fi
			if [[ $jobCores -ge 65 && $jobCores -le 128 ]]; then r65_128=$jobCores; fi
			if [[ $jobCores -ge 129 && $jobCores -le 256 ]]; then r129_256=$jobCores; fi
			if [[ $jobCores -ge 257 && $jobCores -le 512 ]]; then r257_512=$jobCores; fi
			if [[ $jobCores -gt 512 ]]; then rGT512=$jobCores; fi
			
			dictionary["$partition-1"]=$((dictionary["$partition-1"]+r1))
			dictionary["$partition-2"]=$((dictionary["$partition-2"]+r2))
			dictionary["$partition-3"]=$((dictionary["$partition-3"]+r3_4))
			dictionary["$partition-4"]=$((dictionary["$partition-4"]+r5_8))
			dictionary["$partition-5"]=$((dictionary["$partition-5"]+r9_16))
			dictionary["$partition-6"]=$((dictionary["$partition-6"]+r17_32))
			dictionary["$partition-7"]=$((dictionary["$partition-7"]+r33_64))
			dictionary["$partition-8"]=$((dictionary["$partition-8"]+r65_128))
			dictionary["$partition-9"]=$((dictionary["$partition-9"]+r129_256))
			dictionary["$partition-10"]=$((dictionary["$partition-10"]+r257_512))
			dictionary["$partition-11"]=$((dictionary["$partition-11"]+rGT512))		
		fi
	done

	#echo "$totQueued-$totRunning-$r1-$r2-$r3_4-$r5_8-$r9_16-$r17_32-$r33_64-$r65_128-$r129_256-$r257_512-$rGT512" > /tmp/totalPartSeg.$segment
	for p in "${partitionlist[@]}"; do
		echo "$p: ${dictionary[$p-q]}-${dictionary[$p-r]}"
	done
#	> /tmp/groupNodeSeg.$segment
#
#	#Set up a dictionary for each group to have 3 variables available
#	declare -A dictionary
#	for group in "${grouplist[@]}"; do
#		temp="-b"
#		T_busy=$group$temp
#		temp="-i"
#		T_idle=$group$temp
#		temp="-d"
#		T_down=$group$temp
#		
#		dictionary[$T_busy]=0
#		dictionary[$T_idle]=0
#		dictionary[$T_down]=0
#	done
#
#	#For each item find busy, idle, down cores, add them up and send them
#	#  to a temp file
#	for index in `seq $start $end`; do
#		item=($(echo ${list[$index]} | sed 's/,/ /g'))
#		name=$(echo ${item[0]})
#		alloc=$(echo ${item[1]})
#		tot=$(echo ${item[2]})
#		state=$(echo ${item[3]})
#		
#		busy=$alloc
#		
#		if [ "$state" == "ALLOCATED" ] || [ "$state" == "IDLE" ] || [ "$state" == "MIXED" ]; then
#			temp=$((tot-alloc))
#			idle=$temp
#		else
#			temp=$((tot-alloc))
#			down=$temp
#		fi
#		
#		#Find which group this node belongs to and add to busy-idle-down
#		
#		#Remove any numbers and special characters from the name to get
#		#  a group
#		grp=$(echo $name | sed 's/[0-9!@#$%^&*)(_+=-].*//g')
#		
#		#Check to see if it's a group that's configured
#		contains() {
#			t1=$1
#			shift
#			l=("$@")
#			[[ ${l[@]} =~ $t1 ]] && echo "true" || echo "false"
#		}
#		
#		inGroup=$(contains $grp ${grouplist[@]})
#		
#		#If it's configured add it to the proper place in the dictionary
#		if [[ "$inGroup" == "true" ]]; then
#			temp="-b"
#			T_busy=$grp$temp
#			temp="-i"
#			T_idle=$grp$temp
#			temp="-d"
#			T_down=$grp$temp
#			
#			dictionary[$T_busy]=$((dictionary[$T_busy]+busy))
#			dictionary[$T_idle]=$((dictionary[$T_idle]+idle))
#			dictionary[$T_down]=$((dictionary[$T_down]+down))
#		fi
#		
#	done
#
#	#Write the results of each group to a temp file
#	for group in "${grouplist[@]}"; do
#		temp="-b"
#		T_busy=$group$temp
#		temp="-i"
#		T_idle=$group$temp
#		temp="-d"
#		T_down=$group$temp
#		
#		echo "$group-${dictionary[$T_busy]}-${dictionary[$T_idle]}-${dictionary[$T_down]}" >> /tmp/groupNodeSeg.$segment
#	done
}
function part_indiv() {
	array=("$@")
	
	parseList "indivPartSeg" "${array[@]}"
	
	wait
	
	#for x in $(seq 0 $((segs-1))); do
	#	echo "Reconstructing"
	#done
	
# OLD SHTOOF
#	totQueued=0
#	totRunning=0
#	r1=0
#	r2=0
#	r3_4=0
#	r5_8=0
#	r9_16=0
#	r17_32=0
#	r33_64=0
#	r65_128=0
#	r129_256=0
#	r257_512=0
#	rGT512=0
#	for item in "${array[@]}"; do
#		jobPart=$(echo $item | cut -f1 -d ',')
#		if [[ $jobPart == *$part* ]]; then
#			jobState=$(echo $item | cut -f2 -d ',')
#			case "$jobState" in
#				"PD") totQueued=$(($totQueued + 1));;
#				"R") totRunning=$(($totRunning + 1))
#			esac
#
#			if [[ $1 == "true" ]] && [[ $jobState == "R" ]]; then
#			jobCores=$(echo  $item | cut -f3 -d ',')
#			if [[ $jobCores == 1 ]]; then r1=$(($r1 + 1)); fi
#			if [[ $jobCores == 2 ]]; then r2=$(($r2 + 2)); fi
#			if [[ $jobCores -ge 3 && $jobCores -le 4 ]]; then r3_4=$(($r3_4 + $jobCores)); fi
#			if [[ $jobCores -ge 5 && $jobCores -le 8 ]]; then r5_8=$(($r5_8 + $jobCores)); fi
#			if [[ $jobCores -ge 9 && $jobCores -le 16 ]]; then r9_16=$(($r9_16 + $jobCores)); fi
#			if [[ $jobCores -ge 17 && $jobCores -le 32 ]]; then r17_32=$(($r17_32 + $jobCores)); fi
#			if [[ $jobCores -ge 33 && $jobCores -le 64 ]]; then r33_64=$(($r33_64 + $jobCores)); fi
#			if [[ $jobCores -ge 65 && $jobCores -le 128 ]]; then r65_128=$(($r65_128 + $jobCores)); fi
#			if [[ $jobCores -ge 129 && $jobCores -le 256 ]]; then r129_256=$(($r129_256 + $jobCores)); fi
#			if [[ $jobCores -ge 257 && $jobCores -le 512 ]]; then r257_512=$(($r257_512 + $jobCores)); fi
#			if [[ $jobCores -gt 512 ]]; then rGT512=$(($rGT512 + $jobCores)); fi
#		fi		
#	fi
#	done

#Fix this for individual partitions
#	case "$log_level" in
#		0)
#		  verbose_logging=/dev/null
#		  minimal_logging=/dev/null
#		;;
#		1)
#		  verbose_logging=/dev/null
#		  minimal_logging=$log_loc/all_part.log
#		;;
#		2) 
#		  verbose_logging=$log_loc/all_part.log 2>&1
#		  minimal_logging=$log_loc/all_part.log 2>&1
#		;;
#	esac
#
#	if [[ "$corejob_graphing" == "true" ]]; then
#		  echo "`date +%s`-$totQueued-$totRunning-$r1-$r2-$r3_4-$r5_8-$r9_16-$r17_32-$r33_64-$r65_128-$r129_256-$r257_512-$rGT512" #>> $verbose_logging 2>&1
#		  rrdtool update $rrd_loc/all_part_corejob.rrd -t R1:R2:R3:R4:R5:R6:R7:R8:R9:R10:R11 `date +%s`:$r1:$r2:$r3_4:$r5_8:$r9_16:$r17_32:$r33_64:$r65_128:$r129_256:$r257_512:$rGT512 >> $minimal_logging &
#		  rrdtool update $rrd_loc/all_part_queue.rrd -t queued:running `date +%s`:$totQueued:$totRunning >> $minimal_logging &
#
#	else
#		  echo "`date +%s`-$totQueued-$totRunning" #>> $verbose_logging
#		  rrdtool update $rrd_loc/all_part_queue.rrd -t queued:running `date +%s`:$totQueued:$totRunning >> $minimal_logging &
#	fi


#		  echo "Partition $part: `date +%s`-$totQueued-$totRunning-$r1-$r2-$r3_4-$r5_8-$r9_16-$r17_32-$r33_64-$r65_128-$r129_256-$r257_512-$rGT512" #>> $log_loc/"$part"_part.log 2>&1
# 		  rrdtool update $rrd_loc/"$part"_part_corejob.rrd -t R1:R2:R3:R4:R5:R6:R7:R8:R9:R10:R11 `date +%s`:$r1:$r2:$r3_4:$r5_8:$r9_16:$r17_32:$r33_64:$r65_128:$r129_256:$r257_512:$rGT512 >> $log_loc/"$part"_part.log 2>&1 &
#		  rrdtool update $rrd_loc/"$part"_part_queue.rrd -t queued:running `date +%s`:$totQueued:$totRunning >> $log_loc/"$part"_part.log 2>&1 &
#		  echo "`date +%s`-$totQueued-$totRunning" #>> $loc_loc/"$part"_part.log 2>&1
#		  rrdtool update $rrd_loc/"$part"_part_queue.rrd -t queued:running `date +%s`:$totQueued:$totRunning >> $loc_loc/"$part"_part.log 2>&1 &
}

#--------------------------------------
#------- Main Program Commands --------
#--------------------------------------
#Get the information on the nodes and jobs, make sure to wait so all info is returned before continuing
#get_node_info
{
if [ $node_totaling == "true" ] || [ $group_graphing == "true" ] || [ $node_graphing == "true" ]; then
	node_info=($(get_node_info))
fi
if [ $part_totaling == "true" ] || [ $partition_graphing == "true" ]; then
	job_info=($(get_job_info))
fi

#Check what's configured to update and call the functions needed as background processes
# Totaling takes the longest, sequential for now (bleh)
if [[ $node_totaling == "true" ]]; then
		node_total "${node_info[@]}" &
fi
if [[ $part_totaling == "true" ]]; then
		part_total "${job_info[@]}" &
fi


#If grouping is enabled spawn a thread for each group to find info on that
if [[ $group_graphing == "true" ]]; then
		node_group "${node_info[@]}" &
fi

#If individual node graphing is on spawn a thread for each node to work on
if [[ $node_graphing == "true" ]]; then
		parseList "node_indiv" "${node_info[@]}" >/dev/null &
fi

#If partition graphing is enabled spawn a thread for each partition in the conf
if [[ $partition_graphing == "true" ]]; then
	part_indiv "${job_info[@]}" &
fi

wait
}
