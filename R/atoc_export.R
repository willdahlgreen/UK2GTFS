#' Export ATOC stations as GTFS stops.txt
#'
#' @details
#' Export ATOC stations as GTFS stops.txt
#'
#' @param station station SF data frame from the importMSN function
#' @param TI TI object
#' @noRd
#'
station2stops <- function(station, TI) {

  # Discard Unneded Columns
  TI <- TI[, c("TIPLOC code", "NALCO", "TPS Description", "CRS Code")]
  station <- station[, c(
    "Station Name", "CATE Interchange status", "TIPLOC Code",
    "CRS Code", "geometry"
  )]

  jnd <- dplyr::left_join(TI, station, by = c("TIPLOC code" = "TIPLOC Code"))
  station.extra <- station[!station$`TIPLOC Code` %in% jnd$`TIPLOC code`, ]
  station.extra$`TIPLOC code` <- station.extra$`TIPLOC Code`
  station.extra$NALCO <- NA
  station.extra$`CRS Code.y` <- station.extra$`CRS Code`
  station.extra$`TPS Description` <- NA
  station.extra$`CRS Code.x` <- NA
  station.extra <- station.extra[, names(jnd)]
  jnd <- suppressWarnings(dplyr::bind_rows(jnd, station.extra))

  jnd$geometry <- sf::st_sfc(jnd$geometry)
  jnd <- sf::st_sf(jnd)
  sf::st_crs(jnd) <- 4326

  jnd$CRS <- ifelse(is.na(jnd$`CRS Code.y`), jnd$`CRS Code.x`,
                    jnd$`CRS Code.y`)
  jnd$name <- ifelse(is.na(jnd$`TPS Description`), jnd$`Station Name`,
                     jnd$`TPS Description`)

  stops <- jnd[, c("CRS", "TIPLOC code", "name")]
  stops <- stops[!sf::st_is_empty(stops), ]

  stops.final <- stops

  stops.final <- as.data.frame(stops.final)
  stops.final$geometry <- sf::st_sfc(stops.final$geometry)
  stops.final <- sf::st_sf(stops.final)
  sf::st_crs(stops.final) <- 4326
  stops.final <- stops.final[, c("TIPLOC code", "CRS", "name", "geometry")]

  # recorder the match the GTFS stops.txt
  names(stops.final) <- c("stop_id", "stop_code", "stop_name", "geometry")
  coords <- sf::st_coordinates(stops.final)
  stops.final$stop_lat <- coords[, 2]
  stops.final$stop_lon <- coords[, 1]
  # sub metre precison is sufficent
  stops.final$stop_lat <- round(stops.final$stop_lat, 5)
  stops.final$stop_lon <- round(stops.final$stop_lon, 5)
  stops.final <- as.data.frame(stops.final)
  stops.final$geometry <- NULL

  # Built tiploc to CRS lookup
  lookup <- as.data.frame(jnd)
  lookup <- lookup[, c("TIPLOC code", "CRS")]
  lookup$match <- ifelse(is.na(lookup$CRS), lookup$`TIPLOC code`, lookup$CRS)
  lookup <- lookup[, c("TIPLOC code", "match")]
  names(lookup) <- c("TIPLOC", "match")



  results <- list(stops.final, lookup)
  names(results) <- c("stops", "lookup")
  return(results)
}


