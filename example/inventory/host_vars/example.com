---
elastic:
  instance_name: "master01"
  ip_address: "{{ hostvars[inventory_hostname]['service_ip'] }}"
  hostname: "{{inventory_hostname}}"
  nodetype: es_master
  ports:
    - "9200"
    - "9300"
  deployment_type: "single-node"
  noderoles:
    - data
    - master
    - ingest
    - transform
    - remote_cluster_client
  memory_limit: 6g
  cpu_limit: 2
  heap_size: "3g"
  java_opts: "-Xms3g -Xmx3g"
  rack_id: A1
  server_room: B1

kibana:
  instance_name: "internal01"
  ip_address: 0.0.0.0
  java_opts: "-Xms1g -Xmx1g"
  memory_limit: 2g
  cpu_limit: 1
  ports:
    - "5601"

metricbeat:
  instance_name: "internal01"
  ip_address: "0.0.0.0"
  memory_limit: 1g
  cpu_limit: 1
  ports:
    - "5066"
    - "5067"
  elastic_http_scheme: "{{es_api_scheme}}"
  kibana_http_scheme: "https"
  beat_http_scheme: "http"
  logstash_http_scheme: "http"
  certificate_validation: "certificate"
  source_cluster_name: "{{elastic_cluster_name}}"
  monitoring_cluster_url: "{{es_api_scheme}}://{{ hostvars[inventory_hostname]['service_ip'] }}:9200"
  monitoring_read_user_name: "remote_monitoring_user"
  monitoring_read_user_pass: "{{remote_monitoring_user_password}}"
  monitoring_write_user_name: "es_monitoring_user"
  monitoring_write_user_pass: "{{vault_es_monitoring_user_password}}"

logstash:
  instance_name: "internal01"
  ip_address: "0.0.0.0"
  java_opts: "-Xms1g -Xmx1g"
  memory_limit: 1g
  cpu_limit: 1
  xpack_management: false
  api_port: "9600"
  ports:
    - "5045"
    - "7500"
    - "7501"
    - "7502"
    - "7503"
    - "7504"
    - "7505"
    - "9600"
    - "9601"

filebeat:
  instance_name: "internal01"
  ip_address: "0.0.0.0"
  memory_limit: 1g
  cpu_limit: 1
  ports:
    - "5066"
