from matplotlib import pyplot as plt
from matplotlib.ticker import MultipleLocator
import re
import pandas as pd

def prepare_data(articles_df, regex_list, column='text'):
    data = []
    regex_list.reverse()
    for regex in regex_list:
        if type(regex) is tuple:
            term, regex = regex
        else:
            term = regex
        for year, year_df in articles_df.groupby('year'):
            total_word_count = year_df[column].apply(lambda x: len(x.split())).sum()
            count = year_df[column].apply(lambda x: len(re.findall(regex, x))).sum()
            data.append({'year': year,
                         'term': term,
                         'count': count,
                         'regex': regex,
                         'total_word_count': total_word_count})

    aggregated = pd.DataFrame(data)
    return aggregated

def print_occurences(data_frame, regex_list):
    output_list = []

    for regex in regex_list:
        regex_data = data_frame[data_frame['term'] == regex]
        year_occurrences = [f"{year}({count})" for year, count in zip(regex_data['year'], regex_data['count']) if count > 0]
        formatted_output = f"{regex}: " + ", ".join(year_occurrences)
        output_list.append(formatted_output)

    print("\n".join(output_list))


def plot_by_year(data, dep_col='term', col_search_term='regex',
                 title= None, x_label=None, y_label=None, y_axis_limit=None,
                 file=None, dpi=300, scale_factor=300, color='darkblue'):
    years = data['year'].values
    dep_var = data[dep_col].values
    citation_counts = data['count'].values
    total_word_counts = data['total_word_count'].values

    # Calculate relative frequencies
    relative_frequencies = citation_counts / total_word_counts

    # Find the highest relative frequency across all data
    max_relative_frequency = max(relative_frequencies)

    # Scale the relative frequencies so that the highest relative frequency corresponds to a suitable size for the dots
    scaled_relative_frequencies = (relative_frequencies / max_relative_frequency) * scale_factor

    # Create plot with higher DPI
    fig, ax = plt.subplots(dpi=dpi)

    # Set the x and y-axis labels if given
    if x_label:
        ax.set_xlabel(x_label)
    if y_label:
        ax.set_ylabel(y_label)

    # Scatter plot with scaled relative frequencies as size
    ax.scatter(years, dep_var, s=scaled_relative_frequencies, color=color, zorder=2)

    # Annotate with the search term (right-aligned, half-size of labels, in grey)
    # if col_search_term in data.columns:
    #     annotated_terms = set()  # Keep track of terms that have been annotated
    #     for y, term, search_term in zip(dep_var, data[dep_col], data[col_search_term]):
    #         if term not in annotated_terms:
    #             annotated_terms.add(term)
    #             ax.annotate(search_term, (min(years), y), textcoords="offset points",
    #                         xytext=(-10, 0), ha='right', fontsize='small', color='grey')


    # Connect the earliest and last point of each observed variable with a line
    for dep_v in set(dep_var):
        dep_data = data[(data[dep_col] == dep_v) & (data['count'] > 0)].sort_values('year')
        if len(dep_data) > 1:
            ax.plot([dep_data['year'].iloc[0], dep_data['year'].iloc[-1]],
                    [dep_data[dep_col].iloc[0], dep_data[dep_col].iloc[-1]],
                    color='grey', linewidth=0.5, zorder=1)

    # Set the y-axis limits
    if y_axis_limit is not None:
        ax.set_ylim(y_axis_limit)

    # Increase the number of year labels on the x-axis
    #min_year = min(years)
    #max_year = max(years)
    #ax.xaxis.set_major_locator(MultipleLocator(base=x_ticks_base))
    #ax.set_xticks(range(min_year, max_year+1), minor=False)

    if file is not None:
        # Save the plot with higher DPI
        plt.savefig(file, bbox_inches="tight", dpi=dpi)

    if title is not None:
        plt.title(title)

    # Show the plot
    return plt.show()


def plot_by_year_absolute(data, dep_col='term', dep_label='Term', file=None, y_axis_limit=None,
                          title= None, alpha_from_relative_frequency=False, dpi=300):
    years = data['year'].values
    dep_var = data[dep_col].values
    citation_counts = data['count'].values

    # Create plot
    fig, ax = plt.subplots(dpi=dpi)

    # Set the x and y-axis labels
    ax.set_xlabel('Year')
    ax.set_ylabel(dep_label)

    if alpha_from_relative_frequency:
        total_word_counts = data['total_word_count'].values
        relative_frequencies = citation_counts / total_word_counts

        # Find the max and min relative frequencies
        max_relative_frequency = max(relative_frequencies)
        min_relative_frequency = min(relative_frequencies)

        # Calculate the alpha values based on the relative frequencies
        alpha_values = 0.5 + ((relative_frequencies - min_relative_frequency) / (max_relative_frequency - min_relative_frequency)) * 0.5

        # Scatter plot with citation counts as size and alpha values as transparency levels
        ax.scatter(years, dep_var, s=citation_counts, color='darkblue', alpha=alpha_values)
    else:
        # Scatter plot with citation counts as size and no transparency
        ax.scatter(years, dep_var, s=citation_counts, color='darkblue', alpha=1.0)

    # Connect the earliest and last point of each observed variable with a line
    for dep_v in set(dep_var):
        dep_data = data[data[dep_col] == dep_v][['year', dep_col]].sort_values('year')
        ax.plot(dep_data['year'], dep_data[dep_col], color='grey', linewidth=0.5)

    if y_axis_limit is not None:
        ax.set_ylim(y_axis_limit)  # Set the y-axis limits

    if file is not None:
        plt.savefig(file, bbox_inches="tight", dpi=dpi)

    if title is not None:
        plt.title(title)

    # Show the plot
    return plt.show()