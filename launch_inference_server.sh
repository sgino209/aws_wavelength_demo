#!/bin/bash
cd inference
source inference/bin/activate
cd torchserve-examples
torchserve --start --model-store model_store --models fasterrcnn=fasterrcnn.mar --ts-config config.properties
