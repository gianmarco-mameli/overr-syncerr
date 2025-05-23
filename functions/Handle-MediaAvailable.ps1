function Handle-MediaAvailable {
    param ([psobject]$payload)
	
	 # Ensure Media Available handling is enabled
    if (-not $enableMediaAvailableHandling) {
        Log-Message -Type "WRN" -Message "Media Available handling is disabled."
        return
    }
	
    # Extract relevant information from the payload
    $mediaType = $payload.media.media_type
    $tmdbId = $payload.media.tmdbId
    $tvdbId = $payload.media.tvdbId
    $plexUsername = $payload.request.requestedBy_username

    Log-Message -Type "INF" -Message "Processing $mediaType request for Plex user: $plexUsername with TMDB ID: $tmdbId"

    # Ensure that Plex host and token are set
    if (-not $plexHost -or -not $plexToken) {
        Log-Message -Type "ERR" -Message "Plex host or token not set. Cannot proceed."
        return
    }

    # Handling movies
    if ($mediaType -eq "movie") {
        $sectionId = $moviesSectionId
        $mediaTypeForSearch = "1"  # Movie type for Plex API

        # API call to get movie title and release date
        $movieLookupUrl = "$overseerrUrl/movie/$tmdbId"
        Log-Message -Type "INF" -Message "Movie Lookup URL: $movieLookupUrl"
        try {
            $headers = @{
                'X-Api-Key' = $overseerrApiKey
            }
            $movieDetails = Invoke-RestMethod -Uri $movieLookupUrl -Method Get -Headers $headers
            $title = $movieDetails.title
            $releaseDate = $movieDetails.releaseDate
            $year = $releaseDate.Split('-')[0]  # Extract year from release date
        } catch {
            Log-Message -Type "ERR" -Message"Error fetching movie details: $_"
            return
        }
    }

    # Handling TV shows (including anime)
    elseif ($mediaType -eq "tv") {
        $sectionId = $seriesSectionId
        $mediaTypeForSearch = "2"  # TV type for Plex API

        # API call to check seriesType and get series title and year
        if ($null -ne $tmdbId) {
            $seriesLookupUrl = "$overseerrUrl/service/sonarr/lookup/$tmdbId"
            Log-Message -Type "INF" -Message "Series Lookup URL (TMDB): $seriesLookupUrl"
        } elseif ($null -ne $tvdbId) {
            $seriesLookupUrl = "$overseerrUrl/service/sonarr/lookup/$tvdbId?type=tvdb"
            Log-Message -Type "INF" -Message "Series Lookup URL (TVDB): $seriesLookupUrl"
        } else {
            Log-Message -Type "ERR" -Message "Both TMDB ID and TVDB ID are missing."
            return
        }

        try {
            $headers = @{
                'X-Api-Key' = $overseerrApiKey
            }
            $seriesDetails = Invoke-RestMethod -Uri $seriesLookupUrl -Method Get -Headers $headers
            $matchedSeries = $seriesDetails | Where-Object { $_.tmdbId -eq $tmdbId -or $_.tvdbId -eq $tvdbId }
            if ($null -eq $matchedSeries) {
                Log-Message -Type "ERR" -Message "No matching series found for tmdbId: $tmdbId or tvdbId: $tvdbId"
                return
            }
            $title = $matchedSeries.title
            $year = $matchedSeries.year
            if ($matchedSeries.seriesType -eq "anime") {
                $sectionId = $animeSectionId
            }
        } catch {
            Log-Message -Type "ERR" -Message "Error fetching series details: $_"
            return
        }
    } else {
        Log-Message -Type "ERR" -Message "Unsupported media type: $mediaType"
        return
    }

    Log-Message -Type "SUC" -Message "Extracted Title: $title"
    Log-Message -Type "SUC" -Message "Extracted Year: $year"

    # Search for the media item in Plex using the title and year
    $searchUrl = "$plexHost/library/sections/$sectionId/all?type=$mediaTypeForSearch&title=" + [System.Uri]::EscapeDataString($title) + "&year=$year&X-Plex-Token=$plexToken"
   
    try {
        $mediaItems = Invoke-RestMethod -Uri $searchUrl -Method Get -ContentType "application/xml"
    } catch {
        Log-Message -Type "ERR" -Message "Error contacting Plex server: $_"
        return
    }

    try {
        if ($mediaType -eq "movie") {
            $mediaItem = $mediaItems.MediaContainer.Video | Where-Object { $_.title -eq $title -and $_.year -eq $year }
        } elseif ($mediaType -eq "tv") {
            $mediaItem = $mediaItems.MediaContainer.Directory | Where-Object { $_.title -eq $title -and $_.year -eq $year }
        }
    } catch {
        Log-Message -Type "ERR" -Message "Error parsing Plex server response: $_"
        return
    }

    if ($null -eq $mediaItem) {
        Log-Message -Type "ERR" -Message "Media item not found after filtering."
        return
    }

    $ratingKey = $mediaItem.ratingKey
    Log-Message -Type "SUC" -Message "Extracted Rating Key: $ratingKey"

    # Call Add-TagToMedia with the appropriate parameters
    Add-TagToMedia -newTag $plexUsername
	
	# Set the preferred audio track for the user
    if ($enableAudioPref){
	Set-AudioTrack -ratingKey $ratingKey -plexUsername $plexUsername
	}
}
