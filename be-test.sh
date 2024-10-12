# set -e
WORKDIR=$(pwd)
MUBENCH_WORKDIR="/home/ubuntu/muBench" 
MIGRATOR_WORKDIR="/home/ubuntu/pod-migrator"
AGENT_WORKDIR="/home/ubuntu/edge-cloud-env"
LOGFILE="$WORKDIR/deployment.log"
MUBENCH_CONFIG_PATH="Configs/K8sParameters.json"  # Used by redeploy.sh
LAYER=("all")  # cloud / edge / all
WORKMODEL=("chain")  # Used by redeploy.sh
OUTPUT_DIR="$WORKDIR/results"
OUTPUT_PREFIX="verified2"
source ~/miniconda3/etc/profile.d/conda.sh
conda activate base

cd $WORKDIR 
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
REPLICA_CNTS=(5 3 1)
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
                echo "[$(date)] Running test $i with replica count $replica" | tee -a $LOGFILE
                cd $MUBENCH_WORKDIR
                # Deploy the environment with the current replica count
                echo "[$(date)] Redeploying with $replica replicas..." | tee -a $LOGFILE
                kubectl delete -f yamls/
                rm -rf yamls/*
                python configGenerator.py --workmodel $workmodel --replicaCnt $replica --layer $layer
                python Deployers/K8sDeployer/RunK8sDeployer.py -c ./tmp/k8s_parameters.json

                # Start the tests
                echo "[$(date)] Starting tests for replica count $replica, test $i..." | tee -a $LOGFILE
                # Tester has internal 10 seconds delay for running the test
                python Benchmarks/Runner/Runner.py -c tmp/runner_parameters.json >> $OUTPUT_DIR/${OUTPUT_PREFIX}_Runner.log 2>&1 &
                TESTER_PID=$!  # 保存测试进程的ID
                sleep 10
                # Run the migrator
                cd $MIGRATOR_WORKDIR
                echo "[$(date)] Collecting latency data $replica, test $i..." | tee -a $LOGFILE
                go run . -v 1 -test --replicaCnt=$replica --strategy=be --output=$OUTPUT_DIR/${OUTPUT_PREFIX}_${layer}_${workmodel}_replica${replica}.csv >> $OUTPUT_DIR/${OUTPUT_PREFIX}_Migrator.log 2>&1

                # Kill the test process
                echo "[$(date)] Killing test process with PID: $TESTER_PID" | tee -a $LOGFILE
                kill -TERM $TESTER_PID

                echo "[$(date)] Test $i with replica count $replica completed." | tee -a $LOGFILE
            done

            echo "[$(date)] Finished processing replica count: $replica" | tee -a $LOGFILE
        done
    done
done
# Kill the server process
echo "[$(date)] Shutting down the server with PID: $SERVER_PID" | tee -a $LOGFILE
kill $SERVER_PID

echo "[$(date)] Script completed successfully." | tee -a $LOGFILE