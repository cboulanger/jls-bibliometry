from pyvis.network import Network
import pandas as pd
import networkx as nx
from IPython.display import display, IFrame
from ipywidgets import interactive, widgets

def draw_network(df, start_year, end_year, edge_width=3):
    df_year = df[(df['Year'] >= start_year) & (df['Year'] <= end_year)]
    df_year = df_year.groupby(['Source', 'Target']).size().reset_index()
    df_year.columns = ['Source', 'Target', 'Weight']

    # Create a directed graph
    G = nx.from_pandas_edgelist(df_year, source='Source', target='Target', edge_attr='Weight', create_using=nx.DiGraph())

    # Create a PyVis network
    net = Network(height='750px', width='100%', bgcolor='#222222', font_color='white')

    # for each node and its attributes in the networkx graph
    for node,node_attrs in G.nodes(data=True):
        net.add_node(str(node), **node_attrs)

    # for each edge and its attributes in the networkx graph
    for source,target,edge_attrs in G.edges(data=True):
        # if value/width not specified directly, and weight is specified, set 'value' to 'weight'
        if not 'value' in edge_attrs and 'weight' in edge_attrs:
            # place at key 'value' the weight of the edge
            edge_attrs['value']=edge_attrs['weight']
        # add the edge
        net.add_edge(str(source), str(target), **edge_attrs)

    # Save as HTML and return the IFrame
    net.save_graph("figure/network.html")
    return IFrame(src="figure/network.html", width=980, height=600)

def create_interactive_network(df, window=5):
    min_year = df['Year'].min()
    max_year = df['Year'].max()

    widget = interactive(draw_network,
                         {'manual': True},
                         df=widgets.fixed(df),
                         start_year=widgets.IntSlider(min=min_year, max=max_year - window + 1, step=1, value=min_year),
                         end_year=widgets.IntSlider(min=min_year + window - 1, max=max_year, step=1, value=min_year + window - 1),
                         edge_width=3)
    return display(widget)

# To use the function, you should call:
# widget = create_interactive_network(df)
# display(widget)