#' Export ATOC stations and FLF file as transfers.txt
#'
#' @details
#' Export ATOC FLF file as transfers.txt
#'
#' @param station station SF data frame from the importMSN function
#' @param flf imported flf file from importFLF
#' @param path_out Path to save file to
#' @noRd
#'
station2transfers <- function(station, flf, path_out) {

  ### SECTION 4: ############################################################
  # make make the transfers.txt
  # transfer betwwen stations are in the FLF file
  transfers1 <- flf[, c("from", "to", "time")]
  transfers1$time <- transfers1$time * 60
  transfers1$transfer_type <- 2

  # transfer within sations are in the stations file
  transfers2 <- station[, c("TIPLOC Code", "CRS Code", "Minimum Change Time")]
  transfers2 <- as.data.frame(transfers2)
  transfers2$geometry <- NULL

  transfers3 <- transfers2[, c("TIPLOC Code", "CRS Code")]
  names(transfers3) <- c("from_stop_id", "CRS Code")
  transfers1 <- dplyr::left_join(transfers1, transfers3,
                                 by = c("from" = "CRS Code"))
  names(transfers3) <- c("to_stop_id", "CRS Code")
  transfers1 <- dplyr::left_join(transfers1, transfers3,
                                 by = c("to" = "CRS Code"))
  transfers1 <- transfers1[, c("from_stop_id", "to_stop_id",
                               "transfer_type", "time")]
  names(transfers1) <- c("from_stop_id", "to_stop_id",
                         "transfer_type", "min_transfer_time")

  transfers2$min_transfer_time <- as.integer(transfers2$`Minimum Change Time`) * 60
  transfers2$to_stop_id <- transfers2$`TIPLOC Code`
  transfers2$transfer_type <- 2
  names(transfers2) <- c("from_stop_id", "CRS Code", "Minimum Change Time",
                         "min_transfer_time", "to_stop_id", "transfer_type")
  transfers2 <- transfers2[, c("from_stop_id", "to_stop_id", "transfer_type",
                               "min_transfer_time")]

  transfers <- rbind(transfers1, transfers2)
  return(transfers)
}

#' split overlapping start and end dates#
#'
#' @param cal cal object
#' @details split overlapping start and end dates
#' @noRd

splitDates <- function(cal) {

  # get all the dates that
  dates <- c(cal$start_date, cal$end_date)
  dates <- dates[order(dates)]
  # create all unique pairs
  dates.df <- data.frame(
    start_date = dates[seq(1, length(dates) - 1)],
    end_date = dates[seq(2, length(dates))]
  )

  cal.new <- dplyr::left_join(dates.df, cal,
                              by = c("start_date" = "start_date",
                                     "end_date" = "end_date"))

  if ("P" %in% cal$STP) {
    match <- "P"
  } else {
    match <- cal$STP[cal$STP != "C"]
    match <- match[1]
  }

  # fill in the original missing schdule
  for (j in seq(1, nrow(cal.new))) {
    if (is.na(cal.new$UID[j])) {
      st_tmp <- cal.new$start_date[j]
      ed_tmp <- cal.new$end_date[j]
      new.UID <- cal$UID[cal$STP == match & cal$start_date <= st_tmp &
                           cal$end_date >= ed_tmp]
      new.Days <- cal$Days[cal$STP == match & cal$start_date <= st_tmp &
                             cal$end_date >= ed_tmp]
      new.roWID <- cal$rowID[cal$STP == match & cal$start_date <= st_tmp &
                               cal$end_date >= ed_tmp]
      new.ATOC <- cal$`ATOC Code`[cal$STP == match & cal$start_date <= st_tmp &
                                    cal$end_date >= ed_tmp]
      new.Retail <- cal$`Retail Train ID`[cal$STP == match &
                                            cal$start_date <= st_tmp &
                                            cal$end_date >= ed_tmp]
      new.head <- cal$Headcode[cal$STP == match & cal$start_date <= st_tmp &
                                 cal$end_date >= ed_tmp]
      new.Status <- cal$`Train Status`[cal$STP == match &
                                         cal$start_date <= st_tmp &
                                         cal$end_date >= ed_tmp]
      if (length(new.UID) == 1) {
        cal.new$UID[j] <- new.UID
        cal.new$Days[j] <- new.Days
        cal.new$rowID[j] <- new.roWID
        cal.new$`ATOC Code`[j] <- new.ATOC
        cal.new$`Retail Train ID`[j] <- new.Retail
        cal.new$`Train Status`[j] <- new.Status
        cal.new$Headcode[j] <- new.head
        cal.new$STP[j] <- match
      } else if (length(new.UID) > 1) {
        message("Going From")
        print(cal)
        message("To")
        print(cal.new)
        stop()
        # readline(prompt="Press [enter] to continue")print()
      }
    }
  }

  # remove any gaps
  cal.new <- cal.new[!is.na(cal.new$UID), ]

  # remove duplicated rows
  cal.new <- cal.new[!duplicated(cal.new), ]

  # modify end and start dates
  for (j in seq(1, nrow(cal.new))) {
    if (cal.new$STP[j] == "P") {
      # check if end date need changing
      if (j < nrow(cal.new)) {
        if (cal.new$end_date[j] == cal.new$start_date[j + 1]) {
          cal.new$end_date[j] <- (cal.new$end_date[j] - 1)
        }
      }
      # check if start date needs changing
      if (j > 1) {
        if (cal.new$start_date[j] == cal.new$end_date[j - 1]) {
          cal.new$start_date[j] <- (cal.new$start_date[j] + 1)
        }
      }
    }
  }

  # remove cancled trips
  cal.new <- cal.new[cal.new$STP != "C", ]

  # fix duration
  cal.new$duration <- cal.new$end_date - cal.new$start_date + 1

  # remove any zero or negative day schduels
  cal.new <- cal.new[cal.new$duration > 0, ]

  # Append UID to note the changes
  if (nrow(cal.new) > 0) {
    if (nrow(cal.new) < 27) {
      cal.new$UID <- paste0(cal.new$UID, " ", letters[1:nrow(cal.new)])
    } else {
      # Cases where we need extra letters, gives upto 676 ids
      lett <- paste0(rep(letters, each = 26), rep(letters, times = 26))
      cal.new$UID <- paste0(cal.new$UID, " ", lett[1:nrow(cal.new)])
    }
  } else {
    cal.new <- NA
  }


  return(cal.new)
}



