#' get naptan
#'
#' download the naptan stop locations
#' @param url url to naptan in csv format
#' @param naptan_extra data frame of missing stops
#' @export
# get_naptan <- function(url = "http://naptan.app.dft.gov.uk/datarequest/GTFS.ashx", naptan_extra = naptan_missing) {
#   utils::download.file(url = url, destfile = "naptan.zip", mode = "wb")
#   dir.create("temp_naptan")
#   utils::unzip("naptan.zip", exdir = "temp_naptan")
#   naptan <- utils::read.csv("temp_naptan/Stops.txt", stringsAsFactors = FALSE, sep = "\t")
#   unlink("temp_naptan", recursive = TRUE)
#   file.remove("naptan.zip")
#
#   # clean file
#   names(naptan) <- c("stop_id", "stop_code", "stop_name", "stop_lat", "stop_lon", "stop_url", "vehicle_type")
#   naptan <- naptan[, names(naptan_extra)]
#
#   # format
#   naptan$stop_lon <- format(round(naptan$stop_lon, 6), scientific = FALSE)
#   naptan$stop_lat <- format(round(naptan$stop_lat, 6), scientific = FALSE)
#
#   # Append extra data
#   naptan_extra <- naptan_extra[!naptan_extra$stop_id %in% naptan$stop_id, ]
#   naptan <- rbind(naptan, naptan_extra)
#
#   return(naptan)
# }

# buses branch: use this version (has more lat lons). load naptan_missing in whichever R session function called.
get_naptan <- function(url = "http://naptan.app.dft.gov.uk/DataRequest/Naptan.ashx?format=csv", naptan_extra) {
  utils::download.file(url = url, destfile = "naptan.zip", mode = "wb")
  dir.create("temp")
  utils::unzip("naptan.zip", exdir = "temp")
  # buses branch: use data.table for speed
  naptan <- data.table::fread("temp/stops.csv", stringsAsFactors = F)
  unlink("temp", recursive = T)
  file.remove("naptan.zip")

  # clean file
  # buses branch: also include StopType for filtering later
  naptan <- naptan[, c("ATCOCode", "NaptanCode", "CommonName", "Longitude", "Latitude", "StopType")]
  names(naptan) <- c("stop_id", "stop_code", "stop_name", "stop_lon", "stop_lat", "StopType")

  naptan$stop_lon <- format(round(naptan$stop_lon, 6), scientific = FALSE)
  naptan$stop_lat <- format(round(naptan$stop_lat, 6), scientific = FALSE)

  # Append alterative tags

  naptan_extra <- naptan_extra[!naptan_extra$stop_id %in% naptan$stop_id,]
  naptan <- rbind(naptan, naptan_extra, fill = T)

  return(naptan)
}
