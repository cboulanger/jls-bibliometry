import json, re
from py2neo import Graph, Path, Node, Relationship, walk
from pyvis.network import Network
from IPython.display import display, HTML, Image
from typing import Union
from textwrap import shorten
import subprocess


def strip_property_prefix(input_dict, prefix):
    output_dict = {}
    for key, value in input_dict.items():
        if key.startswith(prefix):
            new_key = key[len(prefix):]
        else:
            new_key = key
        output_dict[new_key] = value
    return output_dict

def py2neo_to_pyvis(net: Network,
                    obj: Union[Path, Node, Relationship],
                    auto_rel_label=False,
                    edge_default_width=3,
                    font_default_size=20):
    if type(obj) is Path:
        for o in walk(obj):
            py2neo_to_pyvis(net, o)
    elif type(obj) is Node:
        p = strip_property_prefix(dict(obj), "vis_")
        label = p.get('label') or p.get('display_name') or p.get('title') or p.get('name') or p.get('id') or ''
        p['label'] = shorten(label, width=50, placeholder="...").replace(':', ':\n')
        if 'group' not in p or p['group'] is None:
            p['group'] = str(obj.labels)
        if 'font' not in p or p['font'] is None:
            p['font'] = {'size': font_default_size}
        net.add_node(obj.identity, **p)
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
        p = strip_property_prefix(dict(obj), "vis_")
        if 'title' not in p or p['title'] is None:
            p['title'] = neo4j_label
        if 'label' not in p or p['label'] is None:
            p['label'] = (neo4j_label if auto_rel_label else None)
        if 'group' not in p or p['group'] is None:
            p['group'] = neo4j_label
        if 'width' not in p or p['width'] is None:
            p['width'] = edge_default_width
        net.add_edge(start_node.identity, end_node.identity, **p)


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
            options['layout'] = {"randomSeed": seed, "improvedLayout": True}
            options = json.dumps(options)
            net.set_options(options)
    for row in data:
        for obj in row.values():
            py2neo_to_pyvis(net, obj, auto_rel_label=auto_rel_label)
    return net


def generate_script(min_edge_value: int = 10):
    return """
        const storageId = "pyvis-network-slider-value"
        let edgeCache = []; // this array will store the removed edges
        const slider = document.getElementById("edgeValueSlider");
        
        // update the network according to the slider value
        const updateNetwork = value => {
          // Check each edge
          edges.forEach(edge => {
            // if edge value is less than slider value, move it to the cache
            if (edge.value < value) {
              edgeCache.push(edge); // add to cache
              edges.remove(edge.id); // remove from DataSet
            }
          });
          // Check each cached edge
          for (let i = edgeCache.length - 1; i >= 0; i--) {
            let cachedEdge = edgeCache[i];
            // If cached edge value is more than or equal to slider value, re-add it to the network
            if (cachedEdge.value >= value) {
              edges.add(cachedEdge); // add back to DataSet
              edgeCache.splice(i, 1); // remove from cache
            }
          }
          window.localStorage.setItem(storageId, value);
        };
        
        // update the display with the value of the slider
        const displaySliderValue = value => {
            document.getElementById("sliderValue").innerText = value
        }
        
        // determine highest and lowest number of citation 
        let min = Math.min(...edges.get().map(edge => edge.value));
        let max = Math.max(...edges.get().map(edge => edge.value));
        
        // dynamically determine the slider options (=ticks)
        let steps = [1, 2, 5, 10, 25, 50, 100];
        let maxOptions = 10;
        let delta = max - min;
        let step;
        for(let s of steps) {
            step = s;
            if(Math.ceil(delta / s) <= maxOptions) break;
        }
        
        // configure the slider
        slider.addEventListener('change', e => updateNetwork(e.target.value));
        slider.addEventListener('input', e => displaySliderValue(e.target.value))
        slider.min = min;
        slider.max = max;
        const datalist = document.getElementById('steplist');
        let start = Math.floor(min / step) * step; // Start from the nearest higher multiple of step
        for (let i = start; i <= max; i += step) {
            let option = document.createElement('option');
            option.value = Math.max(i,min);
            datalist.appendChild(option);
        }
        // the default slider value comes either from the "min_edge_value" query param, 
        // the local storage (to persist across pages), or a value passed to the script
        const defaultValue = parseInt(new URLSearchParams(document.location.search).get('min_edge_value')) || 
                parseInt(window.localStorage.getItem(storageId)) || $min_edge_value;
        const value = Math.min(defaultValue, max);
        slider.value = value;
        updateNetwork(value);
        displaySliderValue(value)
    """.replace("$min_edge_value", str(min_edge_value))


