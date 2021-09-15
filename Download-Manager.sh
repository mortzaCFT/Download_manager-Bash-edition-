#!/bin/bash
#editor,Coder by mortza

#----------------------------------------
#Change this to whereever you choose to install the program

trap 'normalplease'  1 2 3 15
BASEDIR="$HOME/downloadmanager"

#----------------------------------------
#Do not edit below this line unless you KNOW what you are doing

PROGNAME=`basename $0`
INPUTFILE="$BASEDIR/downloadlist"
PAUSEDFILE="$BASEDIR/pausedfilelist"
LOGDIR="$BASEDIR/downloadlogs"
COMPLETEDLOGS="$LOGDIR/completedlogs"
PROGRESSLOGS="$LOGDIR/progresslogs"
REMOVEDLOGS="$LOGDIR/removedlogs"
PROBLEMLOGS="$LOGDIR/problemlogs"
PIDFILE="$LOGDIR/getfiles.pid"
TMPDIR="$BASEDIR/tmp"
LOGFILE="$LOGDIR/downloads.log"
DEFAULT_SAVE_LOCATION="$BASEDIR/unsorted_downloads"

#----------------------------------------
#export all variables

export BASEDIR PROGNAME INPUTFILE INPUTFILE PAUSEDFILE LOGDIR COMPLETEDLOGS PROGRESSLOGS REMOVEDLOGS PROBLEMLOGS PIDFILE TMPDIR LOGFILE

#----------------------------------------
#functions

normalplease()
{
	echo -e "\nReceived interrupt\n"
}

#-----------------------------------------
#help

help()
{
echo "Usage: `basename $0`
 [-h] [-i] [-g] [-k] [-c] [-C] [-a] [-d file to be deleted from downloads] [-p file to be paused from downloads] [-P file being downloaded] [-r download file to be resumed] [ -n {download location},url]
|------------------------------------|
  h - display this help screen
  i	- enter $PROGNAME in interactive mode
  g	- start downloads
  k - stop ongoing downloads
        c      - cleanup download list (removes fully retrieved files)
	C	- Check for completed downloads and downloads and resume any downloads that are not in progress
	s	- show currently ongoing downloads
	n	- add download to list: if no download location is specified, file will be saved to default save location
	d	- delete download from list
	p	- pause download
	P	- show progress of download in realtime (ctrl-c to abort)
	a	- see available paused downloads
	r	- resume paused download
|------------------------------------|"
}

#----------------------------------------
#menu

menu()
{
	exit="false"
	while [ $exit != "true" ]
	do
		clear
		copyright
		echo "What would you like to do?"
		echo "1. See current downloads in progress"
		echo "2. See paused downloads"
		echo "3. Add file to download"
		echo "4. Remove file from downloads (downloaded file will be deleted!)"
		echo "5. Pause File being downloaded (you will have to bring it back to the active list later)"
		echo "6. Resume Paused download"
		echo "7. Stop all downloads in progress"
		echo "8. Start downloads that have not been paused"
		echo "9. Check if all ongoing downloads are ok"
		echo "10. See currently ongoing download in realtime"
		echo "0. exit" Exit
		echo -n "Please enter your choice"
		read choice
		case $choice in
			0) exit="true" ;;
			1) showstatus ;;
			2) showavailable ;;
			3) echo -n "Download URL: ";read url;echo -n "Save Location: "; read location; adddownloads "$location" "$url" ;;
			4) echo -n "Enter URL or filename: ";read filename; removedownloads $filename ;;
			5) echo -n "Enter URL or filename: ";read filename; pausedownloads  $filename;;
			6) echo -n "Enter URL or filename: ";read filename; resumedownloads $filename;;
			7) stopdownloads ;;
			8) getfiles ;;
			9) checkdownloads ;;
			10) echo -n "Enter download filename:";read filename; showprogress $filename ;;
			*) echo "Please enter a valid choice";
		esac
		echo "Press Enter to continue"
		read
	done
}
if [ $# -lt 1 ]
then
	help
else
	create_dir_structure
	while getopts "aghikcCsd:p:P:r:n:" Option
	do
	  case $Option in
	    h     ) help ; exit 0 ;;
	    a	  ) mode=available ;;
	    g     ) mode=getfiles ;;
	    i     ) mode=interactive ;;
	    k     ) mode=kill ;;
	    c     ) mode=clean ;;
	    C	  ) mode=check ;;
	    s	  ) mode=status ;;
	    d	  ) mode=delete;deletefile=$OPTARG ;;
	    p	  ) mode=pause;pausefile=$OPTARG ;;
	    P	  ) mode=progress;progressfile=$OPTARG ;;
	    r	  ) mode=resume;resumefile=$OPTARG ;;
	    n	  ) mode=add; adddetails=$OPTARG ;;
	    *     ) help ; exit $BADOPTION;;   # DEFAULT
	  esac
	done
