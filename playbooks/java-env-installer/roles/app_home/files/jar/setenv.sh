#
# Java jar setenv.sh
#
# In most cases you do not have to modify this file.
# If you want to set JAVA_OPTS or CATALINA_OPTS, use "app_opts.sh".
#

JAVA_HOME="$APP_HOME/jdk"
WEBAPPS_DIR="$APP_HOME/webapps"
APP_PID="$APP_HOME/app.pid"
APP_LOG="$APP_HOME/logs/app.log"

# Get APP_OPTS from another file
if [ -f $APP_HOME/app_opts.sh ]; then
  source $APP_HOME/app_opts.sh
fi
