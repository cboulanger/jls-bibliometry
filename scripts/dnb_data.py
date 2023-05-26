# code written with the help of GPT-4

import requests
from bs4 import BeautifulSoup
import csv
import urllib.parse
from lxml import etree
import os
import matplotlib.pyplot as plt
from collections import defaultdict
import re
import numpy as np
import seaborn as sns

def generate_query_string(person, startRecord):
    base_url = "https://services.dnb.de/sru/dnb"
    query = f'per="{person}"'
    encoded_query = urllib.parse.quote(query)
    query_url = f"{base_url}?operation=searchRetrieve&version=1.1&query={encoded_query}&recordSchema=oai_dc&maximumRecords=100&startRecord={startRecord}"
    return query_url

def fetch_data(person, start_record):
    url = generate_query_string(person, start_record)
    response = requests.get(url)
    xml_data = response.content

    soup = BeautifulSoup(xml_data, 'lxml-xml')
    diagnostics = soup.find('diagnostics')
    if diagnostics:
        diag_message = diagnostics.find('message').text
        diag_details = diagnostics.find('details').text
        print(f"Error: {diag_message} - {diag_details}")
        return None
    return xml_data

def parse_records(xml_data):
    ns = {
        "oai_dc": "http://www.openarchives.org/OAI/2.0/oai_dc/",
        "dc": "http://purl.org/dc/elements/1.1/",
        "srw": "http://www.loc.gov/zing/srw/"
    }

    root = etree.fromstring(xml_data)
    records = root.xpath('//srw:record', namespaces=ns)
    num_records = int(root.xpath('//srw:numberOfRecords', namespaces=ns)[0].text)

    results = []

    for record in records:
        title_elements = record.xpath('.//dc:title', namespaces=ns)
        if not title_elements:
            continue
        title = title_elements[0].text

        authors = record.xpath('.//dc:creator', namespaces=ns)
        author_list = []
        for author in authors:
            author_list.append(author.text)
        authors_str = '; '.join(author_list)

        publication_year_elements = record.xpath('.//dc:date', namespaces=ns)
        if publication_year_elements:
            publication_year = publication_year_elements[0].text
        else:
            publication_year = ""

        results.append([title, authors_str, publication_year])

    return results, num_records


def query_to_csv(person, file_path):
    start_record = 1
    num_records = 0
    retrieved_records = 0

    with open(file_path, 'w', newline='', encoding='utf-8') as csvfile:
        csvwriter = csv.writer(csvfile)
        csvwriter.writerow(['Title', 'Author', 'Publication Year'])

    while True:
        xml_data = fetch_data(person, start_record)
        if xml_data is not None:
            results, num_records = parse_records(xml_data)
            if not results:
                break

            with open(file_path, 'a', newline='', encoding='utf-8') as csvfile:
                csvwriter = csv.writer(csvfile)
                for row in results:
                    csvwriter.writerow(row)
            retrieved_records += len(results)
            start_record += len(results)

            if retrieved_records >= num_records:
                break

def load_data_from_csv(file_path):
    data = []
    with open(file_path, 'r', newline='', encoding='utf-8') as csvfile:
        csvreader = csv.reader(csvfile)
        next(csvreader)  # Skip the header row
        for row in csvreader:
            data.append(row)
    return data

def compare_persons(persons, year_start, year_end = float('inf')):
    all_data = {}
    for person in persons:
        last_name = person.split()[0]
        file_path = f"data/{last_name}.csv"
        if not os.path.exists(file_path):
            query_to_csv(person, file_path)
        data = load_data_from_csv(file_path)
        all_data[person] = data

    # Count publications by year for each person
    yearly_counts = defaultdict(lambda: defaultdict(int))
    for person, data in all_data.items():
        for row in data:
            year = extract_first_year(row[2])
            if year and year_start <= int(year) <= year_end:
                yearly_counts[person][year] += 1

    return yearly_counts

def extract_first_year(year_str):
    years = re.findall(r'\d{4}', year_str)
    if years:
        return years[0]
    return None

def plot_comparison(yearly_counts):
    plt.figure(figsize=(15, 8))
    min_year = float('inf')
    max_year = float('-inf')

    markers = ['o', 's', '^', 'v', 'P', 'X', 'D', 'H']
    linestyles = ['-', '--', '-.', ':', (0, (3, 5, 1, 5)), (0, (3, 1, 1, 1)), (0, (5, 5)), (0, (5, 1))]

    for i, (person, counts) in enumerate(yearly_counts.items()):
        years = sorted(filter(None, map(int, counts.keys())))
        publications = [counts[str(year)] for year in years]
        plt.scatter(years, publications, label=person, marker=markers[i])

        # Plot the median curve using local regression
        sns.regplot(x=years, y=publications, lowess=True, scatter=False, line_kws={'linestyle': linestyles[i], 'alpha': 0.5})

        min_year = min(min_year, min(years))
        max_year = max(max_year, max(years))

    major_ticks = np.arange(min_year, max_year + 1, 5)
    minor_ticks = np.arange(min_year, max_year + 1, 1)

    plt.gca().xaxis.set_major_locator(plt.FixedLocator(major_ticks))
    plt.gca().xaxis.set_minor_locator(plt.FixedLocator(minor_ticks))
    plt.gca().tick_params(axis='x', rotation=45)

    plt.xlabel('Year')
    plt.ylabel('Number of Publications')
    plt.title('Number of Publications per Year')
    plt.legend()
    plt.show()







