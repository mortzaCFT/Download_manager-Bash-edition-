#!/bin/bash

if [ "$me" != "root" ]
then
	echo "Run this script to install the program as root only"
	echo "The silent Install..."
	exit 1
fi
	cp downloads /usr/local/bin && echo "Installation complete"/n"Download manager ready to use"/n "Coded by mortza"


	
