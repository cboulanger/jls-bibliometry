from py2neo import Node, Relationship
from utils import get_graph
from tqdm import tqdm
import pandas as pd
import argparse
import math

# Parsing CLI arguments
parser = argparse.ArgumentParser(description='Import CSV to Neo4j')
parser.add_argument('--row-num', type=int, help='The row number to start from')
args = parser.parse_args()

# Set up a link to the Neo4j database
graph = get_graph("jls-journal-network")

# Delete all nodes and relationships in the graph if not resuming
if args.row_num is None:
    graph.delete_all()

# Create unique constraints
graph.run("CREATE CONSTRAINT unique_work_id IF NOT EXISTS ON (w:Work) ASSERT w.id IS UNIQUE")
graph.run("CREATE CONSTRAINT unique_venue_name IF NOT EXISTS ON (v:Venue) ASSERT v.name IS UNIQUE")
graph.run("CREATE CONSTRAINT unique_author_display_name IF NOT EXISTS ON (a:Author) ASSERT a.display_name IS UNIQUE")

# Import CSV
df = pd.read_csv('data/wos-jls-journal-network.csv', low_memory=False)

# Check if a row number is given, if not start from the beginning
start_row = args.row_num if args.row_num else 0

# Use tqdm to display a progress bar
for index, row in tqdm(df.iterrows(), total=df.shape[0]):
    # Skip rows until the starting row
    if index < start_row:
        continue

    # Create nodes
    work = Node("Work", id=row['item_id'], year=row['pubyear'], title=row['item_title'])
    work.__primarylabel__ = "Work"
    work.__primarykey__ = "id"

    if not pd.isnull(row['source_title']):
        venue = Node("Venue", name=row['source_title'])
        venue.__primarylabel__ = "Venue"
        venue.__primarykey__ = "name"

        # Create relationships
        work_venue = Relationship(work, "PUBLISHED_IN", venue)
        graph.merge(work_venue)

    if not pd.isnull(row['first_author']):
        author = Node("Author", display_name=row['first_author'])
        author.__primarylabel__ = "Author"
        author.__primarykey__ = "display_name"

        # Create relationships
        author_work = Relationship(author, "CREATOR_OF", work)
        graph.merge(author_work)

    # Check if 'item_id_cited' exists and if so, create the 'CITES' relationship
    if not pd.isnull(row['item_id_cited']):
        cited_work = Node("Work", id=row['item_id_cited'])
        cited_work.__primarylabel__ = "Work"
        cited_work.__primarykey__ = "id"

        work_cites = Relationship(work, "CITES", cited_work)
        graph.merge(work_cites, "Work", "id")

    # Write to Neo4j database
    graph.merge(work, "Work", "id")
