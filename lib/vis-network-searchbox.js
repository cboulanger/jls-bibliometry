// This is unused (and mostly unfunctional) code from vis-network-searchbox.html that might be useful later

function expandNode(nodeId) {

    // Get connected nodes and edges
    const connectedNodeIds = network.getConnectedNodes(nodeId);
    const connectedEdgeIds = network.getConnectedEdges(nodeId);

    // Show connected edges depending on slider value
    if (connectedEdgeIds.length == 0) {
        return
    }

    const edgesToUpdate = connectedEdgeIds.map(edgeId => {
        const edge = edges.get(edgeId);
        edge.hidden = edge.value < Number(edgeValueSlider.value);
        return edge;
    });

    // Show connected nodes depending on whether they have visible edges
    const visibleNodeIds = new Set();
    connectedEdgeIds.forEach(edgeId => {
        const edge = edges.get(edgeId);
        if (!edge.hidden) {
            visibleNodeIds.add(edge.from);
            visibleNodeIds.add(edge.to);
        }
    });
    const nodesToUpdate = connectedNodeIds.map(nodeId => {
        const node = nodes.get(nodeId)
        node.hidden = !visibleNodeIds.has(node.id)
        return node
    })
    nodes.update(nodesToUpdate)
    edges.update(edgesToUpdate);
}

function resolveOverlaps(nodes, minDistance=200, maxDistance=1000, timeout = 5000) {
    let startTime = Date.now();
    let elapsed = 0;
    let changed = true;

    while (changed && elapsed < timeout) {
        changed = false;

        for (let i = 0; i < nodes.length; i++) {
            for (let j = i + 1; j < nodes.length; j++) {
                let node1 = nodes[i];
                let node2 = nodes[j];

                let dx = node2.x - node1.x;
                let dy = node2.y - node1.y;
                let distance = Math.sqrt(dx * dx + dy * dy);

                // Nodes are too close
                if (distance < minDistance) {
                    changed = true;

                    let angle = Math.atan2(dy, dx);
                    let moveDistance = (minDistance - distance) / 2.0;

                    node1.x -= moveDistance * Math.cos(angle);
                    node1.y -= moveDistance * Math.sin(angle);
                    node2.x += moveDistance * Math.cos(angle);
                    node2.y += moveDistance * Math.sin(angle);
                }
                // Nodes are too far
                else if (distance > maxDistance) {
                    changed = true;

                    let angle = Math.atan2(dy, dx);
                    let moveDistance = (distance - maxDistance) / 2.0;

                    node1.x += moveDistance * Math.cos(angle);
                    node1.y += moveDistance * Math.sin(angle);
                    node2.x -= moveDistance * Math.cos(angle);
                    node2.y -= moveDistance * Math.sin(angle);
                }
            }
        }

        // Update the elapsed time
        elapsed = Date.now() - startTime;
    }

    if (elapsed >= timeout) {
        console.warn("Time limit reached before resolving all overlaps and separations");
    }
}

function distributeNodesRadially(centerNodeId, connectedNodes, minDistance = 100) {

    // Fetch the central node
    const centerNode = nodes.get(centerNodeId);

    // Determine the angle step based on the number of nodes
    const angleStep = 2 * Math.PI / connectedNodes.length;

    // Distribute nodes radially
    const nodesToUpdate = connectedNodes.map((node, index) => {
        const angle = index * angleStep;
        return {
            id: node.id,
            x: centerNode.x + minDistance * Math.cos(angle),
            y: centerNode.y + minDistance * Math.sin(angle),
            hidden: false
        };
    });

    nodes.update(nodesToUpdate);

    network.redraw()
}


// not working
function showSubgraph(params) {
    if (params.nodes.length > 0) {
        const nodeId = params.nodes[0];

        // Get connected nodes and edges
        const connectedNodes = network.getConnectedNodes(nodeId);
        const connectedEdges = network.getConnectedEdges(nodeId);

        // Update connected nodes to be visible
        const nodesToUpdate = connectedNodes.map(id => ({ id, hidden: false }));
        nodes.update(nodesToUpdate);

        // Update connected edges to be visible
        const edgesToUpdate = connectedEdges.map(id => ({ id, hidden: false }));
        edges.update(edgesToUpdate);

        // Backup hidden nodes and remove them temporarily
        const hiddenNodes = nodes.get({ filter: node => node.hidden });
        nodes.remove(hiddenNodes.map(node => node.id));

        // Enable physics and let it stabilize the remaining nodes
        network.setOptions({ physics: {
            enabled: true,
            solver: 'repulsion',
            repulsion: {
                nodeDistance: 500,
                centralGravity: 0.1
            }
        } });

        network.once("stabilized", function() {
            // Restore the hidden nodes
            //nodes.add(hiddenNodes);

            // Disable physics
            network.setOptions({ physics: false });
        });
    }
}