fi

case $mode in
 "interactive"	) menu ;;
 "getfiles"	) getfiles ;;
 "kill"		) stopdownloads ;;
 "clean"	) cleandownloadlist ;;
 "status"	) showstatus ;;
 "add"		) location=`echo $adddetails | awk -F, '{print $1}'`
			url=`echo $adddetails | awk -F, '{print $2}'`
			echo -e "location: $location\n url: $url"
			if [ -z $location ] && [ -z $url ]
			then
				echo "Incorrect download specification"
				echo "Please enter download as: \"save location\",\"url\""
				exit 2
			elif [ -z $url ]
			then
				#that would mean that only an url was passed
				#The file should be saved in the default save location
				url=$adddetails
				location=$DEFAULT_SAVE_LOCATION
			fi
			echo going to add...
			adddownloads "$location" "$url"
			;;
 "delete"	) removedownloads $deletefile ;;
 "pause"	) pausedownloads $pausefile ;;
 "resume"	) resumedownloads $resumefile ;;
 "available"	) showavailable ;;
 "check"	) checkdownloads ;;
 "progress"	) showprogress $progressfile ;;
esac

#----------------------------------------
#function to check download logs and if there are any fully retrieved files, remove them from the download list

cleandownloadlist()
{
	TEMPFILE="$TMPDIR/cleaner.tmp.$$"
	LISTTEMP="$TMPDIR/downloadlist.tmp.$$"
	cd $PROGRESSLOGS
	grep -l "fully retrieved" * > $TEMPFILE 2>/dev/null
	grep -l "saved" * >> $TEMPFILE 2>/dev/null
	#add entries to download manager log to record fully retrieved files
	while read line
	do
		mv $PROGRESSLOGS/$line $COMPLETEDLOGS/$line
		echo "Removed fully retrieved download $line from the downloads list at `date`" >> $LOGFILE
	done<$TEMPFILE
	grep -vf $TEMPFILE $INPUTFILE > $LISTTEMP
	mv $LISTTEMP $INPUTFILE
	rm -f $TEMPFILE 
}

