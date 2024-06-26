# The Journal of Law and Society in context - a bibliometric analysis

[![DOI](https://zenodo.org/badge/645641151.svg)](https://zenodo.org/doi/10.5281/zenodo.10807724)

This repository contains code and generated figures for the following publications:

- BOULANGER, C., CREUTZFELDT, N., & HENDRY, J. The Journal of Law and Society in context: a bibliometric analysis. Journal of Law and Society. 2024;1–25. https://doi.org/10.1111/jols.12465   (Open Access)
- BOULANGER, C., CREUTZFELDT, N., & HENDRY, J. The Journal of Law and Society in Context: Our Bibliometric Methodology’ (2023) J. of Law and Society Blog, at https://journaloflawandsociety.co.uk/blog/the-journal-of-law-and-society-in-context-descriptive-analysis-of-metadata/ . Archived at https://zenodo.org/doi/10.5281/zenodo.10807615 

The graphs and figures are also published in high resolution at https://cboulanger.github.io/jls-bibliometry .

The data for the  queries in the notebooks were obtained by querying the Web of Science and OpenAlex databases as well as
by automatic citation extraction from the full texts of the Journal of Law and Society. The data of citation extraction is
partially erroneous and incomplete due to the current deficiencies automated extraction. However, these errors
should be evenly distributed. Therefore, results that do not concern individual values but express larger trends,
are expected be generally reliable.

The scripts in this repository were written with coding assistance from https://chat.openai.com using GPT-4.

## Requirements & Configuration

- You'll need a Neo4J server >= v4.4
- For the Jupyter Notebook, you neet install the required python modules (either through conda or pip):
`py2neo python-dotenv pandas pyvis nltk mplcursors tqdm langdetect langcodes language_data matplotlib`
- In order to generate screenshots from the interactive HTML visualizations, you need to install the Playwright library:
  https://playwright.dev/python/docs/intro
- Rename `.env.dist` and adapt the values to fit your local environment
- For the corpus analyses, run the following code once:
  ```
  import nltk
  nltk.download('stopwords')
  nltk.download('punkt')
  ```

## Data

- Data from OpenAlex as well as the data obtained from machine extraction can be found here: 
  https://doi.org/10.5281/zenodo.8389925 as a data dump which can be imported into the Neo4J Graph database v4.4.
- The data obtained from the Web of Science cannot be shared due to legal reasons.
- The same applies to the fulltexts of the JLS. If you do not have a licence for https://onlinelibrary.wiley.com/journal/14676478
  you can use the service https://constellate.org and apply for the temporal download of the full text stored at 
  https://www.jstor.org/journal/jlawsociety and https://www.jstor.org/journal/britjlawsoci for research purposes.
