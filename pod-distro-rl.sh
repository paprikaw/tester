#!/bin/bash
# set -e
WORKDIR=$(pwd)
MUBENCH_WORKDIR="/home/ubuntu/muBench" 
MIGRATOR_WORKDIR="/home/ubuntu/pod-migrator"
AGENT_WORKDIR="/home/ubuntu/edge-cloud-env"
LOGFILE="$WORKDIR/deployment.log"

LAYER="all"  # cloud / edge / all
MODEL=("ppo" "dqn")  # dqn / ppo
PATTERN=("aggregator_sequential")  # Used by redeploy.sh
MUBENCH_CONFIG_PATH="Configs/K8sParameters.json"  # Used by redeploy.sh
OUTPUT_DIR="$WORKDIR/results"
TAG="distribution"
mkdir -p $OUTPUT_DIR/$TAG/rl
TARGET_OUTPUT_DIR="$OUTPUT_DIR/$TAG/rl"
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

# Define replica counts
REPLICA_CNTS=(5)
# Loop over replica counts
for iter in {1..6}
do
    echo "[$(date)] Iteration: $iter" | tee -a $LOGFILE
    for model in "${MODEL[@]}"
    do
        for pattern in "${PATTERN[@]}"
        do            
            cd $AGENT_WORKDIR
            setsid python server.py --modelname $model --pattern $pattern --tag complete >> $TARGET_OUTPUT_DIR/RL_Server.log  2>&1 &
            SERVER_PID=$!  # 保存服务器的进程ID
            echo "[$(date)] Server started with PID: $SERVER_PID" | tee -a $LOGFILE
            for replica in "${REPLICA_CNTS[@]}"
            do
                echo "[$(date)] Processing replica count: $replica, model: $model, pattern: $pattern" | tee -a $LOGFILE
                cd $MUBENCH_WORKDIR
                python configGenerator.py --workmodel=$pattern --replicaCnt=$replica --layer=$LAYER
                # Run tests for each replica count
                for i in {1..5}
                do
                    echo "[$(date)] Running test $i with replica count $replica, model: $model, pattern: $pattern" | tee -a $LOGFILE
                    cd $MUBENCH_WORKDIR
                    # Deploy the environment with the current replica count
                    echo "[$(date)] Redeploying with $replica replicas..." | tee -a $LOGFILE
                    kubectl delete -f yamls/
                    rm -rf yamls/*
                    python Deployers/K8sDeployer/RunK8sDeployer.py -c ./tmp/k8s_parameters.json
                    sleep 5
                    # Start the tests
                    echo "[$(date)] Starting tests for replica count $replica, test $i..." | tee -a $LOGFILE
                    cd $MIGRATOR_WORKDIR
                    echo "[$(date)] Running migrator for replica count $replica, test $i, model: $model, pattern: $pattern..." | tee -a $LOGFILE
                    go run . -v 2 --mode=pod_distribution --strategy=rl --output=$TARGET_OUTPUT_DIR/${pattern}_${model}_replica${replica}.csv >> $TARGET_OUTPUT_DIR/RL_Migrator.log 2>&1

                    # Kill the test process
                    echo "[$(date)] Killing test process with PID: $TESTER_PID" | tee -a $LOGFILE
                    kill -TERM $TESTER_PID

                    echo "[$(date)] Test $i with replica count $replica completed." | tee -a $LOGFILE
                done
                # echo "[$(date)] Finished processing replica count: $replica, model: $model, pattern: $pattern" | tee -a $LOGFILE
            done
            echo "[$(date)] Shutting down the server with PID: $SERVER_PID" | tee -a $LOGFILE
            kill -TERM $SERVER_PID
        done
    done
done
echo "[$(date)] Script completed successfully." | tee -a $LOGFILE
