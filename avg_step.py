import pandas as pd
import os

# Define the path to the CSV file
csv_path = './results/complete/rl'
msa = "chain"
strategy = "ppo"
replicas = [1, 3, 5]
# List all files in the directory
files = os.listdir(csv_path)

for replica in replicas:
    csv_file = f"{csv_path}/{msa}_{strategy}_replica{replica}.csv"
    # Read the CSV file and calculate the average of the 'step' column
    if csv_file:
        df = pd.read_csv(csv_file)
        if 'step' in df.columns:
            avg_step = df['step'].mean()
            print(f'Average step for {msa} {strategy} {replica}: {avg_step}')
        else:
            print('The column "step" does not exist in the CSV file.')
    else:
        print('No CSV file found in the specified directory.')
