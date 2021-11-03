# Ansible Collection for deploying Elasticsearch Stack by using podman pods and containers

## About
### Use case
I would like to have a production grade Elasticsearch cluster - with all of its additional components - deployed in containers in multiple hosts.

Operation costs should be reduced by using Ansible for automation but without introducing the complexity (and step learning curve) of a Kubernetes distribution.

It is admittedly a transition state between [Pets and Cattle](https://www.hava.io/blog/cattle-vs-pets-devops-explained).

Containers are used for:
 - Limiting the system resources (CPU, RAM) to components (also being able to comply to License)
 - As a 'packaging tool' for shipping the software with its dependencies.
 - Preparing landscape when situation is getting bigger. Ie. [Build Kubernetes pods with Podman play kube](https://www.redhat.com/sysadmin/podman-play-kube-updates)

### Implemented components

All components are based on the official Elasticsearch [Docker images](https://docker.elastic.co).

The following roles can be installed.

 - Elasticsearch
 - Kibana
 - Filebeat (automatically configured for ingesting logs from all installed components)
 - Metricbeat (automatically configured for monitoring all installed components)
 - Logstash

### Host-networking
Although you can use bridge networking (CNI), the current setup works best when used with host networking.

Why to use host-networking:
 - Easy scalability (adding plus hosts by IP address is easy)
 - The lack of oob DNS resolution between containers. There is a workaround by using dnsname CNI plugin from https://github.com/containers/dnsname however you still sticked to a single host.
 - Setting up overlay network over CNI between multiple nodes is not easy, so as the management of the containers.

### Scalability
Should you want to extend your landscape with multiple elasticsearch hosts.

1. Just add the extra nodes to the inventory into their appropriate groups.
2. Extend `host_vars` with a file representing the new host from the inventory
3. Run ansible-playbook again.

### Reverse proxy
You can use any kind of reverse proxies to provide access to Kibana or any other components.

I suggest to use Traefik for auto-discovery. Kibana container is labeled up for Traefik by default.

Setting up podman for providing a Docker-compatible socket is easy.

```yml
- name: Setting up podman socket for Docker compatibility
  block:
    - name: Enable the systemd socket of podman
      ansible.builtin.systemd:
        name: "podman.socket"
        state: "started"
        enabled: "yes"

    - name: get the path to podman socket
      shell:
        cmd: systemctl show podman.socket | grep ListenStream | cut -d"=" -f2
      register: podman_listenstream

    - name: set the fact of location of podman socket
      set_fact:
        podman_socket: "{{ podman_listenstream.stdout }}"
```

Reference `podman_socket` when mounting 'Docker's socket' into Traefik.

```yml
    volume:
      - "{{ ansible_facts['podman_socket'] | default('/run/podman/podman.sock') }}:/var/run/docker.sock"
```

### Logstash pipelines

There are two pipeline schemes already provided.
 - Arcsight
 - Beat

They are disabled by default.
For usage please check `logstash_pipelines` in roles/logstash/defaults/main.yml

## Automatic startup of pods and container after host reboots
Each roles creates a systemd service units both for pods and containers.

Only the pod service unit will be 'enabled'.

SystemD will take care of automatically restarting the pods and the containers upon reboot and in case of '[on-failure](https://docs.podman.io/en/latest/markdown/podman-generate-systemd.1.html)'.

### Migration after hosts are renamed

Hostnames are included in the name of persistent directories. Although it is not a best practice (see pets vs cattle), it helps manual troubleshooting.

If you plan to rename hosts you should:
1. Create a new inventory entry for the host(s)
2. Issue `ansible-playbook -i new_inventory playbook.yml --tags createdirs`
3. Stop the pods (and remove the orphan systemd service units in /etc/systemd/system/ )
4. Manually move the data from old persistend directories to the recently created.
5. Redeploy but now use the new inventory

## Usage

### Persistent volumes

The persistent volumes of containers are located under two directories:

- /var/src/containers/volume/
- /var/src/containers/config/

These directories are the de facto locations for such purposes at least on RHEL systems and derivatives (SELinux contexts).

Configuration files are generated from templates.

### Example playbook

collections/requirements.yml
```yml
---
collections:
  - containers.podman
  - community.general
  - abalage.elasticstack_podman
```

playbook.yml
```yml
---
- hosts: all
  remote_user: root
  become: yes
  become_method: sudo
  collections:
    - abalage.elasticstack_podman

- name: Deploy Elasticsearch hosts
  hosts: elastic_hosts
  roles:
    - name: abalage.elasticstack_podman.elasticsearch
      tags:
        - elasticsearch
        - elk

- name: Deploy Kibana hosts
  hosts: kibana_hosts
  roles:
    - name: abalage.elasticstack_podman.kibana
      tags:
        - kibana
        - elk

- name: Deploy Filebeat hosts
  hosts: filebeat_hosts
  roles:
    - name: abalage.elasticstack_podman.filebeat
      tags:
        - filebeat
        - elk
        - beats

- name: Deploy Metricbeat hosts
  hosts: metricbeat_hosts
  roles:
    - name: abalage.elasticstack_podman.metricbeat
      tags:
        - metricbeat
        - elk
        - beats

- name: Deploy Logstash hosts
  hosts: logstash_hosts
  roles:
    - name: abalage.elasticstack_podman.logstash
      tags:
        - logstash
        - elk
```

### Example host inventory

```ini
[all]
example.com    ansible_connection=local

[all:vars]
service_ip=172.18.0.1
firewalld_zone="internal"
timezone="Europe/Budapest"

##### elastic stack #####
[elastic_stack:vars]
cluster_uuid='aaaaaabbbbbcccccc'

[elastic_stack:children]
elastic_hosts
kibana_hosts
metricbeat_hosts
filebeat_hosts
logstash_hosts

[elastic_hosts:children]
elastic_master_nodes
elastic_ml_nodes

[elastic_master_nodes]
example.com

[elastic_ml_nodes]

[kibana_hosts]
example.com

[metricbeat_hosts]
example.com

[filebeat_hosts]
example.com

[logstash_hosts]
example.com
```

### Getting the cluster_uuid

FIXME

### Filling up the inventory variables

There are two place where you should change the default values

#### Group vars: 'elastic_stack/vault'

Here you should add the required certificates in PEM format and other secrets.
Do not forget to encrypt it by ansible-vault.

```yml
---
vault_cluster_ca_crt: |
    -----BEGIN CERTIFICATE-----
    -----END CERTIFICATE-----

vault_cluster_instance_crt: |
    -----BEGIN CERTIFICATE-----
    -----END CERTIFICATE-----

vault_cluster_instance_cert_key: |
    -----BEGIN RSA PRIVATE KEY-----
    -----END RSA PRIVATE KEY-----

vault_apm_system_password: ""
vault_beats_system_password: ""
vault_elastic_password: ""
vault_filebeat_kibana_setup_user_password: ""
vault_filebeat_publisher_user_password: ""
vault_filebeat_setup_user_password: ""
vault_kibana_system_password: ""
vault_logstash_admin_password: ""
vault_logstash_internal_password: ""
vault_logstash_system_password: ""
vault_logstash_user_password: ""
vault_remote_monitoring_user_password: ""

# es_users_custom
vault_sng_writer_password: ""
vault_es_monitoring_user_password: ""

vault_kibana_fqdn: ""

vault_kibana_security_encryptionkey: ""
vault_kibana_savedobjects_encryptionkey: ""
vault_kibana_reporting_encryptionkey: ""
```

#### Host vars

Not all of these are required as long as the defaults are suitable for you.

Please be careful when you change the key names in the (Python) dicts of 'elastic', 'kibana', and so on. They will not be merged [when the variables are evaluated](https://docs.ansible.com/ansible/latest/user_guide/playbooks_variables.html#variable-precedence-where-should-i-put-a-variable).

Also see [Limitations](#Limitations)

```yaml
---
elastic:
  instance_name: "master01"
  ip_address: 172.18.0.1
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
  certificate_validation: "none"
  source_cluster_name: "{{elastic_cluster_name}}"
  monitoring_cluster_url: "https://{{inventory_hostname}}:9200"
  monitoring_read_user_name: "remote_monitoring_user"
  monitoring_read_user_pass: "{{remote_monitoring_user_password}}"
  monitoring_write_user_name: "remote_monitoring_user"
  monitoring_write_user_pass: "{{remote_monitoring_user_password}}"

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
```

## Securing Elasticsearch cluster

There is a multi layered security guide for Elasticsearch.

1. Create credentials for built-in users:
   This is already handled by the playbooks.
   Reference: https://www.elastic.co/guide/en/elasticsearch/reference/current/security-minimal-setup.html
2. Configure TLS for transport layer. This is for traffic happening over TCP port 9300.
   The playbooks handle these once you manually placed the certificates in PEM format into the inventory.
   Reference: https://www.elastic.co/guide/en/elasticsearch/reference/current/security-basic-setup.html
3. Configure TLS for HTTP REST API traffic. This is for traffic happening over TCP port 9200.
   Most notable examples are Kibana and Beats.
   This is not implemented yet by the playbooks. See [Limitations](#Limitations)
   Reference: https://www.elastic.co/guide/en/elasticsearch/reference/current/security-basic-setup-https.html

### Howto create SSL certs

Follow the steps displayed on screen to create certificates in PEM format.

```bash
 $ mkdir -p /tmp/certs && podman run --rm -ti -v /tmp/certs/:/tmp/certs/ elasticsearch:7.15.1 bash
 $ ./bin/elasticsearch-certutil ca --pem
 $ cp elastic-stack-ca.zip /tmp/certs/
 $ ./bin/elasticsearch-certutil cert --pem --ca-key ca/ca.key --ca-cert ca/ca.crt --name newchuck
 $ cp certificate-bundle.zip /tmp/certs/
 $ ./bin/elasticsearch-certutil http
 $ cp elasticsearch-ssl-http.zip /tmp/certs/

```

Unpack the archives to access the certificates and keys.
You should add the appropriate certificates and keys into the inventory in `group_vars/elastic_stack/vault`.

## FAQ

1. Why not using docker-compose?
   - Why no to use [anything else than Docker](https://balagetech.com/convert-docker-compose-services-to-pods)?

2. Why pods and not plain containers?
   - "[Pods](https://kubernetes.io/docs/concepts/workloads/pods) are the smallest deployable units of computing that you can create and manage in Kubernetes."

3. Can I use my own container images?
   - Yes you can overwrite the necessary image references in the inventory.

## Limitations

Some features are not planned, while othere are on the TODO list.

- (not planned) No license management is implemented.
- (todo) There is no automated SSL certificate creation implemented. See [Howto create SSL certs](#howtossl) below.
- (todo) Use separate certificates for HTTP REST traffic. Currently the same cert and key is used.
- (todo) Stale or orphan systemd units are not cleaned up
- (todo) Kibana uses the instance certificate and key for HTTPS. It is a security antipattern.
- (todo) The whole dict (ie. `elastic`) needs to be copied into host_vars to overwrite it without breaking it. The `es_roles_custom` and `es_users_custom` dicts do already have a solution to that issue in elasticsearch/tasks/main.yml.
- (todo) Place the credentials into keystores and do not leave them in plain text on the filesystem.

## Development

Should you want to adjust for example the configuraiton of a component, then have a look at the available options in the appropriate templates and defaults file.

For example the default values of Elasticsearch can be found here: `~/.ansible/collections/ansible_collections/abalage/elasticstack_podman/roles/elasticsearch/defaults/main.yml`

While the template which utilizes them can be found here: `~/.ansible/collections/ansible_collections/abalage/elasticstack_podman/roles/elasticsearch/templates/elasticsearch.yml.j2`

In most cases it is enough to overwrite a variable's value in inventory.

