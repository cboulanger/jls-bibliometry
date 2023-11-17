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

source('lib/query-open-ai-api.R')

# configuraion
min_year <- 0
min_all_years <- 5
louvain_cluster_resolution <- 1.1
ignore_journals <- c('sustainability',
                     'choice reviews online',
                     'repec: research papers in economics',
                     "doaj (doaj: directory of open access journals)")
# data source
journal_id <- "jls"
data_vendor <- "wos"
data_vendor <- "openalex"
data_file <- paste0("data/", journal_id, "-journal-network-", data_vendor, ".csv")
result_file <- paste0("docs/", journal_id, "-journal-network-", data_vendor, ".html")

title_network <- paste(journal_id, "journal network with cluster resolution of", louvain_cluster_resolution, "(Source:", paste0(data_vendor, ")"))

# dataframe with columns source_title1, source_title2, count_citations
df <- read.csv(data_file, encoding = "UTF-8") |>
  # remove journals that have a high citation rate but are not relevant for our question
  filter(!(str_to_lower(source_title_citing) %in% ignore_journals) &
           !(str_to_lower(source_title_cited) %in% ignore_journals)) |>
  # remove self-citations
  filter(source_title_citing != source_title_cited) |>
  # remove journals which do not meet a minimum of citations per year
  filter(count_citations >= min_year)

# Create list of nodes with id and label
all_nodes <- data.frame(label = unique(c(df$source_title_citing, df$source_title_cited))) |>
  mutate(id=seq_along(label))

# add a column with abbreviated labels
stop_words <- c("&","and", "the", "of", "in", "a", "der", "die", "das")
abbreviate_label <- function(string) {
  words <- strsplit(string, "\\s+")[[1]]
  words <- words[!tolower(words) %in% stop_words]
  initials <- substr(words, 1, 1)
  tolower(paste0(initials, collapse = ""))
}
all_nodes <- all_nodes |>
  mutate(abbr = sapply(label, abbreviate_label))

# add the node ids to the citation data
df <- df |>
  inner_join(all_nodes, by = c("source_title_citing" = "label")) |>
  rename(from = id) |>
  inner_join(all_nodes, by = c("source_title_cited" = "label"))|>
  rename(to = id)

# Calculate total citations made by each journal per year and compute normalized weight
citing_totals_per_year <- df |>
  group_by(from, citation_year) |>
  summarise(total_citing_year = sum(count_citations)) |>
  ungroup()
df <- df |>
  left_join(citing_totals_per_year, by=c("from", "citation_year")) |>
  mutate(normalized_weight = count_citations / total_citing_year)

# Calculate total_citing
total_citing_df <- all_nodes |>
  left_join(df, by = c("id" = "from")) |>
  group_by(id) |>
  summarize(total_citing = sum(count_citations, na.rm = TRUE)) |>
  ungroup()

# Calculate total_cited
total_cited_df <- all_nodes |>
  left_join(df, by = c("id" = "to")) |>
  group_by(id) |>
  summarize(total_cited = sum(count_citations, na.rm = TRUE)) |>
  ungroup()

# Combine everything
all_nodes <- all_nodes |>
  left_join(total_citing_df, by = "id") |>
  left_join(total_cited_df, by = "id") |>
  select(id, label, abbr, total_citing, total_cited) |>
  arrange(id)

# save as a html table
file_journal_table <- paste0(journal_id,"-journal-network-journals-", data_vendor,".html")
all_nodes |>
  select(label, total_citing, total_cited) |>
  htmlTable::addHtmlTableStyle(align="lrr") |>
  htmlTable::htmlTable(caption = paste0("<h1>Journals in ",journal_id," network (Source: ", data_vendor,")</h1>")) |>
  htmltools::save_html(paste0("docs/",file_journal_table))

# Create list of edges
directed_edges <- df |>
  select(from, to, count_citations, normalized_weight) |>
  group_by(from, to) |>
  summarise(count = sum(count_citations), median_weight = median(normalized_weight)) |>
  ungroup() |>
  filter(count > min_all_years) |>
  mutate(from = as.integer(from),
         to = as.integer(to),
         width = pmin(median_weight * 3, 10),
         label = as.character(count),
         weight = median_weight)

# Convert into undirected graph combining citations in both directions
edges <- directed_edges |>
  # Calculate count_from_to and count_to_from
  mutate(
    count_from_to = as.integer(ifelse(from < to, count, 0)),
    count_to_from = as.integer(ifelse(from > to, count, 0))
  ) |>
  # create a unique edge_id for both directions
  rowwise() |>
  mutate(edge_id = paste(pmin(from, to), pmax(from, to), sep = "-")) |>
  ungroup() |>
  # summarize the values of the directed edged
  group_by(edge_id) |>
  summarise(
    from = first(from),
    to = first(to),
    total_count = sum(count),
    combined_weight = median(weight, na.rm = TRUE),
    count_from_to = sum(count_from_to),
    count_to_from = sum(count_to_from)
  ) |>
  ungroup() |>
  left_join(directed_edges, by = c("from", "to")) |>
  group_by(edge_id) |>
  # Create the count_from_to and count_to_from
  summarise(
    from = first(from),
    to = first(to),
    total_count = first(total_count),
    combined_weight = first(combined_weight),
    count_from_to = first(count_from_to),
    count_to_from = first(count_to_from)
  ) |>
  ungroup() |>
  # add journal names back as acronyms
  inner_join(all_nodes |> select(id, abbr), by = c("from" = "id")) |>
  rename(abbr_from = abbr) |>
  inner_join(all_nodes |> select(id, abbr), by = c("to" = "id")) |>
  rename(abbr_to = abbr) |>
  # Final mutation to create label and size
  mutate(
    title = paste(abbr_from, "->", abbr_to, ":", count_from_to, "<br>",
                  abbr_to, "->", abbr_from, ":", count_to_from),
    weight = combined_weight,
    size = combined_weight * 10,
    value = total_count
  ) |>
  select(from, to, title, weight, size, value)