#' internal function for matching stop_times to the basic schdule
#'
#' @details
#' Takes in a row of the schdedule and then gets the next row (schedule must
#'    be sorted by rowID)
#'
#' @param schedule.rowID rowID field from schedule object
#' @param stop_times.rowID rowID field from stop_times object
#' @param ncores number of processes for parallel processing (default = 1)
#' @noRd
#'
matchRoutes <- function(schedule.rowID, stop_times.rowID, ncores = 1) {
  schedule_tmp <- matrix(c(schedule.rowID,
                           schedule.rowID[2:length(schedule.rowID)],
                           max(schedule.rowID) + 99999), ncol = 2)

  if (ncores == 1) {
    matches <- lapply(1:nrow(schedule_tmp), function(x) {
      stop_times.rowID[dplyr::between(
        stop_times.rowID,
        schedule_tmp[x, 1],
        schedule_tmp[x, 2]
      )]
    })
  } else {
    CL <- parallel::makeCluster(ncores) # make clusert and set number of core
    parallel::clusterExport(cl = CL, varlist = c("stop_times.rowID",
                                                 "schedule_tmp"),
                            envir = environment())
    parallel::clusterEvalQ(cl = CL, {
      library(dplyr)
    })
    matches <- parallel::parLapply(cl = CL, 1:nrow(schedule_tmp),
                                   function(x) {
      stop_times.rowID[dplyr::between(
        stop_times.rowID,
        schedule_tmp[x, 1],
        schedule_tmp[x, 2]
      )]
    })
    parallel::stopCluster(CL)
  }

  # names(matches) = schedule_tmp[1:10]
  result <- data.frame(
    stop_times.rowID = unlist(matches),
    schedule.rowID = rep(schedule.rowID, times = lengths(matches))
  )

  return(result)
}

