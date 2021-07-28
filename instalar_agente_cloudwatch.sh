yum -y install amazon-cloudwatch-agent
amazon-linux-extras install -y collectd
yum -y install collectd-curl
cat <<EOT > /opt/aws/amazon-cloudwatch-agent/bin/config.json
{
   "agent":{
      "metrics_collection_interval":60,
      "run_as_user":"root",
      "debug": false
   },
   "logs":{
      "logs_collected":{
         "files":{
            "collect_list":[
               {
                  "file_path":"/var/log/messages",
                  "log_group_name":"OBM",
                  "log_stream_name":"{instance_id}"
               }
            ]
         }
      },
      "metrics_collected":{
         "prometheus":{
            "log_group_name":"prometheus-test",
            "prometheus_config_path":"/opt/aws/amazon-cloudwatch-agent/prometheus.yaml",
            "emf_processor":{
               "metric_declaration_dedup":true,
               "metric_namespace":"prometheus-test",
               "metric_unit":{
                  "ledger_blockchain_height":"Count"
               },
               "metric_declaration":[
                  {
                     "source_labels":[
                        "job"
                     ],
                     "label_matcher":"^MONITORACAO$",
                     "dimensions":[
                        [
                           "InstanceId",
                           "instance",
                           "channel"
                        ]
                     ],
                     "metric_selectors":[
                        "^ledger_blockchain_height$",
                        "^gossip_state_height$"
                     ]
                  }
               ]
            }
         }
      }
   },
   "metrics":{
     "append_dimensions":{
         "AutoScalingGroupName":"${aws:AutoScalingGroupName}",
         "ImageId":"${aws:ImageId}",
         "InstanceId":"${aws:InstanceId}",
         "InstanceType":"${aws:InstanceType}"
      },
      "metrics_collected":{
         "collectd":{
            
         },
         "cpu":{
            "measurement":[
               "cpu_usage_idle",
               "cpu_usage_iowait",
               "cpu_usage_user",
               "cpu_usage_system"
            ],
            "metrics_collection_interval":60,
            "totalcpu":false
         },
         "disk":{
            "measurement":[
               "used_percent",
               "inodes_free"
            ],
            "metrics_collection_interval":60,
            "resources":[
               "*"
            ]
         },
         "diskio":{
            "measurement":[
               "io_time",
               "write_bytes",
               "read_bytes",
               "writes",
               "reads"
            ],
            "metrics_collection_interval":60,
            "resources":[
               "*"
            ]
         },
         "mem":{
            "measurement":[
               "mem_used_percent"
            ],
            "metrics_collection_interval":60
         },
         "netstat":{
            "measurement":[
               "tcp_established",
               "tcp_time_wait"
            ],
            "metrics_collection_interval":60
         },
         "swap":{
            "measurement":[
               "swap_used_percent"
            ],
            "metrics_collection_interval":60
         }
      }
   }
}
EOT

cat <<EOT > /opt/aws/amazon-cloudwatch-agent/prometheus.yaml
global:
  scrape_interval: 5m
  scrape_timeout: 10s
scrape_configs:
- job_name: MONITORACAO
  sample_limit: 10000
  file_sd_configs:
    - files: ["/opt/aws/amazon-cloudwatch-agent/prometheus_sd_1.yaml"]
EOT

export INSTANCEID=$(cat /var/lib/cloud/data/instance-id)
cat <<EOT > /opt/aws/amazon-cloudwatch-agent/prometheus_sd_1.yaml
- targets:
    - 127.0.0.1:8443
  labels:
    InstanceId: $INSTANCEID
EOT

mkdir /etc/collectd/
cat <<EOT > /etc/collectd.conf
LoadPlugin logfile
LoadPlugin curl
LoadPlugin network

<Plugin logfile>
        LogLevel "info"
        File "/var/log/collectd.log"
        Timestamp true
        PrintSeverity false
</Plugin>

<Plugin curl>
    <Page "healthz">
        URL "http://localhost:8443/healthz";
        MeasureResponseCode true
    </Page>
</Plugin>

<Plugin network>
    <Server "127.0.0.1" "25826">
        SecurityLevel Encrypt
        Username "user"
        Password "secret"
    </Server>
</Plugin>
EOT

cat <<EOT > /etc/collectd/auth_file
user: secret
EOT

systemctl start collectd
systemctl enable collectd
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json
systemctl restart amazon-cloudwatch-agent
systemctl enable amazon-cloudwatch-agent
