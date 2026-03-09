#!/bin/bash

cat > /tmp/setup-scripts/solve_module_01.yml << 'ENDOFPLAY'
---
- name: Solve Module 01 - AAP + Terraform Enterprise
  hosts: localhost
  connection: local
  gather_facts: false
  collections:
    - ansible.controller

  vars:
    aap_host: "https://localhost"
    aap_username: admin
    aap_password: "ansible123!"
    aap_validate_certs: false
    guid: "{{ lookup('env', 'GUID') }}"
    domain: "{{ lookup('env', 'DOMAIN') }}"
    aws_access_key: "{{ lookup('env', 'AWS_ACCESS_KEY_ID') }}"
    aws_secret_key: "{{ lookup('env', 'AWS_SECRET_ACCESS_KEY') }}"
    tfe_hostname: "https://tfe-https-{{ guid }}.{{ domain }}"
    tfe_internal: "https://terraform"
    tfe_org: rhdp-tf-org
    tfe_workspace_name: TFE-Demo
    tfe_project_name: rhdp-initial-project

  tasks:

    # ===================================================================
    # Task 1: Create TFE API Token
    # ===================================================================

    - name: Check for stored TFE API token
      ansible.builtin.stat:
        path: /tmp/tfe-api-token.txt
      register: tfe_token_file

    - name: Read stored TFE API token
      ansible.builtin.slurp:
        src: /tmp/tfe-api-token.txt
      register: tfe_token_slurp
      when: tfe_token_file.stat.exists

    - name: Set TFE token from stored file
      ansible.builtin.set_fact:
        tfe_api_token: "{{ (tfe_token_slurp.content | b64decode).strip() }}"
      when: tfe_token_file.stat.exists

    - name: Validate stored TFE token
      ansible.builtin.uri:
        url: "{{ tfe_internal }}/api/v2/account/details"
        method: GET
        headers:
          Authorization: "Bearer {{ tfe_api_token }}"
          Content-Type: "application/vnd.api+json"
        validate_certs: false
        status_code: [200, 401, 403]
      register: tfe_token_check
      when: tfe_api_token is defined and tfe_api_token | length > 0

    - name: Clear invalid stored token
      ansible.builtin.set_fact:
        tfe_api_token: ""
      when:
        - tfe_token_check is defined
        - tfe_token_check.status | default(401) != 200

    - name: Create TFE API token via IACT
      when: tfe_api_token is not defined or tfe_api_token | length == 0
      block:
        - name: Retrieve IACT from TFE
          ansible.builtin.uri:
            url: "{{ tfe_internal }}/admin/retrieve-iact"
            method: GET
            validate_certs: false
            return_content: true
          register: iact_result
          retries: 5
          delay: 10
          until: iact_result is success

        - name: Create admin API token using IACT
          ansible.builtin.uri:
            url: "{{ tfe_internal }}/api/v2/admin/initial-admin-token?token={{ iact_result.content | trim }}"
            method: POST
            headers:
              Content-Type: "application/vnd.api+json"
            validate_certs: false
            status_code: [200, 201]
          register: admin_token_result

        - name: Set TFE API token
          ansible.builtin.set_fact:
            tfe_api_token: "{{ admin_token_result.json.token }}"

        - name: Store TFE API token for reuse
          ansible.builtin.copy:
            content: "{{ tfe_api_token }}"
            dest: /tmp/tfe-api-token.txt
            mode: '0600'

    # ===================================================================
    # Task 2: Create TFE Workspace + AWS Variables
    # ===================================================================

    - name: Get TFE projects
      ansible.builtin.uri:
        url: "{{ tfe_internal }}/api/v2/organizations/{{ tfe_org }}/projects"
        method: GET
        headers:
          Authorization: "Bearer {{ tfe_api_token }}"
          Content-Type: "application/vnd.api+json"
        validate_certs: false
      register: tfe_projects

    - name: Set project ID
      ansible.builtin.set_fact:
        tfe_project_id: "{{ tfe_projects.json.data | selectattr('attributes.name', 'equalto', tfe_project_name) | map(attribute='id') | first }}"

    - name: Check if TFE workspace exists
      ansible.builtin.uri:
        url: "{{ tfe_internal }}/api/v2/organizations/{{ tfe_org }}/workspaces/{{ tfe_workspace_name }}"
        method: GET
        headers:
          Authorization: "Bearer {{ tfe_api_token }}"
          Content-Type: "application/vnd.api+json"
        validate_certs: false
        status_code: [200, 404]
      register: tfe_ws_check

    - name: Create TFE workspace
      ansible.builtin.uri:
        url: "{{ tfe_internal }}/api/v2/organizations/{{ tfe_org }}/workspaces"
        method: POST
        body_format: json
        body:
          data:
            type: workspaces
            attributes:
              name: "{{ tfe_workspace_name }}"
              description: "My Initial Workspace for my first TFE demo."
            relationships:
              project:
                data:
                  type: projects
                  id: "{{ tfe_project_id }}"
        headers:
          Authorization: "Bearer {{ tfe_api_token }}"
          Content-Type: "application/vnd.api+json"
        validate_certs: false
        status_code: [200, 201]
      register: tfe_ws_create
      when: tfe_ws_check.status == 404

    - name: Set workspace ID
      ansible.builtin.set_fact:
        tfe_workspace_id: >-
          {{ tfe_ws_create.json.data.id
             if tfe_ws_check.status == 404
             else tfe_ws_check.json.data.id }}

    - name: Get existing workspace variables
      ansible.builtin.uri:
        url: "{{ tfe_internal }}/api/v2/workspaces/{{ tfe_workspace_id }}/vars"
        method: GET
        headers:
          Authorization: "Bearer {{ tfe_api_token }}"
          Content-Type: "application/vnd.api+json"
        validate_certs: false
      register: tfe_existing_vars

    - name: Add AWS_ACCESS_KEY_ID env var to workspace
      ansible.builtin.uri:
        url: "{{ tfe_internal }}/api/v2/workspaces/{{ tfe_workspace_id }}/vars"
        method: POST
        body_format: json
        body:
          data:
            type: vars
            attributes:
              key: AWS_ACCESS_KEY_ID
              value: "{{ aws_access_key }}"
              category: env
              sensitive: false
        headers:
          Authorization: "Bearer {{ tfe_api_token }}"
          Content-Type: "application/vnd.api+json"
        validate_certs: false
        status_code: [200, 201]
      when: >-
        tfe_existing_vars.json.data
        | selectattr('attributes.key', 'equalto', 'AWS_ACCESS_KEY_ID')
        | list | length == 0

    - name: Add AWS_SECRET_ACCESS_KEY env var to workspace
      ansible.builtin.uri:
        url: "{{ tfe_internal }}/api/v2/workspaces/{{ tfe_workspace_id }}/vars"
        method: POST
        body_format: json
        body:
          data:
            type: vars
            attributes:
              key: AWS_SECRET_ACCESS_KEY
              value: "{{ aws_secret_key }}"
              category: env
              sensitive: true
        headers:
          Authorization: "Bearer {{ tfe_api_token }}"
          Content-Type: "application/vnd.api+json"
        validate_certs: false
        status_code: [200, 201]
      when: >-
        tfe_existing_vars.json.data
        | selectattr('attributes.key', 'equalto', 'AWS_SECRET_ACCESS_KEY')
        | list | length == 0

    # ===================================================================
    # Task 3: Create Terraform Enterprise Credential Type in AAP
    # ===================================================================

    - name: Create Terraform Enterprise credential type
      ansible.controller.credential_type:
        name: "Terraform Enterprise credential type"
        description: "Terraform Enterprise credential type for Terraform Enterprise"
        kind: cloud
        inputs:
          fields:
            - id: hostname
              type: string
              label: Terraform Enterprise Hostname
            - id: org
              type: string
              label: Organization
            - id: workspace
              type: string
              label: Workspace
            - id: token
              type: string
              label: Token
              secret: true
          required:
            - hostname
            - org
            - workspace
            - token
        injectors:
          extra_vars:
            tf_hostname: "{% raw %}{{ hostname }}{% endraw %}"
            tf_org: "{% raw %}{{ org }}{% endraw %}"
            tf_workspace: "{% raw %}{{ workspace }}{% endraw %}"
            tf_token: "{% raw %}{{ token }}{% endraw %}"
        state: present
        controller_username: "{{ aap_username }}"
        controller_password: "{{ aap_password }}"
        controller_host: "{{ aap_host }}"
        validate_certs: "{{ aap_validate_certs }}"

    # ===================================================================
    # Task 4: Create Terraform Enterprise Credential in AAP
    # ===================================================================

    - name: Create Terraform Enterprise credential
      ansible.controller.credential:
        name: "Terraform Enterprise credential"
        organization: Default
        credential_type: "Terraform Enterprise credential type"
        inputs:
          hostname: "{{ tfe_hostname }}"
          org: "{{ tfe_org }}"
          workspace: "{{ tfe_workspace_name }}"
          token: "{{ tfe_api_token }}"
        controller_username: "{{ aap_username }}"
        controller_password: "{{ aap_password }}"
        controller_host: "{{ aap_host }}"
        validate_certs: "{{ aap_validate_certs }}"

    # ===================================================================
    # Task 5: Create Terraform Inventory Source in AAP
    # ===================================================================

    - name: Create Terraform Inventory Source
      ansible.controller.inventory_source:
        name: "AWS source for TFE resources"
        description: "AWS source for TFE resources"
        inventory: "Terraform Inventory"
        credential: "AWS Credential"
        source: ec2
        execution_environment: "Terraform Execution Environment"
        overwrite: true
        update_on_launch: true
        organization: Default
        source_vars:
          hostnames:
            - "tag:Name"
          compose:
            ansible_host: public_ip_address
            ansible_ssh_pipelining: "true"
        state: present
        controller_username: "{{ aap_username }}"
        controller_password: "{{ aap_password }}"
        controller_host: "{{ aap_host }}"
        validate_certs: "{{ aap_validate_certs }}"

    - name: Sync Terraform Inventory Source
      ansible.controller.inventory_source_update:
        name: "AWS source for TFE resources"
        inventory: "Terraform Inventory"
        organization: Default
        controller_username: "{{ aap_username }}"
        controller_password: "{{ aap_password }}"
        controller_host: "{{ aap_host }}"
        validate_certs: "{{ aap_validate_certs }}"

    # ===================================================================
    # Task 6: Create APPLY Job Template + Workflow, then Launch
    # ===================================================================

    - name: Create Terraform Enterprise APPLY job template
      ansible.controller.job_template:
        name: "Terraform Enterprise APPLY"
        job_type: run
        organization: Default
        inventory: "Demo Inventory"
        project: "Terraform Demos Project"
        playbook: "playbooks/terraform_apply_plan.yml"
        execution_environment: "Terraform Execution Environment"
        credentials:
          - "Terraform Enterprise credential"
        extra_vars:
          aws_region: us-east-2
          aws_name_tag: tfevm
          aws_instance_size: t2.micro
          aws_instance_count: 1
          aws_instance_public_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAKzl1JGwZh92P1ABxIVHE52I2nJk+h7ED4B6GgbMXAl hmourad@hmourad-mac"
        state: present
        controller_username: "{{ aap_username }}"
        controller_password: "{{ aap_password }}"
        controller_host: "{{ aap_host }}"
        validate_certs: "{{ aap_validate_certs }}"

    - name: Create WF-Terraform Enterprise APPLY workflow
      ansible.controller.workflow_job_template:
        name: "WF-Terraform Enterprise APPLY"
        organization: Default
        workflow_nodes:
          - identifier: apply_node
            unified_job_template:
              organization:
                name: Default
              name: "Terraform Enterprise APPLY"
              type: job_template
            related:
              success_nodes:
                - identifier: inv_sync_node
              failure_nodes: []
              always_nodes: []
          - identifier: inv_sync_node
            unified_job_template:
              name: "AWS source for TFE resources"
              type: inventory_source
            related:
              success_nodes:
                - identifier: nginx_node
              failure_nodes: []
              always_nodes: []
          - identifier: nginx_node
            unified_job_template:
              organization:
                name: Default
              name: "Install Nginx on RHEL"
              type: job_template
            related:
              success_nodes: []
              failure_nodes: []
              always_nodes: []
        controller_username: "{{ aap_username }}"
        controller_password: "{{ aap_password }}"
        controller_host: "{{ aap_host }}"
        validate_certs: "{{ aap_validate_certs }}"

    - name: Launch WF-Terraform Enterprise APPLY
      ansible.controller.workflow_launch:
        workflow_template: "WF-Terraform Enterprise APPLY"
        wait: true
        controller_username: "{{ aap_username }}"
        controller_password: "{{ aap_password }}"
        controller_host: "{{ aap_host }}"
        validate_certs: "{{ aap_validate_certs }}"

    # ===================================================================
    # Task 7: Create DESTROY Job Template + Workflow, then Launch
    # ===================================================================

    - name: Create Terraform Enterprise DESTROY job template
      ansible.controller.job_template:
        name: "Terraform Enterprise DESTROY"
        job_type: run
        organization: Default
        inventory: "Demo Inventory"
        project: "Terraform Demos Project"
        playbook: "playbooks/terraform_destroy_plan.yml"
        execution_environment: "Terraform Execution Environment"
        credentials:
          - "Terraform Enterprise credential"
        state: present
        controller_username: "{{ aap_username }}"
        controller_password: "{{ aap_password }}"
        controller_host: "{{ aap_host }}"
        validate_certs: "{{ aap_validate_certs }}"

    - name: Create WF-Terraform Enterprise DESTROY workflow
      ansible.controller.workflow_job_template:
        name: "WF-Terraform Enterprise DESTROY"
        organization: Default
        workflow_nodes:
          - identifier: destroy_node
            unified_job_template:
              organization:
                name: Default
              name: "Terraform Enterprise DESTROY"
              type: job_template
            related:
              success_nodes:
                - identifier: destroy_sync_node
              failure_nodes: []
              always_nodes: []
          - identifier: destroy_sync_node
            unified_job_template:
              name: "AWS source for TFE resources"
              type: inventory_source
            related:
              success_nodes: []
              failure_nodes: []
              always_nodes: []
        controller_username: "{{ aap_username }}"
        controller_password: "{{ aap_password }}"
        controller_host: "{{ aap_host }}"
        validate_certs: "{{ aap_validate_certs }}"

    - name: Launch WF-Terraform Enterprise DESTROY
      ansible.controller.workflow_launch:
        workflow_template: "WF-Terraform Enterprise DESTROY"
        wait: true
        controller_username: "{{ aap_username }}"
        controller_password: "{{ aap_password }}"
        controller_host: "{{ aap_host }}"
        validate_certs: "{{ aap_validate_certs }}"

ENDOFPLAY

export ANSIBLE_LOCALHOST_WARNING=False
export ANSIBLE_INVENTORY_UNPARSED_WARNING=False
ANSIBLE_COLLECTIONS_PATH=/root/ansible-automation-platform-containerized-setup/collections/ansible_collections/ /usr/bin/ansible-playbook /tmp/setup-scripts/solve_module_01.yml
