#!/bin/bash
# set -e
WORKDIR=$(pwd)
MUBENCH_WORKDIR="/home/ubuntu/muBench" 
MIGRATOR_WORKDIR="/home/ubuntu/pod-migrator"
AGENT_WORKDIR="/home/ubuntu/edge-cloud-env"
LOGFILE="$WORKDIR/deployment.log"

LAYER=("all" "cloud" "edge")  # cloud / edge / all
PATTERN=("chain")  # Used by redeploy.sh
# PATTERN=("chain")  # Used by redeploy.sh
# SEQ_CASE_WAITING_TIME=("120")
# SEQ_CASE_AFTER_WAITING_TIME=("200")
# SEQ_QOS_THRESHOLD=("250")  # Used by redeploy.sh
# SEQ_TARGET_NODE_A="tb-edge-vm-4-1"
# SEQ_TARGET_NODE_B="tb-cloud-vm-8-1"

CUR_CASE_WAITING_TIME="150"
CUR_CASE_AFTER_WAITING_TIME="150"
CUR_QOS_THRESHOLD="0"  # Used by redeploy.sh
CUR_TARGET_NODE_A="tb-edge-vm-4-1"
CUR_TARGET_NODE_B="tb-cloud-vm-8-1"
CUR_STABLE_START_TIME="90"
CUR_EXPERIMENT_WAITING_TIME="30"
REPLICA_CNT=3

# CUR_CASE_WAITING_TIME=$PAR_CASE_WAITING_TIME
# CUR_QOS_THRESHOLD=$PAR_QOS_THRESHOLD
# CUR_TARGET_NODE_A=$PAR_TARGET_NODE_A
# CUR_TARGET_NODE_B=$PAR_TARGET_NODE_B
# CUR_STABLE_START_TIME=$PAR_STABLE_START_TIME
# CUR_EXPERIMENT_WAITING_TIME=$PAR_EXPERIMENT_WAITING_TIME
# CUR_CASE_AFTER_WAITING_TIME=$PAR_CASE_AFTER_WAITING_TIME

MUBENCH_CONFIG_PATH="Configs/K8sParameters.json"  # Used by redeploy.sh
OUTPUT_DIR="$WORKDIR/tests"
TAG="nodefailed"
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
        python configGenerator.py --workmodel=$pattern --replicaCnt=$REPLICA_CNT --layer=$LAYER
        # Deploy the environment with the current replica count
        echo "[$(date)] Redeploying with $REPLICA_CNT replicas..." | tee -a $LOGFILE
        kubectl delete -f yamls/
        rm -rf yamls/*
        python Deployers/K8sDeployer/RunK8sDeployer.py -c ./tmp/k8s_parameters.json
        sleep 5
        # Start the tests
        echo "[$(date)] Starting tests" | tee -a $LOGFILE
        setsid python Benchmarks/Runner/Runner.py -c tmp/runner_parameters.json >> $TARGET_OUTPUT_DIR/RL_Runner.log 2>&1 &
        cd $MIGRATOR_WORKDIR
        echo "[$(date)] Running migrator" | tee -a $LOGFILE
        go run . -v 2 --mode=nodefailed -t ${CUR_CASE_WAITING_TIME} -qos ${CUR_QOS_THRESHOLD} --target_node_a=${CUR_TARGET_NODE_A} --target_node_b=${CUR_TARGET_NODE_B} --output=$TARGET_OUTPUT_DIR/${pattern}_${layer}_replica${REPLICA_CNT}.csv --stable_start_time=${CUR_STABLE_START_TIME} --experiment_waiting_time=${CUR_EXPERIMENT_WAITING_TIME} --after_wait_time=${CUR_CASE_AFTER_WAITING_TIME} >> $TARGET_OUTPUT_DIR/RL_Migrator.log 2>&1
        # Kill the test process
        echo "[$(date)] Killing test process with PID: $TESTER_PID" | tee -a $LOGFILE
        kill -TERM $TESTER_PID
    done
done
cd $MUBENCH_WORKDIR
kubectl delete -f yamls/
echo "[$(date)] Script completed successfully." | tee -a $LOGFILE
