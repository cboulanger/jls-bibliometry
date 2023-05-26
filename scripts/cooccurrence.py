# this code has been almost entirely written by GPT-4

import nltk
import re
from nltk.corpus import stopwords
from nltk.stem import SnowballStemmer
from collections import Counter
from tqdm.notebook import tqdm
from langcodes import Language
import pandas as pd
import seaborn as sns
import matplotlib.pyplot as plt
from typing import List

import langdetect

def translate_lang_code(lang_code):
    return Language.make(language=lang_code).display_name().lower()

# define a function to detect the language of a text string
def detect_language(text):
    try:
        return translate_lang_code(langdetect.detect(text))
    except:
        return None

def get_stopwords(language, default_language='english'):
    try:
        stop_words = set(stopwords.words(language))
    except:
        stop_words = set(stopwords.words(default_language))
    return stop_words

def get_stemmer(language, default_language='english'):
    try:
        return SnowballStemmer(language)
    except:
        return SnowballStemmer(default_language)


def filter_df(df, regex):
    # remove documents that do not contain the search term
    mask = df['text'].apply(lambda text: re.search(regex, text) is not None)
    return df.loc[mask]

def find_cooccurring_words(df, regex, default_language='english', window_size=30, ignore=None):
    # tokenize the corpus into sentences
    sentences = [nltk.sent_tokenize(text) for text in df['text']]

    # iterate over the sentences and tokenize each sentence into words, remove stop words, and create a bag-of-words representation
    bag_of_words = []

    for doc in tqdm(sentences, desc='Tokenizing and stemming...'):
        doc_bow = []
        for sentence in doc:
            words = nltk.word_tokenize(sentence)
            language = detect_language(sentence) or default_language
            stemmer = get_stemmer(language, default_language=default_language)
            stop_words = get_stopwords(language, default_language=default_language)
            words = [
                (w, stemmer.stem(w)) for w in words \
                    if w.isalpha() and w.lower() not in stop_words and (ignore is None or not re.search(ignore,w))
            ]
            doc_bow.extend(words)
        bag_of_words.append(doc_bow)

    # iterate over the bag-of-words of each document and count the frequency of each word that co-occurs with the search term
    cooccurring_words = []
    global_cooccurring_words = Counter()
    for doc_bow in tqdm(bag_of_words, desc='Analyzing co-occurring words...'):
        doc_cooccurring_words = Counter()
        for i, word_tuple in enumerate(doc_bow):
            word, stemmed_word = word_tuple
            if re.search(regex, word):
                for j in range(max(i - window_size, 0), min(i + window_size + 1, len(doc_bow))):
                    if j != i and not re.search(regex, doc_bow[j][0]):
                        doc_cooccurring_words[doc_bow[j][1]] += 1
                        global_cooccurring_words[doc_bow[j][1]] += 1
        cooccurring_words.append(doc_cooccurring_words)

    return cooccurring_words, global_cooccurring_words

def filter_counters(counters: List[Counter], global_counter: Counter, max_global: int = 100, max_doc: int = 20) -> List[Counter]:
    filtered_counters = []

    # Find the most common words in global_cooccurring_words
    global_common_words = set(word for word, _ in global_counter.most_common(max_global))

    # Iterate over cooccurring_words and filter each Counter based on the intersection
    for counter in counters:
        local_common_words = set(word for word, _ in counter.most_common(max_doc))
        intersecting_words = local_common_words & global_common_words
        filtered_counter = Counter({word: counter[word] for word in intersecting_words})
        filtered_counters.append(filtered_counter)

    return filtered_counters

def create_heatmap(df, counters, max_words=20):
    labels = [f"{author} ({year})" for author, year in zip(df['author'], df['year'])]

    # Find the most common words across all counters
    total_counts = Counter()
    for counter in counters:
        total_counts += counter
    common_words = [word for word, _ in total_counts.most_common(max_words)]

    # Create a matrix of word frequencies for each counter
    data = []
    for counter in counters:
        row = [counter[word] for word in common_words]
        data.append(row)

    # Create a DataFrame and visualize the heatmap
    df = pd.DataFrame(data, columns=common_words, index=labels)
    plt.figure(figsize=(12, 6))
    sns.heatmap(df, annot=True, cmap='coolwarm', fmt='d')
    plt.yticks(rotation=0)
    plt.show()
