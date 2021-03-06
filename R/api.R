# Copyright 2016 Alex Ioannides
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


# ---- classes, methods and predicates ------------------------------------------------------------


#' elasticsearchr predicate functions.
#'
#' Predicate functions for identifying different elasticsearchr object types.
#'
#' @param x An elasticsearchr object.
#' @return Boolean.
#' @name elastic_predicates
NULL

#' @export
#' @rdname elastic_predicates
is_elastic <- function(x) inherits(x, "elastic")

#' @export
#' @rdname elastic_predicates
is_elastic_rescource <- function(x) inherits(x, "elastic_rescource")

#' @export
#' @rdname elastic_predicates
is_elastic_api <- function(x) inherits(x, "elastic_api")

#' @export
#' @rdname elastic_predicates
is_elastic_query <- function(x) inherits(x, "elastic_query")

#' @export
#' @rdname elastic_predicates
is_elastic_aggs <- function(x) inherits(x, "elastic_aggs")

#' @export
#' @rdname elastic_predicates
is_elastic_sort <- function(x) inherits(x, "elastic_sort")


#' elastic_rescource class constructor.
#'
#' Objects of this class contain all of the information required to locate documents in an
#' Elasticsearch cluster.
#'
#' @export
#'
#' @param cluster_url URL to the Elastic cluster.
#' @param index The name of an index on the Elasticsearch cluster.
#' @param doc_type [optional] The name of a document type within the index.
#' @return An \code{elastic_rescource} object.
#'
#' @examples
#' \dontrun{
#' my_data <- elastic("http://localhost:9200", "iris", "data")
#' }
elastic <- function(cluster_url, index, doc_type = NULL) {
  stopifnot(is.character(cluster_url), is.character(index), is.character(doc_type) | is.null(doc_type),
            valid_url(cluster_url))

  if (is.null(doc_type)) {
    valid_cluster_url <- paste(cluster_url, index, "_search", sep = "/")
  } else {
    valid_cluster_url <- paste(cluster_url, index, doc_type, "_search", sep = "/")
  }

  structure(list("search_url" = valid_cluster_url, "cluster_url" = cluster_url,
                 "index" = index, "doc_type" = doc_type), class = c("elastic_rescource", "elastic"))
}


#' Define Elasticsearch query.
#'
#' @export
#'
#' @param json JSON object describing the query that needs to be executed.
#' @param size [optional] The number of documents to return. If left unspecified, then the default
#' if to return all documents.
#' @param source [optional] The fields to return. If left unspecified, then the default is to return
#' all fields.
#' @return An \code{elastic_query} object.
#'
#' @seealso \url{https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl.html}
#'
#' @examples
#' all_docs <- query('{"match_all": {}}')
query <- function(json, size = 0, source = '') {
  stopifnot(valid_json(json))
  api_call <- paste0('"query":', json)
  structure(list("api_call" = api_call, "size" = size, "source" = source),
            class = c("elastic_query", "elastic_api", "elastic"))
}


#' Define Elasticsearch query sort
#'
#' @export
#'
#' @param json JSON object describing the sorting required on the query results.
#' @return An \code{elastic_sort} object.
#'
#' @seealso \url{https://www.elastic.co/guide/en/elasticsearch/reference/5.0/search-request-sort.html}
#'
#' @examples
#' sort_by_key <- sort_on('[{"sort_key": {"order": "asc"}}]')
sort_on <- function(json) {
  stopifnot(valid_json(json))
  api_call <- paste0('"sort":', json)
  structure(list("api_call" = api_call), class = c("elastic_sort", "elastic_api", "elastic"))
}


#' Define Elasticsearch aggregation.
#'
#' @export
#'
#' @param json JSON object describing the aggregation that needs to be executed.
#' @return An \code{elastic_aggs} object.
#'
#' @seealso \url{https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations.html}
#'
#' @examples
#' avg_sepal_width_per_cat <- aggs('{"avg_sepal_width_per_cat": {
#'       "terms": {"field": "species"},
#'       "aggs": {"avg_sepal_width": {"avg": {"field": "sepal_width"}}}}
#' }')
aggs <- function(json) {
  stopifnot(valid_json(json))
  api_call <- paste0('"aggs":', json)
  structure(list("api_call" = api_call), class = c("elastic_aggs", "elastic_api", "elastic"))
}


# ---- operators ----------------------------------------------------------------------------------


