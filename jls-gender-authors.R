#devtools::install_github("kalimu/genderizeR")
library(neo4r)
library(dplyr)
library(tidyr)
library(ggplot2)
library(genderizeR)
library(stringr)

# parse a .env file including variable expansion
parse_dotenv <- function(filepath=".env") {
  lines <- readLines(filepath, warn = FALSE)
  env_vars <- list()
  for (line in lines) {
    if (grepl("^#", line) || grepl("^$", line)) { next }
    kv <- strsplit(line, "=")[[1]]
    key <- kv[1]
    value <- kv[2]
    value <- sub("^['\"]", "", value)
    value <- sub("['\"]$", "", value)
    for (var_name in names(env_vars)) {
      value <- gsub(paste0("\\$", var_name), env_vars[[var_name]], value)
      value <- gsub(paste0("\\$\\{", var_name, "\\}"), env_vars[[var_name]], value)
    }
    env_vars[[key]] <- value
  }
  return(env_vars)
}

# not currently used
getNeo4jConnection <- function(config){
  neo4j_api$new(
    #url = paste0('http://', config$NEO4J_HOST, ':', config$NEO4J_HTTP_PORT),
    url = 'http://localhost:7474',
    user = config$NEO4J_USERNAME,
    password = config$NEO4J_PASSWORD
  )
}

get_author_year <- function(filename) {
  read.csv(filename, encoding = "UTF-8") |>
    filter(!is.na(author)) |>
    filter(author != "") |>
    separate_rows(author, sep = ";") |>
    mutate(author = str_to_lower(str_trim(author))) |>
    separate(author, into = c("first_name", "last_name"), sep = "(?<= )(?=[^ ]+$)", remove = TRUE) |>
    mutate(across(c(first_name, last_name), str_trim))
}

get_given_names_db <- function(author_year, api_key) {
  row_names <- c('count','name','gender','probability','country_id')

  if (file.exists("data/jls-names-gender.Rdata")) {
    load("data/jls-names-gender.Rdata")
  }

  if (exists("given_names_db")) {
    missing_names <- author_year |>
      filter(!first_name %in% given_names_db$name &
               !str_detect(first_name, "^\\s*([a-zA-Z]\\.\\s*)+$")) |>
      pull(first_name)
  } else {
    missing_names <- author_year$first_name
  }

  if (!exists("given_names_db") || length(missing_names) > 0) {
    missing_given_names_db <- genderizeR::findGivenNames(missing_names, apikey = api_key)
    colnames(missing_given_names_db) <- row_names # fix wrong column names
    if (exists("given_names_db")) {
      given_names_db <- rbind(given_names_db, missing_given_names_db)
    } else {
      given_names_db <- missing_given_names_db
    }
    save(given_names_db, file = "data/jls-names-gender.Rdata")
  }
  given_names_db
}

get_author_year_gender <- function(author_year, given_names_db) {
  first_names_gender <- author_year |>
    filter(!is.na(first_name)) |>
    distinct(first_name) |>
    pull(first_name) |>
    genderizeR::genderize(genderDB = given_names_db,)

  author_year |>
    merge(first_names_gender, by.x="first_name", by.y="givenName") |>
    select(last_name, first_name, year, gender) |>
    arrange(last_name, first_name, year) |>
    unique()
}

plotAuthorsGenderTimeseries <- function(year_gender, filename, title, year_steps = 5) {
  gender_by_year <- year_gender %>%
    group_by(year) %>% 
    count(gender) %>% 
    pivot_wider(names_from = gender, values_from = n, values_fill=0)
  gender_by_year$sum <- rowSums(gender_by_year[2:3])
  max_num_articles <- max(gender_by_year$sum)
  gender_by_year$female_percent <- as.numeric(gender_by_year$female/(gender_by_year$male+gender_by_year$female) * max_num_articles)

  breaks_years <- seq(min(gender_by_year$year), max(gender_by_year$year))
  breaks_years <- breaks_years[breaks_years %% year_steps == 0]

  p <- gender_by_year[, 1:3] %>% pivot_longer(-year) %>% 
    ggplot(aes(x=year,y=value,fill=name)) +
    ggtitle(title) +
    geom_bar(stat = 'identity') +
    geom_line(
      data = gender_by_year[,-2:-4], 
      mapping = aes(x=year, y=female_percent, group=1),
      size=1, color="red", inherit.aes = FALSE
    ) +
    geom_smooth(
      data = gender_by_year[,-2:-4], 
      mapping = aes(x=year, y=female_percent, group=1),
      size=1, color="orange", inherit.aes = FALSE,
      method = "lm",
    ) +
    scale_y_continuous(
      sec.axis = sec_axis(
        trans = ~. / (max_num_articles), 
        name = "Percentage of female authors", 
        labels = function(b) { paste0(round(b * 100, 0), "%")}
      ) 
    ) +
    scale_x_continuous(breaks = breaks_years) +
    theme(axis.text.x=element_text(angle=90,hjust=1,vjust=0.5), 
          axis.text.y.right = element_text(color = "red")) +
    labs(x="Year", y="Number of articles", fill='Gender')
  ggsave(filename, dpi=600, width = 10)
  p
}

config <- parse_dotenv()
given_names_db <- get_given_names_db(author_year, config$GENDERIZER_API_KEY)

# data was downloaded from constellate.org

jls <- get_author_year("data/jls-author-year-constellate.csv") |>
  get_author_year_gender(given_names_db = given_names_db)
plotAuthorsGenderTimeseries(jls, "docs/article-fig-06.png",
                              "Journal of Law and Society - Gender of article authors (Source: constellate.org")

jls2 <- get_author_year("data/jls-author-year-openalex.csv") |>
  get_author_year_gender(given_names_db = given_names_db)
plotAuthorsGenderTimeseries(jls, "docs/article-fig-06.png",
                            "Journal of Law and Society - Gender of article authors (Source: openalex.org)")

sls <- get_author_year("data/sls-author-year.csv") |>
  get_author_year_gender(given_names_db = given_names_db)
plotAuthorsGenderTimeseries(sls, "docs/sls-author-gender.png",
                              "Social & Legal Studies - Gender of article authors")

ijlc <- get_author_year("data/ijlc-author-year.csv") |>
  get_author_year_gender(given_names_db = given_names_db)
plotAuthorsGenderTimeseries(sls, "docs/ijlc-author-gender.png",
                            "International Journal of Law and Context - Gender of article authors")
