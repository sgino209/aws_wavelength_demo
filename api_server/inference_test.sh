#!/bin/bash
target_ip=${1:-10.0.0.11}
curl -X POST http://${target_ip}:8080/predictions/fasterrcnn -T apiserver/kitten.jpg
