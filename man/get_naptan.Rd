% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/get_naptan.R
\name{get_naptan}
\alias{get_naptan}
\title{get naptan}
\usage{
get_naptan(
  url = "http://naptan.app.dft.gov.uk/datarequest/GTFS.ashx",
  naptan_extra = naptan_missing
)
}
\arguments{
\item{url}{url to naptan in csv format}

\item{naptan_extra}{data frame of missing stops}
}
\description{
download the naptan stop locations
}