# TODO: Does not work within functions, rejig to work in package.
#
#' internal function for cleaning calendar
#'
#' @details
#' check for schdules that don overlay with the day they rund i.e.
#'     Mon - Sat schduel for a sunday only service
#' return a logcal vector of if the calendar is valid
#'
#' @param tmp 1 row dataframe
#' @noRd
#'
checkrows <- function(tmp) {
  # tmp = res.calendar[i,]
  # message(paste0("done ",i))
  if (tmp$duration < 7) {
    days.valid <- weekdays(seq.POSIXt(from = as.POSIXct.Date(tmp$start_date),
                                      to = as.POSIXct.Date(tmp$end_date),
                                      by = "DSTday"))
    days.valid <- tolower(days.valid)
    days.match <- tmp[, c("monday", "tuesday", "wednesday", "thursday",
                          "friday", "saturday", "sunday")]
    days.match <- sapply(days.match, function(x) {
      x == 1
    })
    days.match <- days.match[days.match]
    days.match <- names(days.match)
    if (any(days.valid %in% days.match)) {
      return(TRUE)
    } else {
      return(FALSE)
    }
  } else {
    return(TRUE)
  }
}

# TODO: make mode affect name
#' internal function for contructing longnames of routes
#'
#' @details
#' creates the long name of a route from appopriate variaibles
#'
#' @param routes routes data.frame
#' @param stop_times stop_times data.frame
#' @noRd
#'
longnames <- function(routes, stop_times) {
  stop_times_sub <- dplyr::group_by(stop_times, trip_id)
  stop_times_sub <- dplyr::summarise(stop_times_sub,
    schedule = unique(schedule),
    stop_a = stop_id[stop_sequence == 1],
    # seq = min(stop_sequence),
    stop_b = stop_id[stop_sequence == max(stop_sequence)]
  )

  stop_times_sub$route_long_name <- paste0("Train from ", stop_times_sub$stop_a, " to ", stop_times_sub$stop_b)
  stop_times_sub <- stop_times_sub[!duplicated(stop_times_sub$schedule), ]
  stop_times_sub <- stop_times_sub[, c("schedule", "route_long_name")]

  routes <- dplyr::left_join(routes, stop_times_sub, by = c("rowID" = "schedule"))

  return(routes)
}

#' make calendar
#'
#' @details
#' split overlapping start and end dates
#'
#' @param schedule scheduel data.frame
#' @param ncores number of processes for parallel processing (default = 1)
#' @noRd
#'
makeCalendar <- function(schedule, ncores = 1) {
  # prep the inputs
  calendar <- schedule[, c("Train UID", "Date Runs From", "Date Runs To", "Days Run", "STP indicator", "rowID", "Headcode", "ATOC Code", "Retail Train ID", "Train Status")]
  calendar$`STP indicator` <- as.character(calendar$`STP indicator`)
  # calendar = calendar[order(-calendar$`STP indicator`),]
  names(calendar) <- c("UID", "start_date", "end_date", "Days", "STP", "rowID", "Headcode", "ATOC Code", "Retail Train ID", "Train Status")
  calendar$duration <- calendar$end_date - calendar$start_date + 1

  # UIDs = unique(calendar$UID)
  # length_todo = length(UIDs)
  message(paste0(Sys.time(), " Constructing calendar and calendar_dates"))
  calendar_split <- split(calendar, calendar$UID)


  if (ncores > 1) {
    cl <- parallel::makeCluster(ncores)
    # parallel::clusterExport(
    #   cl = cl,
    #   varlist = c("calendar", "UIDs"),
    #   envir = environment()
    # )
    parallel::clusterEvalQ(cl, {
      loadNamespace("UK2GTFS")
    })
    pbapply::pboptions(use_lb = TRUE)
    res <- pbapply::pblapply(calendar_split,
      # 1:length_todo,
      makeCalendar.inner,
      # UIDs = UIDs,
      # calendar = calendar,
      cl = cl
    )
    parallel::stopCluster(cl)
    rm(cl)
  } else {
    res <- pbapply::pblapply(
      calendar_split,
      # 1:length_todo,
      makeCalendar.inner # ,
      # UIDs = UIDs,
      # calendar = calendar
    )
  }

  res.calendar <- lapply(res, `[[`, 1)
  res.calendar <- dplyr::bind_rows(res.calendar)
  res.calendar_dates <- lapply(res, `[[`, 2)
  res.calendar_dates <- res.calendar_dates[!is.na(res.calendar_dates)]
  res.calendar_dates <- dplyr::bind_rows(res.calendar_dates)

  days <- lapply(res.calendar$Days, function(x) {
    as.integer(substring(x, 1:7, 1:7))
  })
  days <- matrix(unlist(days), ncol = 7, byrow = TRUE)
  days <- as.data.frame(days)
  names(days) <- c("monday", "tuesday", "wednesday", "thursday",
                   "friday", "saturday", "sunday")

  res.calendar <- cbind(res.calendar, days)
  res.calendar$Days <- NULL

  message(paste0(Sys.time(),
                 " Removing trips that only occur on days of the week that are non-operational"))
  res.calendar.split <- split(res.calendar, seq(1, nrow(res.calendar)))


  if (ncores > 1) {
    cl <- parallel::makeCluster(ncores)
    parallel::clusterEvalQ(cl, {
      loadNamespace("UK2GTFS")
    })
    keep <- pbapply::pbsapply(res.calendar.split,
      checkrows,
      cl = cl
    )
    parallel::stopCluster(cl)
    rm(cl)
  } else {
    keep <- pbapply::pbsapply(res.calendar.split, checkrows)
  }

  res.calendar <- res.calendar[keep, ]

  return(list(res.calendar, res.calendar_dates))
}

