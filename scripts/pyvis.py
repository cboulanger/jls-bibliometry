import os, json, re
from py2neo import Graph, Path, Node, Relationship, walk
from pyvis.network import Network
from IPython.display import display, HTML
from typing import Union
from textwrap import shorten

def py2neo_to_pyvis(net: Network, obj: Union[Path, Node, Relationship], auto_rel_label=False, edge_default_width = 3):
    if type(obj) is Path:
        for o in walk(obj):
            py2neo_to_pyvis(net, o)
    elif type(obj) is Node:
        if obj['label'] is None or obj['label'] == "":
            label = obj['display_name'] or obj['title'] or obj['name'] or obj['id'] or ''
            label = shorten(label, width=50, placeholder="...").replace(':', ':\n')
            obj['label'] = label
        obj['group'] = obj['group'] or str(obj.labels)
        net.add_node(obj.identity, font={'size': 20}, **obj)
    elif issubclass(type(obj), Relationship):
        start_node = obj.start_node
        end_node = obj.end_node
        # check that no relations already exists (doesn't allow multiple relationships)
        for e in net.edges:
            if e['from'] == start_node.identity and e['to'] == end_node.identity:
                return
        py2neo_to_pyvis(net, start_node)
        py2neo_to_pyvis(net, end_node)
        neo4j_label = type(obj).__name__
        if obj['title'] is None:
            obj['title'] = neo4j_label
        if obj['label'] is None:
            obj['label'] = (neo4j_label if auto_rel_label else None)
        if obj['group'] is None:
            obj['group'] = str(obj.labels)
        if obj['width'] is None:
            obj['width'] = edge_default_width
        net.add_edge(start_node.identity, end_node.identity, **obj)

def create_or_update_network(graph: Graph,
                             query: str,
                             height: str = "300px",
                             auto_rel_label=False,
                             net: Network = None,
                             seed: int = None,
                             **kwargs) -> Network:
    data = graph.run(query, **kwargs).data()
    if net is None:
        net = Network(height, notebook=True, cdn_resources='in_line', directed=True)
        net.force_atlas_2based(overlap=0.7, damping=1)
        if seed is not None:
            options = json.loads(net.options.to_json())
            options['layout'] = {"randomSeed":seed, "improvedLayout":True}
            options = json.dumps(options)
            net.set_options(options)
    for row in data:
        for obj in row.values():
            py2neo_to_pyvis(net, obj, auto_rel_label= auto_rel_label)
    return net

def draw_network(net: Network,
                 title: str = None,
                 caption: str = None,
                 file: str = None,
                 url: str = None,
                 prev_url: str = None,
                 next_url: str = None,
                 link_only: bool = False):
    html = net.generate_html()
    # remove nonsense in the generated html
    html = re.sub(r'<center>.*?<h1></h1>.*?</center>', '', html, flags=re.M|re.S)
    # optional: add title
    if title is not None:
        html = html.replace("<head>", f'<head><title>{title}</title>')
        html = html.replace("<body>", f'<body><h1 style="text-align:center">{title}</h1>')
    # optional: caption
    if caption is not None:
        html = html.replace("</body>", f'\n<div style="text-align:center">{caption}</div>\n</body>')
    # optional: back & forward links
    if prev_url or next_url:
        nav_bar = '<div style="text-align:center">'
        if caption:
            nav_bar = "<hr/>" + nav_bar
        if prev_url:
            nav_bar += f'[&nbsp;<a href="{prev_url}">Previous</a>&nbsp;]'
        if next_url:
            nav_bar += f' [&nbsp;<a href="{next_url}">Next</a>&nbsp;]'
        nav_bar += '</div>'
        html = html.replace("</body>", f'\n{nav_bar}\n</body>')
    # stop physics after timeout
    html = html.replace("</body>", '\n<script>window.setTimeout(()=>network.setOptions({physics:false}),1000)</script>\n</body>')
    # optional: save to file
    if file is not None:
        if file.endswith(".html"):
            with open(file, mode="w", encoding="utf-8") as f:
                f.write(html)
        else:
            raise RuntimeError("Unsupported file extension")
    # optional: return a link only
    if link_only and url:
        display(HTML(f'<a href="{url}" target="_blank">Click here to open {os.path.basename(file)}.</a>'))
    elif link_only and file:
        display(HTML(f'<a href="{file}" target="_blank">Click here to open {os.path.basename(file)}.</a>'))
    else:
        display(HTML(html))

# convenience method
def draw(graph: Graph,
         query: str,
         height: str = "300px",
         title: str = None,
         file: str = None,
         link_only = False,
         do_display = True,
         seed = None,
         auto_rel_label=False,
         **kwargs):
    # deprecated do_display
    if do_display == False:
        link_only = True
    net = create_or_update_network(graph, query, height=height, seed=seed, auto_rel_label=auto_rel_label, **kwargs)
    return draw_network(net, file=file, link_only=link_only, title=title)

def create_timeseries(graph: Graph,
                      query: str, file_id:str,
                      title: str = None,
                      caption: str = None,
                      seed=5,
                      file_prefix="docs/"):
    start_year = 1974
    end_year = 2023
    num_ranges = 5
    for i in range(num_ranges):
        decade_start = start_year + (i * 10)
        decade_end = decade_start + 9
        if decade_end > end_year:
            decade_end = end_year
        net = create_or_update_network(graph, query, height="600", seed=seed,
                                       year_start=decade_start, year_end=decade_end)
        file = f"{file_id}-{decade_start}-{decade_end}.html"
        url = f"https://cboulanger.github.io/jls-bibliometry/{file}"
        prev_url = f"{file_id}-{decade_start-10}-{decade_start-1}.html" if i > 0 else None
        next_url = f"{file_id}-{decade_end+1}-{decade_end+10}.html" if i < (num_ranges - 1) else None
        draw_network(net, title=f"{title}, {decade_start} - {decade_end}", caption=caption,
                     prev_url=prev_url, next_url= next_url,
                     file=f"{file_prefix}{file}", url=url, link_only=True)
