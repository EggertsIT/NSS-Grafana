#!/bin/bash

apt upgrade -y && apt upgrade -y
apt install -y apt-transport-https software-properties-common wget curl
sudo mkdir -p /etc/apt/keyrings/ 
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list
apt update -y
apt install grafana-enterprise -y
systemctl daemon-reload
systemctl start grafana-server
systemctl enable grafana-server.service
apt update -y
apt install loki promtail syslog-ng -y
systemctl enable loki
systemctl enable promtail
systemctl stop loki
systemctl stop promtail
systemctl stop syslog-ng
cat > /etc/loki/config.yml << EOF
auth_enabled: false
server:
  http_listen_port: 3100
  grpc_listen_port: 9096
  http_server_write_timeout: 310s
  http_server_read_timeout: 310s
ingester:
  chunk_encoding: snappy
common:
  instance_addr: 127.0.0.1
  path_prefix: /tmp/loki
  storage:
    filesystem:
      chunks_directory: /tmp/loki/chunks
      rules_directory: /tmp/loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory
querier:
  max_concurrent: 8
  query_timeout: 300s
  engine:
    timeout: 300s
query_range:
  results_cache:
    cache:
      embedded_cache:
        enabled: true
        max_size_mb: 100
limits_config:
  query_timeout: 300s
  split_queries_by_interval: 15m
  max_query_parallelism: 24 
schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h
frontend_worker:
  match_max_concurrent: true
ruler:
  alertmanager_url: http://127.0.0.1:9093
analytics:
  reporting_enabled: false
EOF

cat > /etc/promtail/config.yml << EOF
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/tmp/promtail-syslog-positions.yml

clients:
  - url: http://localhost:3100/loki/api/v1/push

scrape_configs:
  - job_name: zscaler
    syslog:
      listen_address: 127.0.0.1:1514
      labels:
        job: zscaler
    pipeline_stages:
    - logfmt:
        mapping:
          action:
          reason:
          proto:
          dept:

    - labels:
        action: action
        reason: reason
        proto: proto
        dept: dept

        
    relabel_configs:
      - source_labels: [__syslog_message_hostname]
        target_label: host
EOF

cat > /etc/syslog-ng/syslog-ng.conf << EOF
@version: 3.35
@include "scl.conf"

# Syslog-ng configuration file, compatible with default Debian syslogd
# installation.

# First, set some global options.
options { chain_hostnames(off); flush_lines(0); use_dns(no); use_fqdn(no);
          dns_cache(no); owner("root"); group("adm"); perm(0640);
          stats_freq(0); bad_hostname("^gconfd$");
};

########################
# Sources
########################
# This is the default behavior of sysklogd package
# Logs may come from unix stream, but not from another machine.
#
source s_src {
       system();
       internal();
};
source s_net {
               tcp(ip(0.0.0.0) port(514));
               udp(ip(0.0.0.0) port(514));
};
# If you wish to get logs from remote machine you should uncomment
# this and comment the above source line.
#
#source s_net { tcp(ip(127.0.0.1) port(1000)); };

########################
# Destinations
########################
# First some standard logfile
#
destination d_auth { file("/var/log/auth.log"); };
destination d_cron { file("/var/log/cron.log"); };
destination d_daemon { file("/var/log/daemon.log"); };
destination d_kern { file("/var/log/kern.log"); };
destination d_lpr { file("/var/log/lpr.log"); };
destination d_mail { file("/var/log/mail.log"); };
destination d_syslog { file("/var/log/syslog"); };
destination d_user { file("/var/log/user.log"); };
destination d_uucp { file("/var/log/uucp.log"); };

# This files are the log come from the mail subsystem.
#
destination d_mailinfo { file("/var/log/mail.info"); };
destination d_mailwarn { file("/var/log/mail.warn"); };
destination d_mailerr { file("/var/log/mail.err"); };

# Logging for INN news system
#
destination d_newscrit { file("/var/log/news/news.crit"); };
destination d_newserr { file("/var/log/news/news.err"); };
destination d_newsnotice { file("/var/log/news/news.notice"); };

# Some 'catch-all' logfiles.
#
destination d_debug { file("/var/log/debug"); };
destination d_error { file("/var/log/error"); };
destination d_messages { file("/var/log/messages"); };

# The root's console.
#
destination d_console { usertty("root"); };

# Virtual console.
#
destination d_console_all { file("tty10"); };

# The named pipe /dev/xconsole is for the nsole' utility.  To use it,
# you must invoke nsole' with the -file' option:
#
#    $ xconsole -file /dev/xconsole [...]
#
destination d_xconsole { pipe("/dev/xconsole"); };

