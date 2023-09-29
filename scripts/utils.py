import pandas as pd
from tqdm.notebook import tqdm
import json
import requests
import re
import csv
from py2neo import Graph
import os
import pickle
from dotenv import load_dotenv
from IPython.display import display, HTML
import time

load_dotenv()

def get_graph(name):
    return Graph(os.getenv('NEO4J_URL'), name=name)

def get_corpus_dir(name):
    return os.path.join(os.getenv('CORPUS_BASE_DIR'), name)

class DOICache:
    def __init__(self, file_path):
        self.file_path = file_path
        self.cache = self.load_cache()

    def load_cache(self):
        cache = {}
        with open(self.file_path, newline='') as csvfile:
            reader = csv.DictReader(csvfile)
            for row in reader:
                cache[row['DOI']] = int(row['year'])
        return cache

    def get_year(self, DOI):
        return self.cache.get(DOI)

    def get_dois(self):
        return self.cache.keys()


def extract_year(metadata):
    if 'published-print' in metadata:
        pub_info = metadata['published-print']
    elif 'issued' in metadata:
        pub_info = metadata['issued']
    else:
        return None

    if 'date-parts' in pub_info:
        year = pub_info['date-parts'][0][0]
    elif 'raw' in pub_info:
        year = pub_info['raw'][:4]
    else:
        return None

    return int(year)

def extract_author(metadata):
    author = metadata.get('author', [])
    return author[0].get('family','') if len(author) > 0 else ''

def get_metadata(doi, doi_cache: DOICache=None):
    cache_file = f'cache/{doi}.json'
    metadata = None
    if os.path.exists(cache_file):
        with open(cache_file, 'r') as f:
            metadata = json.load(f)
    if metadata is None or len(metadata) == 0:
        # in case doi is incomplete, find the complete version in the doi cache
        if doi_cache:
            for d in doi_cache.get_dois():
                if d[:len(doi)] == doi:
                    doi = d
                    break
        email = os.environ.get("CROSSREF_API_EMAIL")

        for attempt in range(3):  # Retry mechanism
            url = f'https://api.crossref.org/works/{doi}?mailto={email}'
            try:
                response = requests.get(url, timeout=3)  # Timeout of 3 seconds
                metadata = response.json()['message']
                break  # Break out of the loop if the request is successful
            except requests.exceptions.Timeout:
                if attempt == 2:  # If this was the third attempt
                    print(f"Timeout error: could not retrieve data from {url}")
                    break
                else:
                    print(f"Attempt {attempt + 1} failed, retrying...")
                    time.sleep(1)
            except json.JSONDecodeError:
                if doi.endswith(".x"):
                    break
                # add ".x" and try again
                doi += ".x"

    if metadata is None:
        print(f"CrossRef error: could not load metadata for {doi}")

    os.makedirs(os.path.dirname(cache_file), exist_ok=True)
    with open(cache_file, 'w') as f:
        json.dump(metadata, f)
    return metadata

def extract_metadata_from_filename(input_string):
    pattern = r'^(?P<author>.*?)\s\((?P<year>\d{4})\)\s(?P<title>.*)\.txt$'
    match = re.match(pattern, input_string)

    if match:
        author = match.group('author')
        year = int(match.group('year'))
        title = match.group('title')
        return author, year, title
    else:
        return None

def truncate(s, x):
    return s[:x] + '...' if len(s) > x else s

def create_corpus(corpus_dir, doi_cache : DOICache=None) -> pd.DataFrame:
    articles = []
    for filename in tqdm(os.listdir(corpus_dir), desc="Analyzing article corpus"):
        file_path = os.path.join(corpus_dir, filename)
        if os.path.isfile(file_path) and filename.endswith('.txt'):
            with open(file_path, 'r', encoding='utf-8') as f:
                text = f.read()
                if filename.startswith('10.'):
                    doi = filename.replace('_', '/', 1).strip('.txt')
                    if doi_cache is not None:
                        year = doi_cache.get_year(doi)
                        if year is None:
                            # try extended doi
                            doi = f"{doi}.x"
                            year = doi_cache.get_year(doi)
                        title = author = None
                    metadata = get_metadata(doi, doi_cache)
                    if metadata is not None:
                        year = extract_year(metadata)
                        title = metadata.get('title',[None])[0]
                        author = extract_author(metadata)
                    else:
                        continue
                    articles.append({
                        'doi': doi,
                        'text': text,
                        'year': year,
                        'title': title,
                        'author': author
                    })
                elif (metadata := extract_metadata_from_filename(filename)) is not None:
                    author, year, title = metadata
                    articles.append({
                        'doi': None,
                        'text': text,
                        'year': year,
                        'title': title,
                        'author': author
                    })
    return pd.DataFrame(articles).sort_values(by='year').astype({'year':'Int64'})

def create_cached_corpus(cache_id:str):
    corpus_dir = os.getenv(f"{cache_id.upper()}_CORPUS_DIR")
    if not os.path.exists(corpus_dir):
        raise RuntimeError(f"Invalid corpus dir '{corpus_dir}'")
    cache_file_path = f'cache/{cache_id}.pkl'
    if not os.path.exists(cache_file_path):
        doi_cache_file = f"data/{cache_id}-doi-to-year.csv"
        doi_cache = DOICache(doi_cache_file) if os.path.exists(doi_cache_file) else None
        articles_df = create_corpus(corpus_dir, doi_cache)
        with open(cache_file_path, mode='wb') as f:
            pickle.dump(articles_df, f)
    else:
        with open(cache_file_path, mode='rb') as f:
            articles_df = pickle.load(f)
    return articles_df

def df_to_html(df, file=None):

    """
    Generate (and optionally save) a Jupyter like html of pandas dataframe
    Adapted from https://github.com/ljmartin/df_to_svg/blob/main/code/write_html.ipynb
    """

    styles = [
        #table properties
        dict(selector=" ",
             props=[("margin","0"),
                    ("font-family",'"Helvetica", "Arial", sans-serif'),
                    ("border-collapse", "collapse"),
                    ("border","none"),
                    #("border", "2px solid #ccf") #border looks bad
                    ]),

        #header color - optional
        #     dict(selector="thead",
        #          props=[("background-color","#cc8484")
        #                ]),

        #background shading
        dict(selector="tbody tr:nth-child(even)",
             props=[("background-color", "#fff")]),
        dict(selector="tbody tr:nth-child(odd)",
             props=[("background-color", "#eee")]),

        #cell spacing
        dict(selector="td",
             props=[("padding", ".5em")]),

        #header cell properties
        dict(selector="th",
             props=[("font-size", "100%"),
                    ("text-align", "center")]),
    ]
    html = (df.style.set_table_styles(styles)).to_html()
    html = f"""
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
</head>
<body>
{html}
</body>
</html>
    """
    if file:
        with open(file, 'w', encoding='utf-8') as b:
            b.write(html)
    return display(HTML(html))
