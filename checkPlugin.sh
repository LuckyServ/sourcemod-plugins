#!/bin/bash
# 
# Prints the list of unused and missing plugins for sourcemod configs.
#
# Author: Luckylock
#
# ----------
# USER GUIDE
# ----------
#
# 1) cd in the l4d2 directory, then run this script
#
# 2) run the script once to get the options
#   ./checkPlugin.sh
#
# 3) Use the script like so:
#   ./checkPlugin.sh zonemod zm1v1 zm2v2 zm3v3 zonemod

# Validate number of arguments
if (( $# < 2 )); then
    echo "Usage: ./checkPlugin.sh <plugins optional directory> <config name 1> <config name 2> ..."
    echo
    echo "Possible <plugins optional directory>"
    find ./addons/sourcemod/plugins/optional/ -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort
    echo
    echo "Possible <config names>"
    find ./cfg/cfgogl -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort
    exit
fi

# Set our path variables
PATH_PLUGINS="addons/sourcemod/plugins/optional/$1"

for i in $(seq 2 $#); do
    [[ -d cfg/cfgogl/${!i} ]] || {
        echo "Invalid config path: cfg/cfgogl/${!i}"
        exit
    }
    PATH_CONFIG="$PATH_CONFIG cfg/cfgogl/${!i}"
done

[[ -d $PATH_PLUGINS ]] || {
    echo "Invalid plugin path: $PATH_PLUGINS"
    exit
}

# Get the list of used plugins in optional
USED_PLUGINS="$(grep '^ *sm plugins load optional' $(find $PATH_CONFIG -type f) -h | sed 's/sm plugins load //g' | sort -u)"

# Get the list of plugins that are present in optional
ALL_PLUGINS="$(find "$PATH_PLUGINS" -type f | sed 's/addons\/sourcemod\/plugins\///g' | sort)"

echo "-----------------------"
echo "List of unused plugins:"
echo "-----------------------"
comm -3 <(echo "$ALL_PLUGINS") <(echo "$USED_PLUGINS") | grep '^o' | sed -E "s/(.*)/addons\/sourcemod\/plugins\/\1/g"

echo

echo "------------------------"
echo "List of missing plugins:"
echo "------------------------"
grep --color -f <(comm -3 <(echo "$USED_PLUGINS") <(echo "$ALL_PLUGINS") | grep '^o') $(find $PATH_CONFIG -type f)
