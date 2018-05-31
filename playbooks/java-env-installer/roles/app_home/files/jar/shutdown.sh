#!/bin/sh

# resolve links - $0 may be a softlink
PRG="$0"

while [ -h "$PRG" ]; do
  ls=`ls -ld "$PRG"`
  link=`expr "$ls" : '.*-> \(.*\)$'`
  if expr "$link" : '/.*' > /dev/null; then
    PRG="$link"
  else
    PRG=`dirname "$PRG"`/"$link"
  fi
done

# Get standard environment variables
PRGDIR=`dirname "$PRG"`

# Finally, get APP_HOME
APP_HOME=`cd "$PRGDIR/" >/dev/null; pwd`

# Locate and source setenv.sh
if [ -f $APP_HOME/setenv.sh ]; then
  source $APP_HOME/setenv.sh
else
  echo "setenv.sh not found, missing required parameters."
fi

# SHUTDOWN USING PID
if [ -f $APP_PID ]; then
  kill -9 `cat $APP_PID`
  rm -f $APP_PID
else
  echo "PID file not found. Aborting."
fi