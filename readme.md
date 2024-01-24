# The Journal of Law and Society - Bibliometric and Digital Humanities Perspectives

This repository contains code and generated figures for the paper by Boulanger/Creutzfeldt/Hendry,
"The Journal of Law and Society - Bibliometric and Digital Humanities Perspectives" (working title).

Please visit https://cboulanger.github.io/jls-bibliometry/ for the figures.

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
- The same applies to the fulltexts of the JLS, which you will have to download and convert to text
  files yourself, if you want to run the corpus analyses. 