#----------------------------------------
#check for completed downloads, as well as resume any downloads that are not running due to link failures, etc
checkdownloads()
{
	cleandownloadlist
	if [ ! -f $PIDFILE ]
	then
		echo "No downloads currently in progress"
	else
		PROBLEMTEMP=$TMPDIR/checkdownloads.probems.tmp.$$
		PIDTEMP=$TMPDIR/checkdownloads.pid.tmp.$$
		REMOVEPIDS=$TMPDIR/checkdownloads.remove.pid.tmp.$$
		INPUTTEMP=$TMPDIR/checkdownloads.input.tmp.$$
		REMOVEINPUT=$TMPDIR/checkdownloads.remove.input.tmp.$$
		oldtty=`tty`
		while read line
		do
			PID=`echo $line|awk -F:: '{print $1}'`
			file=`echo $line|awk -F:: '{print $2}'`
      
	#===================================
			ps -p $PID|grep wget > /dev/null
			if [ $? != 0 ]
			then
    #===================================
				echo "$PID::$file" >> $REMOVEPIDS
				progressfile=$PROGRESSLOGS/$file
				if [ -f $progressfile ]
				then
					problemfile=$PROBLEMLOGS/$file
    #===================================
					#first, check if the save location was valid
					grep "\(No such file\|Not Found\)" $progressfile 2>&1 >/dev/null
					urlcheck=$?
					url=`grep $file $INPUTFILE|awk -F:: '{print $1}'`
					savelocation=`grep "/$file:" $INPUTFILE|awk -F:: '{print $2}'`
					echo "savelocation=$savelocation"
					echo "urlcheck=$urlcheck"
					if [ ! -d $savelocation ] || [ ! -w $savelocation ] || [ ! -x $savelocation ]
					then
						echo "download $file cannot be saved in $savelocation: check directory" >>$LOGFILE
						mv $progressfile $problemfile
						echo "$url::$savelocation" >> $REMOVEINPUT
					elif [ $urlcheck == 0 ]
					then
						echo "Remote server returned document not found error for $file" >> $LOGFILE
						mv $progressfile $problemfile
						echo "$url::$savelocation" >> $REMOVEINPUT
					else
    #===================================
					#add the file to the restart list
						grep $file $INPUTFILE >> $PROBLEMTEMP
					fi
				fi
			fi
		done<$PIDFILE
    #===================================
		#now, clean up the pidfile
		if [ -f $REMOVEPIDS ]
		then
			echo "Removing already completed and problematic downloads from active processes list:"
			grep -vf $REMOVEPIDS $PIDFILE > $PIDTEMP
			mv $PIDTEMP $PIDFILE
			rm -f $REMOVEPIDS
			echo "done"
		else
			echo "No problems found during check"
		fi
    #===================================
		#..and the download list
		if [ -f $REMOVEINPUT ]
		then
			grep -vf $REMOVEINPUT $INPUTFILE > $INPUTTEMP
			mv $INPUTTEMP $INPUTFILE
			rm -f $REMOVEINPUT
		fi
   #===================================
		#and restart the stopped wget processes
		if [ -f $PROBLEMTEMP ]
		then
			echo "Resuming problematic downloads...."
			while read line
			do
			    url=`echo $line|awk -F:: '{print $1}'`
			    savelocation=`echo $line|awk -F:: '{print $2}'`
			    filename=`echo $url|awk -F/ '{print $NF}'`
			    outputfile="$PROGRESSLOGS/$filename"
			    cd $savelocation 
			    nohup wget -c "$url"  -o $outputfile  > /dev/null &
			    PID=$!
			    echo "$PID::$filename" >> $PIDFILE 
			    echo "$filename"
			    echo -e "Resumed problematic download at `date`:\nURL:\t $url \nFILENAME:$savelocation/$filename\n">>$LOGFILE
			 done < $PROBLEMTEMP
			 rm -f $PROBLEMTEMP
			 echo "done"
		fi
	fi
}

#----------------------------------------

