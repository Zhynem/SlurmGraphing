<!-- # Author: Michael Luker -->
<!-- # Project: SlurmGraphing -->
<!-- # Version: 1.0 (Speculative Sanderling) -->
<!-- # Date: August 10, 2014 -->

SlurmGraphing
=============

Visualize the utilization of an HPC environment configured with Slurm from a convenient web interface.

Version 1.0 (Speculative Sanderling)

Please read the [wiki](https://github.com/MichaelLuker/SlurmGraphing/wiki) for details about configuring.

**Requirements**

At this point in time I'm not sure about absolute requirements but I will describe the setup this software was made for.

-The machine: Virtual machine with 4 2.6 GHz processors with access to slurm configured for our cluster. Also configured for web access. This is a dedicated host to graphing our resource use, and root was the only account used during setup.

-Bash version 4.1.2

-Python version 2.6.6

-RRDtool version 1.3.8

-Apache 2.2.15 (I assume another program would work as long cgi can be configured.)

**Installing**

1: Change to the directory you wish to keep the software in

2: git clone https://github.com/michaelluker/SlurmGraphing.git

3: cd SlurmGraphing

4: ./configure \[flags\] (Run ./configure -h or ./configure --help or check the wiki to see detailed list of options)

5: Create an entry in your crontab to run cron_script.sh every time step
    
**Things to note**

-Partitions that contain every node are not needed for any data collection. If all jobs run in a partition like this it is recommended partition totaling is turned off to avoid unnecessary parsing and graphing.

-The configure script will detect hidden partitions. If there are hidden partitions you do not wish to track run the configure script without the -q (quiet) flag on.

-Log files are not automatically cleaned in any way. If the logging level is set to 1 or 2 they will get large over time.

-Depending on time step and duration options set RRD files may take up a lot of space, as well as take a long time to create. Running configure without the -q flag will output which RRD files are currently being created. (An RRD file is created at full size and will not take up any more space once data starts being stored)

-If you change your mind about an option later you can directly modify options from the sgraphing.conf and config.py files.
