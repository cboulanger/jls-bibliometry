# code adapted from https://github.com/nicolewhite/neo4j-jupyter/blob/master/scripts/vis.py

from IPython.display import IFrame, display, HTML
import json
import uuid

def vis_network(nodes, edges, physics=False, node_size=25, font_size=14):
    html = """
    <html>
    <head>
      <script type="text/javascript" src="https://unpkg.com/vis-network/standalone/umd/vis-network.min.js"></script>
    </head>
    <body>

    <div id="{id}"></div>

    <script type="text/javascript">
      const nodes = {nodes};
      const edges = {edges};

      const container = document.getElementById("{id}");
      const data = {{ nodes, edges }};

      const options = {{
          nodes: {{
              shape: 'dot',
              size: {node_size},
              font: {{
                  size: {font_size}
              }}
          }},
          edges: {{
              font: {{
                  size: 14,
                  align: 'middle'
              }},
              color: 'gray',
              arrows: {{
                  to: {{enabled: true, scaleFactor: 0.5}}
              }},
              smooth: {{enabled: false}}
          }},
          physics: {{
              enabled: {physics}
          }}
      }};

      const network = new vis.Network(container, data, options);
      index = nodes.reduce( (a,v) => {{a[v.id] = v; return a}}, nodes)
      network.on("doubleClick", evt => {{
        node = index[evt.nodes[0]]
        if (node.url) {{
            window.open(node.url)
        }}
      }})
    </script>
    </body>
    </html>
    """

    unique_id = str(uuid.uuid4())
    html = html.format(id=unique_id,
                       nodes=json.dumps(nodes),
                       edges=json.dumps(edges),
                       physics=json.dumps(physics),
                       node_size=node_size,
                       font_size=font_size)
    return display(HTML(html))

    # filename = f"figure/graph-{unique_id}.html"
    # file = open(filename, "w")
    # file.write(html)
    # file.close()
    #
    # return IFrame(filename, width="100%", height="400")


def draw(graph, query, options, physics=False, db=None):

    if db is not None:
        query = f"use `{db}` {query}"

    data = graph.run(query).data()

    nodes = []
    edges = []

    def get_vis_info(node, id):
        node_label = list(node.labels)[0]
        prop_key = options.get(node_label)
        if prop_key is dict:
            vis_label = node[prop_key['label'] if 'label' in prop_key else 'label']
            vis_title = node[prop_key['title'] if 'title' in prop_key else 'title']
            vis_value = node[prop_key['value'] if 'value' in prop_key else 'value']
        else:
            vis_label = vis_title = node[prop_key]
            vis_value = 1

        return {"id": id,
                "label": vis_label,
                "group": node_label,
                "title": vis_title,
                "value": vis_value,
                "url":   node['url']}

    for row in data:
        source_node = row['source_node']
        source_id = source_node.identity
        rel = row['rel']
        target_node = row['target_node']
        target_id = target_node.identity

        source_info = get_vis_info(source_node, source_id)

        if source_info not in nodes:
            nodes.append(source_info)

        if rel is not None:
            target_info = get_vis_info(target_node, target_id)

            if target_info not in nodes:
                nodes.append(target_info)

            rel_type = type(rel).__name__
            if rel_type in options:
                label = str(rel[options.get(rel_type)])
            else:
                label = rel_type

            edges.append({"from": source_info["id"],
                          "to": target_info["id"],
                          "value": rel['value'],
                          "label": label})

    font_size = options.get('font_size') or 14
    node_size = options.get('node_size') or 20
    return vis_network(nodes, edges, physics=physics, font_size=font_size, node_size=node_size)

def table(graph, query, db=None):
    if db is not None:
        query = f"use `{db}` {query}"
    return graph.run(query).to_data_frame()