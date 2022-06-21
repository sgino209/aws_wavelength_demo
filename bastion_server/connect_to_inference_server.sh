#!/bin/bash
target_ip=${1:-10.0.0.11}
ssh -i ~/.ssh/aws-alef8.pem -A ubuntu@${target_ip}
