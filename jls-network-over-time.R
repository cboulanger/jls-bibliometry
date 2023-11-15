library(network)
library(networkDynamic)
library(tidyverse)
library(ndtv)

# config
top_n_cited <- 20
top_n_citing <- 20
year_start <- 2000
year_end <- 2010
years_per_slice <- 5

cat("Importing data for",as.character(year_start),"-",as.character(year_end),fill=TRUE)
df <- read.csv("data/jls-author-network-owndata.csv", encoding = "UTF-8") |>
  filter(pub_year >= year_start & pub_year <= year_end) |>
  rename(from = citing_author) |>
  rename(to = cited_author) |>
  rename(year = pub_year) |>
  rename(count = citation_count)

# Create a lookup table for journal titles to IDs
names <- unique(c(df$from, df$to))
vertices <- tibble(id = seq_along(names), name = names)

# Convert source and target authors to ids
data <- df |>
  left_join(vertices, by = c("from" = "name")) |>
  select(-from) |>
  rename(from = id) |>
  left_join(vertices, by = c("to" = "name")) |>
  select(-to) |>
  rename(to = id) |>
  select(from, to, year, count) |>
  filter(from != to) # remove self-citations

cat("Found", as.character(nrow(data)), "items.",fill=TRUE)

cat("Determine the", as.character(top_n_cited), "most cited authors in ",
    as.character(years_per_slice), "-year windows",fill=TRUE)

# create sliding time windows
sliding_window <- function(year) {
  seq(year - 2, year + 2)
}
tmp <- data |>
  rowwise() |>
  mutate(window = list(sliding_window(year))) |>
  unnest(window)

# Find the n most-cited items within each 5-year window
top_to_values <- tmp |>
  group_by(window, to) |>
  summarise(n = n(), .groups = 'drop') |>
  arrange(window, desc(n)) |>
  group_by(window) |>
  slice_head(n = top_n_cited) |>
  ungroup()

# Filter original data based on the top_to_values
data <- data |>
  inner_join(top_to_values, by = c("to", "year" = "window")) |>
  select(-n)

cat("Found", as.character(nrow(data)), "items.", fill = TRUE)

cat("Within these, limit to the", as.character(top_n_citing), "most citing authors...", fill = TRUE)

# Find the top 10 most-occurring `from` values for each unique `to` value
top_from_per_to <- data |>
  group_by(to, from) |>
  summarise(n = n(), .groups = 'drop') |>
  arrange(to, desc(n)) |>
  group_by(to) |>
  slice_head(n = top_n_citing) |>
  ungroup()

# Filter the dataframe to include only rows with the top 10 most-occurring `from` values per unique `to` value
data <- data |>
  inner_join(top_from_per_to, by = c("from", "to")) |>
  select(-n)

cat("Found", as.character(nrow(data)), "items.",fill=TRUE)

cat("Create network and activation data...",fill=TRUE)

# filter the complete list of vertices to the ones contained in the edge list and add a new index
vertex_ids <- unique(c(data$from, data$to))
vertices <- vertices |>
  filter(id %in% vertex_ids) |>
  arrange(id) |>
  mutate(new_id = row_number())

# Update the 'from' and 'to' columns in the data to match these new row indices
data <- data |>
  left_join(vertices, by = c("from" = "id")) |>
  select(-from) |>
  rename(from = new_id) |>
  left_join(vertices, by = c("to" = "id")) |>
  select(-to) |>
  rename(to = new_id) |>
  select(from, to, year, count)

# Create the edges data
edges <- data |>
  select(from, to) |>
  unique()

# Create the vertex attributes
vertex_attr <- list(name = vertices$name)

# Create the network
net <- network(matrix(c(edges$from, edges$to), ncol = 2),
               directed = TRUE,
               loops = FALSE,
               vertex.attr = vertex_attr,
               vertices = nrow(vertices))
network.vertex.names(net) <- vertices$name

cat("Computing dynamic network...",fill=TRUE)

# Create edge spells with columns [onset, terminus, tail, head]
edge_spells <- data |>
  mutate(onset = year, terminus = year, tail = from, head = to)  |>
  select(onset, terminus, tail, head) |>
  as.data.frame()

# Create vertex spells with columns [onset, terminus, vertex_id]
# Find the first (min) and last (max) time each vertex is mentioned and add a spell for all years in between
vertex_spells <- edge_spells |>
  pivot_longer(
    cols = c(tail, head),
    names_to = "temp_col",
    values_to = "vertex_id"
  ) |>
  select(onset, terminus, vertex_id) |>
  group_by(vertex_id) |>
  summarise(
    onset = min(onset),
    terminus = max(terminus)
  ) |>
  ungroup() |>
  rowwise() |>
  summarise(
    onset = list(seq(from = onset, to = terminus, by = 1)),
    vertex_id = vertex_id
  ) |>
  unnest(onset) |>
  arrange(vertex_id, onset) |>
  mutate(onset = as.integer(onset)) |>
  mutate(terminus = onset) |>
  select(onset, terminus, vertex_id) |>
  as.data.frame()

dynNet <- networkDynamic(net,
               edge.spells = edge_spells,
               vertex.spells = vertex_spells,
               verbose = TRUE)

cat("Rendering movie...",fill=TRUE)

get_normalized_indegree <- function(slice) {
  # Calculate in-degrees
  in_degree_values <- degree(slice, gmode = "indegree")

  # Normalize by the maximum in-degree
  max_degree <- max(in_degree_values, na.rm = TRUE)
  if (max_degree == 0) {
    max_degree <- 1
  }
  normalized_in_degree <- 1 + 2 * (in_degree_values / max_degree)

  # If all in-degree values are NA (for isolated nodes), set them to 0
  if (all(is.na(normalized_in_degree))) {
    normalized_in_degree <- rep(0, length(normalized_in_degree))
  }
  # Replace NAs with 0s
  normalized_in_degree[is.na(normalized_in_degree)] <- 0

  return(normalized_in_degree)
}

get_vertex_labels <- function(slice) {
  in_degree_values <- degree(slice, gmode = "indegree")
  hide_vertex_labels_ids <- which(in_degree_values < 3)
  existing_labels <- if ("vertex.names" %in% list.vertex.attributes(slice)) {
    get.vertex.attribute(slice, "vertex.names")
  } else {
    as.character(1:network.size(slice))
  }
  existing_labels[hide_vertex_labels_ids] <- ""
  return(existing_labels)
}


# Create the plot parameter list
plot_params <- list(
  vertex.cex = get_normalized_indegree,
  label = get_vertex_labels,
  label.cex = get_normalized_indegree,
  main="Network of most-cited authors with most-citing authors (Source: JLS dataset)",
  displaylabels=TRUE)

d3_options <- list( animationDuration=2000)

render.d3movie(dynNet,
               plot.par = plot_params,
               d3.options = d3_options,
               frame.duration = 5000,
               filename = "figure/jls-most-cited-most-citing-movie.html",
               verbose = TRUE)
