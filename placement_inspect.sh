WORKDIR=$(pwd)
MUBENCH_WORKDIR="/home/ubuntu/muBench" 
MIGRATOR_WORKDIR="/home/ubuntu/pod-migrator"
AGENT_WORKDIR="/home/ubuntu/edge-cloud-env"
LOGFILE="$WORKDIR/deployment.log"

LAYER="all"  # cloud / edge / all
MUBENCH_CONFIG_PATH="Configs/K8sParameters.json"  # Used by redeploy.sh
OUTPUT_DIR="$WORKDIR/tests"
TAG="complete"
mkdir -p $OUTPUT_DIR/$TAG/rl
TARGET_OUTPUT_DIR="$OUTPUT_DIR/$TAG/rl"
model="ppo"
pattern="aggregator_parallel"
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

echo "[$(date)] Starting the server with model: $model, pattern: $pattern in the background..." | tee -a $LOGFILE
cd $AGENT_WORKDIR
setsid python server.py --modelname $model --pattern $pattern --tag $TAG >> $TARGET_OUTPUT_DIR/RL_Server.log  2>&1 &
SERVER_PID=$!  # 保存服务器的进程ID
echo "[$(date)] Running test $i with replica count $replica, model: $model, pattern: $pattern" | tee -a $LOGFILE
cd $MUBENCH_WORKDIR

# Deploy the environment with the current replica count
echo "[$(date)] Redeploying with $replica replicas..." | tee -a $LOGFILE
kubectl delete -f yamls/
rm -rf yamls/*
python Deployers/K8sDeployer/RunK8sDeployer.py -c ./tmp/k8s_parameters.json
sleep 5
# Run the migrator
cd $MIGRATOR_WORKDIR
echo "[$(date)] Running migrator for replica count $replica, test $i, model: $model, pattern: $pattern..." | tee -a $LOGFILE
go run . -v 2 --mode=test --strategy=rl --output=$TARGET_OUTPUT_DIR/${pattern}_${model}_replica${replica}.csv 2>&1

# Kill the test process
echo "[$(date)] Killing test process with PID: $TESTER_PID" | tee -a $LOGFILE
kill -TERM $TESTER_PID
