#
# Java jar startup.sh scripts
#
# **In most cases, you don't have to modify this file.**
#

# Count jar file in ARTIFACT_DIR. Throw error if not equal to one.

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

if [ -f "$APP_PID" ]; then
  if [ -s "$APP_PID" ]; then
    echo "Existing PID file found during start."
    if [ -r "$APP_PID" ]; then
      PID=`cat "$APP_PID"`
      ps -p $PID >/dev/null 2>&1
      if [ $? -eq 0 ] ; then
        echo "App appears to still be running with PID $PID. Start aborted."
        echo "If the following process is not your app process, remove the PID file and try again:"
        ps -f -p $PID
        exit 1
      else
        echo "Removing/clearing stale PID file."
        rm -f "$APP_PID" >/dev/null 2>&1
        if [ $? != 0 ]; then
          if [ -w "$APP_PID" ]; then
            cat /dev/null > "$APP_PID"
          else
            echo "Unable to remove or clear stale PID file. Start aborted."
            exit 1
          fi
        fi
      fi
    else
      echo "Unable to read PID file. Start aborted."
      exit 1
    fi
  else
    rm -f "$APP_PID" >/dev/null 2>&1
    if [ $? != 0 ]; then
      if [ ! -w "$APP_PID" ]; then
        echo "Unable to remove or write to empty PID file. Start aborted."
        exit 1
      fi
    fi
  fi
fi

# Locate jar file
jar_file=`find $ARTIFACT_DIR -maxdepth 1 -name "*.jar"`
jar_file_count=`echo $jar_file | wc -w`

if [ "$jar_file_count" -eq "0" ]; then
  echo "Error: Jar file not found."
  exit 1
elif [ "$jar_file_count" -gt "1" ]; then
  echo "Error: More than one jar file found:"
  echo ""
  echo "`for i in $jar_file; do echo $i ; done`"
  echo ""
  echo "Aborting."
  exit 1
else
  echo "Jar file found: $jar_file"
fi

# And Run it.

nohup $JAVA_HOME/bin/java $JVM_OPTS $JAVA_OPTS -jar $jar_file -server $APP_OPTS  >> $APP_LOG 2>&1 &
echo $! > $APP_PID