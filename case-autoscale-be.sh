#!/bin/bash
# set -e
WORKDIR=$(pwd)
MUBENCH_WORKDIR="/home/ubuntu/muBench" 
MIGRATOR_WORKDIR="/home/ubuntu/pod-migrator"
AGENT_WORKDIR="/home/ubuntu/edge-cloud-env"
LOGFILE="$WORKDIR/deployment.log"

LAYER=("all" "cloud" "edge")  # cloud / edge / all
PATTERN=("aggregator_parallel" "aggregator_sequential")  # Used by redeploy.sh
# PATTERN=("chain")  # Used by redeploy.sh
# SEQ_CASE_WAITING_TIME=("120")
# SEQ_CASE_AFTER_WAITING_TIME=("200")
# SEQ_QOS_THRESHOLD=("250")  # Used by redeploy.sh
# SEQ_TARGET_NODE_A="tb-edge-vm-4-1"
# SEQ_TARGET_NODE_B="tb-cloud-vm-8-1"

CUR_CASE_WAITING_TIME="150"
CUR_CASE_AFTER_WAITING_TIME="150"
CUR_QOS_THRESHOLD="0"  # Used by redeploy.sh
MUBENCH_CONFIG_PATH="Configs/K8sParameters.json"  # Used by redeploy.sh
OUTPUT_DIR="$WORKDIR/results"
TAG="autoscaling"
mkdir -p $OUTPUT_DIR/$TAG
TARGET_OUTPUT_DIR="$OUTPUT_DIR/$TAG"
# Clean up function to run on exit
cleanup() {
    echo "[$(date)] Cleaning up resources..." | tee -a $LOGFILE
    if [[ -n "$TESTER_PID" ]]; then
        echo "[$(date)] Killing test process with PID: $TESTER_PID" | tee -a $LOGFILE
        kill -TERM $TESTER_PID
    fi
    pkill -P $$  # Kill all child processes of the script
    cd $MUBENCH_WORKDIR
    kubectl delete -f yamls/
    echo "[$(date)] Cleanup completed." | tee -a $LOGFILE
    exit 1
}

# Set up trap to catch SIGINT (Ctrl+C) and call cleanup
trap cleanup SIGINT

source ~/miniconda3/etc/profile.d/conda.sh
conda activate base


cd $MUBENCH_WORKDIR
if [ -d "yamls" ]; then
    kubectl delete -f yamls/
fi

# Start uncordoning nodes
echo "[$(date)] Starting to uncordon nodes..." | tee -a $LOGFILE
cd $MIGRATOR_WORKDIR && ./uncordon.sh
rm $TARGET_OUTPUT_DIR/*.log
# Define replica counts
# Loop over replica counts
for pattern in "${PATTERN[@]}"
do            
    for layer in "${LAYER[@]}"
    do
        cd $MUBENCH_WORKDIR
        rm -rf yamls/*
        python configGenerator.py --workmodel=$pattern --replicaCnt=1 --layer=$LAYER
        # Deploy the environment with the current replica count
        echo "[$(date)] Redeploying with $REPLICA_CNT replicas..." | tee -a $LOGFILE
        python Deployers/K8sDeployer/RunK8sDeployer.py -c ./tmp/k8s_parameters.json
        sleep 5 

        # Start the tests
        echo "[$(date)] Starting tests" | tee -a $LOGFILE
        cd $MIGRATOR_WORKDIR
        go run . -v 3 --mode=autoscaling -qos ${CUR_QOS_THRESHOLD} --output=$TARGET_OUTPUT_DIR/${pattern}_${layer}.csv --strategy=be >> $TARGET_OUTPUT_DIR/RL_Migrator.log 2>&1
        # Kill the test process

        cd $MUBENCH_WORKDIR
        kubectl delete -f yamls/
        rm -rf yamls/*
        sleep 15
    done
done
echo "[$(date)] Script completed successfully." | tee -a $LOGFILE