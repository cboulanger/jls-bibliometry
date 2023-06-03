# NOTE: This code is published as documentation on how the author-gender timeseries was produced.
# It is NOT working as-is.

#devtools::install_github("kalimu/genderizeR")
library(neo4r)
library(dplyr)
library(tidyr)
library(ggplot2)
library(genderizeR)

getNeo4jConnection <- function(){
  neo4j_api$new(
    url = "http://localhost:7474",
    user = "neo4j",
    password = "neo4j_local"
  )
}

main <- function() {
  neo4j_query <- '
  match (a:Author)-[:CREATOR_OF]->(w:Work)-[:PUBLISHED_IN]->(v:Venue)
  where v.id = "j law soc"
  return a.family, a.given, w.year
  '
  neo4j_result <- call_neo4j(neo4j_query, getNeo4jConnection(), type="row")
  
  # transform in a format that we can work with, clean up garbage years
  articles <- data.frame(t(neo4j_result)) |>
    rename(last_name=value, first_name=value.1, year=value.2) |>
    filter(year >= 1974)
  
  authors_full_name <- articles |>
    select(last_name, first_name) |> 
    unique() |> 
    arrange(last_name) |>
    filter(stringr::str_length(first_name)>2 & !grepl("\\.",first_name))

  given_names <- authors_full_name |>
    select(first_name) |>
    unique() |>
    arrange(first_name)
  
  given_names_db <- given_names |>
    genderizeR::findGivenNames() |> # this sends requests to external API with rate limits
    unique() # for some reason, there are duplicates in the result
  
  save(given_names_db, file="jls-names-gender.Rdata")
  
  first_names_gender <- genderize(authors_full_name, genderDB = given_names_db,)
  
}



##
## (Re-)generate file containing gender analysis of first names for batch
## processing where gender info is missing in reconciled data
##
# https://github.com/kalimu/genderizeR

createFirstNameGenderTable <- function() {
  first_names <- unique(select(authors, first_name))
  first_names_sorted <- sort(first_names$first_name)
  given_names <- findGivenNames(first_names_sorted)
  first_names_gender <- genderize(first_names_sorted, genderDB = given_names)
  save(first_names_gender, file="first-names-gender.Rdata")
  first_names_gender
}

## 
## Add gender info to author data
##
addGenderInfo <- function(authors) {
  for (row in seq_len(nrow(authors))) {
    author <- authors[row, "full_name"]
    auth_rec_row <- which(auth_rec[,1] == author)
    # gender 
    gender <- (auth_rec[auth_rec_row, "Geschlecht"])
    if (isTRUE(!is.null(gender) && !is.na(gender))) {
      if (gender == "Männlich") {
        gender <- "male"
      } else if (gender == "Weiblich") {
        gender <- "female"
      } else {
        gender <- NA
      }
    } else {
      gender <- NA
    }
    
    if (isTRUE(is.na(gender))) {
      first_names_gender_row <- which(first_names_gender[,"text"] == authors[row, "first_name"])
      if (!is.null(first_names_gender_row)) {
        gender <- (first_names_gender[first_names_gender_row, "gender"])
        auth_rec[auth_rec_row, "Geschlecht"] <- if (isTRUE(gender == "male")) "Männlich" else if (isTRUE(gender == "female")) "Weiblich" else ""
      }
    }
    authors[row, "gender"] <- gender
    #print(paste(author, gender, sep=": "))
  }
  authors
}

plotAuthorsGenderTimeseries <- function(articles) {
  gender_by_year <- articles %>%
    mutate(year = format(date, "%Y")) %>% 
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
    labs(x="Year", y="Articles", fill='Gender')
  p
}