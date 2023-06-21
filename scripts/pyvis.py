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

def generate_script():
    return """
        const storageId = "pyvis-network-slider-value"
        let edgeCache = []; // this array will store the removed edges
        const slider = document.getElementById("edgeValueSlider");
        const onSliderChange = value => {
          document.getElementById("sliderValue").innerText = value;
          // Check each edge
          edges.forEach(edge => {
            // If edge value is less than slider value and edge is not hidden
            if (edge.value < value && !edge.hidden) {
              edge.hidden = true; // mark as hidden
              edgeCache.push(edge); // add to cache
              edges.remove(edge.id); // remove from DataSet
            }
          });
          // Check each cached edge
          for (let i = edgeCache.length - 1; i >= 0; i--) {
            let cachedEdge = edgeCache[i];
            // If cached edge value is more than or equal to slider value and edge is hidden
            if (cachedEdge.value >= value && cachedEdge.hidden) {
              cachedEdge.hidden = false; // mark as visible
              edges.add(cachedEdge); // add back to DataSet
              edgeCache.splice(i, 1); // remove from cache
            }
          }
          window.localStorage.setItem(storageId, value);
        };
        // determine highest and lowest number of citation 
        let min = Math.min(...edges.get().map(edge => edge.value));
        let max = Math.max(...edges.get().map(edge => edge.value));
        
        // dynamically determine the slider options (=ticks)
        let steps = [1, 2, 5, 10, 25, 50, 100];
        let maxOptions = 10;
        let delta = max - min;
        let step;
        for(let s of steps) {
            if(Math.ceil(delta / s) <= maxOptions) {
                step = s;
                break;
            }
        }
        
        // configure the slider
        slider.addEventListener('change', e => onSliderChange(e.target.value));
        slider.min = min;
        slider.max = max;
        const datalist = document.getElementById('steplist');
        let start = Math.floor(min / step) * step; // Start from the nearest higher multiple of step
        for (let i = start; i <= max; i += step) {
            let option = document.createElement('option');
            option.value = Math.max(i,min);
            datalist.appendChild(option);
        }
        const value = window.localStorage.getItem(storageId) || 10;
        slider.value = Math.min(value, max);
        onSliderChange(value);
    """

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
    # navigation bar
    nav_bar = '<div style="text-align:center">'
    if caption:
        nav_bar = "<hr/>" + nav_bar
    # optional: back and forward links
    if prev_url or next_url:
        if prev_url:
            nav_bar += f'<a href="{prev_url}">Previous</a>'
            nav_bar += '&nbsp;| '
        if next_url:
            nav_bar += f'<a href="{next_url}">Next</a>'
            nav_bar += '&nbsp;| '
    nav_bar += '<datalist id="steplist"></datalist>'
    nav_bar += 'Minimum citations:&nbsp;<span id="sliderValue"></span>&nbsp;'
    nav_bar += '<input style="width:200px" type="range" class="slider" id="edgeValueSlider" list="steplist"></input>'
    nav_bar += '&nbsp;| '
    nav_bar += 'Enable physics:&nbsp;<input type="checkbox" checked onchange="network.setOptions({ physics: this.checked })">'
    nav_bar += '</div>'
    nav_bar += f'\n<script>{generate_script()}</script>'
    html = html.replace("</body>", f'\n{nav_bar}\n</body>')
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
