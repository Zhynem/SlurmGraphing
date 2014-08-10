#!/bin/bash

# Author: Michael Luker
# Project: SlurmGraphing
# Version: 1.0 (Speculative Sanderling)
# Date: August 10, 2014

#Read the .conf file
script_loc=$(readlink -f $0)
script_dir=$(dirname $script_loc)
source "$script_dir"/sgraphing.conf

heartbeat=$(($time_step * 2))

function check_for_rrd()
{
	tocheck=$1$2
	state=$(ls $rrd_loc | grep $tocheck)
	if [ -z "$state" ]; then
		echo "false"
	else
		echo "true"
	fi
}

if [[ "$partition_graphing" == "true" ]]; then
	for part in "${partitionlist[@]}"; do
		exists=$(check_for_rrd $part "_part_queue.rrd")
		if [ "$exists" == "false" ]; then
			echo "Creating $part part RRD file" && rrdtool create $rrd_loc/"$part"_part_queue.rrd --start 0 --step $time_step DS:queued:GAUGE:$heartbeat:0:U DS:running:GAUGE:$heartbeat:0:U RRA:LAST:0.5:1:$time_duration
			if [[ $corejob_graphing == "true" ]]; then
				echo "Creating $part corejob RRD file" && rrdtool create $rrd_loc/"$part"_part_corejob.rrd --start 0 --step $time_step DS:R1:GAUGE:$heartbeat:0:U DS:R2:GAUGE:$heartbeat:0:U DS:R3:GAUGE:$heartbeat:0:U DS:R4:GAUGE:$heartbeat:0:U DS:R5:GAUGE:$heartbeat:0:U DS:R6:GAUGE:$heartbeat:0:U DS:R7:GAUGE:$heartbeat:0:U DS:R8:GAUGE:$heartbeat:0:U DS:R9:GAUGE:$heartbeat:0:U DS:R10:GAUGE:$heartbeat:0:U DS:R11:GAUGE:$heartbeat:0:U RRA:LAST:0.5:1:$time_duration
			fi
		fi
	done
fi

if [[ "$group_graphing" == "true" ]]; then
	for group in "${grouplist[@]}"; do
		exists=$(check_for_rrd $group "_group.rrd")
		if [ "$exists" == "false" ]; then
			echo "Creating $group group RRD file" && rrdtool create $rrd_loc/"$group"_group.rrd --start 0 --step $time_step DS:busy:GAUGE:$heartbeat:0:U DS:idle:GAUGE:$heartbeat:0:U DS:offline:GAUGE:$heartbeat:0:U RRA:LAST:0.5:1:$time_duration
		fi
	done
fi

if [[ "$node_graphing" == "true" ]]; then
	for node in "${nodelist[@]}"; do
		exists=$(check_for_rrd $node "_node.rrd")
		if [ "$exists" == "false" ]; then
			echo "Creating $node node RRD file" && rrdtool create $rrd_loc/"$node"_node.rrd --start 0 --step $time_step DS:busy:GAUGE:$heartbeat:0:U DS:idle:GAUGE:$heartbeat:0:U DS:offline:GAUGE:$heartbeat:0:U RRA:LAST:0.5:1:$time_duration
		fi
	done
fi

if [[ "$node_totaling" == "true" ]]; then
	exists=$(check_for_rrd "all" "_group.rrc")
	if [ "$exists" == "false" ]; then
		echo "Creating node totaling RRD Files"
		rrdtool create $rrd_loc/all_group.rrd --start 0 --step $time_step DS:busy:GAUGE:$heartbeat:0:U DS:idle:GAUGE:$heartbeat:0:U DS:offline:GAUGE:$heartbeat:0:U RRA:LAST:0.5:1:$time_duration
	fi
fi

if [[ "$part_totaling" == "true" ]]; then
	exists=$(check_for_rrd "all" "_part_queue.rrd")
	if [ "$exists" == "false" ]; then
		echo "Creating partition totaling RRD Files"
		rrdtool create $rrd_loc/all_part_queue.rrd --start 0 --step $time_step DS:queued:GAUGE:$heartbeat:0:U DS:running:GAUGE:$heartbeat:0:U RRA:LAST:0.5:1:$time_duration
		if [[ $corejob_graphing == "true" ]]; then
			echo "Creating $part corejob RRD file" && rrdtool create $rrd_loc/all_part_corejob.rrd --start 0 --step $time_step DS:R1:GAUGE:$heartbeat:0:U DS:R2:GAUGE:$heartbeat:0:U DS:R3:GAUGE:$heartbeat:0:U DS:R4:GAUGE:$heartbeat:0:U DS:R5:GAUGE:$heartbeat:0:U DS:R6:GAUGE:$heartbeat:0:U DS:R7:GAUGE:$heartbeat:0:U DS:R8:GAUGE:$heartbeat:0:U DS:R9:GAUGE:$heartbeat:0:U DS:R10:GAUGE:$heartbeat:0:U DS:R11:GAUGE:$heartbeat:0:U RRA:LAST:0.5:1:$time_duration
		fi
	fi
fi

wait
echo "All RRD files have been created"
