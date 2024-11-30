python configGenerator.py --workmodel chain --replicaCnt 5 --layer cloud 
echo "[$(date)] Redeploying with $replica replicas..." | tee -a $LOGFILE
kubectl delete -f yamls/
rm -rf yamls/*
python Deployers/K8sDeployer/RunK8sDeployer.py -c ./tmp/k8s_parameters.json