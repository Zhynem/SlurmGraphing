#Controller: Functions that control the states of the argument variables

#Import needed items
import threading, subprocess

def initialize(args):
	#Depending on what's configured we need different values
	if(args.g_graphing == 'true' or args.n_graphing == 'true'):
		args.graphItem="total"
		args.partition="None"
		args.group="total"
		args.graphType="cores"
		args.rangeVal=1
		args.period="hour"
	elif(args.p_graphing == 'true'):
		args.graphItem="partition"
		args.partition="partition"
		args.group="None"
		args.graphType="jobs"
		args.rangeVal=1
		args.period="hour"

#Get inputs from the cgi form
def getInputs(args):
	#Get configured radio and slide values
	args.graphItem = str(args.form.getvalue('graphItem'))

	if args.p_graphing == 'true' and args.graphItem == 'partition':
		args.partition = "partition"
	else:
		args.partition = "None"

	if args.jc_graphing == 'true':
		args.graphType = str(args.form.getvalue('graphType'))
	else:
		args.graphType = "None"

	if (args.g_graphing == 'true' or args.n_graphing == 'true') and args.graphItem != 'partition':
		args.group = args.graphItem
	else:
		args.group = "None"

	if args.slider == 'true':
		args.rangeVal = str(args.form.getvalue('rangeVal'))
	else:
		args.rangeVal = '1'
	
	#if args.manual == 'true':
		#Do something that will be determined later

	#Check to see if an image link was clicked
	if (args.main_links == 'true') :
		for item in args.groupList:
			temp = str(args.form.getvalue('graphLink-%s.x' % item))
			if temp != 'None':
				args.group = item

	#If everything is None or NULL the page has just loaded and needs to be fed some inputs
	#if (args.partition == "None" and args.graphType == "None" and args.group == "None"):
	if (args.graphItem == 'None' or args.graphItem == 'NULL'):
		initialize(args)
#	args.lastType = str(args.form.getvalue('lastType')) Might not need

def interpretInput(args):
	#Based on the inputs (and config) recieved create a list of items that will be checked
	if (args.g_graphing == 'true' or args.n_graphing == 'true'):
		for item in args.groupList:
			if item == args.group:
				args.checked_list[item] = "Checked"
				args.graphType = "cores"
			else:
				args.checked_list[item] = ""

	if args.p_graphing == 'true':
		if args.partition == 'partition':
			args.checked_list["Partition"] = "Checked"
		else:
			args.checked_list["Partition"] = ""
		if args.partition == 'partition' and args.graphType == 'None':
			args.graphType = 'jobs'

	if args.jc_graphing == 'true':
		if args.graphType == 'jobs':
			args.checked_list["Jobs"] = "Checked"
		else:
			args.checked_list["Jobs"] = ""
		if args.graphType == 'corejob':
			args.checked_list["Cores"] = "Checked"
		else:
			args.checked_list["Cores"] = ""

	if args.node_totaling == 'true':
		args.groupList.append("all")
		if args.group == 'total':
			args.checked_list['all'] = "Checked"
			args.graphType = "cores"
		else:
			args.checked_list['all'] = ""
	else:
		if args.group == 'total':
			args.checked_list['all'] = "Checked"
			args.graphType = "cores"
		else:
			args.checked_list['all'] = ""
	
	if args.part_totaling == 'true':
		args.partList.append("all")

	if(args.g_graphing == 'false' and args.n_graphing == 'true' and args.group == 'total'):
		args.group = ""
			
	#Convert rangeVal into a period of time for updating and linking to the correct graphs
	if(args.rangeVal == '1'):
		args.period = "hour"
	elif(args.rangeVal == '2'):
		args.period = "day"
	elif(args.rangeVal == '3'):
		args.period = "week"
	elif(args.rangeVal == '4'):
		args.period = "month"
	elif(args.rangeVal == '5'):
		args.period = "year"
	elif(args.rangeVal == '6'):
		args.period = "twoyear"

def updateGraphs(args):
	#Define the possible threads that will be used
	class Cluster_Partition_Thread(threading.Thread):
		def __init__(self, sg, sl, rm, gt, pr):
			super(Cluster_Partition_Thread, self).__init__()
			self.seg = sg
			self.seg_len = sl
			self.remain = rm
			self.graphType = gt
			self.period = pr

		def run(self):
			start = self.seg * self.seg_len
			end = (self.seg * self.seg_len) + (self.seg_len + self.remain)
			for x in range(start, end):
				if(args.graphType == "cores"):
					item = args.groupList[x]
				else:
					item = args.partList[x]
				subprocess.call([args.graph_script, str(item), str(self.graphType), str(self.period)])

	class NodeThread(threading.Thread):
		def __init__(self, sg, sl, rm, pr):
			super(NodeThread, self).__init__()
			self.seg = sg
			self.seg_len = sl
			self.remain = rm
			self.period = pr

		def run(self):
			start = self.seg * self.seg_len
			end = (self.seg * self.seg_len) + (self.seg_len + self.remain)
			for x in range(start, end):
				item = args.nodeList[x]
				if(args.group in item):
					subprocess.call([args.graph_script, str(item), str('node'), str(self.period)])

	#Object to hold all the threads that will be spawned
	threads = []

	#Create the correct threads and start them
	if(args.group != 'None' and args.group == 'total' and args.g_graphing == 'true'):
		seg_length = len(args.groupList)/args.max_segs
		remainder = len(args.groupList)%args.max_segs
		for x in range(0, args.max_segs):
			if(x == args.max_segs - 1 ):
				w= Cluster_Partition_Thread(x, seg_length, remainder, args.graphType, args.period)
				threads.append(w)
				w.start()

			else:
				w= Cluster_Partition_Thread(x, seg_length, 0, args.graphType, args.period)
				threads.append(w)
				w.start()
				

	elif((args.group != 'None' and args.group != 'total') and args.n_graphing == 'true'):
		#Print a large group total above the node breakdown if group graphing is enabled
		if(args.g_graphing == 'true'):
			subprocess.call([args.graph_script, str(args.group), str(args.graphType), str(args.period)])
		seg_length = len(args.nodeList)/args.max_segs
		remainder = len(args.nodeList)%args.max_segs
		for x in range(0, args.max_segs):
			if(x == args.max_segs - 1):
				w = NodeThread(x, seg_length, remainder, args.period)
				threads.append(w)
				w.start()
			else:
				w = NodeThread(x, seg_length, 0, args.period)
				threads.append(w)
				w.start()
		
	elif(args.group == 'None' and args.partition == 'partition' and args.p_graphing == 'true'):
		seg_length = len(args.partList)/args.max_segs
		remainder = len(args.partList)%args.max_segs
		for x in range(0, args.max_segs):
			if(x == args.max_segs - 1 ):
				w= Cluster_Partition_Thread(x, seg_length, remainder, args.graphType, args.period)
				threads.append(w)
				w.start()

			else:
				w= Cluster_Partition_Thread(x, seg_length, 0, args.graphType, args.period)
				threads.append(w)
				w.start()
		
	#Wait for threads to finish before moving on
	for x in range(0, args.max_segs):
		w = threads[x]
		w.join()

