library(httr)
library(jsonlite)
library(dotenv)

# Function to send requests to OpenAI API with automatic message composition
send_openai_request <- function(model, prompt, max_tokens=256, temperature=1, top_p=1, frequency_penalty=0, presence_penalty=0, max_retries=3, retry_delay=5) {
  api_key <- Sys.getenv("OPENAI_API_KEY")

  if (api_key == "") {
    stop("API key not found. Please check your .env file.")
  }

  # Check if the model name starts with "gpt"
  if (!startsWith(tolower(model), "gpt")) {
    stop("The provided model is not compatible with the chat API.")
  }

  messages <- list(
    list(role = "system", content = "You are a helpful assistant."),
    list(role = "user", content = prompt)
  )

  data <- list(
    model = model,
    messages = messages,
    max_tokens = max_tokens,
    temperature = temperature,
    top_p = top_p,
    frequency_penalty = frequency_penalty,
    presence_penalty = presence_penalty
  )

  # Convert the data to JSON
  json_data <- toJSON(data, auto_unbox = TRUE)

  # Perform the POST request
  for (attempt in 1:max_retries) {
    response <- tryCatch({
      POST(
        url = "https://api.openai.com/v1/chat/completions",
        body = json_data,
        encode = "json",
        add_headers(`Authorization` = paste("Bearer", api_key), `Content-Type` = "application/json"),
        timeout(10)
      )
    }, error = function(e) NULL)

    if (!is.null(response) && response$status_code == 200) {
      content <- fromJSON(content(response, "text", encoding = "UTF-8"))
      message <- as.list(content$choices$message)
      # Success!
      return(message$content)
    } else if (!is.null(response)) {
      cat("Error response from OpenAI:", content(response, "text", encoding = "UTF-8"), "\n")
      return(paste("Error:", response$status_code))
    } else {
      cat("Request timeout or other error. Attempt", attempt, "of", max_retries, "\n")
    }
    if (attempt < max_retries) {
      Sys.sleep(retry_delay)
    }
  }
  stop("Too many retries.")
}

# Function to find a common thematic area for a list of journal names
find_common_theme <- function(journal_names) {
  prompt <- paste("Identify common thematic areas or headings that encompasses the following journals:",
                  paste(journal_names, collapse = ", "), ".",
                  "If the list of journals contains several areas which are difficult to classify und a common heading, include up to three subject areas, in order of frequency",
                  "Just return the heading as a comma-separated list of maximum 3 topics.",
                  "Do not include any other explanation or commentary"
  )
  return(send_openai_request("gpt-3.5-turbo", prompt))
}

rename_headers <- function(df) {
  for (col_name in names(df)) {

    # Extract non-NA values from the column
    non_na_values <- na.omit(df[[col_name]])

    # Check if there are any non-NA values to process
    if (length(non_na_values) > 0) {
      print(paste("Querying OpenAI GPT to create community label for ", col_name))
      # Find the common theme for non-NA values
      common_theme <- tolower(find_common_theme(non_na_values))
      print(common_theme)

      # Rename the column header
      names(df)[names(df) == col_name] <- common_theme
    }
  }
  return(df)
}


