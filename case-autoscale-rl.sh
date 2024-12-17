#!/bin/bash
# set -e
WORKDIR=$(pwd)
MUBENCH_WORKDIR="/home/ubuntu/muBench" 
MIGRATOR_WORKDIR="/home/ubuntu/pod-migrator"
AGENT_WORKDIR="/home/ubuntu/edge-cloud-env"
LOGFILE="$WORKDIR/deployment.log"

LAYER="all"  # cloud / edge / all
MODEL=("ppo" "dqn")  # dqn / ppo
PATTERN=("aggregator_parallel")  # Used by redeploy.sh
REPLICA_CNT=1

CUR_QOS_THRESHOLD=80

MUBENCH_CONFIG_PATH="Configs/K8sParameters.json"  # Used by redeploy.sh
OUTPUT_DIR="$WORKDIR/results"
TAG="autoscaling"
mkdir -p $OUTPUT_DIR/$TAG
TARGET_OUTPUT_DIR="$OUTPUT_DIR/$TAG"
# Clean up function to run on exit
cleanup() {
    echo "[$(date)] Cleaning up resources..." | tee -a $LOGFILE
    if [[ -n "$SERVER_PID" ]]; then
        echo "[$(date)] Shutting down the server with PID: $SERVER_PID" | tee -a $LOGFILE
        kill -TERM $SERVER_PID
    fi
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
# If yamls exists, try to undeploy it from the cluster to make cluster state consistent
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
    for model in "${MODEL[@]}"
    do            
        cd $AGENT_WORKDIR
        setsid python server.py --modelname $model --pattern $pattern --tag complete3 >> $TARGET_OUTPUT_DIR/RL_Server.log  2>&1 &
        SERVER_PID=$!  # 保存服务器的进程ID
        echo "[$(date)] Server started with PID: $SERVER_PID" | tee -a $LOGFILE


        cd $MUBENCH_WORKDIR
        echo "[$(date)] Generating config for replica count $REPLICA_CNT, model: $model, pattern: $pattern" | tee -a $LOGFILE
        rm -rf yamls/*
        python configGenerator.py --workmodel=$pattern --replicaCnt=$REPLICA_CNT --layer=$LAYER
        python Deployers/K8sDeployer/RunK8sDeployer.py -c ./tmp/k8s_parameters.json

        sleep 5
        cd $MIGRATOR_WORKDIR
        echo "[$(date)] Starting tests for replica count $REPLICA_CNT, model: $model, pattern: $pattern" | tee -a $LOGFILE
        go run . -v 3 --mode=autoscaling -qos ${CUR_QOS_THRESHOLD} --output=$TARGET_OUTPUT_DIR/${pattern}_${model}.csv --strategy=rl >> $TARGET_OUTPUT_DIR/RL_Migrator.log 2>&1
        # Kill the test process
        echo "[$(date)] Shutting down the server with PID: $SERVER_PID" | tee -a $LOGFILE
        kill -TERM $SERVER_PID

        cd $MUBENCH_WORKDIR
        kubectl delete -f yamls/
        sleep 10
    done
done
echo "[$(date)] Script completed successfully." | tee -a $LOGFILE
