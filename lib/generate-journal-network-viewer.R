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
library(tibble)

source('lib/query-open-ai-api.R')

htmlTable::setHtmlTableTheme(
  align = "lrr",
  col.rgroup = c("none", "#EEEEEE"),
  pos.caption = "top",
  css.cell = 'padding-left: 10px; padding-right: 10px;',
  css.header = 'padding-left: 10px; padding-right: 10px;'
)

generate_journal_network_viewer <- function(
  journal_id,
  data_vendor,
  data_file,
  result_file,
  min_all_years = 5,
  louvain_cluster_resolution = 1.1,
  label_groups_with_chatgpt = FALSE,
  ignore_journals = c()
) {
  if (!is.character(journal_id)  || !is.character(data_vendor) || !is.character(data_file) || !is.character(result_file)){
    stop("Missing arguments")
  }

  title_network <- paste(journal_id, "journal network (Source:", paste0(data_vendor, ")"))

  # dataframe with columns source_title1, source_title2, count_citations
  df <- read.csv(data_file, encoding = "UTF-8") |>
    # remove journals that have a high citation rate but are not relevant for our question
    filter(!(str_to_lower(source_title_citing) %in% ignore_journals) &
             !(str_to_lower(source_title_cited) %in% ignore_journals)) |>
    # remove self-citations
    filter(source_title_citing != source_title_cited)

  # get year range
  citation_year_first <- min(df$citation_year)
  citation_year_last <- max(df$citation_year)

  description <- paste0('Citation data coverage: ', citation_year_first, ' - ', citation_year_last, '<br>',
                        'Minimum citations all years:', min_all_years, '<br>',
                        'Louvain cluster resolution:', louvain_cluster_resolution, '<br>'
  )

  # Create list of nodes with id and label
  all_nodes <- data.frame(label = unique(c(df$source_title_citing, df$source_title_cited))) |>
    mutate(id = seq_along(label))

  # add a column with abbreviated labels
  stop_words <- c("&", "and", "the", "of", "in", "a", "der", "die", "das")

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
    left_join(citing_totals_per_year, by = c("from", "citation_year")) |>
    mutate(normalized_weight = count_citations / total_citing_year)

  # Create a histogram plot of the distribution of the normalized weight
  plot <- ggplot(df, aes(x = normalized_weight)) +
    geom_histogram(binwidth = 0.005, fill = "blue", color = "black") +
    theme_minimal() +
    labs(title = "Distribution of Normalized Weights",
         x = "Normalized Weight",
         y = "Count")
  file_distribution_normalized_weights <- paste0(journal_id,"-", data_vendor, "-", "weight_distribution_plot.png")
  ggsave( paste0("docs/",file_distribution_normalized_weights), plot, width = 10, height = 6, dpi = 300)


  # Scaled Adjusted Log-Transformed Normalized Weights to have more evenly spread values for a slider
  p <- -1  # Power for the adjusted logarithmic transformation
  n <- 100  # The fixed number to scale the values to

  # Apply the adjusted logarithmic transformation
  df$adjusted_log_weight <- log(df$normalized_weight^p + 1)

  # Perform min-max normalization to scale values to range 0 to n
  min_value <- min(df$adjusted_log_weight)
  max_value <- max(df$adjusted_log_weight)

  # Perform min-max normalization and round to get integer values in range 0 to n
  df$scaled_weight <- (n * as.integer(p < 0)) - as.integer(round((df$adjusted_log_weight - min_value) / (max_value - min_value) * n))

  scaled_to_ratio <-df |>
    group_by(scaled_weight) |>
    summarise(normalized_weight = median(normalized_weight)) |>
    deframe()

  # Create the histogram plot of the scaled data
  plot_scaled <- ggplot(df, aes(x = scaled_weight)) +
    geom_histogram(binwidth = 1, fill = "blue", color = "black") +
    theme_minimal() +
    labs(title = paste0("Distribution of Scaled Adjusted Log-Transformed Weights (0 to ", n, ", power =", p, ")"),
         x = paste("Scaled Adjusted Log-Transformed Weight (0 to", n, ")"),
         y = "Count")

  file_distr_scaled_adj_log_transf_norm_weights <- paste0(journal_id,"-", data_vendor, "-", "scaled_adjusted_log_transformed_weight_distribution_plot.png")
  ggsave(paste0("docs/",file_distr_scaled_adj_log_transf_norm_weights), plot_scaled, width = 10, height = 6, dpi = 300)

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

  #calcuate first year with citation data
  years_citing <- df  |>
    select(from, citation_year) |>
    rename(id = from) |>
    group_by(id) |>
    summarize(year_first = min(citation_year), year_last = max(citation_year)) |>
    ungroup() |>
    mutate(years_citing = paste0(year_first, "-", year_last))

  #calcuate first year with citation data
  years_cited <- df  |>
    select(to, citation_year) |>
    rename(id = to) |>
    group_by(id) |>
    summarize(year_first = min(citation_year), year_last = max(citation_year)) |>
    ungroup() |>
    mutate(years_cited = paste0(year_first, "-", year_last))

  # Combine everything
  all_nodes <- all_nodes |>
    left_join(total_citing_df, by = "id") |>
    left_join(total_cited_df, by = "id") |>
    left_join(years_citing, by = "id") |>
    left_join(years_cited, by = "id") |>
    select(id, label, abbr, total_citing, total_cited, years_citing, years_cited) |>
    arrange(id)

  # save as a html table
  file_journal_table <- paste0(journal_id, "-journal-network-journals-", data_vendor, ".html")
  all_nodes |>
    select(-id, -abbr) |>
    htmlTable::htmlTable(caption = paste0("<h1>Journals in ", journal_id, " network (Source: ", data_vendor, ")</h1>")) |>
    htmltools::save_html(paste0("docs/", file_journal_table))

  # function to format weights
  format_weight <- function(weight) {
    ifelse(weight >= .0001, round(weight, 4), "< 0.0001")
  }

  # Create list of edges summarizing edge data for all years
  directed_edges <- df |>
    select(from, to, count_citations, normalized_weight) |>
    group_by(from, to) |>
    summarise(
      count = sum(count_citations),
      weight = median(normalized_weight)) |>
    ungroup() |>
    filter(count > min_all_years) |>
    mutate(from = as.integer(from),
           to = as.integer(to))

  # Convert into undirected graph combining citations in both directions
  edges <- directed_edges |>
    # move count and weight values to separate column according to direction
    mutate(
      count_from_to = as.integer(ifelse(from < to, count, 0)),
      count_to_from = as.integer(ifelse(from > to, count, 0)),
      weight_from_to = ifelse(from < to, weight, 0),
      weight_to_from = ifelse(from > to, weight, 0)
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
      weight = sum(weight),
      # merge values into the separate columns
      count_from_to = sum(count_from_to),
      count_to_from = sum(count_to_from),
      weight_from_to = sum(weight_from_to),
      weight_to_from = sum(weight_to_from)
    ) |>
    ungroup() |>
    # add journal names back as acronyms
    inner_join(all_nodes |> select(id, abbr), by = c("from" = "id")) |>
    rename(abbr_from = abbr) |>
    inner_join(all_nodes |> select(id, abbr), by = c("to" = "id")) |>
    rename(abbr_to = abbr) |>
    ungroup() |>
    select(-edge_id)

  # Filter out nodes without edges
  edges_node_ids <- unique(c(edges$from, edges$to)) |> sort()
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
  cluster_groups <- as.integer(membership(cluster))
  cluster_names <- as.integer(cluster$names)
  cluster_df <- tibble(id = cluster_names, group = cluster_groups)

  # create a purely illustrative plot of the communities:
  file_communities <- paste0("jls-journal-network-communities-graph-", data_vendor, ".png")
  png(paste0("docs/", file_communities), width = 800, height = 600)
  plot(cluster, graph, vertex.label = NA, vertex.size = 5, edge.color = NA, edge.label = NA)
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
  if (label_groups_with_chatgpt && Sys.getenv("OPENAI_API_KEY") != "") {
    df_communities <- rename_headers(df_communities)
  }

  # groups info
  groups_headings <- colnames(df_communities)
  groups_df <- data.frame(id = seq_along(groups_headings), group_name = groups_headings)

  # save as a html table
  file_group_table <- paste0(journal_id, "-journal-network-communities-table-", data_vendor, ".html")
  htmlTable::htmlTable(df_communities, caption = paste0("<h1>", title_network, "</h1>")) |>
    htmltools::save_html(paste0("docs/", file_group_table))

  # re-convert igraph to vis network data
  graph_data <- toVisNetworkData(graph)

  # extract nodes from igraph and add community
  vis_nodes <- graph_data$nodes |>
    mutate(id = as.integer(id)) |>
    select(id) |>
    # add the node data back in
    inner_join(filtered_nodes, by = "id") |>
    # add the group id and name
    inner_join(cluster_df, by = "id") |>
    inner_join(groups_df, by = c("group" = "id")) |>
    # add label and title
    mutate(label = paste0(label, "\n(", abbr, ")"),
           title = paste0(paste0("<div class='node-title-label'>", label, "</div>"),
                          "Group: ", group_name, "<br>",
                          "Citing references: ", total_citing, " (", years_citing, ")<br>",
                          "Cited references: ", total_cited, " (", years_cited, ")<br>"
           )) |>
    select(id, label, group, title)

  # Extract edges and create visual properties
  vis_edges <- graph_data$edges |>
    # create the text shown on popup
    mutate(
      title = paste(
        abbr_from, "->", abbr_to, ":", count_from_to,
        ifelse(count_from_to > 0, paste0("(", format_weight(weight_from_to), ")"), ""),
        "<br>",
        abbr_to, "->", abbr_from, ":", count_to_from,
        ifelse(count_to_from > 0, paste0("(", format_weight(weight_to_from), ")"), ""),
        "<br>"
      )
    ) |>
    rowwise() |>
    # value is the higher of the normalized weights in either direction
    mutate(value = round(max(weight_from_to, weight_to_from),5)) |>
    ungroup() |>
    select(from, to, title, value)

  # create visualization
  vn <- visNetwork(vis_nodes, vis_edges, width = "100%", height = "100vh") |>
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
      smooth = list(type = "continuous", roundness = 0.7),
      font = list(align = "middle"),
      color = list(color = "#0085AF", highlight = "#C62F4B")
    )  |>
    visLayout(randomSeed = 11)  |>
    visPhysics(solver = "forceAtlas2Based",
               forceAtlas2Based = list(gravitationalConstant = -5000)) |>
    visInteraction(hideEdgesOnZoom = T, hideNodesOnDrag = T) |>
    visOptions(highlightNearest = list(enabled = T, degree = 1, hover = T)) |>
    visSave('cache/last-vis-graph.html', selfcontained = T)

  # add searchbox code to HTML output
  html <- readLines('cache/last-vis-graph.html') |>
    paste(collapse = "\n") |>
    str_replace_all('on\\(\\"doubleClick\\"', 'on("doubleClickDisabled"')  # disable doubleClick events in the visNetwork implementation

  searchbox_html <- readLines("lib/vis-network-searchbox.html") |> paste(collapse = "\n")
  html <- gsub("(<body.*?>)", paste0("\\1\n", searchbox_html), html)

  # update variables placeholders
  html <- html |>
    str_replace("\\$title", title_network) |>
    str_replace("\\$description", description) |>
    str_replace("\\$groups", toJSON(groups_headings)) |>
    str_replace("\\$scaled_to_ratio", toJSON(scaled_to_ratio, pretty = TRUE)) |>
    str_replace("<title>visNetwork</title>", paste0("<title>", title_network, "</title>")) |>
    str_replace("\\$file_journal_table", file_journal_table) |>
    str_replace("\\$file_group_table", file_group_table) |>
    str_replace("\\$file_communities", file_communities) |>
    str_replace("\\$file_distribution_normalized_weights", file_distribution_normalized_weights) |>
    str_replace("\\$file_distr_scaled_adj_log_transf_norm_weights", file_distr_scaled_adj_log_transf_norm_weights)

  writeLines(html, result_file)
}


