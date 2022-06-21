#!/bin/bash
target_ip=${1:-54.200.130.4}
ssh -i ~/.ssh/aws-alef8.pem -A ubuntu@${target_ip}
