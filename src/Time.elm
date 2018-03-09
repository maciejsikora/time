effect module Time where { subscription = MySub } exposing
  ( Posix
  , now
  , posixToMillis
  , millisToPosix
  , Zone
  , utc
  , toYear
  , toMonth
  , toDay
  , toWeekday
  , toHour
  , toMinute
  , toSecond
  , toMillis
  , every
  , Month(..)
  , Weekday(..)
  , customZone
  )


{-| Library for working with time and time zones.

# Time
@docs Posix, now, posixToMillis, millisToPosix

# Time Zones
@docs Zone, utc, here

# Human Times
@docs toYear, toMonth, toDay, toWeekday, toHour, toMinute, toSecond, toMillis

# Time Subscriptions
@docs every

# Weeks and Months
@docs Weekday(..), Month(..)

# Time Zone Builder
@docs customZone

-}


import Basics exposing (..)
import Dict
import Elm.Kernel.Scheduler
import Elm.Kernel.Time
import List exposing ((::))
import Maybe exposing (Maybe(..))
import Platform
import Platform.Sub exposing (Sub)
import String exposing (String)
import Task exposing (Task)



-- POSIX


{-| A computer representation of time. It is the same all over Earth, so if we
have a phone call or meeting at a certain POSIX time, there is no ambiguity.

It is very hard for humans to _read_ a POSIX time though, so we use functions
like [`toHour`](#toHour) and [`toMinute`](#toMinute) to `view` them.
-}
type Posix = Posix Int


{-| Get the POSIX time at the moment when this task is run.
-}
now : Task x Posix
now =
  Elm.Kernel.Time.now Posix


{-| Turn a `Posix` time into the number of milliseconds since 1970 January 1
at 00:00:00 UTC. It was a Thursday.
-}
posixToMillis : Posix -> Int
posixToMillis (Posix millis) =
  millis


{-| Turn milliseconds into a `Posix` time.
-}
millisToPosix : Int -> Posix
millisToPosix =
  Posix



-- TIME ZONES


{-| Information about a particular time zone.

The [IANA Time Zone Database][iana] tracks things like UTC offsets and
daylight-saving rules so that you can turn a `Posix` time into local times
within a time zone.

Did you know that in California the times change from 3pm PST to 3pm PDT to
capture whether it is daylight-saving time? The database tracks those
abbreviation changes too. (Tons of time zones do that actually.)

[iana]: https://www.iana.org/time-zones
-}
type Zone =
  Zone String (List Era)


type alias Era =
  { start : Int
  , offset : Int
  , abbr : String
  }


{-| The time zone for Coordinated Universal Time ([UTC][])

The `utc` zone has no time adjustments. It never observes daylight-saving
time and it never shifts around based on political restructuring.

[UTC]: https://en.wikipedia.org/wiki/Coordinated_Universal_Time
-}
utc : Zone
utc =
  Zone "Etc/Utc" []


{-| **Primarily for library authors.**

I am proposing [a JavaScript API][api] that would allow us to expose a function
like this:

    here : Task x Zone

Until that becomes possible, it is necessary to load information from the IANA
time zone database yourself, and different people will want to do this in
different ways. For example, if your users all live in one time-zone, you may
just want to have the data in Elm. If you have users everywhere, maybe you want
to load time zone information as needed through HTTP requests? Or all at once
and cache it?

To avoid forcing everyone to use one strategy, the `customZone` function allows
you to create a `Zone` with data you have obtained however you please. This
means libraries can hard-code the data, provide HTTP requests, etc. and you can
pick the strategy that is best for you.

**Note:** If you prefer the `here` API, try to get TC39 to consider [this
JavaScript API][api] for time zones!
-}
customZone : String -> List Era -> Maybe Zone
customZone abbr eras =
  Debug.crash "TODO"



-- DATES


{-| What year is it?!

    import Time exposing (millisToPosix, utc, year)

    year utc (millisToPosix 0) == 1970
    year nyc (millisToPosix 0) == 1969

    -- pretend `nyc` is the `Zone` for America/New_York.
-}
toYear : Zone -> Posix -> Int
toYear zone time =
  (toCivil (toAdjustedMinutes zone time)).year


{-| What month is it?!

    import Time exposing (millisToPosix, month, utc)

    month utc (millisToPosix 0) == Jan
    month nyc (millisToPosix 0) == Dec

    -- pretend `nyc` is the `Zone` for America/New_York.
-}
month : Zone -> Posix -> Month
month zone time =
  case (toCivil (toAdjustedMinutes zone time)).month of
    1  -> Jan
    2  -> Feb
    3  -> Mar
    4  -> Apr
    5  -> May
    6  -> Jun
    7  -> Jul
    8  -> Aug
    9  -> Sep
    10 -> Oct
    11 -> Nov
    _  -> Dec


{-| What day is it?!

    import Time exposing (day, millisToPosix, utc)

    day utc (millisToPosix 0) == 1
    day nyc (millisToPosix 0) == 31

    -- pretend `nyc` is the `Zone` for America/New_York.
-}
day : Zone -> Posix -> Int
day zone time =
  (toCivil (toAdjustedMinutes zone time)).day


{-| What day of the week is it?

    import Time exposing (millisToPosix, utc, weekday)

    weekday utc (millisToPosix 0) == Thu
    weekday nyc (millisToPosix 0) == Wed

    -- pretend `nyc` is the `Zone` for America/New_York.
-}
weekday : Zone -> Posix -> Weekday
weekday zone time =
  case modBy 7 (toAdjustedMinutes zone time // (60 * 24)) of
    0 -> Thu
    1 -> Fri
    2 -> Sun
    3 -> Sat
    4 -> Mon
    5 -> Tue
    _ -> Wed


{-| What hour is it?

    import Time exposing (hour, millisToPosix, utc)

    hour utc (millisToPosix 0) == 0  -- 12am
    hour nyc (millisToPosix 0) == 19 -- 7pm

    -- pretend `nyc` is the `Zone` for America/New_York.
-}
hour : Zone -> Posix -> Int
hour zone time =
  modBy 24 (toAdjustedMinutes zone time // 60)


{-|
    import Time exposing (millisToPosix, minute, utc)

    minute utc (millisToPosix 0) == 0

This can be different in different time zones. Some time zones are offset
by a half-hour!
-}
minute : Zone -> Posix -> Int
minute zone time =
  modBy 60 (toAdjustedMinutes zone time)


{-|
    import Time exposing (millisToPosix, second, utc)

    second utc (millisToPosix    0) == 0
    second utc (millisToPosix 1234) == 1
    second utc (millisToPosix 5678) == 5
-}
second : Date -> Int
second date =
  modBy 60 (posixToMillis date.time // 1000)


{-|
    import Time exposing (millis, millisToPosix, utc)

    millis utc (millisToPosix    0) == 0
    millis utc (millisToPosix 1234) == 234
    millis utc (millisToPosix 5678) == 678
-}
millis : Date -> Int
millis date =
  modBy 1000 (posixToMillis date.time)



-- DATE HELPERS


toAdjustedMinutes : Zone -> Posix -> Int
toAdjustedMinutes (Zone _ eras) time =
  toAdjustedMinutesHelp (posixToMillis time // 60000) eras


toAdjustedMinutesHelp : Int -> List Era -> Int
toAdjustedMinutesHelp posixMinutes eras =
  case eras of
    [] ->
      posixMinutes

    era :: olderEras ->
      if era.start < posixMinutes then
        posixMinutes + era.offset
      else
        toAdjustedMinutesHelp posixMinutes olderEras


toCivil : Int -> { year : Int, month : Int, day : Int }
toCivil minutes =
  let
    rawDay    = (minutes // (60 * 24)) + 719468
    era       = (if rawDay >= 0 then rawDay else rawDay - 146096) // 146097
    dayOfEra  = rawDay - era * 146097 -- [0, 146096]
    yearOfEra = (dayOfEra - dayOfEra // 1460 + dayOfEra // 36524 - dayOfEra // 146096) // 365 -- [0, 399]
    year      = yearOfEra + era * 400
    dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra // 4 - yearOfEra // 100) -- [0, 365]
    mp        = (5 * dayOfYear + 2) // 153 -- [0, 11]
    month     = mp + (if mp < 10 then 3 else -9) -- [1, 12]
  in
  { year = year + (if month <= 2 then 1 else 0)
  , month = month
  , day = dayOfYear - (153 * mp + 2) // 5 + 1 -- [1, 31]
  }



-- TIME TRAVEL


-- getDaysInMonth : TimeZone -> Year -> Month -> List Int
-- diff : Unit -> Date -> Date -> Int
-- travel : Unit -> Int -> Date -> Date
-- type Unit = Years | Months | Days | Hours | Minutes | Seconds | Millis



-- WEEKDAYS AND MONTHS


{-| Represents a `Weekday` so that you can convert it to a `String` or `Int`
however you please. For example, if you need the Japanese representation, you
can say:

    toJapaneseWeekday : Weekday -> String
    toJapaneseWeekday weekday =
      case weekday of
        Mon -> "月"
        Tue -> "火"
        Wed -> "水"
        Thu -> "木"
        Fri -> "金"
        Sat -> "土"
        Sun -> "日"
-}
type Weekday = Mon | Tue | Wed | Thu | Fri | Sat | Sun


{-| Represents a `Month` so that you can convert it to a `String` or `Int`
however you please. For example, if you need the Danish representation, you
can say:

    toDanishMonth : Month -> String
    toDanishMonth month =
      case month of
        Jan -> "januar"
        Feb -> "februar"
        Mar -> "marts"
        Apr -> "april"
        May -> "maj"
        Jun -> "juni"
        Jul -> "juli"
        Aug -> "august"
        Sep -> "september"
        Oct -> "oktober"
        Nov -> "november"
        Dec -> "december"
-}
type Month = Jan | Feb | Mar | Apr | May | Jun | Jul | Aug | Sep | Oct | Nov | Dec



-- SUBSCRIPTIONS


{-|

**Note:** this function is not for animation!
-}
every : Unit -> Int -> (Posix -> msg) -> Sub msg
every interval tagger =
  subscription (Every interval tagger)


type MySub msg =
  Every Time (Time -> msg)


subMap : (a -> b) -> MySub a -> MySub b
subMap f (Every interval tagger) =
  Every interval (f << tagger)



-- EFFECT MANAGER


type alias State msg =
  { taggers : Taggers msg
  , processes : Processes
  }


type alias Processes =
  Dict.Dict Time Platform.ProcessId


type alias Taggers msg =
  Dict.Dict Time (List (Time -> msg))


init : Task Never (State msg)
init =
  Task.succeed (State Dict.empty Dict.empty)


onEffects : Platform.Router msg Time -> List (MySub msg) -> State msg -> Task Never (State msg)
onEffects router subs {processes} =
  let
    newTaggers =
      List.foldl addMySub Dict.empty subs

    leftStep interval taggers (spawnList, existingDict, killTask) =
      (interval :: spawnList, existingDict, killTask)

    bothStep interval taggers id (spawnList, existingDict, killTask) =
      (spawnList, Dict.insert interval id existingDict, killTask)

    rightStep _ id (spawnList, existingDict, killTask) =
      ( spawnList
      , existingDict
      , Elm.Kernel.Scheduler.kill id
          |> Task.andThen (\_ -> killTask)
      )

    (spawnList, existingDict, killTask) =
      Dict.merge
        leftStep
        bothStep
        rightStep
        newTaggers
        processes
        ([], Dict.empty, Task.succeed ())
  in
    killTask
      |> Task.andThen (\_ -> spawnHelp router spawnList existingDict)
      |> Task.andThen (\newProcesses -> Task.succeed (State newTaggers newProcesses))


addMySub : MySub msg -> Taggers msg -> Taggers msg
addMySub (Every interval tagger) state =
  case Dict.get interval state of
    Nothing ->
      Dict.insert interval [tagger] state

    Just taggers ->
      Dict.insert interval (tagger :: taggers) state


spawnHelp : Platform.Router msg Time -> List Time -> Processes -> Task.Task x Processes
spawnHelp router intervals processes =
  case intervals of
    [] ->
      Task.succeed processes

    interval :: rest ->
      let
        spawnTimer =
          Elm.Kernel.Scheduler.spawn (setInterval interval (Platform.sendToSelf router interval))

        spawnRest id =
          spawnHelp router rest (Dict.insert interval id processes)
      in
        spawnTimer
          |> Task.andThen spawnRest


onSelfMsg : Platform.Router msg Time -> Time -> State msg -> Task Never (State msg)
onSelfMsg router interval state =
  case Dict.get interval state.taggers of
    Nothing ->
      Task.succeed state

    Just taggers ->
      let
        tellTaggers time =
          Task.sequence (List.map (\tagger -> Platform.sendToApp router (tagger time)) taggers)
      in
        now
          |> Task.andThen tellTaggers
          |> Task.andThen (\_ -> Task.succeed state)


setInterval : Time -> Task Never () -> Task x Never
setInterval =
  Elm.Kernel.Time.setInterval
