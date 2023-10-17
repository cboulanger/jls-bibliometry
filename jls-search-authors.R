library(shiny)
library(visNetwork)

# Sample data
nodes <- data.frame(id = 1:5, label = c("Node 1", "Node 2", "Node 3", "Node 4", "Node 5"))
edges <- data.frame(from = c(1, 2, 3, 4), to = c(2, 3, 4, 5))

# UI
ui <- fluidPage(
  textInput("searchBox", "Search Node: "),
  visNetworkOutput("network")
)

# Server logic
server <- function(input, output, session) {
  # Create a reactive expression based on the search input
  reactive_network_data <- reactive({
    search_text <- input$searchBox
    if (search_text == "") {
      # Empty network
      list(nodes = data.frame(), edges = data.frame())
    } else {
      # Filter nodes and edges based on search criteria
      filtered_nodes <- nodes[grep(search_text, nodes$label, ignore.case = TRUE),]
      filtered_edges <- edges[edges$from %in% filtered_nodes$id | edges$to %in% filtered_nodes$id, ]
      list(nodes = filtered_nodes, edges = filtered_edges)
    }
  })

  # Render network
  output$network <- renderVisNetwork({
    network_data <- reactive_network_data()
    visNetwork(network_data$nodes, network_data$edges)
  })
}

# Run the app
shinyApp(ui, server)
