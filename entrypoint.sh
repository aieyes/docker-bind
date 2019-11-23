#!/bin/bash
set -e

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
	local var="$1"
	local fileVar="${var}_FILE"
	local def="${2:-}"
	if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
		echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
		exit 1
	fi
	local val="$def"
	if [ "${!var:-}" ]; then
		val="${!var}"
	elif [ "${!fileVar:-}" ]; then
		val="$(< "${!fileVar}")"
	fi
	export "$var"="$val"
	unset "$fileVar"
}

file_env 'ROOT_PASSWORD'
file_env 'FTPUSER_PASSWORD'

ROOT_PASSWORD=${ROOT_PASSWORD:-password}
WEBMIN_ENABLED=${WEBMIN_ENABLED:-true}

BIND_DATA_DIR=${DATA_DIR}/bind
WEBMIN_DATA_DIR=${DATA_DIR}/webmin
PROFTP_DATA_DIR=${DATA_DIR}/proftpd
FTPUSER_PASSWORD=${FTPUSER_PASSWORD:-ftpuser}

# ProFTPD files
FTPD_BIN=/usr/sbin/proftpd
FTPD_CONF=/etc/proftpd/proftpd.conf
PIDFILE=/var/run/proftpd.pid

create_proftpd_data_dir() {

  # ftp root dir
  mkdir -p ${PROFTP_DATA_DIR}

  # populate default proftpd configuration if it does not exist
  if [ ! -d ${PROFTP_DATA_DIR}/etc ]; then
    mv /etc/proftpd ${PROFTP_DATA_DIR}/etc
  fi
  rm -rf /etc/proftpd
  ln -sf ${PROFTP_DATA_DIR}/etc /etc/proftpd
  chmod -R 0775 ${PROFTP_DATA_DIR}
  chown -R ${PROFTP_USER}:${PROFTP_USER} ${PROFTP_DATA_DIR}

  # make data dir
  if [ ! -d ${PROFTP_DATA_DIR}/data ]; then
    mkdir -p ${PROFTP_DATA_DIR}/data
    usermod -m -d ${PROFTP_DATA_DIR}/data ${PROFTP_USER}
    #chown ${PROFTP_USER}:${PROFTP_USER} ${PROFTP_DATA_DIR}/data
  fi
  usermod -m -d ${PROFTP_DATA_DIR}/data ${PROFTP_USER} || echo "usermod ftpuser"
}

create_bind_data_dir() {
  mkdir -p ${BIND_DATA_DIR}

  # populate default bind configuration if it does not exist
  if [ ! -d ${BIND_DATA_DIR}/etc ]; then
    mv /etc/bind ${BIND_DATA_DIR}/etc
  fi
  rm -rf /etc/bind
  ln -sf ${BIND_DATA_DIR}/etc /etc/bind
  chmod -R 0775 ${BIND_DATA_DIR}
  chown -R ${BIND_USER}:${BIND_USER} ${BIND_DATA_DIR}

  if [ ! -d ${BIND_DATA_DIR}/lib ]; then
    mkdir -p ${BIND_DATA_DIR}/lib
    chown ${BIND_USER}:${BIND_USER} ${BIND_DATA_DIR}/lib
  fi
  rm -rf /var/lib/bind
  ln -sf ${BIND_DATA_DIR}/lib /var/lib/bind
}

create_webmin_data_dir() {
  mkdir -p ${WEBMIN_DATA_DIR}
  chmod -R 0755 ${WEBMIN_DATA_DIR}
  chown -R root:root ${WEBMIN_DATA_DIR}

  # populate the default webmin configuration if it does not exist
  if [ ! -d ${WEBMIN_DATA_DIR}/etc ]; then
    mv /etc/webmin ${WEBMIN_DATA_DIR}/etc
  fi
  rm -rf /etc/webmin
  ln -sf ${WEBMIN_DATA_DIR}/etc /etc/webmin
}

set_root_passwd() {
  echo "root:$ROOT_PASSWORD" | chpasswd
}

create_proftpd_user() {
  useradd ${PROFTP_USER} || echo "$PROFTP_USER already exists."
  echo "$PROFTP_USER:$FTPUSER_PASSWORD" | chpasswd
}

create_named_pid_dir() {
  mkdir -m 0775 -p /var/run/named
  chown root:${BIND_USER} /var/run/named
}

create_bind_cache_dir() {
  mkdir -m 0775 -p /var/cache/bind
  chown root:${BIND_USER} /var/cache/bind
}

create_named_pid_dir
create_bind_data_dir
create_bind_cache_dir

create_proftpd_user
create_proftpd_data_dir

start_proftpd() {
  if [ -f $PIDFILE ]; then
   pid=`cat $PIDFILE`
  fi

  if [ ! -x $FTPD_BIN ]; then
    echo "$0: $FTPD_BIN: cannot execute"
    exit 1
  fi

  if [ -n "$pid" ]; then
    echo "$0: proftpd [PID $pid] already running"
    exit
  fi

  if [ -r $FTPD_CONF ]; then
    echo "Starting proftpd..."

    $FTPD_BIN -c $FTPD_CONF

  else
    echo "$0: cannot start proftpd -- $FTPD_CONF missing"
  fi
}

# allow arguments to be passed to named
if [[ ${1:0:1} = '-' ]]; then
  EXTRA_ARGS="$@"
  set --
elif [[ ${1} == named || ${1} == $(which named) ]]; then
  EXTRA_ARGS="${@:2}"
  set --
fi

# default behaviour is to launch named
if [[ -z ${1} ]]; then
  if [ "${WEBMIN_ENABLED}" == "true" ]; then
    create_webmin_data_dir
    set_root_passwd
    echo "Starting webmin..."
    /etc/init.d/webmin start
  fi

  echo "Starting proftpd..."
  start_proftpd

  echo "Starting named..."
  exec $(which named) -u ${BIND_USER} -g ${EXTRA_ARGS}

else
  exec "$@"
fi