#' make calendar hleper function
#' @param i row number to do
#' @noRd
#'
makeCalendar.inner <- function(calendar.sub) { # i, UIDs, calendar){
  # UIDs.sub = UIDs[i]
  # calendar.sub = calendar[calendar$UID == UIDs.sub,]
  # calendar.sub = schedule[schedule$`Train UID` == UIDs.sub,]
  if (nrow(calendar.sub) == 1) {
    # make into an single entry
    return(list(calendar.sub, NA))
  } else {
    # check duration and types
    dur <- as.numeric(calendar.sub$duration[calendar.sub$STP != "P"])
    typ <- calendar.sub$STP[calendar.sub$STP != "P"]
    typ.all <- calendar.sub$STP
    if (all(dur == 1) & all(typ == "C") & length(typ) > 0 &
        length(typ.all) == 2) {
      # One Day cancelationss
      # Modify in the calendar_dates.txt
      return(list(
        calendar.sub[calendar.sub$STP == "P", ],
        calendar.sub[calendar.sub$STP != "P", ]
      ))
    } else {
      # check for identical day pattern
      if (length(unique(calendar.sub$Days)) == 1 &
          sum(typ.all == "P") == 1) {
        calendar.new <- UK2GTFS:::splitDates(calendar.sub)
        return(list(calendar.new, NA))
      } else {
        # split by day pattern
        splits <- list()
        daypatterns <- unique(calendar.sub$Days)
        for (k in seq(1, length(daypatterns))) {
          # select for each patter but include cancellations with a
          # different day pattern
          calendar.sub.day <- calendar.sub[calendar.sub$Days == daypatterns[k] | calendar.sub$STP == "C", ]

          if (all(calendar.sub.day$STP == "C")) {
            # ignore cases of only cancleds
            splits[[k]] <- NULL
          } else {
            calendar.new.day <- UK2GTFS:::splitDates(calendar.sub.day)
            # rejects nas
            if (class(calendar.new.day) == "data.frame") {
              calendar.new.day$UID <- paste0(calendar.new.day$UID, k)
              splits[[k]] <- calendar.new.day
            }
          }
        }
        splits <- dplyr::bind_rows(splits)
        return(list(splits, NA))
      }
    }
  }
}