#' Index a data frame.
#'
#' Inserting records (or documents) into Elasticsearch is referred to as "indexing' the data. This
#' function considers each row of a data frame as a document to be indexed into an Elasticsearch
#' index.
#'
#' If the data frame contains a column named 'id', then this will be used to assign document ids.
#' Otherwise, Elasticsearch will automatically assigne the documents random ids.
#'
#' @export
#'
#' @param rescource An \code{elastic_rescource} object that contains the information on the
#' Elasticsearch cluster, index and document type, where the indexed data will reside. If this does
#' not already exist, it will be created automatically.
#' @param df data.frame whose rows will be indexed as documents in the Elasticsearch cluster.
#'
#' @seealso \url{https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-index_.html}
#'
#' @examples
#' \dontrun{
#' elastic("http://localhost:9200", "iris", "data") %index% iris
#' }
`%index%` <- function(rescource, df) UseMethod("%index%")

#' @export
`%index%.elastic_rescource` <- function(rescource, df) {
  stopifnot(is_elastic_rescource(rescource), is.data.frame(df), !is.null(rescource$doc_type))
  colnames(df) <- cleaned_field_names(colnames(df))

  df_size_mb <- utils::object.size(df) / (1000 * 1000)
  chunk_size_mb <- 10
  num_data_chunks <- ceiling(df_size_mb / chunk_size_mb)
  num_rows_per_chunk <- ceiling(nrow(df) / num_data_chunks)
  chunk_indices <- lapply(X = seq(1, nrow(df), num_rows_per_chunk),
                          FUN = function(x) c(x, min(nrow(df), x + num_rows_per_chunk - 1)))

  lapply(X = chunk_indices, FUN = function(x) index_bulk_dataframe(rescource, df[x[1]:x[2], ]))
  message("... data successfully indexed", appendLF = FALSE)
}


#' Create Elasticsearch index with custom mapping.
#'
#' Mappings are the closest concept to traditional database 'schema'. This function allows the
#' creation of Elasticsearch indicies with custom mappings. If left unspecified, Elasticsearch will
#' infer the type of each field based on the first document indexed.
#'
#' @export
#'
#' @param rescource An \code{elastic_rescource} object that contains the information on the
#' Elasticsearch cluster, index and document type, where the indexed data will reside. If this does
#' not already exist, it will be created automatically.
#' @param mapping A JSON object containing the mapping details required for the index.
#'
#' @seealso \url{https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping.html}
#'
#' @examples
#' \dontrun{
#' elastic("http://localhost:9200", "iris", "data") %create% mapping_default_simple()
#' }
`%create%` <- function(rescource, mapping) UseMethod("%create%")

#' @export
`%create%.elastic_rescource` <- function(rescource, mapping) {
  response <- httr::PUT(paste(rescource$cluster_url, rescource$index, sep = "/"), body = mapping)
  check_http_code_throw_error(response)
  message(paste("...", rescource$index, "has been created"))
}


#' Delete Elasticsearch index.
#'
#' Delete all of the documents within a particular document type (if specified), or delete an
#' entire index (if the document type is unspecified.)
#'
#' @export
#'
#' @param rescource An \code{elastic_rescource} object that contains the information on the
#' Elasticsearch cluster, index and document type, where the indexed data will reside. If this does
#' not already exist, it will be created automatically.
#' @param approve Must be equal to \code{"TRUE"} for deletion for all documents in a rescource,
#' OR be a character vector of document ids if only specific documents need to be deleted.
#'
#' @examples
#' \dontrun{
#' elastic("http://localhost:9200", "iris", "data") %delete% TRUE
#' }
`%delete%` <- function(rescource, approve) UseMethod("%delete%")

#' @export
`%delete%.elastic_rescource` <- function(rescource, approve) {
  if (is.character(approve) & is.vector(approve)) {
    ids <- approve
  } else {
    if (approve != TRUE) stop("please approve deletion") else ids <- NULL
  }

  if (is.null(ids)) {
    if (is.null(rescource$doc_type)) {
      response <- httr::DELETE(paste(rescource$cluster_url, rescource$index, sep = "/"))
      check_http_code_throw_error(response)
      message(paste0("... ", rescource$index, " has been deleted"))
    } else {
      api_call_payload <- '{"query": {"match_all": {}}}'
      doc_type_ids <- as.vector(scroll_search(rescource, api_call_payload, extract_id_results))
      metadata <- create_metadata("delete", rescource$index, rescource$doc_type, doc_type_ids)
      deletions_file <- create_bulk_delete_file(metadata)
      response <- httr::PUT(url = rescource$cluster_url,
                            path = "/_bulk",
                            body = httr::upload_file(deletions_file))

      file.remove(deletions_file)
      check_http_code_throw_error(response)
      message(paste0("... ", rescource$index, "/", rescource$doc_type, " has been deleted"))
    }
  } else {
    metadata <- create_metadata("delete", rescource$index, rescource$doc_type, ids)
    deletions_file <- create_bulk_delete_file(metadata)
    response <- httr::PUT(url = rescource$cluster_url,
                          path = "/_bulk",
                          body = httr::upload_file(deletions_file))

    file.remove(deletions_file)
    check_http_code_throw_error(response)
    message(paste0("... ", paste0(ids, collapse = ", "), " have been deleted"))
  }
}


