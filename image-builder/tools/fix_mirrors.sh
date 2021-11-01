#!/bin/bash
# This script is to workaround very unreliable mirrors in opendev infra.
# Note that proxy support is not needed, as this problem only exists for
# upstream mirrors not behind any proxies.

for bad_mirror in $@; do
    # See if troublesome mirror is configured here
    if apt-cache policy | grep "$bad_mirror"; then
	echo "Detected troubled apt-cache policy:"
	apt-cache policy
	# Replace troublesome mirror with working mirror if it's not reachable
	# Try installing a small package
	apt -y install cpu-checker || (
	    bad_mirror_uri="$(apt-cache policy | grep archive | head -1 | awk '{print $2}')"
	    sed -i "s@$bad_mirror_uri@http://us.archive.ubuntu.com/ubuntu@g" /etc/apt/sources.list
	    sed -i "s@$bad_mirror_uri@http://us.archive.ubuntu.com/ubuntu@g" /etc/apt/sources.list.d/*
	    echo "Modified apt-cache policy:"
	    apt-cache policy
	    echo "Update apt sources list:"
	    apt -y update
	    )
        break
    fi
done