#' Duplicate stop_times
#'
#' @details
#' Function that duplicates top times for trips that have been split into
#'     multiple trips
#'
#' @param calendar calendar data.frame
#' @param stop_times stop_times data.frame
#' @param ncores number of processes for parallel processing (default = 1)
#' @noRd
#'
duplicate.stop_times_alt <- function(calendar, stop_times, ncores = 1) {
  calendar.nodup <- calendar[!duplicated(calendar$rowID), ]
  calendar.dup <- calendar[duplicated(calendar$rowID), ]
  rowID.unique <- as.data.frame(table(calendar.dup$rowID))
  rowID.unique$Var1 <- as.integer(as.character(rowID.unique$Var1))
  stop_times <- dplyr::left_join(stop_times, rowID.unique,
                                 by = c("schedule" = "Var1"))
  stop_times_split <- split(stop_times, stop_times$schedule)

  # TODO: The could handle cases of non duplicated stoptimes within duplicate.stop_times.int
  # rather than splitting and rejoining, would bring code tidyness and speed improvements
  duplicate.stop_times.int <- function(stop_times.tmp) {
    # message(i)
    # stop_times.tmp = stop_times[stop_times$schedule == rowID.unique$Var1[i],]
    # reps = rowID.unique$Freq[i]
    reps <- stop_times.tmp$Freq[1]
    if (is.na(reps)) {
      return(NULL)
    } else {
      index <- rep(seq(1, reps), nrow(stop_times.tmp))
      index <- index[order(index)]
      stop_times.tmp <- stop_times.tmp[rep(seq(1, nrow(stop_times.tmp)), reps), ]
      stop_times.tmp$index <- index
      return(stop_times.tmp)
    }
  }

  if (ncores == 1) {
    stop_times.dup <- pbapply::pblapply(stop_times_split, duplicate.stop_times.int)
  } else {
    cl <- parallel::makeCluster(ncores)
    stop_times.dup <- pbapply::pblapply(stop_times_split,
      duplicate.stop_times.int,
      cl = cl
    )
    parallel::stopCluster(cl)
    rm(cl)
  }

  stop_times.dup <- dplyr::bind_rows(stop_times.dup)
  # stop_times.dup$index <- NULL

  # Join on the nonduplicated trip_ids
  trip.ids.nodup <- calendar.nodup[, c("rowID", "trip_id")]
  stop_times <- dplyr::left_join(stop_times, trip.ids.nodup, by = c("schedule" = "rowID"))
  stop_times <- stop_times[!is.na(stop_times$trip_id), ] # when routes are cancled their stop times are left without valid trip_ids

  # join on the duplicated trip_ids
  calendar2 <- dplyr::group_by(calendar, rowID)
  calendar2 <- dplyr::mutate(calendar2, Index = seq(1, dplyr::n()))

  stop_times.dup$index2 <- as.integer(stop_times.dup$index + 1)
  trip.ids.dup <- calendar2[, c("rowID", "trip_id", "Index")]
  trip.ids.dup <- as.data.frame(trip.ids.dup)
  stop_times.dup <- dplyr::left_join(stop_times.dup, trip.ids.dup, by = c("schedule" = "rowID", "index2" = "Index"))
  stop_times.dup <- stop_times.dup[, c(
    "arrival_time", "departure_time", "stop_id", "stop_sequence",
    "pickup_type", "drop_off_type", "rowID", "schedule", "trip_id"
  )]
  stop_times <- stop_times[, c(
    "arrival_time", "departure_time", "stop_id", "stop_sequence",
    "pickup_type", "drop_off_type", "rowID", "schedule", "trip_id"
  )]

  # stop_times.dup = stop_times.dup[order(stop_times.dup$rowID),]

  stop_times.comb <- rbind(stop_times, stop_times.dup)

  return(stop_times.comb)
}



