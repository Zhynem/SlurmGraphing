#!/bin/bash

source ./sgraphing.conf

heartbeat=$(($time_step * 2))

function check_for_rrd()
{
	tocheck=$1$2
	state=$(ls ../RRDFiles/ | grep $tocheck)
	if [ -z "$state" ]; then
		echo "false"
	else
		echo "true"
	fi
}


if [[ $partition_graphing == "true" ]]; then
	for part in "${partitionlist[@]}"; do
		exists=$(check_for_rrd $part "_part_queue.rrd")
		if [ "$exists" == "false" ]; then
			echo "Creating $part part RRD file" && rrdtool create ../RRDFiles/"$part"_part_queue.rrd --start 0 --step $time_step DS:queued:GAUGE:$heartbeat:0:U DS:running:GAUGE:$heartbeat:0:U RRA:LAST:0.5:1:$time_duration &
			if [[ $corejob_graphing == "true" ]]; then
				echo "Creating $part corejob RRD file" && rrdtool create ../RRDFiles/"$part"_part_corejob.rrd --start 0 --step $time_step DS:R1:GAUGE:$heartbeat:0:U DS:R2:GAUGE:$heartbeat:0:U DS:R3:GAUGE:$heartbeat:0:U DS:R4:GAUGE:$heartbeat:0:U DS:R5:GAUGE:$heartbeat:0:U DS:R6:GAUGE:$heartbeat:0:U DS:R7:GAUGE:$heartbeat:0:U DS:R8:GAUGE:$heartbeat:0:U DS:R9:GAUGE:$heartbeat:0:U DS:R10:GAUGE:$heartbeat:0:U DS:R11:GAUGE:$heartbeat:0:U RRA:LAST:0.5:1:$time_duration &
			fi
		fi
	done
fi

if [[ $group_graphing == "true" ]]; then
	for group in "${grouplist[@]}"; do
		exists=$(check_for_rrd $group "_group.rrd")
		if [ "$exists" == "false" ]; then
			echo "Creating $group group RRD file" && rrdtool create ../RRDFiles/"$group"_group.rrd --start 0 --step $time_step DS:busy:GAUGE:$heartbeat:0:U DS:idle:GAUGE:$heartbeat:0:U DS:offline:GAUGE:$heartbeat:0:U RRA:LAST:0.5:1:$time_duration &
		fi
	done
fi

if [[ $node_graphing == "true" ]]; then
	for node in "${nodelist[@]}"; do
		exists=$(check_for_rrd $node "_node.rrd")
		if [ "$exists" == "false" ]; then
			echo "Creating $node node RRD file" && rrdtool create ../RRDFiles/"$node"_node.rrd --start 0 --step $time_step DS:busy:GAUGE:$heartbeat:0:U DS:idle:GAUGE:$heartbeat:0:U DS:offline:GAUGE:$heartbeat:0:U RRA:LAST:0.5:1:$time_duration &
		fi
	done
fi

if [[ $totaling == "true" ]]; then
	exists=$(check_for_rrd "all")
	if [ "$exists" == "false" ]; then
		echo "Creating totaling RRD Files"
		rrdtool create ../RRDFiles/all_group.rrd --start 0 --step $time_step DS:busy:GAUGE:$heartbeat:0:U DS:idle:GAUGE:$heartbeat:0:U DS:offline:GAUGE:$heartbeat:0:U RRA:LAST:0.5:1:$time_duration &
		rrdtool create ../RRDFiles/all_part_queue.rrd --start 0 --step $time_step DS:queued:GAUGE:$heartbeat:0:U DS:running:GAUGE:$heartbeat:0:U RRA:LAST:0.5:1:$time_duration &
		if [[ $corejob_graphing == "true" ]]; then
			echo "Creating $part corejob RRD file" && rrdtool create ../RRDFiles/all_part_corejob.rrd --start 0 --step $time_step DS:R1:GAUGE:$heartbeat:0:U DS:R2:GAUGE:$heartbeat:0:U DS:R3:GAUGE:$heartbeat:0:U DS:R4:GAUGE:$heartbeat:0:U DS:R5:GAUGE:$heartbeat:0:U DS:R6:GAUGE:$heartbeat:0:U DS:R7:GAUGE:$heartbeat:0:U DS:R8:GAUGE:$heartbeat:0:U DS:R9:GAUGE:$heartbeat:0:U DS:R10:GAUGE:$heartbeat:0:U DS:R11:GAUGE:$heartbeat:0:U RRA:LAST:0.5:1:$time_duration &
		fi
	fi
fi

wait
echo "All RRD files have been created"
