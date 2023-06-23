# see also https://www.r-bloggers.com/2019/06/interactive-network-visualization-with-r/

library(igraph)
library(neo4r)
library(dplyr)
library(tidyr)
library(ggplot2)
library(ggExtra)
library(data.table)
library(dotenv)
library(visNetwork)
library(igraph)

min_year <- 5
min_all_years <- 25

if (!exists("journal_network")) {
  journal_network <- read.csv('data/wos-jls-journal-network.csv')
}

df <- journal_network |>
  select(ref_source_title, source_title, ref_pubyear) |>
  mutate(ref_source_title = tolower(ref_source_title), source_title = tolower(source_title), ref_pubyear = as.integer(ref_pubyear)) |>
  mutate(ref_source_title = if_else(ref_source_title == "j law soc", "journal of law and society", ref_source_title)) |>
  group_by(ref_source_title, source_title, ref_pubyear) |>
  summarise(count = n()) |>
  ungroup()

# get highest count
max_count <- max(df$count)

# Create list of nodes
all_nodes <- data.frame(label = unique(c(df$ref_source_title, df$source_title))) %>%
  filter(label != "")  
all_nodes$id <- seq_along(all_nodes$label)
all_nodes <- all_nodes |> select(id, label)

# Create list of edges
edges <- df |>
  inner_join(all_nodes, by = c("source_title" = "label")) |>
  rename(from = id) |>
  inner_join(all_nodes, by = c("ref_source_title" = "label"))|>
  filter(count > min_year) |> 
  rename(to = id) |>
  select(from, to, count) |>
  group_by(from, to) |>
  summarise(count = sum(count)) |>
  ungroup() |>
  mutate(rel_count = (count/max_count)) |>
  filter(count > min_all_years) |>
  mutate(width = pmin(rel_count*3, 10), 
         label = as.character(count),
         weight = count) |>
  filter(from != to)


# Create graph for Louvain
graph <- graph_from_data_frame(edges, vertices = all_nodes, directed = F)

# Louvain Comunity Detection
cluster <- cluster_louvain(graph)
cluster_groups <- membership(cluster)
cluster_df <- tibble(group=cluster_groups)
cluster_df$id <- as.integer(rownames(cluster_df))
nodes <- left_join(all_nodes, cluster_df, by = "id")
colnames(nodes)[3] <- "group"

vn <- visNetwork(nodes, edges, width = "100%", height = "800px") %>%
  visIgraphLayout() %>%
  visNodes(
    shape = "dot",
    color = list(
      background = "#0085AF",
      border = "#013848",
      highlight = "#FF8000"
    ),
    shadow = list(enabled = TRUE, size = 10)
  ) %>%
  visEdges(
    shadow = FALSE,
    color = list(color = "#0085AF", highlight = "#C62F4B")
  )  %>%
  visLayout(randomSeed = 11)

vn  %>% 
  visEdges(arrows = "to", smooth=list(type="continuous", roundness=0.7))  %>%
  visPhysics(solver = "forceAtlas2Based",
             forceAtlas2Based = list(gravitationalConstant = -5000)) %>%
  visOptions(highlightNearest = list(enabled = T, degree = 1, hover = T),
             selectedBy = "group", nodesIdSelection = TRUE)
#visNetworkEditor(object=vn)
vn