showpogress()
{
	#check for correct number of parameters
	if [ $# != 1 ]
	then
		echo "Incorrect call to showprogress function in program, please contact developer"
	else
		#first, check for sane downloads
		checkdownloads
		file=$1
		progressfile=$PROGRESSLOGS/$1
		if [ ! -f $progressfile ]
		#check for file in currently downloaded file logs
		then
			echo "The download specified is not currently in progress, please check filename and try again!"
		else
			echo "Please press <CTRL><C> to stop"
			tail -f $progressfile
		fi
	fi
}

#----------------------------------------
#fuction valid Url link
adddownloads()
{
	if [ $# -ne 2 ]
	then
		 echo "incorrect usage of the adddownloads function occured"
	         exit -1
        else
                       savelocation=$1
		       url=$2

		       #Simple validity check of url
		       protocol=`echo $url|awk -F:// '{print $1}'`
		       site=`echo $url|awk -F/ '{print $3}'`
		       if  [ "$protocol" != "http" ] && [ "$protocol" != "https" ] && [ "$protocol" != ftp ]
		       then
		       	echo "Please specify a valid url (only http, https, and ftp supported)"
			exit 1
		       fi
		       if [ ! -d $savelocation ] || [ ! -w $savelocation ] || [ ! -x $savelocation ]
		       then
		       	echo "download $file cannot be saved in $savelocation: check if directory exists and if you have permission to write to it" 
			exit 2
		       fi
		       echo "$url::$savelocation" >> $INPUTFILE
                       filename=`echo $url|awk -F/ '{print $NF}'`
                       outputfile="$PROGRESSLOGS/$filename"
                       echo "Starting download of $filename"
                       echo -e "Filename: $filename\nSave location: $savelocation\nURL: $url"
                       cd $savelocation
                       nohup wget -c "$url"  -o $outputfile > /dev/null &
                       PID=$!
                       echo "$PID::$filename" >> $PIDFILE
		       echo -e "Added download at `date`:\nURL:\t $url \nFILENAME:$savelocation/$filename\n">>$LOGFILE
	fi
}

#----------------------------------------

removedownloads()
{
	if [ $# -ne 1 ]
	then
		echo "incorrect usage of the removedownloads function occured"
		echo "Please contact developer to troubleshoot problem"
		exit -1
	else
		file=$1
		PROGRESSFILE=$PROGRESSLOGS/$file
		if [ ! -f $PROGRESSFILE ]
		then
			echo "The specified download is not in progress!"
		else
			cleanfile=$file
		fi
	fi
	if [ -n "$cleanfile" ]
	then
		url=`grep $cleanfile $INPUTFILE|awk -F:: '{print $1}'`
		savelocation=`grep $cleanfile $INPUTFILE|awk -F:: '{print $2}'`
		filename=`echo $url|awk -F/ '{print $NF}'`
		#kill the running download if it is running
		if [ -f $PIDFILE ]
		then
			PIDTEMP="$TMPDIR/pid.tmp.$$"
			PID=`grep $cleanfile $PIDFILE|awk -F:: '{print $1}'`
			kill $PID
			grep -v $cleanfile $PIDFILE >$PIDTEMP
			mv $PIDTEMP $PIDFILE
		fi
		#remove the download from the downloads list
	        LISTTEMP="$TMPDIR/downloadlist.tmp.$$"
	        grep -v $cleanfile $INPUTFILE > $LISTTEMP
	        mv $LISTTEMP $INPUTFILE
		#check if inputfile is empty, and remove it if so
		if [ ! -s $INPUTFILE ]
		then
			rm -f $INPUTFILE 
			echo "No more downloads in queue"
			echo "No more downloads in queue at `date`" >> $LOGFILE
		fi
		#remove the downloaded file itself
		rm -f "$savelocation/$filename"
		mv $PROGRESSLOGS/$cleanfile $REMOVEDLOGS/$cleanfile
		echo "Incomplete download permanently removed at `date`">> $REMOVEDLOGS/$cleanfile
		echo "Permanently removed partial download $cleanfile from download list and hard disk at `date`">> $LOGFILE
	fi
}

#----------------------------------------

pausedownloads()
{
        if [ $# -ne 1 ]
        then
                echo "incorrect usage of the pausedownloads function occured"
                echo "Please contact developer to troubleshoot problem"
                exit -1
        else
                file=$1
		PROGRESSFILE=$PROGRESSLOGS/$file
                if [ ! -f $PROGRESSFILE ]
                then
                        echo "The specified download is not in progress!"
                else
                        cleanfile=$file
                fi
        fi
        if [ -n "$cleanfile" ]
        then
                #kill the running download if it is running
                if [ -f $PIDFILE ]
                then
                        PIDTEMP="$TMPDIR/pid.tmp.$$"
                        PID=`grep $cleanfile $PIDFILE|awk -F:: '{print $1}'`
                        kill $PID
			grep -v $cleanfile $PIDFILE >$PIDTEMP
                        mv $PIDTEMP $PIDFILE
                fi
                #remove the download from the downloads list
                LISTTEMP="$TMPDIR/downloadlist.tmp.$$"
		grep $cleanfile $INPUTFILE >> $PAUSEDFILE
                grep -v $cleanfile $INPUTFILE > $LISTTEMP
                mv $LISTTEMP $INPUTFILE
		echo "Paused download $cleanfile at `date`" >> $LOGFILE
        fi
}

#----------------------------------------

showavailable()
{
        if [ -f $PAUSEDFILE ]
        then
                echo "Currently running downloads:"
                echo -e "URL\t\t\t\tSaved Location\t\t\t\tPercentage"
                while read line
                do
                        url=`echo $line|awk -F:: '{print $1}'`
		        savelocation=`echo $line|awk -F:: '{print $2}'`
        	        filename=`echo $url|awk -F/ '{print $NF}'`
			PROGRESSFILE=$PROGRESSLOGS/$filename
                        percentage=`tail $PROGRESSFILE -n2|head -n1|awk -F\% '{print $1}'|awk '{print $NF}'`
                        echo -e "$url\t\t$savelocation\t\t$percentage"
                done < $PAUSEDFILE
        else
                echo "No paused downloads"
        fi
}

#----------------------------------------

resumedownloads()
{
        if [ $# -ne 1 ]
        then
                echo "incorrect usage of the resumedownloads function occured"
                echo "Please contact developer to troubleshoot problem"
                exit -1
        else
                resumefile=$1
                if [ ! -f $PAUSEDFILE ] || [ ! `grep $resumefile $PAUSEDFILE` ]
                then
                        echo "The specified download is not available for resuming..please check available downloads with $0 -a!"
                else
		       line=`grep "$resumefile" $PAUSEDFILE`
		       echo $line >> $INPUTFILE
		       RESUMETEMP=$TMPDIR/resume.tmp.$$
		       grep -v $line $PAUSEDFILE > $RESUMETEMP
		       mv $RESUMETEMP $PAUSEDFILE
		       #remove paused file list if empty
		       if [ ! -s $PAUSEDFILE ]
		       then
		       		rm -f $PAUSEDFILE
		       fi
                       url=`echo $line|awk -F:: '{print $1}'`
                       savelocation=`echo $line|awk -F:: '{print $2}'`
                       filename=`echo $url|awk -F/ '{print $NF}'`
		       outputfile="$PROGRESSLOGS/$filename"
		       echo "Resuming download of $filename"
		       echo -e "Filename: $filename\nSave location: $savelocation\nURL: $url"
		       cd $savelocation
		       nohup wget -c "$url"  -o $outputfile  > /dev/null &
		       PID=$!
		       echo "$PID::$filename" >> $PIDFILE
		       echo "Resumed paused download $filename at `date`" >> $LOGFILE
                fi
        fi
}

#----------------------------------------

stopdownloads()
{
	echo -e "Checking if there are any downloads to stop...\n"

	if [ -f $PIDFILE ]
	then
        	while read line
	        do
        	        PID=`echo $line|awk -F:: '{print $1}'`
	                file=`echo $line|awk -F:: '{print $2}'`
                	echo "stopping download for $file"
        	        kill $PID
	        done<$PIDFILE
        	rm -f $PIDFILE
		echo "Stopped all active downloads at `date`" >> $LOGFILE
	else
		echo "No downloads to stop.."
	fi
	echo -e "\ndone"
}

#----------------------------------------
#function to fetch files as specified in the downloadlist

getfiles()
{
     if [ -s $INPUTFILE ]
     then
	#stop any downloads managed by getfiles
	stopdownloads
	#first, clean download list
	cleandownloadlist
	while read line
	do
		url=`echo $line|awk -F:: '{print $1}'`
		savelocation=`echo $line|awk -F:: '{print $2}'`
		filename=`echo $url|awk -F/ '{print $NF}'`
		outputfile="$PROGRESSLOGS/$filename"
		echo "Starting download for $filename"
		echo "changing directory to $savelocation"
		cd "$savelocation"
		echo "Started download of $url at `date`" >> $outputfile
		nohup wget -c "$url"  -o $outputfile > /dev/null &
		PID=$!
		echo "$PID::$filename" >> $PIDFILE
	done < $INPUTFILE
	echo "Started download of files in active list at `date`">> $LOGFILE
     else
     	echo "No files listed for download, you might want to add some by "downloads -n" or going to interactive mode"
     fi
}

#----------------------------------------

showstatus()
{
	if [ -s $PIDFILE ]
	then
		echo "Currently running downloads:"
		echo -e "PID\t\tFile\t\t\tPercentage\t\tSpeed"
		while read line
		do
			PID=`echo $line|awk -F:: '{print $1}'`
                        file=`echo $line|awk -F:: '{print $2}'`
			PROGRESSFILE=$PROGRESSLOGS/$file
			percentage=`tail $PROGRESSFILE -n2|head -n1|awk -F\% '{print $1}'|awk '{print $NF}'`
			speed=`tail $PROGRESSFILE -n2|head -n1|awk -F\% '{print $2}'`
			echo -e "$PID\t\t$file\t\t$percentage%\t\t$speed"
		done < $PIDFILE
	else
		echo "No managed downloads currently in progress"
	fi
}

#----------------------------------------
 #GOOD LUCK :)
#----------------------------------------