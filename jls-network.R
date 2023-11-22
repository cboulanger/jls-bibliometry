source('lib/generate-journal-network-viewer.R')

run <- function( journal_id, data_vendor) {
  generate_journal_network_viewer(
    journal_id = journal_id,
    data_vendor = data_vendor,
    data_file = paste0("data/", journal_id, "-journal-network-", data_vendor, ".csv"),
    result_file = paste0("docs/", journal_id, "-journal-network-", data_vendor, ".html"),
    min_all_years = 25,
    louvain_cluster_resolution = 1.1,
    label_groups_with_chatgpt = TRUE,
    ignore_journals = c('sustainability',
                         'choice reviews online',
                         'repec: research papers in economics',
                         "doaj (doaj: directory of open access journals)")

  )
  print(paste("Finished generating the", journal_id, "network using data from", data_vendor ))
}

# main
run("jls","openalex")
run("jls", "wos")




