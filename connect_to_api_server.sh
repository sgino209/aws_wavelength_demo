#!/bin/bash
target_ip=${1:-10.0.0.141}
ssh -i ~/.ssh/aws-alef8.pem -A ubuntu@${target_ip}
