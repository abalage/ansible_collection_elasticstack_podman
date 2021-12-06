# Ansible Collection for deploying Elasticsearch Stack by using podman pods and containers

## About

To read more about this collection, check this blog post. [https://balagetech.com/deploy-elasticsearch-stack-with-podman-and-ansible](https://balagetech.com/deploy-elasticsearch-stack-with-podman-and-ansible)

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

The persistent volumes of containers are located under two directories by default:

- /var/src/containers/volume/
- /var/src/containers/config/

These directories are the de facto locations for such purposes at least on RHEL systems and derivatives (SELinux contexts).

### Example playbook

You should find an example inventory in `[https://github.com/abalage/ansible_collection_elasticstack_podman/tree/main/example/playbook](examples/playbook)` directory of the repo.

### Example inventory

You should find an example inventory in `[https://github.com/abalage/ansible_collection_elasticstack_podman/tree/main/example/inventory](examples/inventory)` directory of the repo.

Regarding `host_vars`. Please be careful when you change the key names in the (Python) dicts of 'elastic', 'kibana', and so on. They will not be merged [when the variables are evaluated](https://docs.ansible.com/ansible/latest/user_guide/playbooks_variables.html#variable-precedence-where-should-i-put-a-variable).

### Getting the `cluster_uuid`

Normally the cluster_uuid would not be required as compoents with output.elasticsearch will find it out automatically, however there could be cases (ie. using a dedicated monitoring cluster) where this information is required.

1. On first run the UUID will be generated automatically. Go to Stack Monitoring in Kibana and find the cluster_uuid in the url.
2. Adjust the cluster_uuid in the inventory
3. Run ansible-playbook again with ```--tags metricbeat --tags filebeat```

## Securing Elasticsearch cluster

There is a multi layered security guide for Elasticsearch.

1. Create credentials for built-in users:
   This is already handled by the playbooks.
   Reference: https://www.elastic.co/guide/en/elasticsearch/reference/current/security-minimal-setup.html
2. Configure TLS for transport layer. This is for traffic happening over TCP port 9300.
   The playbooks handle these once you manually placed the certificates either in PKCS12 (preferred) or in PEM format into the inventory.
   Reference: https://www.elastic.co/guide/en/elasticsearch/reference/current/security-basic-setup.html
3. Configure TLS for HTTP REST API traffic. This is for traffic happening over TCP port 9200.
   Most notable examples are Kibana and Beats.
   The playbooks handle these once you manually placed the certificates either in PKCS12 (preferred) or in PEM format into the inventory.
   Reference: https://www.elastic.co/guide/en/elasticsearch/reference/current/security-basic-setup-https.html

To create these manually follow these steps.

```bash
 $ mkdir -p /tmp/certs && podman run --rm -ti -v /tmp/certs/:/tmp/certs/ docker.elastic.co/elasticsearch/elasticsearch:7.15.1 bash
 $ ./bin/elasticsearch-certutil ca
 $ ./bin/elasticsearch-certutil cert --ca elastic-stack-ca.p12 --name example.com
 $ ./bin/elasticsearch-certutil http
 $ cp *.zip *.p12 /tmp/certs/
 $ exit
```

```bash
 $ mkdir -p /tmp/certs && podman run --rm -ti -v /tmp/certs/:/tmp/certs/ docker.elastic.co/elasticsearch/elasticsearch:7.15.1 bash
 $ ./bin/elasticsearch-certutil ca --pem
 $ unzip elastic-stack-ca.zip
 $ ./bin/elasticsearch-certutil cert --pem --ca-key ca/ca.key --ca-cert ca/ca.crt --name example.com
 $ ./bin/elasticsearch-certutil http
 $ cp *.zip /tmp/certs/
 $ exit
```

Unpack the archives to access the certificates and keys.
You should add the appropriate certificates and keys into the inventory in `group_vars/elastic_stack/vault`.
Do not forget to use inline vaults. Especially in case you use Ansible Tower or AWX.

## FAQ

1. Why not using docker-compose?
   - Why no to use [anything else than Docker](https://balagetech.com/convert-docker-compose-services-to-pods)?

2. Why pods and not plain containers?
   - "[Pods](https://kubernetes.io/docs/concepts/workloads/pods) are the smallest deployable units of computing that you can create and manage in Kubernetes."

3. Can I use my own container images?
   - Yes you can overwrite the necessary image references in the inventory.

## Known issues

Some features are not planned, while othere are on the TODO list.

- (todo) no ansible tests yet
- (todo) no official docs/ yet
- (todo) FQCN is not used everywhere where it should
- (todo) There is no automated SSL certificate creation implemented. See [Howto create SSL certs](#howtossl) below.
- (todo) Stale or orphan systemd units are not cleaned up
- (todo) Kibana uses the instance certificate and key for HTTPS. It is a security antipattern.
- (todo) The whole dict (ie. `elastic`) needs to be copied into host_vars to overwrite it without breaking it. The `es_roles_custom` and `es_users_custom` dicts do already have a solution to that issue in elasticsearch/tasks/main.yml.
- (todo) Place the credentials into keystores and do not leave them in plain text on the filesystem.
- (not planned) lack of AD integration
- (not planned) No license management is implemented.
