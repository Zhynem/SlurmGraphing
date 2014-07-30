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

	if args.totaling == 'true':
		args.partList.append("all")
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
		def __init__(self, it, gt, per):
			super(Cluster_Partition_Thread, self).__init__()
			self.item = it
			self.graphType = gt
			self.period = per

		def run(self):
			subprocess.call([args.graph_script, str(self.item), str(self.graphType), str(self.period)])

	class NodeThread(threading.Thread):
		def __init__(self, it, per):
			super(NodeThread, self).__init__()
			self.item = it
			self.period = per

		def run(self):
			subprocess.call([args.graph_script, str(self.item), str('node'), str(self.period)])

	#Object to hold all the threads that will be spawned
	thread_objects = {}

	#Create the correct threads and start them
	if(args.group != 'None' and args.group == 'total' and args.g_graphing == 'true'):
		for item in args.groupList:
			thread_objects[item] = Cluster_Partition_Thread(item, args.graphType, args.period)
			thread_objects[item].start()

	elif((args.group != 'None' and args.group != 'total') and args.n_graphing == 'true'):
		#Print a large group total above the node breakdown if group graphing is enabled
		if(args.g_graphing == 'true'):
			subprocess.call([args.graph_script, str(args.group), str(args.graphType), str(args.period)])
		for item in args.nodeList:
			if(args.group in item):
				thread_objects[item] = NodeThread(item, args.period)
				thread_objects[item].start()
		
	elif(args.group == 'None' and args.partition == 'partition' and args.p_graphing == 'true'):
		for item in args.partList:
			thread_objects[item] = Cluster_Partition_Thread(item, args.graphType, args.period)
			thread_objects[item].start()
		
	#Wait for threads to finish before moving on
	for item in thread_objects:
		thread_objects[item].join()

