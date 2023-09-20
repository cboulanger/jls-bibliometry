from matplotlib import pyplot as plt
import re
import pandas as pd

def prepare_data(articles_df, regex_list):
    data = []

    for regex in regex_list:
        for year, year_df in articles_df.groupby('year'):
            total_word_count = year_df['text'].apply(lambda x: len(x.split())).sum()
            count = year_df['text'].apply(lambda x: len(re.findall(regex, x))).sum()
            data.append({'year': year, 'term': regex, 'count': count, 'total_word_count': total_word_count})

    aggregated = pd.DataFrame(data)
    return aggregated

def plot_by_year(data, dep_col='term', dep_label='Term', file=None, y_axis_limit=None, title= None, relative_frequency=False):
    years = data['year'].values
    dep_var = data[dep_col].values
    citation_counts = data['count'].values

    # Create plot
    fig, ax = plt.subplots()

    # Set the x and y-axis labels
    ax.set_xlabel('Year')
    ax.set_ylabel(dep_label)

    # Scatter plot with citation counts as size
    ax.scatter(years, dep_var, s=citation_counts, color='darkblue')

    if relative_frequency:
        total_word_counts = data['total_word_count'].values
        relative_frequencies = citation_counts / total_word_counts
        scaling_factor = max(citation_counts) / max(relative_frequencies)
        scaled_relative_frequencies = relative_frequencies * scaling_factor

        # Overlay scatter plot with scaled relative frequencies in a lighter color
        ax.scatter(years, dep_var, s=scaled_relative_frequencies, color='lightblue', alpha=0.6)

    # Connect the earliest and last point of each observed variable with a line
    for dep_v in set(dep_var):
        dep_data = data[data[dep_col] == dep_v][['year', dep_col]].sort_values('year')
        ax.plot(dep_data['year'], dep_data[dep_col], color='grey', linewidth=0.5)

    if y_axis_limit is not None:
        ax.set_ylim(y_axis_limit)  # Set the y-axis limits

    if file is not None:
        plt.savefig(file, bbox_inches="tight", dpi=300)

    if title is not None:
        plt.title(title)

    # Show the plot
    return plt.show()
