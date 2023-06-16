import matplotlib.pyplot as plt
import pandas as pd
import numpy as np

def plot_stacked_area(df, window_size=1, var_label=None, value_label=None, title=None):
    # Pivot the data so each unique value in 'var' becomes a column
    pivot_df = df.pivot(index='year', columns='var', values='value')

    # Apply rolling mean
    smoothed_df = pivot_df.rolling(window_size).mean()

    # Plot the data
    plt.figure(figsize=(10,7))
    plt.stackplot(smoothed_df.index, smoothed_df.transpose(), labels=smoothed_df.columns, colors=plt.get_cmap('gray_r')(np.linspace(0.1, 1, len(smoothed_df.columns))))

    # Add a legend
    if var_label:
        plt.legend(title=var_label)
    else:
        plt.legend()

    # Add Y label if provided
    if value_label:
        plt.ylabel(value_label)

    # Add title if provided
    if title:
        plt.title(title)

    plt.show()