# Send the messages to an other host
#
#destination d_net { tcp("127.0.0.1" port(1000) log_fifo_size(1000)); };

# Debian only
destination d_ppp { file("/var/log/ppp.log"); };

########################
# Filters
########################
# Here's come the filter options. With this rules, we can set which 
# message go where.

filter f_dbg { level(debug); };
filter f_info { level(info); };
filter f_notice { level(notice); };
filter f_warn { level(warn); };
filter f_err { level(err); };
filter f_crit { level(crit .. emerg); };

filter f_debug { level(debug) and not facility(auth, authpriv, news, mail); };
filter f_error { level(err .. emerg) ; };
filter f_messages { level(info,notice,warn) and 
                    not facility(auth,authpriv,cron,daemon,mail,news); };

filter f_auth { facility(auth, authpriv) and not filter(f_debug); };
filter f_cron { facility(cron) and not filter(f_debug); };
filter f_daemon { facility(daemon) and not filter(f_debug); };
filter f_kern { facility(kern) and not filter(f_debug); };
filter f_lpr { facility(lpr) and not filter(f_debug); };
filter f_local { facility(local0, local1, local3, local4, local5,
                        local6, local7) and not filter(f_debug); };
filter f_mail { facility(mail) and not filter(f_debug); };
filter f_news { facility(news) and not filter(f_debug); };
filter f_syslog3 { not facility(auth, authpriv, mail) and not filter(f_debug); };
filter f_user { facility(user) and not filter(f_debug); };
filter f_uucp { facility(uucp) and not filter(f_debug); };

filter f_cnews { level(notice, err, crit) and facility(news); };
filter f_cother { level(debug, info, notice, warn) or facility(daemon, mail); };

filter f_ppp { facility(local2) and not filter(f_debug); };
filter f_console { level(warn .. emerg); };

########################
# Log paths
########################
log { source(s_src); filter(f_auth); destination(d_auth); };
log { source(s_src); filter(f_cron); destination(d_cron); };
log { source(s_src); filter(f_daemon); destination(d_daemon); };
log { source(s_src); filter(f_kern); destination(d_kern); };
log { source(s_src); filter(f_lpr); destination(d_lpr); };
log { source(s_src); filter(f_syslog3); destination(d_syslog); };
log { source(s_src); filter(f_user); destination(d_user); };
log { source(s_src); filter(f_uucp); destination(d_uucp); };

log { source(s_src); filter(f_mail); destination(d_mail); };
#log { source(s_src); filter(f_mail); filter(f_info); destination(d_mailinfo); };
#log { source(s_src); filter(f_mail); filter(f_warn); destination(d_mailwarn); };
#log { source(s_src); filter(f_mail); filter(f_err); destination(d_mailerr); };

log { source(s_src); filter(f_news); filter(f_crit); destination(d_newscrit); };
log { source(s_src); filter(f_news); filter(f_err); destination(d_newserr); };
log { source(s_src); filter(f_news); filter(f_notice); destination(d_newsnotice); };
#log { source(s_src); filter(f_cnews); destination(d_console_all); };
#log { source(s_src); filter(f_cother); destination(d_console_all); };

#log { source(s_src); filter(f_ppp); destination(d_ppp); };

log { source(s_src); filter(f_debug); destination(d_debug); };
log { source(s_src); filter(f_error); destination(d_error); };
log { source(s_src); filter(f_messages); destination(d_messages); };

log { source(s_src); filter(f_console); destination(d_console_all);
                                    destination(d_xconsole); };
log { source(s_src); filter(f_crit); destination(d_console); };

# All messages send to a remote site
destination d_loki {
        syslog("127.0.0.1" transport("tcp") port(1514));
    };
log {
	source(s_net);
	destination(d_loki);
};
###
# Include all config files in /etc/syslog-ng/conf.d/
###
@include "/etc/syslog-ng/conf.d/*.conf"
EOF
systemctl start loki
systemctl start promtail
systemctl start syslog-ng
cat > /tmp/datasource.json << EOF
{
    "name": "Loki",
    "type": "loki",
    "url": "http://localhost:3100",
    "access": "proxy",
    "isDefault": true,
    "jsonData": {}
}
EOF
curl -X POST -H "Content-Type: application/json" -u "admin:admin" -d @/tmp/datasource.json localhost:3000/api/datasources
systemctl restart loki
systemctl restart promtail
systemctl restart syslog-ng
echo ""
echo "Done!!"
