# see also https://www.r-bloggers.com/2019/06/interactive-network-visualization-with-r/
# todo: statistical validation of results: https://cran.r-project.org/web/packages/robin/vignettes/robin.html

library(igraph)
library(tidyr)
library(ggplot2)
library(ggExtra)
library(data.table)
library(dotenv)
library(visNetwork)
library(igraph)
library(stringr)
library(gridExtra)
library(htmlTable)
library(htmltools)
library(dplyr)

# configuraion
min_year <- 0
min_all_years <- 5
louvain_cluster_resolution <- 1
ignore_journals <- c('sustainability',
                     'choice reviews online',
                     'repec: research papers in economics',
                     "doaj (doaj: directory of open access journals)")
# data source
journal_id <- "jls"
data_vendor <- "wos"
data_file <- paste0("data/", journal_id, "-journal-network-", data_vendor, ".csv")

# dataframe with columns source_title1, source_title2, count_citations
df <- read.csv(data_file) |>
  # remove journals that have a high citation rate but are not relevant for our question
  filter(!(str_to_lower(source_title_citing) %in% ignore_journals) &
           !(str_to_lower(source_title_cited) %in% ignore_journals)) |>
  # remove self-citations
  filter(source_title_citing != source_title_cited) |>
  # remove journals which do not meet a minimum of citations per year
  filter(count_citations >= min_year)

# Calculate total citations made by each journal per year and compute normalized weight
citing_totals_per_year <- df |>
  group_by(source_title_citing, citation_year) |>
  summarise(total_citing = sum(count_citations))
df <- df |>
  left_join(citing_totals_per_year, by=c("source_title_citing", "citation_year")) |>
  mutate(normalized_weight = count_citations / total_citing)

# Create list of nodes with id and label
all_nodes <- data.frame(label = unique(c(df$source_title_citing, df$source_title_cited))) |>
  mutate(id=seq_along(label))

# Create list of edges
edges <- df |>
  inner_join(all_nodes, by = c("source_title_citing" = "label")) |>
  rename(from = id) |>
  inner_join(all_nodes, by = c("source_title_cited" = "label"))|>
  rename(to = id) |>
  select(from, to, count_citations, normalized_weight) |>
  group_by(from, to) |>
  summarise(count = sum(count_citations), median_weight = median(normalized_weight)) |>
  ungroup() |>
  filter(count > min_all_years) |>
  mutate(width = pmin(median_weight * 3, 10),
         label = as.character(count),
         weight = median_weight)

# convert into undirected graph combining citations in both directions
edges <- edges |>
  rowwise() |>
  mutate(edge_id = paste(pmin(from, to), pmax(from, to), sep = "-")) |>
  ungroup() |>
  # Group by the unique id and summarize
  group_by(edge_id) |>
  summarise(
    from = first(from),
    to = first(to),
    total_count = sum(count),
    combined_weight = median(weight, na.rm = TRUE),
    label_AB = sum(if(from < to) count else 0),  # A->B
    label_BA = sum(if(from > to) count else 0)   # B->A
  ) |>
  # Create the desired label and weight
  mutate(
    label = paste(label_AB, "/", label_BA),
    weight = combined_weight,
    size = combined_weight * 10
  ) |>
  select(from, to, label, weight, size)

# Filter out nodes without edges
edges_node_ids <- unique(c(edges$from, edges$to))
filtered_nodes <- all_nodes |>
  filter(id %in% edges_node_ids)

# Create undirected
graph <- graph_from_data_frame(edges, vertices = filtered_nodes, directed = F)

# Remove subgraphs that are unconnected to the main graph
comps <- components(graph)
largest_comp_id <- which.max(comps$csize)
graph <- induced_subgraph(graph, which(comps$membership == largest_comp_id))

# Louvain Comunity Detection
cluster <- cluster_louvain(graph, resolution = louvain_cluster_resolution)
cluster_groups <- membership(cluster)
cluster_df <- tibble(group=cluster_groups) |>
  mutate(id = as.integer(row_number())) |>
  select(id, group)

# create a purely illustrative plot of the communities:
png_file <- paste0("docs/jls-journal-network-communities-graph-", data_vendor, ".png")
png(png_file, width=800, height=600)
plot(cluster, graph, vertex.label=NA, vertex.size=5, edge.color=NA, edge.label=NA)
dev.off()

# plot a table with the communities
journal_communities <- communities(cluster) |>
  lapply(\(ids) filtered_nodes$label[as.integer(ids)])
# Determine the size of the largest community
max_length <- max(lengths(journal_communities))

# create a dataframe table for vieweing
df_communities <- journal_communities |>
  lapply(\(community) c(community, rep(NA, max_length - length(community)))) |>
  as.data.frame(stringsAsFactors = FALSE)

# save as a html table
htmlTable::htmlTable(df_communities) |>
  htmltools::save_html(paste0("docs/",journal_id,"-journal-network-communities-table-", data_vendor,".html"))

# Extract nodes from igraph and add community
graph_data <- toVisNetworkData(graph)
vis_nodes <- graph_data$nodes |>
  mutate(id = as.integer(id)) |>
  select(id) |>
  inner_join(filtered_nodes, by="id") |>
  inner_join(cluster_df, by="id")
# Extract edges
vis_edges <- graph_data$edges

# create visualization
vn <- visNetwork(vis_nodes, vis_edges, width = "100%", height = "1000px") |>
  visIgraphLayout() |>
  visNodes(
    shape = "dot",
    size = 30,
    color = list(
      background = "#0085AF",
      border = "#013848",
      highlight = "#FF8000"
    ),
    shadow = list(enabled = TRUE, size = 10)
  ) |>
  visEdges(
    shadow = FALSE,
    smooth = list(type="continuous", roundness=0.7),
    color = list(color = "#0085AF", highlight = "#C62F4B")
  )  |>
  visLayout(randomSeed = 11)  |>
  visPhysics(
    solver = "forceAtlas2Based",
    barnesHut = list(
      gravitationalConstant = -50000,
      centralGravity = 0.3,
      springLength = 200,
      springConstant = 0.04
    ),
    forceAtlas2Based = list(
      avoidOverlap = 1,
      centralGravity = 0,
      gravitationalConstant = -50000,  # Increase the negative value
      springLength = 2000,                # Increase this value
      springConstant = 0.001,             # Decrease this value
      damping = 0.9                      # Adjust as needed
    )
  ) |>
  visInteraction(hideEdgesOnZoom=T, hideNodesOnDrag=T) |>
  visOptions(highlightNearest = list(enabled = T, degree = 1, hover = T),
             selectedBy = "group", nodesIdSelection = TRUE) |>
  visSave(paste0("docs/", journal_id, "-journal-network-", data_vendor, ".html"), selfcontained = T)
