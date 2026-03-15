#!/bin/bash
IP=$1
USER=$2
PASS=$3

echo "Polling BIG-IP ($IP) for Cloud Failover Extension readiness..."

# Loop until the CFE /info endpoint returns a 200 OK
until curl -k -s -f -o /dev/null -u "$USER:$PASS" "https://$IP/mgmt/shared/cloud-failover/info"; do
    echo "Waiting for CFE REST API on $IP to become available... (Retrying in 20s)"
    sleep 30
done

echo "CFE is installed and ready on $IP!"