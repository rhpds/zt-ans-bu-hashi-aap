#!/bin/bash

if [ -n "$VAULT_LIC" ]; then
    # Write new license
    echo "$VAULT_LIC" | sudo tee /etc/vault.d/vault.hclic > /dev/null
    
    # Set proper permissions
    sudo chmod 640 /etc/vault.d/vault.hclic
    sudo chown vault:vault /etc/vault.d/vault.hclic
    
    echo "License file created successfully at /etc/vault.d/vault.hclic"
    
    # Restart Vault
    echo "Restarting Vault..."
    sudo systemctl restart vault
    
    # Wait and check status
    sleep 3
    if sudo systemctl is-active --quiet vault; then
        echo "Vault restarted successfully"
    else
        echo "Warning: Vault service may not be running properly"
        sudo systemctl status vault
        exit 1
    fi
else
    echo "Error: VAULT_LIC environment variable is not set"
    exit 1
fi
vault operator unseal -address=http://127.0.0.1:8200 -tls-skip-verify 1c6a637e70172e3c249f77b653fb64a820749864cad7f5aa7ab6d5aca5197ec5
#