# Filter out nodes without edges
edges_node_ids <- unique(c(edges$from, edges$to)) |> sort()
filtered_nodes <- all_nodes |>
  filter(id %in% edges_node_ids) |>
  select(id, label, abbr, total_citing, total_cited)

# Create undirected
graph <- graph_from_data_frame(edges, vertices = filtered_nodes, directed = F)

# Remove subgraphs that are unconnected to the main graph
comps <- components(graph)
largest_comp_id <- which.max(comps$csize)
graph <- induced_subgraph(graph, which(comps$membership == largest_comp_id))

# Louvain Comunity Detection
cluster <- cluster_louvain(graph, resolution = louvain_cluster_resolution)
cluster_groups <- as.integer(membership(cluster))
cluster_names <- as.integer(cluster$names)
cluster_df <- tibble(id = cluster_names, group=cluster_groups)

# create a purely illustrative plot of the communities:
file_communities <- paste0("jls-journal-network-communities-graph-", data_vendor, ".png")
png(paste0("docs/",file_communities), width=800, height=600)
plot(cluster, graph, vertex.label=NA, vertex.size=5, edge.color=NA, edge.label=NA)
dev.off()

# create a dataframe containing the journal names
journal_communities <- communities(cluster) |>
  lapply(\(ids) filtered_nodes$label[as.integer(ids)]) |>
  lapply(\(x) iconv(x, to = "UTF-8"))

# Determine the size of the largest community
max_length <- max(lengths(journal_communities))

# create a dataframe table for viewing
df_communities <- journal_communities |>
  lapply(\(community) c(community, rep(NA, max_length - length(community)))) |>
  as.data.frame(stringsAsFactors = FALSE)

# if we have an OpenAI key, rename the groups using GPT
if (Sys.getenv("OPENAI_API_KEY")!="") {
  df_communities <- rename_headers(df_communities)
}

# groups info
groups_headings <- colnames(df_communities)
groups_df <- data.frame(id = seq_along(groups_headings), group_name = groups_headings)

# save as a html table
file_group_table <- paste0(journal_id,"-journal-network-communities-table-", data_vendor,".html")
htmlTable::htmlTable(df_communities, caption = paste0("<h1>", title_network, "</h1>")) |>
  htmltools::save_html(paste0("docs/",file_group_table))

# re-convert igraph to vis network data
graph_data <- toVisNetworkData(graph)

# extract nodes from igraph and add community
vis_nodes <- graph_data$nodes |>
  mutate(id = as.integer(id)) |>
  select(id) |>
  inner_join(filtered_nodes, by="id") |>
  inner_join(cluster_df, by="id") |>
  inner_join(groups_df, by = c("group"="id")) |>
  mutate(label = paste0(label,"\n(",abbr,")"),
         title = paste0(paste0("<div class='node-title-label'>",label, "</div>"),
                        "Group: ", group_name, "<br>",
                        total_citing," total citing references", "<br>",
                        total_cited," total cited references")) |>
  select(id, label, group, title)

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
    font = list(align="middle"),
    color = list(color = "#0085AF", highlight = "#C62F4B")
  )  |>
  visLayout(randomSeed = 11)  |>
  visPhysics(solver = "forceAtlas2Based",
             forceAtlas2Based = list(gravitationalConstant = -5000)) |>
  visInteraction(hideEdgesOnZoom=T, hideNodesOnDrag=T) |>
  visOptions(highlightNearest = list(enabled = T, degree = 1, hover = T)) |>
  visSave('cache/last-vis-graph.html', selfcontained = T)

# add searchbox code to HTML output
html <- readLines('cache/last-vis-graph.html') |> paste(collapse = "\n")
searchbox_html <- readLines("lib/vis-network-searchbox.html") |> paste(collapse = "\n")
html <- gsub("(<body.*?>)", paste0("\\1\n", searchbox_html), html)

# update variables placeholders
groups_json <- toJSON(setNames(journal_communities, groups_headings), pretty = TRUE)
html <- html |>
  str_replace("\\$title", title_network) |>
  str_replace("\\$groups", groups_json) |>
  str_replace("<title>visNetwork</title>", paste0("<title>", title_network, "</title>")) |>
  str_replace("\\$file_journal_table", file_journal_table) |>
  str_replace("\\$file_group_table", file_group_table) |>
  str_replace("\\$file_communities", file_communities)

writeLines(html, result_file)