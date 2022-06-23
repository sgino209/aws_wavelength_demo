#!/bin/bash
cd inference
source inference/bin/activate
cd torchserve-examples
torchserve --stop
