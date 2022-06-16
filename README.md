# alef8_poc

Reference:    
https://aws.amazon.com/blogs/compute/deploying-your-first-5g-enabled-application-with-aws-wavelength    
    
## Setup    
Automatically handled by setup.sh, namely:    
- Create the VPC and associated resources
- Deploy the security groups
- Add the subnets and routing tables
- Create the Elastic IPs and networking interfaces
- Deploy the API and inference instances
- Deploy the bastion / web server
    
## Configure the bastion host/web server    
SSH into the bastion host:    
```
ssh -i /path/to/key.pem -A bitnami@<bastion ip address>
```
Then clone, ramp-up and the delpoy the react webapp:    
```
git clone https://github.com/mikegcoleman/react-wavelength-inference-demo.git
cd react-wavelength-inference-demo && npm install
npm run build
cp -r ./build/* /home/bitnami/htdocs
```
Test that the web app is running correctly by navigating to the public IP address of your bastion instance    
    
## Configure the inference server    
SSH into the bastion host:    
```
ssh -i /path/to/key.pem -A bitnami@<bastion public ip>

```
Then SSH into the inference server instance:    
```
ssh ubuntu@<inference server private ip>
```
Initialize the inference environment:     
```
sudo apt-get update -y 
sudo apt-get install -y virtualenv openjdk-11-jdk gcc python3-dev

mkdir inference && cd inference
virtualenv --python=python3 inference
source inference/bin/activate

pip3 install torch torchtext torchvision sentencepiece psutil future wheel requests torchserve torch-model-archiver

mkdir torchserve-examples && cd torchserve-examples

git clone https://github.com/pytorch/serve.git

mkdir model_store

wget https://download.pytorch.org/models/fasterrcnn_resnet50_fpn_coco-258fb6c6.pth

torch-model-archiver --model-name fasterrcnn --version 1.0 \
--model-file serve/examples/object_detector/fast-rcnn/model.py \
--serialized-file fasterrcnn_resnet50_fpn_coco-258fb6c6.pth \
--handler object_detector \
--extra-files serve/examples/object_detector/index_to_name.json

mv fasterrcnn.mar model_store/

```
Create a configuration file (config.properties) with the following content:    
```
inference_address=http://<your instance private IP>:8080
management_address=http://<your instance private IP>:8081

```
Then, start the Torchserve server:   
```
torchserve --start --model-store model_store --models fasterrcnn=fasterrcnn.mar --ts-config config.properties
```

## Configure the API server    
SSH into the bastion host:    
```
ssh -i /path/to/key.pem -A bitnami@<bastion public ip>

```
Then SSH into the inference server instance:    
```
ssh ubuntu@<api server private ip>
```
### Test the inference server
Test the inference server (substitute the INTERNAL IP of the inference instance in the second line below):   
```
curl -O https://s3.amazonaws.com/model-server/inputs/kitten.jpg
curl -X POST http://<your_inf_server_internal_IP>:8080/predictions/fasterrcnn -T kitten.jpg
```
The inference server returns the labels of the objects it detected, and the corner coordinates of boxes that surround those objects.    
    
### API server config
Initialize the server:   
```
sudo apt-get update -y && sudo apt-get install -y libsm6 libxrender1 libfontconfig1 virtualenv

mkdir apiserver && cd apiserver
git clone https://github.com/mikegcoleman/flask_wavelength_api .

virtualenv --python=python3 apiserver
source apiserver/bin/activate

pip3 install opencv-python flask pillow requests flask-cors

```
Create a configuration file (config_values.txt) with the following line (substituting the INTERNAL IP of your inference server):    
```
http://<your_inf_server_internal_IP>:8080/predictions/fasterrcnn

```
Then, start the Flask application:   
```
python api.py

```

## Test the client application
To test the application, you need to have a device on the carrier’s 5G network.     
From your device’s web browser navigate the bastion / web server’s public IP address.    
In the text box at the top of the app enter the public IP of your API server.    
Next, choose an existing photo from your camera roll, or take a photo with the camera and press the process object button underneath the preview photo (you may need to scroll down).    
The client will send the image to the API server, which forwards it to the inference server for detection.    
The API server then receives back the prediction from the inference server, adds a label and bounding boxes, and return the marked-up image to the client where it will be displayed.    
If the inference server cannot detect any objects in the image, you will receive a message indicating the prediction failed.    

