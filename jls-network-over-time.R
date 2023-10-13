library(network)
library(networkDynamic)
library(tidyverse)
library(ndtv)

# Read the data
data <- read.csv("data/jls-journal-network-openalex.csv") |>
  filter(citation_year >= 1974)

# Create a lookup table for journal titles to IDs
titles <- unique(c(data$source_title_citing, data$source_title_cited))
title_lookup <- tibble(name = titles, id = seq_along(titles))

# Convert source and target titles to ids
data <- data |>
  left_join(title_lookup, by = c("source_title_citing" = "name")) |>
  rename(source_id = id) |>
  left_join(title_lookup, by = c("source_title_cited" = "name")) |>
  rename(target_id = id)

# Create the network using an edgelist
net <- network(matrix(c(data$source_id, data$target_id), ncol = 2), directed = TRUE, loops = FALSE)
network.vertex.names(net) <- titles

# Create networkDynamic object
dynNet <- networkDynamic(net)

# Create a unique identifier for each edge in the original data
data <- data %>% mutate(edge_id_original = paste0(source_id, "-", target_id))

# Initialize a vector to hold the edge IDs from the network object
edge_ids_network <- numeric(nrow(data))

# Create a progress bar
pb <- txtProgressBar(min = 0, max = nrow(data), style = 3)

# Loop through the data to find the corresponding edge IDs in the network object
for (i in seq_len(nrow(data))) {
  # Update progress bar
  setTxtProgressBar(pb, i)

  edge <- data[i, ]
  edge_ids_network[i] <- which.edge(net, tail = edge$source_id, head = edge$target_id)
}

# Close progress bar
close(pb)

# Add these edge IDs as a new column to the original data
data$edge_id_network <- edge_ids_network

# Activate edges
activate.edges(dynNet, onset = data$citation_year, terminus = data$citation_year, e = data$edge_id_network)

# Add vertex activity
activate.vertices(dynNet, onset = min(data$citation_year, na.rm = TRUE), terminus = max(data$citation_year, na.rm = TRUE), v = seq_len(network.size(net)))

# Add count_citations as an edge attribute
set.edge.attribute(dynNet, "count_citations", data$count_citations)

# Render the movie
render.d3movie(dynNet, launchBrowser = TRUE)


