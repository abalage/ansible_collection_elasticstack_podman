# elk-podman-deployment
Deployment playbooks for Elasticsearch Stack by using podman containers

## Requirements

Make sure either your inventory or your runtime environment contains the variable `ansible_remote_user` which is specific to your environment.

## Other collections and roles

This deployment uses an ansible.cfg which configures ansible-galaxy to download requirements into the current working directory.

[Thanks for the hint Jeff](https://www.jeffgeerling.com/blog/2020/ansible-best-practices-using-project-local-collections-and-roles).

Use can download the requirements like this.
```bash
$ ansible-galaxy collection install --force -r collections/requirements.yml
```

## Architecture

The playbook expects several inventory groups to exist.

  - [elastic_hosts] - hosts which has running elasticsearch node(s)
  - [kibana_hosts] - hosts which serve as a kibana endpoint
  - [filebeat_hosts]
  - [metricbeat_hosts]
  - [logstash_hosts]

A host can be member of any of the groups at the same time if [rootfull host networking](https://podman.io/getting-started/network.html) is used.

## Tags

Some parts of the playbook can be invoked separetely or can be excluded.

```
playbook: playbook.yml

  play #1 (all): all    TAGS: []
      TASK TAGS: []

  play #2 (elastic_hosts): Deploy Elasticsearch hosts   TAGS: []
      TASK TAGS: [create_dirs, elasticsearch, elk, security]

  play #3 (kibana_hosts): Deploy Kibana hosts   TAGS: []
      TASK TAGS: [create_dirs, elk, kibana]

  play #4 (filebeat_hosts): Deploy Filebeat hosts       TAGS: []
      TASK TAGS: [beats, create_dirs, elk, filebeat, includevars]

  play #5 (metricbeat_hosts): Deploy Metricbeat hosts   TAGS: []
      TASK TAGS: [beats, create_dirs, elk, includevars, metricbeat]

  play #6 (logstash_hosts): Deploy Logstash hosts       TAGS: []
      TASK TAGS: [create_dirs, elk, logstash]
```

Some tags are self explanatory but some needs some description.

 - `create_dirs` - Creates persistent volumes without starting any containers. Useful for migration.
 - `security` - Invokes Elastic REST API to apply built-in and custom users and roles. Uses the [Native realm](https://www.elastic.co/guide/en/elasticsearch/reference/7.15/realms.html) instead of file realm.
 - `include_vars` - A hack to include variables from other roles. Only used for development.
