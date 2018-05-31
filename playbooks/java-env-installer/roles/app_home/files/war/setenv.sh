#
# Tomcat setenv.sh
#
# In most cases you do not have to modify this file.
# If you want to set JAVA_OPTS or CATALINA_OPTS, use "app_opts.sh".
#

APP_HOME=`realpath $CATALINA_HOME/..`
JAVA_HOME="$APP_HOME/jdk"
WEBAPPS_DIR="$CATALINA_HOME/webapps"
APP_LOG="$APP_HOME/logs/app.log"
APP_PID="$APP_HOME/app.pid"
CATALINA_PID="$APP_PID"

# Options to add when running apps
if [ -f $APP_HOME/app_opts.sh ]; then
  source $APP_HOME/app_opts.sh
fi

CATALINA_OPTS="$JVM_OPTS $APP_OPTS"
