from py2neo import Graph, Path, Node, Relationship, walk
from pyvis.network import Network
from IPython.display import display, HTML, display_png
from typing import Union

def py2neo_to_pyvis(net: Network, obj: Union[Path, Node, Relationship]):
    if type(obj) is Path:
        for o in walk(obj):
            py2neo_to_pyvis(net, o)
    elif type(obj) is Node:
        label = obj['display_name'] or obj['title'] or obj['name'] or obj['id'] or ''
        net.add_node(obj.identity, label=label, group=str(obj.labels), font={'size': 20})
    elif issubclass(type(obj), Relationship):
        start_node = obj.start_node
        end_node = obj.end_node
        py2neo_to_pyvis(net, start_node)
        py2neo_to_pyvis(net, end_node)
        net.add_edge(start_node.identity, end_node.identity)


def draw(graph: Graph, query: str, height: str = "300px", file=None, do_display=True, **kwargs):
    data = graph.run(query, **kwargs).data()
    net = Network(height, notebook=True, cdn_resources='in_line', directed=True)
    net.force_atlas_2based()
    for row in data:
        for obj in row.values():
            py2neo_to_pyvis(net, obj)
    html = net.generate_html()
    if file:
        if file.endswith(".html"):
            with open(file, mode="w", encoding="utf-8") as f:
                f.write(html)
        else:
            raise RuntimeError("Unsupported file extension")
    if do_display:
        display(HTML(html))

#%%
