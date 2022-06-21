#!/bin/bash
target_ip=${1:-52.32.192.244}
ssh -i ~/.ssh/aws-alef8-general.pem -A ubuntu@${target_ip}
