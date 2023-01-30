Project for installing Rancher RKE on ubuntu 22.04

Cluster in HA 

Use service_cidr_block: "10.32.0.0/24" if not using default rke values

Install and startup initial controller node

```
curl -sfL https://get.rke2.io > install.sh
chmod +x install.sh 

sudo ./install.sh

ELB_NAME=""
if [ -z ${ELB_NAME} ] ; then
  echo "You forgot to add the ELB name"
  exit 1
fi

sudo mkdir -p /etc/rancher/rke2
sudo tee /etc/rancher/rke2/config.yaml > /dev/null << EOF
tls-san: 
  - ${ELB_NAME}
cni: calico
EOF

sudo systemctl enable rke2-server
sudo systemctl start rke2-server
sudo systemctl status rke2-server

echo 'export PATH=$PATH:/var/lib/rancher/rke2/bin' >> ~/.bashrc
source ~/.bashrc

sudo ln -s /var/lib/rancher/rke2/agent/etc/crictl.yaml /etc/crictl.yaml
sudo /var/lib/rancher/rke2/bin/crictl ps -a

mkdir ~/.kube
sudo cp /etc/rancher/rke2/rke2.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
kubectl get nodes
kubectl get pods  -A

sudo cat /var/lib/rancher/rke2/server/node-token

```

When installing second and third controllers, you'll need to add the following to 
/etc/rancher/rke2/config.yaml:  Note that ELB_NAME is your load balancer dns name
and token is the contents of /var/lib/rancher/rke2/server/node-token on the initial 
controller node

```
sudo mkdir -p /etc/rancher/rke2
sudo tee /etc/rancher/rke2/config.yaml > /dev/null << EOF
server: https://${ELB_NAME}:9345
token: ${TOKEN}
tls-san: 
  - ${ELB_NAME}
cni: calico
EOF


```

When installing agent nodes

```
curl -sfL https://get.rke2.io > install.sh
chmod +x install.sh 

sudo INSTALL_RKE2_TYPE="agent" ./install.sh

ELB_NAME=""
if [ -z ${ELB_NAME} ] ; then
  echo "You forgot to add the ELB name"
  exit 1
fi

TOKEN=""
if [ -z ${TOKEN} ] ; then
  echo "You forgot to add the token from /var/lib/rancher/rke2/server/node-token on server"
  exit 1
fi

sudo mkdir -p /etc/rancher/rke2
sudo tee /etc/rancher/rke2/config.yaml > /dev/null << EOF
server: https://${ELB_NAME}:9345
token: ${TOKEN}
EOF

sudo systemctl enable rke2-agent
sudo systemctl start rke2-agent
sudo systemctl status rke2-agent

echo 'export PATH=$PATH:/var/lib/rancher/rke2/bin' >> ~/.bashrc
source ~/.bashrc

sudo ln -s /var/lib/rancher/rke2/agent/etc/crictl.yaml /etc/crictl.yaml
sudo /var/lib/rancher/rke2/bin/crictl ps -a

```

To monitor progress  after starting rke2-server or rke2-agent services, you can you journalctl:
```
journalctl -u rke2-server -f   (in another window)
or
journalctl -u rke2-agent -f   (in another window)
```
