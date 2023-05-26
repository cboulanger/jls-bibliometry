from matplotlib import pyplot as plt
import re
import pandas as pd

def prepare_data(articles_df, regex_list):
    data = []

    for regex in regex_list:
        for year, year_df in articles_df.groupby('year'):
            count = year_df['text'].apply(lambda x: len(re.findall(regex, x))).sum()
            data.append({'year': year, 'term': regex, 'count': count})

    aggregated = pd.DataFrame(data)
    return aggregated

def plot_by_year(data, dep_col='term', dep_label='Term'):
    years = data['year'].values
    dep_var = data[dep_col].values
    citation_counts = data['count'].values

    # Create plot
    fig, ax = plt.subplots()

    # Set the x and y axis labels
    ax.set_xlabel('Year')
    ax.set_ylabel(dep_label)

    # Scatter plot with citation counts as size
    scatter = ax.scatter(years, dep_var, s=citation_counts)

    # Connect the earliest and last point of each observed variable with a line
    for dep_v in set(dep_var):
        dep_data = data[data[dep_col] == dep_v][['year', dep_col]].sort_values('year')
        ax.plot(dep_data['year'], dep_data[dep_col], color='grey', linewidth=0.5)

    # Show the plot
    return plt.show()


