# AWS Wavelength Demo
       
![diagram](https://i.ibb.co/bR05hyS/Screen-Shot-2022-06-26-at-14-14-17.png)
    
## References:   
1. https://cloud-images.ubuntu.com/locator
2. https://noise.getoto.net/tag/aws-wavelength
3. https://github.com/mikegcoleman/react-wavelength-inference-demo
4. https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html
5. https://docs.aws.amazon.com/wavelength/latest/developerguide/wavelength-quotas.html
6. https://aws.amazon.com/blogs/compute/deploying-your-first-5g-enabled-application-with-aws-wavelength   
    
---  
    
## Prerequisites:
- Generate a new EC2 machine (t2.micro) in the same target region to run the below from
- SSH to the machine, clone the Git repo, Install AWS CLI, prepare AWS credentials (~/.aws/credentials, see ref4) and a local .env file
- The setup flow is tuned for us-west-2 region. Changing for a different region shall incorporate update of WL_ZONE and NGB (see ref5) and the IMAGE_IDs (see ref1)
     
---  
    
## Setup    
Automatically handled by setup.sh, namely:    
- Create the VPC and associated resources
- Deploy the security groups
- Add the subnets and routing tables
- Create the Elastic IPs and networking interfaces
- Deploy the API and inference instances
- Deploy the bastion / web server
- Note: If using a Mac, please add the PEM keys to the keychain, e.g. ssh-add -K aws-alef8.pem   
   
---  
     
## Quick-Start (demo)
### Terminal1 (Bastion)
```
connect_to_vm.sh
connect_to_bastion.sh
launch_bastion.sh
```
### Terminal2 (Inference server)
```
connect_to_vm.sh
connect_to_bastion.sh
connect_to_inference_server.sh
launch_inference_server.sh
```
### Terminal3 (API server)
```
connect_to_vm.sh
connect_to_bastion.sh
inference_test.sh
launch_api_server.sh
```
   
---  
    
## Bastion host/web server    
SSH into the general-purpose EC2 machine with agent forwarding enabled (connect_to_vm.sh):
```
ssh -i aws-alef8-general.pem -A ubuntu@52.32.192.244
```
SSH into the bastion host from the general_vm, with agent forwarding enabled (connect_to_bastion.sh):    
```
ssh -i aws-alef8.pem -A ubuntu@54.200.130.4 
```
### First time setup
Initialize the bastion environment:     
```
sudo apt update
sudo apt install nodejs npm nginx
git clone https://github.com/mikegcoleman/react-wavelength-inference-demo.git
cd react-wavelength-inference-demo
sudo npm install
npm run build
cd -
```
Note: If npm install fails with error, then try:   
```
cd /usr/local/lib
sudo npm install -g npm@5.3
cd -
sudo npm install
```
Then, setup the following server in /etc/nginx/sites-enabled/default (override the default server):
```
server {
   listen         80 default_server;
   listen         [::]:80 default_server;
   server_name    localhost;
   root           /usr/share/nginx/html;
location / {
       proxy_pass http://127.0.0.1:3000;
       proxy_http_version 1.1;
       proxy_set_header Upgrade $http_upgrade;
       proxy_set_header Connection 'upgrade';
       proxy_set_header Host $host;
       proxy_cache_bypass $http_upgrade;
   }
}
```
Finally, start NginX:    
```
sudo service nginx restart
```
And verify it's working with:    
```
systemctl status nginx.service
```
### Bastion App Launch
Run the app, and keep this SSH terminal open (launch_bastion.sh)
```
cd react-wavelength-inference-demo
npm start
```
Note: later on, it's possible to run it as a systemctl service, constantly at the background.
   
Test that the web app is running correctly by navigating to the public IP address of your bastion instance (http://54.200.130.4)    
    
---  
    
## Inference server    
SSH into the general-purpose EC2 machine with agent forwarding enabled (connect_to_vm.sh):
```
ssh -i aws-alef8-general.pem -A ubuntu@52.32.192.244
```
SSH into the bastion host from the general_vm, with agent forwarding enabled (connect_to_bastion.sh):    
```
ssh -i aws-alef8.pem -A ubuntu@54.200.130.4 
```
Then SSH into the inference server instance, with its private IP (connect_to_inference_server.sh):    
```
ssh ubuntu@10.0.0.11
```
### First time setup
Initialize the inference environment (make sure the EC2 machine has enough storage, 100GB+):     
```
sudo apt-get update -y 
sudo apt-get install -y virtualenv openjdk-11-jdk gcc python3-dev

mkdir inference && cd inference
virtualenv --python=python3 inference
source inference/bin/activate

pip install torch torchtext torchvision sentencepiece psutil future wheel requests torchserve torch-model-archiver captum

mkdir torchserve-examples
cd torchserve-examples

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
Create a configuration file (config.properties) with the following content (in the torchserve-examples folder):    
```
inference_address=http://10.0.0.11:8080
management_address=http://10.0.0.11:8081
```
### Inference App Launch
Then, start the Torchserve server (launch_inference_server.sh)   
```
cd inference
source inference/bin/activate

cd torchserve-examples

torchserve --start --model-store model_store --models fasterrcnn=fasterrcnn.mar --ts-config config.properties
```
Note: the torchserver may be stopped with:
```
torchserve --stop
```
   
---  
    
## Configure the API server    
SSH into the general-purpose EC2 machine with agent forwarding enabled (connect_to_vm.sh):
```
ssh -i aws-alef8-general.pem -A ubuntu@52.32.192.244
```
SSH into the bastion host from the general_vm, with agent forwarding enabled (connect_to_bastion.sh):    
```
ssh -i aws-alef8.pem -A ubuntu@54.200.130.4 
```
Then SSH into the API server instance, with its private IP (connect_to_api_server.sh):    
```
ssh ubuntu@10.0.0.141
```
### First time setup
Initialize the API environment:     
```
sudo apt-get update -y
sudo apt-get install ffmpeg libsm6 libxext6 libxrender1 libfontconfig1 virtualenv -y

mkdir apiserver
cd apiserver
git clone https://github.com/mikegcoleman/flask_wavelength_api .

virtualenv --python=python3 apiserver
source apiserver/bin/activate

pip install opencv-python flask pillow requests flask-cors
```
Create a configuration file (config_values.txt) with the following line (substituting the INTERNAL IP of your inference server):    
```
http://10.0.0.11:8080/predictions/fasterrcnn
```
### Test the inference server (CURL)
Test the inference server (substitute the INTERNAL IP of the inference instance in the second line below):   
```
curl -O https://s3.amazonaws.com/model-server/inputs/kitten.jpg
curl -X POST http://10.0.0.11:8080/predictions/fasterrcnn -T kitten.jpg
```
The inference server returns the labels of the objects it detected, and the corner coordinates of boxes that surround those objects.        
### API App Launch
Start the Flask application (launch_api_server.sh)   
```
cd apiserver
source apiserver/bin/activate

python api.py
```
  
---  
    
## Test the client application
To test the application, you need to have a device on the carrier’s 5G network.     
From your device’s web browser navigate the bastion / web server’s public IP address.    
In the text box at the top of the app enter the public IP of your API server.    
Next, choose an existing photo from your camera roll, or take a photo with the camera and press the process object button underneath the preview photo (you may need to scroll down).    
The client will send the image to the API server, which forwards it to the inference server for detection.    
The API server then receives back the prediction from the inference server, adds a label and bounding boxes, and return the marked-up image to the client where it will be displayed.    
If the inference server cannot detect any objects in the image, you will receive a message indicating the prediction failed.    

