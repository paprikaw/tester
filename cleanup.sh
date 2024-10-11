kill $(pgrep -f "python server.py")
kill $(pgrep -f "./run_tests.sh")
if [ -d "output" ]; then
    rm -rf output
fi