#' fix times for jounrneys that run past midnight
#'
#' @details
#' When train runs over midnight GTFS requries the stop times to be in
#'    24h+ e.g. 26:30:00
#'
#' @param stop_times stop_times data.frame
#' @param safe logical (default = TRUE) should the check for trains
#'    running more than 24h be perfomed?
#'
#' @details
#' Not running the 24 check is faster, if the check is run a warning
#'    is returned, but the error is not fixed. As the longest train
#'    jounrey in the UK is 13 hours (Aberdeen to Penzance) this is
#'    unlikley to be a problem.
#' @noRd
#'
afterMidnight <- function(stop_times, safe = TRUE) {
  stop_times2 <- stop_times
  # stop_times2$arv = as.integer(paste0(substr(stop_times2$arrival_time,1,2),substr(stop_times2$arrival_time,4,5)))
  # stop_times2$dept = as.integer(paste0(substr(stop_times2$departure_time,1,2),substr(stop_times2$departure_time,4,5)))
  stop_times2$arv <- as.integer(stop_times2$arrival_time)
  stop_times2$dept <- as.integer(stop_times2$departure_time)

  stop_times.summary <- dplyr::group_by(stop_times2, trip_id)
  stop_times.summary <- dplyr::summarise(stop_times.summary,
    dept_first = dept[stop_sequence == 1]
  )

  stop_times2 <- dplyr::left_join(stop_times2, stop_times.summary, by = "trip_id")
  stop_times2$arvfinal <- ifelse(stop_times2$arv < stop_times2$dept_first, stop_times2$arv + 2400, stop_times2$arv)
  stop_times2$depfinal <- ifelse(stop_times2$dept < stop_times2$dept_first, stop_times2$dept + 2400, stop_times2$dept)


  if (safe) {
    # check if any train more than 24 hours
    stop_times.summary2 <- dplyr::group_by(stop_times2, trip_id)
    stop_times.summary2 <- dplyr::summarise(stop_times.summary2,
      arv_last = arvfinal[stop_sequence == max(stop_sequence)],
      arv_max = max(arvfinal, na.rm = TRUE)
    )

    check <- stop_times.summary2$arv_last < stop_times.summary2$arv_max
    if (any(check)) {
      warning("24 hour clock correction will return false results for any trip where total travel time exceeds 24 hours")
    }
  }

  numb2time <- function(numb) {
    numb <- as.character(numb)
    cnt <- nchar(numb)
    if (cnt == 4) {
      numb <- paste0(substr(numb, 1, 2), ":", substr(numb, 3, 4), ":00")
    } else if (cnt == 3) {
      numb <- paste0("0", substr(numb, 1, 1), ":", substr(numb, 2, 3), ":00")
    } else if (cnt == 2) {
      numb <- paste0("00:", numb, ":00")
    } else if (cnt == 1) {
      numb <- paste0("00:0", numb, ":00")
    } else {
      stop("Unknown Time Format")
    }
    return(numb)
  }


  stop_times2$arrival_time <- pbapply::pbsapply(stop_times2$arvfinal, numb2time)
  stop_times2$departure_time <- pbapply::pbsapply(stop_times2$depfinal, numb2time)


  stop_times2 <- stop_times2[, c("trip_id", "arrival_time", "departure_time", "stop_id", "stop_sequence", "pickup_type", "drop_off_type")]
  return(stop_times2)
}



#' Clean Activities
#' @param x character activities
#' @details
#' Change Activities code to pickup and drop_off
#' https://wiki.openraildata.com//index.php?title=Activity_codes
#'
#' @noRd
#'
clean_activities2 <- function(x) {

  # Load Data
  # data("activity_codes")

  x <- data.frame(activity = x, stringsAsFactors = FALSE)
  x <- dplyr::left_join(x, activity_codes, by = c("activity"))
  if (anyNA(x$pickup_type)) {
    message("Unknown Activity codes ", paste(unique(x$activity), collapse = " "), " please report these codes as a GitHub Issue")
    x$pickup_type[is.na(x$pickup_type)] <- 0
    x$drop_off_type[is.na(x$drop_off_type)] <- 0
  }

  x <- x[, c("pickup_type", "drop_off_type")]
  return(x)
}
