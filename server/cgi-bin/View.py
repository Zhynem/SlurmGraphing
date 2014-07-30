#View: Recieve variables that were modified by the controller or loaded by the config and display the page accordingly

def display(args):
	#Send the content type and head section
	print '''Content-type:text/html\n\r
<!DOCTYPE html>
<html>
	<head>
		<title>Slurm Usage Graphs</title>
		<link href="/style.css" rel="stylesheet" type="text/css" />
		<script type='text/javascript'>setInterval( "autosubmit()", %s000 );function autosubmit(){ document.inputform.submit();}</script>

		<!-- Prevent caching -->
		<meta http-equiv="cache-control" content="max-age=0" />
		<meta http-equiv="cache-control" content="no-cache" />
		<meta http-equiv="expires" content="0" />
		<meta http-equiv="expires" content="Tue, 01 Jan 1980 1:00:00 GMT" />
		<meta http-equiv="pragma" content="no-cache" />
	</head> ''' % ( args.refresh )
	
#Print all variables and inputs
	if args.debugging == 'true':
		print '''
-------------------------------------------------------------------------------------------------------------------------------------------------------------------<br>
|-- Dynamic Variables --|<br>
graphItem		: %s<br>
partition		: %s<br>
group			: %s<br>
graphType		: %s<br>
rangeVal		: %s<br>
period			: %s<br>
checked_list	: %s<br>
<br>
|-- Read from Config --|<br>
debugging		: %s<br>
totaling		: %s<br>
g_graphing		: %s<br>
n_graphing		: %s<br>
p_graphing		: %s<br>
cj_graphing		: %s<br>
main_links		: %s<br>
node_columns	: %s<br>
slider			: %s<br>
manual			: %s<br>
graph_script	: %s<br>
partList		: %s<br>
groupList		: %s<br>
nodeList		: %s<br>
-------------------------------------------------------------------------------------------------------------------------------------------------------------------<br>
''' % (args.graphItem, args.partition, args.group, args.graphType, args.rangeVal, args.period, args.checked_list, args.debugging, args.totaling, args.g_graphing, args.n_graphing, args.p_graphing, args.jc_graphing, args.main_links, args.node_columns, args.slider, args.manual, args.graph_script, args.partList, args.groupList, args.nodeList)

	#Body, openings of containers
	print '''
	<body onload="refresh();">
		<div id="parts">
		<h1 id="title">Slurm Usage</h1>
			<div class="content">
				<form id="inputform" name="inputform" action="/cgi-bin/Page.py" method="post">
					<div id="inputs">
						<div id="radios">'''
						
	#Radios for switching between partition and group graphs if configured
	if (args.p_graphing == 'true' and (args.g_graphing == 'true' or args.n_graphing == 'true')):
		print'''							<h4><input type="radio" name="graphItem" value="partition" onclick="submit()" %s/>Partitions</h4>
							<hr id="selectBreak"/> ''' % (args.checked_list["Partition"])
	elif (args.p_graphing == 'true' and args.g_graphing == 'false'):
		print'''							<input type="hidden" name="graphItem" value="partition" />'''
	#else:
		#print'''							<input type="hidden" name="graphItem" value="total" />'''
	if (args.g_graphing == 'true'):
		print'''							<h4><input type="radio" name="graphItem" value="total" onclick="submit()" %s />Node Groups</h4>''' % (args.checked_list["all"])
	elif (args.n_graphing == 'true'):
		print'''							<h4><input type="radio" name="graphItem" value="total" onclick="submit()" %s />All Nodes</h4>''' % (args.checked_list["all"])

	#Radios for the node groups
	if(args.n_graphing == 'true'):
		for item in sorted(args.groupList):
			if item != "all":
				print '							<input type="radio" name="graphItem" value="%s" onclick="submit()" %s/>%s<br />' % (item, args.checked_list[item], item.title())
	#Close the radios container
	print '''						</div>'''
	
	if (args.partition == "partition" and args.jc_graphing == 'true'):
		print '''						<div id="selectors">
							<input type="radio" name="graphType" value="jobs" onclick="submit()" %s/>Jobs<br />
							<input type="radio" name="graphType" value="corejob" onclick="submit()" %s/>Cores / Job
						</div> ''' % (args.checked_list['Jobs'], args.checked_list['Cores'])
						
	if (args.slider == 'true'):
		print '''						<div id="rangeInput">
							<input id="rangeSelect" type="range" name="rangeVal" min="1" max="6" value="%s" onclick="submit()"/>
							<ul id="rangeLabel"><li id="hour">Hour</li><li id="day">Day</li><li id="week">Week</li><li id="month">Month</li><li id="year">Year</li><li id="twoyear">2 Years</li></ul>
						</div>''' % (args.rangeVal)

	#Close the inputs container
	print '''					</div>'''

	#Get the correct graphs
	#Graphs for all node groups (linked or not)
	if(args.group == 'total' and args.g_graphing == 'true'):
		print '''                	<div id="formGraphs">'''
		if args.main_links == 'true':
			for item in sorted(args.groupList):
				print '''                		<input type="image" class="graphLink" name="graphLink-%s" value="%s" src="/graphs/slurm-%s-%s-%s.png" alt="slurm test graph"/>''' % (item, item, item, args.graphType, args.period)
		else:
			for item in sorted(args.groupList):
				print '''                		<img class="graphLink" src="/graphs/slurm-%s-%s-%s.png" alt="slurm test graph"/>''' % (item, args.graphType, args.period)
		print '''                	</div>'''
	#Graphs for partitions			
	elif(args.partition == 'partition'):
		print '''                	<div id="formGraphs">'''
		for item in sorted(args.partList):
			print '						<img class="graphLink" src="/graphs/slurm-%s-%s-%s.png" alt="slurm test graph" />' % (item, args.graphType, args.period)
		print '''                	</div>'''

	#Close the form
	print'''		     	</form>'''
	
	#If a node group is being looked at it's outside the form, along with its node breakdown (if configured)
	if(args.group != 'None' and args.group != 'total' and args.g_graphing == 'true'):
			print '				<img class="graph" src="/graphs/slurm-%s-%s-%s.png" alt="slurm test graph" />' % (args.group, args.graphType, args.period)
	
	#Close parts and content container
	print '''			</div>
		</div>'''
	
	#Put the node table outside of everything so it can stretch acrossed the page	
	if(args.n_graphing == 'true' and args.group != 'None' and args.group != 'total'):
		print '''		<div id="nodes">
			<table>'''
		count = 0
		total = 0
		for item in sorted(args.nodeList):
			if(args.group in item):
				if count == 0:
					print '				<tr>'
				print '					<td><img class="node" src="/graphs/slurm-%s-%s-%s.png" alt="slurm test graph" /></td>' % (item, "node", args.period)
				count = count + 1
				total = total + 1
				if count == args.node_columns:
					print '				</tr>'
					count = 0
		temp = total % args.node_columns
		if temp != 0 :
			print "				</tr>"
			
		print '''			</table>
		</div> '''
	
	#Close any remaining open tags	
	print'''	</body>
</html>'''