#' Execute query or search.
#'
#' @export
#'
#' @param rescource An \code{elastic_rescource} object that contains the information on the
#' Elasticsearch cluster, index and document type, where the indexed data will reside. If this does
#' not already exist, it will be created automatically.
#' @param search \code{elastic_query} or \code{elastic_aggs} object.
#' @return A data.frame of search or aggregation results.
#'
#' @examples
#' \dontrun{
#' results <- elastic("http://localhost:9200", "iris", "data") %search% query('{"match_all": {}}')
#' head(results)
#' #   sepal_length sepal_width petal_length petal_width species
#' # 1          4.8         3.0          1.4         0.1  setosa
#' # 2          4.3         3.0          1.1         0.1  setosa
#' # 3          5.8         4.0          1.2         0.2  setosa
#' # 4          5.1         3.5          1.4         0.3  setosa
#' # 5          5.2         3.5          1.5         0.2  setosa
#' # 6          5.2         3.4          1.4         0.2  setosa
#' }
`%search%` <- function(rescource, search) UseMethod("%search%")

#' @export
`%search%.elastic` <- function(rescource, search) {
  stopifnot(is_elastic_rescource(rescource) & is_elastic_api(search))

  if (is_elastic_query(search)) {
    if (search$size != 0) {
      if (search$source != '') {
        api_call_payload <- paste0('{"size":', search$size, ', ', '"_source": ', search$source, ', ', search$api_call, '}')
        return(from_size_search(rescource, api_call_payload))
      } else {
        api_call_payload <- paste0('{"size":', search$size, ', ', search$api_call, '}')
        return(from_size_search(rescource, api_call_payload))
      }
    } else {
      if (search$source != '') {
        api_call_payload <- paste0('{"size": 10000', ', ', '"_source": ', search$source, ', ', search$api_call, '}')
        return(from_size_search(rescource, api_call_payload))
      } else {
        api_call_payload <- paste0('{"size": 10000', ', ', search$api_call, '}')
        return(scroll_search(rescource, api_call_payload))
      }
    }
  } else {
    api_call_payload <- paste0('{', search$api_call, '}')
    return(from_size_search(rescource, api_call_payload))
  }
}


#' Define Elasticsearch aggregation on a secific subset of documents.
#'
#' Sometimes it is necessary to perform an aggregation on the results of a query (i.e. on a subset
#' of all the available documents). This is achieved by adding an \code{aggs} object to a
#' \code{query} object.
#'
#' @export
#'
#' @param x \code{elastic_query} object.
#' @param y \code{elastic_aggs} or \code{elastic_sort} object.
#' @return \code{elastic_aggs} object that contains the query information required for the
#' aggregation.
#'
#' @examples
#' all_docs <- query('{"match_all": {}}')
#' avg_sepal_width_per_cat <- aggs('{"avg_sepal_width_per_cat": {
#'       "terms": {"field": "species"},
#'       "aggs": {"avg_sepal_width": {"avg": {"field": "sepal_width"}}}}
#' }')
#' all_docs + avg_sepal_width_per_cat
#'
#' sort_by_sepal_width <- sort_on('[{"sepal_width": {"order": "asc"}}]')
#' all_docs + sort_by_sepal_width
`+.elastic_api` <- function(x, y) {
  stopifnot(is_elastic_query(x) & is_elastic_aggs(y) |
              is_elastic_aggs(x) & is_elastic_query(y) |
              is_elastic_query(x) & is_elastic_sort(y) |
              is_elastic_sort(x) & is_elastic_query(y))

  if (is_elastic_query(x) & is_elastic_sort(y) | is_elastic_query(y) & is_elastic_sort(x)) {
    query_size <- if (is_elastic_query(x)) x$size else y$size
    api_call <- paste0(x$api_call, ',', y$api_call)
    structure(list("api_call" = api_call, "size" = query_size),
              class = c("elastic_query", "elastic_api", "elastic"))

  } else if (is_elastic_query(x) & is_elastic_aggs(y) | is_elastic_query(y) & is_elastic_aggs(x)) {
    combined_call <- paste0('"size": 0,', x$api_call, ',', y$api_call)
    structure(list(api_call = combined_call), class = c("elastic_aggs", "elastic_api", "elastic"))
  }
}


#' Pretty-print aggs and query JSON objects.
#'
#' @export
#'
#' @param x \code{elastic_query} or \code{elastic_aggs} object.
#' @param ... For consitency with all other \code{print} methods.
#' @return Character string of pretty-printed JSON object.
#'
#' @examples
#' all_docs <- query('{"match_all": {}}')
#' print(all_docs)
print.elastic_api <- function(x, ...) {
  complete_json <- paste0('{', x$api_call, '}')
  jsonlite::prettify(complete_json)
}
