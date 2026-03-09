#!/bin/bash

cat > /tmp/setup-scripts/validate_module_01.yml << 'ENDOFPLAY'
---
- name: Validate Module 01 - AAP + Terraform Enterprise
  hosts: localhost
  connection: local
  gather_facts: false

  vars:
    aap_host: "https://localhost"
    aap_username: admin
    aap_password: "ansible123!"
    tfe_internal: "https://terraform"
    tfe_org: rhdp-tf-org
    tfe_workspace_name: TFE-Demo
    validation_errors: []

  tasks:

    # --- Retrieve TFE token for API validation ---

    - name: Read stored TFE API token
      ansible.builtin.slurp:
        src: /tmp/tfe-api-token.txt
      register: tfe_token_slurp
      ignore_errors: true

    - name: Set TFE API token
      ansible.builtin.set_fact:
        tfe_api_token: "{{ (tfe_token_slurp.content | b64decode).strip() }}"
      when: tfe_token_slurp is success

    # --- AAP Resource Validations ---

    - name: Verify Terraform Enterprise credential type exists
      ansible.builtin.uri:
        url: "{{ aap_host }}/api/v2/credential_types/?name=Terraform+Enterprise+credential+type"
        method: GET
        user: "{{ aap_username }}"
        password: "{{ aap_password }}"
        force_basic_auth: true
        validate_certs: false
      register: val_cred_type
      failed_when: val_cred_type.json.count == 0

    - name: Verify Terraform Enterprise credential exists
      ansible.builtin.uri:
        url: "{{ aap_host }}/api/v2/credentials/?name=Terraform+Enterprise+credential"
        method: GET
        user: "{{ aap_username }}"
        password: "{{ aap_password }}"
        force_basic_auth: true
        validate_certs: false
      register: val_credential
      failed_when: val_credential.json.count == 0

    - name: Verify inventory source exists
      ansible.builtin.uri:
        url: "{{ aap_host }}/api/v2/inventory_sources/?name=AWS+source+for+TFE+resources"
        method: GET
        user: "{{ aap_username }}"
        password: "{{ aap_password }}"
        force_basic_auth: true
        validate_certs: false
      register: val_inv_source
      failed_when: val_inv_source.json.count == 0

    - name: Verify Terraform Enterprise APPLY job template exists
      ansible.builtin.uri:
        url: "{{ aap_host }}/api/v2/job_templates/?name=Terraform+Enterprise+APPLY"
        method: GET
        user: "{{ aap_username }}"
        password: "{{ aap_password }}"
        force_basic_auth: true
        validate_certs: false
      register: val_jt_apply
      failed_when: val_jt_apply.json.count == 0

    - name: Verify Terraform Enterprise DESTROY job template exists
      ansible.builtin.uri:
        url: "{{ aap_host }}/api/v2/job_templates/?name=Terraform+Enterprise+DESTROY"
        method: GET
        user: "{{ aap_username }}"
        password: "{{ aap_password }}"
        force_basic_auth: true
        validate_certs: false
      register: val_jt_destroy
      failed_when: val_jt_destroy.json.count == 0

    - name: Verify WF-Terraform Enterprise APPLY workflow exists
      ansible.builtin.uri:
        url: "{{ aap_host }}/api/v2/workflow_job_templates/?name=WF-Terraform+Enterprise+APPLY"
        method: GET
        user: "{{ aap_username }}"
        password: "{{ aap_password }}"
        force_basic_auth: true
        validate_certs: false
      register: val_wf_apply
      failed_when: val_wf_apply.json.count == 0

    - name: Verify WF-Terraform Enterprise DESTROY workflow exists
      ansible.builtin.uri:
        url: "{{ aap_host }}/api/v2/workflow_job_templates/?name=WF-Terraform+Enterprise+DESTROY"
        method: GET
        user: "{{ aap_username }}"
        password: "{{ aap_password }}"
        force_basic_auth: true
        validate_certs: false
      register: val_wf_destroy
      failed_when: val_wf_destroy.json.count == 0

    # --- TFE Resource Validations ---

    - name: Verify TFE workspace exists
      ansible.builtin.uri:
        url: "{{ tfe_internal }}/api/v2/organizations/{{ tfe_org }}/workspaces/{{ tfe_workspace_name }}"
        method: GET
        headers:
          Authorization: "Bearer {{ tfe_api_token }}"
          Content-Type: "application/vnd.api+json"
        validate_certs: false
        status_code: [200]
      register: val_tfe_workspace
      when: tfe_api_token is defined and tfe_api_token | length > 0

    - name: Validation summary
      ansible.builtin.debug:
        msg:
          - "Credential type 'Terraform Enterprise credential type': PASS"
          - "Credential 'Terraform Enterprise credential': PASS"
          - "Inventory source 'AWS source for TFE resources': PASS"
          - "Job template 'Terraform Enterprise APPLY': PASS"
          - "Job template 'Terraform Enterprise DESTROY': PASS"
          - "Workflow 'WF-Terraform Enterprise APPLY': PASS"
          - "Workflow 'WF-Terraform Enterprise DESTROY': PASS"
          - "TFE workspace '{{ tfe_workspace_name }}': {{ 'PASS' if val_tfe_workspace is success else 'SKIPPED (no TFE token)' }}"

ENDOFPLAY

export ANSIBLE_LOCALHOST_WARNING=False
export ANSIBLE_INVENTORY_UNPARSED_WARNING=False
ANSIBLE_COLLECTIONS_PATH=/root/ansible-automation-platform-containerized-setup/collections/ansible_collections/ /usr/bin/ansible-playbook /tmp/setup-scripts/validate_module_01.yml
