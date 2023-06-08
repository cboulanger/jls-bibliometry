import pandas as pd
from tqdm.notebook import tqdm
import json
import requests
import os
import re
import csv
from dotenv import load_dotenv
from py2neo import Graph

def get_graph(name):
    load_dotenv()
    return Graph(os.getenv('NEO4J_URL'), name=name)

def get_corpus_dir(name):
    load_dotenv()
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

def get_metadata(doi, doi_cache : DOICache=None):
    cache_file = f'cache/{doi}.json'
    metadata = None
    if os.path.exists(cache_file):
        with open(cache_file, 'r') as f:
            metadata = json.load(f)
    else:
        #if metadata is None:
        # in case doi is incomplete, find the complete version in the doi cache
        if doi_cache:
            for d in doi_cache.get_dois():
                if d[:len(doi)] == doi:
                    doi = d
                    break
        url = f'https://api.crossref.org/works/{doi}'
        print(f"Looking up {doi}...")
        response = requests.get(url)
        try:
            metadata = response.json()['message']
        except json.JSONDecodeError:
            print(f"CrossRef error: could not load metadata for {url}")
            metadata = {}

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