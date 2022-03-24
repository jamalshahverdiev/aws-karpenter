#### Before starting to explain how to install and configure Karpenter I want to say, how I came to use Karpenter. Inside of the current project for EKS I have used *`cluster-autoscaler`* with *`cluster-autoscaler-priority-expander`* and *`node-termination-handler`*. The project is huge and each time when I needed to create a new node group I went to search multiple instance types then create node group and change cluster-autoscaler-priority-expander configmap to use this new node group. Just imagine you need to delete this node group or change the priority usage of them. A lot of steps going to be repeated each time. One time I have started to think to search alternatives of cluster-autoscaler and found [this youtube video](https://www.youtube.com/watch?v=3QsVRHVdOnM). This guy in the video really explained all headaches usage of *`cluster-autoscaler`*. Then I have started to go deep dive in [`Karpenter`](https://karpenter.sh/). All following steps will use code files from this github repository. My default *`AWS_REGION`* is *`us-east-2`*

### Required tools:
- [`awscli`](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [`kubectl`](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)
- [`git`](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
- [`eksctl`](https://docs.aws.amazon.com/eks/latest/userguide/eksctl.html)
- [`aws-iam-authenticator`](https://docs.aws.amazon.com/eks/latest/userguide/install-aws-iam-authenticator.html)
- [`helm`](https://helm.sh/docs/intro/install/)
- [`TMUX`](https://computingforgeeks.com/linux-tmux-cheat-sheet/)

#### To create cluster YAML file we must execute `generate_cluster_yaml.sh` script which will create cloudformation stack with new VPC and `3` private/public subnets. It will automatically fill right values inside of `cluster_output.yaml` file which will be used to create cluster. All yaml files located inside of `yamls` folder.

#### Create cluster without node group because we will install calico CNI to the cluster

```bash
$ export AWS_REGION=us-east-2
$ eksctl create cluster -f cluster_output.yaml --without-nodegroup
```

#### Check node group exists or not

```bash
$ CLUSTER_NAME=$(cat cluster_output.yaml| grep -A1 metadata | tail -n1 | awk '{ print $(NF)}')
$ eksctl get nodegroup --cluster=${CLUSTER_NAME}
Error: No nodegroups found
```

#### Delete AWS CNI

```bash
$ kubectl delete -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/release-1.6/config/v1.6/aws-k8s-cni.yaml
clusterrole.rbac.authorization.k8s.io "aws-node" deleted
serviceaccount "aws-node" deleted
clusterrolebinding.rbac.authorization.k8s.io "aws-node" deleted
daemonset.apps "aws-node" deleted
customresourcedefinition.apiextensions.k8s.io "eniconfigs.crd.k8s.amazonaws.com" deleted
```

#### Install Calico CNI

```bash
$ kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
```

#### Create node group

```bash
$ NODEGROUP_NAME=$(cat cluster_output.yaml| grep -A1 -i nodegroups | tail -n1 | awk '{ print $(NF)}')
$ eksctl create nodegroup --config-file ./cluster_output.yaml --include=${NODEGROUP_NAME}
```

#### Look at the calico pods

```bash
$ watch kubectl get pods -n kube-system -o wide
NAME                                       READY   STATUS    RESTARTS   AGE    IP              NODE                            NOMINATED NODE   READINESS GATES
calico-kube-controllers-6b9fbfff44-6vsnm   1/1     Running   0          11m    192.168.200.3   ip-10-227-57-155.ec2.internal   <none>           <none>
calico-node-nw5xr                          1/1     Running   0          112s   10.227.57.155   ip-10-227-57-155.ec2.internal   <none>           <none>
coredns-66cb55d4f4-8kzdk                   1/1     Running   0          25m    192.168.200.2   ip-10-227-57-155.ec2.internal   <none>           <none>
coredns-66cb55d4f4-w2q9d                   1/1     Running   0          25m    192.168.200.1   ip-10-227-57-155.ec2.internal   <none>           <none>
kube-proxy-pzmfm                           1/1     Running   0          112s   10.227.57.155   ip-10-227-57-155.ec2.internal   <none>           <none>
```

#### Set needed variables

```bash
$ AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
$ SUBNET_IDS=$(aws cloudformation describe-stacks \
    --stack-name eksctl-${CLUSTER_NAME}-cluster \
    --query 'Stacks[].Outputs[?OutputKey==`SubnetsPrivate`].OutputValue' \
    --output text)
$ TEMPOUT=$(mktemp)
```

#### Karpenter discovers subnets tagged `kubernetes.io/cluster/$CLUSTER_NAME`. Add this tag to subnets associated configured for your cluster. Retrieve the subnet IDs and tag them with the cluster name. 

```bash
$ aws ec2 create-tags --resources $(echo $SUBNET_IDS | tr ',' '\n') --tags Key="kubernetes.io/cluster/${CLUSTER_NAME}",Value=
```

#### Instances launched by `Karpenter` must run with an `InstanceProfile` that grants permissions necessary to run containers and configure networking. Karpenter discovers the InstanceProfile using the name `KarpenterNodeRole-${ClusterName}`

#### First, create the IAM resources using AWS CloudFormation

```bash
$ curl -fsSL https://karpenter.sh/docs/getting-started/cloudformation.yaml > $TEMPOUT \
&& aws cloudformation deploy \
  --stack-name Karpenter-${CLUSTER_NAME} \
  --template-file ${TEMPOUT} \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides ClusterName=${CLUSTER_NAME}
```

#### Second, grant access to instances using the profile to connect to the cluster. This command adds the Karpenter node role to your *`aws-auth`* configmap, *`allowing nodes with this role to connect to the cluster`*

```bash
$ eksctl create iamidentitymapping --username system:node:{{EC2PrivateDNSName}} --cluster ${CLUSTER_NAME} --arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME} \
  --group system:bootstrappers \
  --group system:nodes
```

#### Associate IAM OIDC provider with EKS cluster

```bash
$ eksctl utils associate-iam-oidc-provider --cluster ${CLUSTER_NAME} --approve
2021-12-24 12:56:39 [ℹ]  eksctl version 0.74.0
2021-12-24 12:56:39 [ℹ]  using region us-east-2
2021-12-24 12:56:40 [ℹ]  IAM Open ID Connect provider is already associated with cluster "karpenter-nonprod" in "us-east-2"
```

#### Karpenter requires permissions like launching instances. This will create an AWS IAM Role, Kubernetes service account, and associate them using [`IRSA`](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/setting-up-enable-IAM.html)

```bash
$ eksctl create iamserviceaccount \
  --cluster $CLUSTER_NAME --name karpenter --namespace karpenter \
  --attach-policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/KarpenterControllerPolicy-$CLUSTER_NAME \
  --approve
```

#### This step is only necessary if this is the first time you’re using EC2 Spot in this account. More details are available [`here`](https://docs.aws.amazon.com/batch/latest/userguide/spot_fleet_IAM_role.html)

```bash
$ aws iam create-service-linked-role --aws-service-name spot.amazonaws.com
An error occurred (InvalidInput) when calling the CreateServiceLinkedRole operation: Service role name AWSServiceRoleForEC2Spot has been taken in this account, please try a different suffix.
```

#### Use helm to deploy Karpenter to the cluster. We created a Kubernetes service account when we created the cluster using [`eksctl`](https://docs.aws.amazon.com/eks/latest/userguide/eksctl.html). Thus, we don’t need the [`helm`](https://helm.sh/docs/intro/install/) chart to do that


```bash
$ helm repo add karpenter https://charts.karpenter.sh
$ helm repo update
$ helm upgrade --install karpenter karpenter/karpenter --namespace karpenter \
  --create-namespace --set serviceAccount.create=false --version 0.5.2 \
  --set controller.clusterName=${CLUSTER_NAME} \
  --set controller.clusterEndpoint=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query "cluster.endpoint" --output json) \
  --set webhook.hostNetwork=true \
  --wait # for the defaulting webhook to install before creating a Provisioner
```

#### Use `generate_karpenter_provisioner_lt.sh` script to generate provisioner, lt file and apply it (It will create security groups and apply rules to cluster and itself)

```bash
$ ./generate_karpenter_provisioner_lt.sh
```

#### To simulate environment with [`AWS Fault Injection Simulator`](https://jamalshahverdiev.medium.com/aws-fault-injection-simulator-6637176b2c83) just execute `get_ec2_spot_instance_ids.sh` script to get all spot instances ids

#### Add the following helm repo to install [`node termination handler`](https://github.com/aws/aws-node-termination-handler). Then create values file and install node termination handler (This label will be used by node termination handler to understand which node is spot to terminate them)

```bash
$ helm repo add eks https://aws.github.io/eks-charts
$ cat <<'EOF' > yamls/values.yaml                                         
nodeSelector:
  karpenter.sh/capacity-type: spot
EOF
$ helm upgrade --install aws-node-termination-handler \
             --namespace kube-system \
             -f yamls/values.yaml \
              eks/aws-node-termination-handler
```


#### *`Important`*: With *`./generate_karpenter_provisioner_lt.sh`* script, inside of the *`aws-auth.yml`* file will be changed AWS account ID and `KarpenterNodeRole` ARNS then will be applied configmap again

#### Important look at the calico controller logs

```bash
$ kubectl logs -f calico-kube-controllers-6b9fbfff44-6vsnm -n kube-system
$ watch kubectl get pods --namespace kube-system
```

#### If you will face `calico` CNI issue about external interface card IP address determination the use the following commands

```bash
$ kubectl set env daemonset/calico-node -n kube-system IP_AUTODETECTION_METHOD=interface=e\*
$ kubectl set env daemonset/calico-node -n kube-system IP_AUTODETECTION_METHOD=can-reach=www.google.com
```

#### Inside of the [`TMUX`](https://computingforgeeks.com/linux-tmux-cheat-sheet/) session open `3` vertical and one horizontal tab to troubleshoot what is happening

```bash
$ tmux new-session -s karpenter
$ watch kubectl get pods --no-headers
$ watch kubectl get nodes
$ kubectl scale deployment inflate --replicas 1
```

In another terminal look at the karpenter logs

```bash
$ kubectl logs -f -n karpenter $(kubectl get pods -n karpenter -l karpenter=controller -o name)
```

### The [`source of the`](https://karpenter.sh/docs/getting-started/) documentation

















