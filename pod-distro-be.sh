#!/bin/bash
# set -e
WORKDIR=$(pwd)
MUBENCH_WORKDIR="/home/ubuntu/muBench" 
MIGRATOR_WORKDIR="/home/ubuntu/pod-migrator"
AGENT_WORKDIR="/home/ubuntu/edge-cloud-env"
MUBENCH_CONFIG_PATH="Configs/K8sParameters.json"  # Used by redeploy.sh
LAYER=("all" "cloud" "edge")  # cloud / edge / all
WORKMODEL=("aggregator_parallel" "aggregator_sequential" "chain")  # Used by redeploy.sh
OUTPUT_DIR="$WORKDIR/results/tests"
TAG="distribution"
TARGET_OUTPUT_DIR="$OUTPUT_DIR/$TAG/be"
LOGFILE="$TARGET_OUTPUT_DIR/deployment.log"
mkdir -p $TARGET_OUTPUT_DIR
source ~/miniconda3/etc/profile.d/conda.sh
conda activate base
cd $TARGET_OUTPUT_DIR
rm *.log
# Start uncordoning nodes
echo "[$(date)] Starting to uncordon nodes..." | tee -a $LOGFILE
cd $MIGRATOR_WORKDIR && ./uncordon.sh

# Clean up function to run on exit
cleanup() {
    echo "[$(date)] Cleaning up resources..." | tee -a $LOGFILE
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
# Define replica counts
REPLICA_CNTS=(1 2 3 4 5)
for iteration in {1..6}
do
    echo "[$(date)] Iteration $iteration..." | tee -a $LOGFILE
    # Loop over replica counts 
    for workmodel in "${WORKMODEL[@]}"
    do
        for layer in "${LAYER[@]}"
        do
            for replica in "${REPLICA_CNTS[@]}"
            do
                echo "[$(date)] Processing replica count: $replica" | tee -a $LOGFILE

                # Generate configuration for current replica count
                cd $MUBENCH_WORKDIR
                echo "[$(date)] Generating configuration for replica count $replica..." | tee -a $LOGFILE
                python configGenerator.py --workmodel $workmodel --replicaCnt $replica --layer $layer

                # Run tests for each replica count
                for i in {1..5}
                do
                    echo "[$(date)] Running test $i with replica count $replica pattern $workmodel layer $layer" | tee -a $LOGFILE
                    cd $MUBENCH_WORKDIR
                    # Deploy the environment with the current replica count
                    echo "[$(date)] Redeploying with $replica replicas..." | tee -a $LOGFILE
                    kubectl delete -f yamls/
                    rm -rf yamls/*
                    python Deployers/K8sDeployer/RunK8sDeployer.py -c ./tmp/k8s_parameters.json
                    # Start the tests
                    cd $MIGRATOR_WORKDIR
                    setsid go run . -v 2 -mode=pod_distribution --strategy=be --output=$TARGET_OUTPUT_DIR/${workmodel}_${layer}_replica${replica}.csv >> $TARGET_OUTPUT_DIR/Migrator.log 2>&1

                    # Kill the test process
                    echo "[$(date)] Killing test process with PID: $TESTER_PID" | tee -a $LOGFILE
                    kill -TERM $TESTER_PID

                    echo "[$(date)] Test $i with replica count $replica completed." | tee -a $LOGFILE
                done
                echo "[$(date)] Finished processing replica count: $replica" | tee -a $LOGFILE
            done
        done
    done
done
# Kill the server process
echo "[$(date)] Shutting down the server with PID: $SERVER_PID" | tee -a $LOGFILE
kill $SERVER_PID

echo "[$(date)] Script completed successfully." | tee -a $LOGFILE