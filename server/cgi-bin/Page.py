#!/usr/bin/python
#Page: Call the controller actions, then display the view
import Controller
import View

#Import needed items
import cgi, cgitb
import config as cfg

#Define a  container for variables that will be used / passed around to multiple functions
class arguments():
	def __init__(self):
			self.form = cgi.FieldStorage()
			self.checked_list={}
			self.graphItem='NULL'
			self.partition='NULL'
			self.group='NULL'
			self.graphType='NULL'
			self.rangeVal='NULL'
			self.period='NULL'
			self.debugging=cfg.debugging
			self.p_graphing=cfg.partition_graphing
			self.jc_graphing=cfg.jobcore_graphing
			self.g_graphing=cfg.group_graphing
			self.n_graphing=cfg.node_graphing			
			self.totaling=cfg.totaling
			self.main_links=cfg.main_links
			self.node_columns=cfg.node_columns
			self.slider=cfg.slider
			self.manual=cfg.manual
			self.refresh=cfg.refresh
			self.graph_script=cfg.graph_script
			self.partList=cfg.partitionlist
			self.groupList=cfg.grouplist
			self.nodeList=cfg.nodelist


#Create the container
args = arguments()

#Use the controller to determine what state the variables are in
Controller.getInputs(args)
Controller.interpretInput(args)
Controller.updateGraphs(args)

#Display the page based on what the controller found out
View.display(args)
