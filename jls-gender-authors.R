#devtools::install_github("kalimu/genderizeR")
library(neo4r)
library(dplyr)
library(tidyr)
library(ggplot2)
library(genderizeR)
library(stringr)

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

getNeo4jConnection <- function(){
  config <- parse_dotenv()
  neo4j_api$new(
    #url = paste0('http://', config$NEO4J_HOST, ':', config$NEO4J_HTTP_PORT),
    url = 'http://localhost:7474',
    user = config$NEO4J_USERNAME,
    password = config$NEO4J_PASSWORD
  )
}



plotAuthorsGenderTimeseries <- function(year_gender) {
  gender_by_year <- year_gender %>%
    group_by(year) %>% 
    count(gender) %>% 
    pivot_wider(names_from = gender, values_from = n, values_fill=0)
  gender_by_year$sum <- rowSums(gender_by_year[2:3])
  max_num_articles <- max(gender_by_year$sum)
  gender_by_year$female_percent <- as.numeric(gender_by_year$female/(gender_by_year$male+gender_by_year$female) * max_num_articles)

  p <- gender_by_year[, 1:3] %>% pivot_longer(-year) %>% 
    ggplot(aes(x=year,y=value,fill=name)) +
    ggtitle("Articles published with gender distribution") + 
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
    theme(axis.text.x=element_text(angle=90,hjust=1,vjust=0.5), 
          axis.text.y.right = element_text(color = "red")) +
    labs(x="Year", y="Number of articles", fill='Gender')
  ggsave("docs/article-fig-06.png", dpi=600, width = 10)
  p
}

if (!exists("author_year")) {
  # transform in a format that we can work with, clean up garbage years and duplicates
  author_year <- read.csv("data/jls-author-year.csv", encoding = "UTF-8") |>
    separate_rows(author, sep = ";") |>
    mutate(author = str_to_lower(str_trim(author))) |>
    separate(author, into = c("first_name", "last_name"), sep = "(?<= )(?=[^ ]+$)", remove = TRUE) |>
    mutate(across(c(first_name, last_name), str_trim))
}
if (!exists("given_names_db")) {
  row_names <- c('count','name','gender','probability','country_id')

  if (file.exists("data/jls-names-gender.Rdata")) {
    load("data/jls-names-gender.Rdata")
  } else {
    given_names_db <- data.frame(matrix(ncol = length(row_names), nrow = 0))
    colnames(given_names_db) <- row_names
  }

  missing_names <- author_year |>
    filter(!first_name %in% given_names_db$name &
             !str_detect(first_name, "^\\s*([a-zA-Z]\\.\\s*)+$")) |>
    pull(first_name)

  if (length(missing_names) > 0) {
    missing_given_names_db <- genderizeR::findGivenNames(missing_names)
    colnames(missing_given_names_db) <- row_names # fix wrong column names
    given_names_db <- rbind(given_names_db, missing_given_names_db)
  }
  save(given_names_db, file = "data/jls-names-gender.Rdata")
}

if (!exists("first_names_gender")) {
  first_names_gender <- author_year |>
    filter(!is.na(first_name)) |>
    distinct(first_name) |>
    pull(first_name) |>
    genderizeR::genderize(genderDB = given_names_db,)
}

author_year |>
  merge(first_names_gender, by.x="first_name", by.y="givenName") |>
  plotAuthorsGenderTimeseries()


