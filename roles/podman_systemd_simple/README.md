podman_systemd_simple
=====================

This role generates systemd service units for pods and containers.

Requirements
------------

Make sure you provide container_name and type when you invoke the role.

Role Variables
--------------

 - service_files_dir: "/etc/systemd/system"
 - container_stop_timeout: 30
 - container_name: "example_container" or "example_pod"
 - type: "container" or "pod"

Dependencies
------------

None.

Example Playbook
----------------

Place the role into your roles directory then import it once you declared your pods or containers.

    - name: Hand over pod and container mgmt to systemd
      import_role:
        vars:
          name: "{{ pod_name }}"
          type: pod
        name: podman_systemd_simple

License
-------

Apache 2.0

Author Information
------------------

balagetech.com
