# see also https://www.r-bloggers.com/2019/06/interactive-network-visualization-with-r/

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
library(htmltools)
library(humaniformat)
library(stringi)
library(tools)
library(svDialogs)


# configuration
min_year <- 0
min_all_years <- 2
louvain_cluster_resolution <- 1
combine_edges <- F
seed <- 11

# data source
journal_id <- "jls"
data_vendor <- dlg_list(list("wos","openalex","owndata"), multiple = FALSE)$res
if (data_vendor=="") {
  simpleError("No datasource given")
}
data_file <- paste0("data/", journal_id, "-author-network-", data_vendor, ".csv")
result_file <- paste0("docs/", journal_id, "-author-network-", data_vendor, ".html")
graph_title <- paste0("JLS Author Network 1985-2023 (Source: ", data_vendor, ")")
graph_description <- paste0("Data includes all citations to and from the Journal of Law and Society,
 1985-2023 as far as they exist in the ", data_vendor, " source data (which might be incomplete).
 To keep the network readable, a citation relationship between two authors is shown only if there
 are ", min_all_years, " or more citations over the time period.")

normalize_name <- function(name) { name }

if (data_vendor == 'openalex') {
  # openalex needs to reverse the names
  normalize_name <- function(name) {
    name_split <- stri_split_fixed(name, " ", simplify = TRUE)
    last_name <- name_split[length(name_split)]
    rest_of_name <- stri_join(name_split[1:(length(name_split) - 1)], collapse = " ")
    reversed_name <- stri_join(last_name, ", ", rest_of_name)
    return(reversed_name)
  }
} else if (data_vendor == 'wos') {
  # web of science: normalize to the last name and first initial
  normalize_name <- function(name) {
    name <- gsub("\\.", "", name)
    name <- gsub(" +", " ", name)
    components <- name |> trimws() |> tolower() |> strsplit(", ")
    last_name <- components[[1]][1]
    first_name <- components[[1]][2]
    first_initial <- substr(first_name, 1, 1)
    normalized_name <- paste0(toTitleCase(last_name), ", ", toupper(first_initial))
    return(normalized_name)
  }
}

# dataframe with columns "citing_author","cited_author","pub_year","citation_count"
df <- read.csv(data_file, encoding = "UTF-8") |> head(5000) |>
  # remve empty and invalid entries
  filter(!is.na(citing_author) & !is.na(cited_author)) |>
  filter(citing_author != "" & cited_author != "") |>
  # remove entries which do not meet a minimum of citations per year
  filter(citation_count >= min_year) |>
  mutate(
    citing_author = sapply(citing_author, normalize_name),
    cited_author = sapply(cited_author, normalize_name)
  ) |>
  # sort by citing author
  arrange(citing_author) |>
  # remove self-citations
  filter(citing_author != cited_author)

# Calculate total citations made by each journal per year
citing_totals_per_year <- df |>
  group_by(citing_author, pub_year) |>
  summarise(total_citing = sum(citation_count))
df <- df |>
  left_join(citing_totals_per_year, by=c("citing_author", "pub_year"))

# Create list of nodes with id and label
all_nodes <- data.frame(label = unique(c(df$citing_author, df$cited_author))) |>
  arrange(label) |>
  mutate(id=seq_along(label)) |>
  select(id,label)

# Create list of edges
edges <- df |>
  inner_join(all_nodes, by = c("citing_author" = "label")) |>
  rename(from = id) |>
  inner_join(all_nodes, by = c("cited_author" = "label")) |>
  rename(to = id) |>
  select(from, to, citation_count) |>
  group_by(from, to) |>
  summarise(count = sum(citation_count)) |>
  ungroup() |>
  filter(count >= min_all_years) |>
  mutate(label = as.character(count))

if (combine_edges) {
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
      label_AB = sum(if(from < to) count else 0),  # A->B
      label_BA = sum(if(from > to) count else 0)   # B->A
    ) |>
    # Create the desired label and weight
    mutate(
      label = paste(label_AB, "/", label_BA),
      value = total_count
    ) |>
    select(from, to, label, value)
}

# Filter out nodes without edges
edges_node_ids <- unique(c(edges$from, edges$to)) |> sort()
filtered_nodes <- all_nodes |>
  filter(id %in% edges_node_ids) |>
  select(id, label)

# Create undirected
graph <- graph_from_data_frame(edges, vertices = filtered_nodes, directed = F)

# Louvain Comunity Detection
cluster <- cluster_louvain(graph, resolution = louvain_cluster_resolution)
cluster_groups <- as.integer(membership(cluster))
cluster_names <- as.integer(cluster$names)
cluster_df <- tibble(id = cluster_names, group=cluster_groups)

# create a purely illustrative plot of the communities:
png_file <- paste0("docs/jls-author-network-communities-graph-", data_vendor, ".png")
png(png_file, width=800, height=600)
plot(cluster, graph, vertex.label=NA, vertex.size=5, edge.color=NA, edge.label=NA)
dev.off()

# plot a table with the communities
journal_communities <- communities(cluster) |>
  lapply(\(ids) filtered_nodes$label[as.integer(ids)])
# Determine the size of the largest community
max_length <- max(lengths(journal_communities))

# create a dataframe table for viewing
df_communities <- journal_communities |>
  lapply(\(community) c(community, rep(NA, max_length - length(community)))) |>
  as.data.frame(stringsAsFactors = FALSE)

# save as a html table
htmlTable::htmlTable(df_communities) |>
  htmltools::save_html(paste0("docs/",journal_id,"-author-network-communities-table-", data_vendor,".html"))

# Extract nodes
vis_nodes <- filtered_nodes |> inner_join(cluster_df, by="id")
vis_edges <- edges |> mutate(value = count)

# create visualization
vn <- visNetwork(vis_nodes, vis_edges, width = "100%", height = "1000px") |>
  visIgraphLayout() |>
  visNodes(
    shape = "dot",
    size = 30,
    shadow = FALSE
  ) |>
  visEdges(
    shadow = FALSE,
    arrows = "to",
    smooth = list(type="continuous", roundness=0.7)
  )  |>
  visLayout(randomSeed = seed, improvedLayout = FALSE)  |>
  visPhysics(
    enabled = T,
    solver = "forceAtlas2Based",
    stabilization = F,
    repulsion = list(nodeDistance = 300),
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
  #visOptions(highlightNearest = list(enabled = T, degree = 1, hover = T), selectedBy = "group") |>
  visSave('cache/last-vis-graph.html', selfcontained = T)

# add searchbox html to page
original_html <- readLines('cache/last-vis-graph.html') |> paste(collapse = "\n")
custom_html <- readLines("lib/vis-network-searchbox.html") |>
  lapply(\(line) gsub("\\$title", graph_title, line)) |>
  lapply(\(line) gsub("\\$description", graph_description, line)) |>
  paste(collapse = "\n")

new_html <- gsub("<body([^>]*)>", paste0("\1\n", custom_html), original_html)
writeLines(new_html, result_file)