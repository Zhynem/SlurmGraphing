SlurmGraphing
=============

Visualize the utilization of an HPC environment configured with Slurm from a convenient web interface.

A release version is not yet ready. Work is still being done in the Developing branch.

Installing
==========

1: Change to the directory you wish to keep the software in

2: git clone https://github.com/michaelluker/SlurmGraphing.git

3: cd SlurmGraphing

4: ./configure \[flags\] (Run ./configure -h or ./configure --help to see detailed list of options)

5: Depending on what flags were chosen there may be additional steps to take. If -q was not a flag used instructions will be printed to the screen. More detailed information is on the github wiki.
    
Things to note
==============

-Partitions that contain every node are not needed for any data collection. If all jobs run in a partition like this it is recommended partition totaling is turned off to avoid unnecessary parsing and graphing.

-If configure is run as root it will detect hidden partitions. If there are hidden partitions you do not wish to track run the configure script without the -q (quiet) flag on, or as another user.

-Log files are not automatically cleaned in any way. If the logging level is set to 1 or 2 they will get large over time.

-Depending on time step and duration options set RRD files may take up a lot of space, as well as take a long time to create. Running configure without the -q flag will output which RRD files are currently being created. (An RRD file is created at full size and will not take up any more space once data starts being stored)

-If you change your mind about an option later you can directly modify options from the sgraphing.conf and config.py files.