def draw_network(net: Network,
                 title: str = None,
                 caption: str = None,
                 file: str = None,
                 screenshot = False,
                 url: str = None,
                 prev_url: str = None,
                 next_url: str = None,
                 show_nav_bar: bool = True,
                 show_slider: bool = False,
                 min_edge_value: int = None,
                 show_physics_toggle: bool = False,
                 link_only: bool = False):
    html = net.generate_html()
    # remove nonsense in the generated html
    html = re.sub(r'<center>.*?<h1></h1>.*?</center>', '', html, flags=re.M | re.S)
    # optional: add title
    if title is not None:
        html = html.replace("<head>", f'<head><title>{title}</title>')
        html = html.replace("<body>", f'<body><h1 style="text-align:center">{title}</h1>')
    # optional: caption
    if caption is not None:
        html = html.replace("</body>", f'\n<div style="text-align:center; text-wrap: balance">{caption}</div>\n</body>')
    # navigation bar
    if show_nav_bar:
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
        if show_slider is not None:
            nav_bar += '<datalist id="steplist"></datalist>'
            nav_bar += 'Minimum citations:&nbsp;<span id="sliderValue" style="width: 30px;display: inline-block;"></span>&nbsp;'
            nav_bar += '<input style="width:200px" type="range" class="slider" id="edgeValueSlider" list="steplist"></input>'
            nav_bar += '&nbsp;| '
        # optional: show checkbox to toggle physics
        if show_physics_toggle == True:
            nav_bar += 'Enable physics:&nbsp;<input type="checkbox" checked onchange="network.setOptions({ physics: this.checked })">'
        nav_bar += '</div>'
        if show_slider is not None:
            nav_bar += f'\n<script>{generate_script(min_edge_value)}</script>'
        html = html.replace("</body>", f'\n{nav_bar}\n</body>')

    # optional: save to file
    if file is not None:
        if file.endswith(".html"):
            with open(file, mode="w", encoding="utf-8") as f:
                f.write(html)
            if screenshot:
                result = subprocess.run(['python', 'scripts/save-screenshot.py', file, "10"], stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE)
                error = result.stderr.decode('utf-8')
                if error != "":
                    raise RuntimeError(error)
        else:
            raise RuntimeError("Unsupported file extension")
    # optional: return a link only
    if link_only and url:
        display(HTML(f'Open graph at <a href="{url}" target="_blank">{url}.</a>'))
    elif file and screenshot:
        display(Image(filename=file.replace('.html', '.png')))
    else:
        display(HTML(html))


# convenience method, deprecated, use create_or_update_network() and draw_network() instead
def draw(graph: Graph,
         query: str,
         height: str = "300px",
         title: str = None,
         file: str = None,
         link_only=False,
         do_display=True,
         seed=None,
         auto_rel_label=False,
         **kwargs):
    # deprecated do_display
    if do_display == False:
        link_only = True
    net = create_or_update_network(graph, query, height=height, seed=seed, auto_rel_label=auto_rel_label, **kwargs)
    return draw_network(net, file=file, link_only=link_only, title=title)


def create_timeseries(graph: Graph,
                      query: str,
                      file_id: str,
                      title: str = None,
                      caption: str = None,
                      screenshot = False,
                      seed: int = 5,
                      min_edge_value: int = None,
                      url: str = None,
                      file_prefix: str = "",
                      show_nav_bar: bool = True,
                      show_slider: bool = True,
                      show_physics_toggle: bool = True,
                      start_year=1974,
                      end_year=2023,
                      num_ranges=5):
    for i in range(num_ranges):
        decade_start = start_year + (i * 10)
        decade_end = decade_start + 9
        if decade_end > end_year:
            decade_end = end_year
        net = create_or_update_network(graph, query, height="600", seed=seed,
                                       year_start=decade_start, year_end=decade_end)
        file = f"{file_id}-{decade_start}-{decade_end}.html"
        prev_url = next_url = graph_url = None
        if url is not None:
            graph_url = f"{url}/{file}"
            prev_url = f"{file_id}-{decade_start - 10}-{decade_start - 1}.html" if i > 0 else None
            next_url = f"{file_id}-{decade_end + 1}-{decade_end + 10}.html" if i < (num_ranges - 1) else None
        draw_network(net, title=f"{title}, {decade_start} - {decade_end}", caption=caption,
                     prev_url=prev_url, next_url=next_url, screenshot=screenshot, link_only=not screenshot,
                     file=f"{file_prefix}{file}", url=graph_url, min_edge_value=min_edge_value, show_nav_bar=show_nav_bar,
                     show_slider=show_slider, show_physics_toggle=show_physics_toggle)

def cleanup(graph: Graph):
    # remove styling properties from nodes and relationships
    graph.run("""
        MATCH (n) WHERE any(key IN keys(n) WHERE key STARTS WITH 'vis_')
        WITH n, [key IN keys(n) WHERE key STARTS WITH 'vis_'] AS keys
        CALL apoc.create.removeProperties(n, keys) YIELD node RETURN node;
    """)
    graph.run("""
        MATCH ()-[r]-() WHERE any(key IN keys(r) WHERE key STARTS WITH 'vis_')
        WITH r, [key IN keys(r) WHERE key STARTS WITH 'vis_'] AS keys
        CALL apoc.create.removeRelProperties(r, keys) YIELD rel RETURN rel;
    """)

