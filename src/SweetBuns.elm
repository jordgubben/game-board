module SweetBuns exposing (..)

import Random exposing (Seed)
import Array
import Set exposing (Set)
import Dict
import Time exposing (Time, second)
import Delay
import Task
import Html exposing (Html, text)
import Html.Attributes as Att exposing (id, class, style)
import Html.Events as Ev exposing (onMouseEnter, onMouseLeave, onClick)
import Sprite exposing (Sprite)
import Grid exposing (..)


main : Program Never Model Msg
main =
    Html.program
        { init = ( initialModel, Task.perform IntiGame Time.now )
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


{-| Complete game model
-}
type alias Model =
    { selectedTile : Maybe Coords
    , things : Grid Thingy
    , moveCount : Int
    , seed : Seed
    }


initialModel : Model
initialModel =
    { selectedTile = Nothing
    , things = initialThings
    , moveCount = 0
    , seed = Random.initialSeed 0
    }


{-| Overall game messages
-}
type Msg
    = SelectTile Coords
    | Fall
    | Spawn
    | Collect
    | IntiGame Time
    | RestartGame


type Thingy
    = Bun (Maybe Flavour)
    | Flour (Maybe Flavour)
    | Water (Maybe Flavour)
    | Flavouring Flavour
    | Obstacle


type Flavour
    = Sugar
    | Chocolate
    | Chilli


type FloorTile
    = PlainTile
    | Spawner (List Thingy)
    | BunCollector
    | WallTile


{-| Complete tile used produced when rendering
-}
type alias RenderableTile =
    { content : Maybe Thingy
    , highlight : Bool
    , floor : FloorTile
    }



-- # UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        IntiGame time ->
            ( initGame time model, Cmd.none )

        RestartGame ->
            ( restartGame model, Cmd.none )

        SelectTile coords ->
            if not <| isGameOver kitchenLevel model.things then
                selectTile coords model
            else
                ( model, Cmd.none )

        Spawn ->
            ( spawnThings model, Cmd.none )

        Fall ->
            ( { model
                | things = applyGravity kitchenLevel model.things
              }
            , Delay.after 1 second Collect
            )

        Collect ->
            ( { model
                | things = collectThings kitchenLevel model.things
              }
            , Cmd.none
            )


{-| Start game with a half full board.
-}
initGame : Time -> Model -> Model
initGame time model =
    let
        seed =
            time |> Time.inMilliseconds |> round |> Random.initialSeed

        ( newThings, seed_ ) =
            fillBoard seed
    in
        { model | seed = seed_, things = Dict.union model.things newThings }


restartGame : Model -> Model
restartGame model =
    let
        ( newThings, seed_ ) =
            fillBoard model.seed
    in
        { model | seed = seed_, things = Dict.union initialThings newThings }


{-| Fill board to the brim with various things
-}
fillBoard : Seed -> ( Grid Thingy, Seed )
fillBoard seed =
    let
        filledRegion =
            { boardSize | height = boardSize.height - 1 }

        --
        -- Start with more Water and Flour than Flavouring
        filler =
            [ Water Nothing
            , Water Nothing
            , Flour Nothing
            , Flour Nothing
            , Flavouring Sugar
            , Flavouring Chilli
            , Flavouring Chocolate
            ]
    in
        Grid.drawBox () filledRegion
            |> Grid.translate ( 0, 0 - filledRegion.height )
            |> Dict.foldl
                (\coords _ ( things, seed ) ->
                    let
                        ( newThing, seed_ ) =
                            pickRandom seed filler
                    in
                        ( Grid.put coords (newThing |> Maybe.withDefault Obstacle) things
                        , seed_
                        )
                )
                ( Grid.empty, seed )


{-| Handle players selection of a tile.
If no tile has been selcted, then just select it.
If a tile is already selected, then attempt to move.
-}
selectTile : Coords -> Model -> ( Model, Cmd Msg )
selectTile coords model =
    case model.selectedTile of
        Just moverCoords ->
            let
                things_ =
                    attemptMove
                        (kitchenLevel
                            |> Dict.filter (always isObstacleTile)
                            |> Dict.keys
                            |> Set.fromList
                        )
                        moverCoords
                        coords
                        model.things
            in
                ( { model
                    | things = things_
                    , selectedTile = Nothing
                    , moveCount = model.moveCount + 1
                  }
                , if model.things /= things_ then
                    Delay.after 0.25 second Spawn
                  else
                    Cmd.none
                )

        Nothing ->
            ( { model | selectedTile = Just coords }, Cmd.none )


isGameOver : Grid FloorTile -> Grid Thingy -> Bool
isGameOver floor things =
    let
        spawnPoints : Set Coords
        spawnPoints =
            findSpawnPoints floor
                |> List.map Tuple.first
                |> Set.fromList

        occupants : Set Coords
        occupants =
            things
                |> Dict.keys
                |> Set.fromList
    in
        Set.diff
            spawnPoints
            occupants
            |> Set.isEmpty


{-| Spawn ingredients at spawn points
-}
spawnThings : Model -> Model
spawnThings model =
    let
        ( spawnedThing, seed_ ) =
            spawnSingelThingRnd model.seed kitchenLevel (model.things |> Dict.keys |> Set.fromList)

        things_ =
            spawnedThing
                |> Maybe.map
                    (\( coords, thing ) ->
                        Dict.insert coords thing model.things
                    )
                |> Maybe.withDefault model.things
    in
        { model | things = things_, seed = seed_ }


spawnSingelThingRnd : Seed -> Grid FloorTile -> Set Coords -> ( Maybe ( Coords, Thingy ), Seed )
spawnSingelThingRnd seed level spawnObstacles =
    let
        -- Pick a random unoccupied spawners coordinates
        ( singlePoint, seed_ ) =
            pickRandom seed
                (findSpawnPoints level
                    |> List.filter (Tuple.first >> (flip Set.member) spawnObstacles >> not)
                )
    in
        ( case singlePoint of
            Just ( coords, things ) ->
                let
                    ( rndThing, seed__ ) =
                        pickRandom seed_ things
                in
                    rndThing
                        |> Maybe.map (\t -> Just ( coords, t ))
                        |> Maybe.withDefault Nothing

            Nothing ->
                Nothing
        , seed_
        )


findSpawnPoints : Grid FloorTile -> List ( Coords, List Thingy )
findSpawnPoints level =
    level
        |> Dict.toList
        |> List.filterMap
            (\( coords, tile ) ->
                case tile of
                    Spawner thing ->
                        Just ( coords, thing )

                    _ ->
                        Nothing
            )


{-| Pick a random element from a list
-}
pickRandom : Seed -> List a -> ( Maybe a, Seed )
pickRandom seed list =
    let
        ( pointsToDrop, seed_ ) =
            (Random.step (Random.int 0 (List.length list - 1)) seed)
    in
        ( list
            |> List.drop pointsToDrop
            |> List.head
        , seed_
        )


{-| Handle players attempt to move something
-}
attemptMove : Set Coords -> Coords -> Coords -> Grid Thingy -> Grid Thingy
attemptMove terrain from to things =
    if isValidMove from to && not (Set.member to terrain) then
        let
            things_ =
                move from to things
        in
            -- If movement could not be prefomed in any other way,
            -- Then let the things teade places
            if things == things_ then
                Grid.swap from to things
            else
                things_
    else
        things


{-| Determine if a move from one place to another is valid, irrespective of environment.
-}
isValidMove : Coords -> Coords -> Bool
isValidMove from to =
    let
        ( fromX, fromY ) =
            from

        ( toX, toY ) =
            to

        ( dx, dy ) =
            ( toX - fromX, toY - fromY )
    in
        (-1 <= dx && dx <= 1) && (-1 <= dy && dy <= 1)


isStable : Grid FloorTile -> Grid Thingy -> Bool
isStable floor things =
    things == applyGravity floor things


{-| Let things fall down where possible, poretially causing mixing of ingredients.
-}
applyGravity : Grid FloorTile -> Grid Thingy -> Grid Thingy
applyGravity level things =
    let
        ( fallers, obstacleThings ) =
            Dict.partition (always isFaller) things

        obstacles : Set Coords
        obstacles =
            Set.union
                (level
                    |> Dict.filter (always isObstacleTile)
                    |> Dict.keys
                    |> Set.fromList
                )
                (obstacleThings |> Dict.keys |> Set.fromList)

        fallers_ =
            List.foldl
                (\( x, y ) m ->
                    if not (Set.member ( x, y - 1 ) obstacles) then
                        move ( x, y ) ( x, y - 1 ) m
                    else
                        m
                )
                fallers
                (Dict.keys fallers)
    in
        Dict.union
            fallers_
            obstacleThings


isFaller : Thingy -> Bool
isFaller thing =
    case thing of
        Obstacle ->
            False

        _ ->
            True


isObstacleTile : FloorTile -> Bool
isObstacleTile tile =
    case tile of
        WallTile ->
            True

        _ ->
            False


{-| If possible, move thing from one set of coords to another.
Will mix ingredients if possible.
If move can not be preformed, then the original unchanged grid is returned.
-}
move : Coords -> Coords -> Grid Thingy -> Grid Thingy
move from to things =
    case ( Grid.get from things, Grid.get to things ) of
        ( Nothing, _ ) ->
            things

        ( Just activeMover, Nothing ) ->
            things
                |> Dict.remove from
                |> Dict.insert to activeMover

        ( Just activeMover, Just occupant ) ->
            mixIngredients activeMover occupant
                |> Maybe.map
                    (\newThing ->
                        things |> Dict.remove from |> Dict.insert to newThing
                    )
                |> Maybe.withDefault things


{-| Combine ingredients (things) into new things.
Returns Noting if the provided commbination is not supported.
-}
mixIngredients : Thingy -> Thingy -> Maybe Thingy
mixIngredients a b =
    case ( a, b ) of
        ( Water waterFlavour, Flour flourFlavour ) ->
            mixBun { water = waterFlavour, flour = flourFlavour }

        ( Flour flourFlavour, Water waterFlavour ) ->
            mixBun { water = waterFlavour, flour = flourFlavour }

        ( Water Nothing, Flavouring flavour ) ->
            Just <| Water (Just flavour)

        ( Flavouring flavour, Water Nothing ) ->
            Just <| Water (Just flavour)

        ( Flour Nothing, Flavouring flavour ) ->
            Just <| Flour (Just flavour)

        ( Flavouring flavour, Flour Nothing ) ->
            Just <| Flour (Just flavour)

        _ ->
            Nothing


mixBun : { flour : Maybe Flavour, water : Maybe Flavour } -> Maybe Thingy
mixBun { flour, water } =
    case ( flour, water ) of
        ( Just flavour, Nothing ) ->
            Just <| Bun <| Just flavour

        ( Nothing, Just flavour ) ->
            Just <| Bun <| Just flavour

        ( Just flourFlavour, Just waterFlavour ) ->
            if (flourFlavour == waterFlavour) then
                Just <| Bun <| Just flourFlavour
            else
                Nothing

        ( Nothing, Nothing ) ->
            Just <| Bun Nothing


{-| Collect all collectable Buns on collectors.
-}
collectThings : Grid FloorTile -> Grid Thingy -> Grid Thingy
collectThings level things =
    let
        collectionPoints =
            level |> Dict.filter (\_ tile -> isBunCollector tile) |> Dict.keys |> Set.fromList

        -- Collect thing if it is a _bun_ on a collection point
        ( collectedThings, remainingThings ) =
            things
                |> Dict.partition
                    (\coords thing ->
                        (Set.member coords collectionPoints)
                            && isCollectableBun thing
                    )
    in
        remainingThings


isBunCollector : FloorTile -> Bool
isBunCollector floorTile =
    case floorTile of
        BunCollector ->
            True

        _ ->
            False


isCollectableBun : Thingy -> Bool
isCollectableBun thing =
    case thing of
        Bun _ ->
            True

        _ ->
            False



-- # SUBSCRIPTIONS


{-| Keep updating regularly while game is running.

    - Spawn new things now and then
    - Lett things fall ASAP

-}
subscriptions : Model -> Sub Msg
subscriptions model =
    if not <| isGameOver kitchenLevel model.things then
        Sub.batch
            ([ Time.every spawnInterval (\_ -> Spawn) ]
                -- Only Have things fall there is something thst could fall (save messages)
                ++ (if not <| isStable kitchenLevel model.things then
                        [ Time.every fallInterval (\_ -> Fall) ]
                    else
                        []
                   )
            )
    else
        Sub.none


spawnInterval : Time
spawnInterval =
    (3 * second)


fallInterval : Time
fallInterval =
    (0.1 * second)



-- # VIEW


view : Model -> Html Msg
view model =
    let
        finalGrid : Grid RenderableTile
        finalGrid =
            Grid.drawBox (PlainTile) boardSize
                |> Grid.translate ( 0, 1 - boardSize.height )
                |> Dict.intersect kitchenLevel
                -- Convert to full tiles
                |> Dict.map (\_ floorTile -> RenderableTile Nothing False floorTile)
                -- Render highlighed column
                |> Dict.map
                    (\coords tile ->
                        if (Just coords == model.selectedTile) then
                            { tile | highlight = True }
                        else
                            tile
                    )
                -- Render buns
                |> Dict.map
                    (\coords tile ->
                        { tile
                            | content = (Dict.get coords model.things)
                        }
                    )
    in
        Html.div
            [ id "game-container"
            , style
                [ ( "position", "relative" )
                , ( "width", (10 * tileSide |> toString) ++ "px" )
                , ( "height", (8 * tileSide |> toString) ++ "px" )
                , ( "border", "10px solid black" )
                ]
            ]
            [ Html.div
                [ id "board-container"
                , style
                    [ ( "position", "absolute" )
                    , ( "top", (1 * tileSide |> toString) ++ "px" )
                    , ( "left", "0" )
                    ]
                ]
                [ Grid.toHtmlDiv ( tileSide, tileSide ) renderTile finalGrid

                -- Display board
                , if isGameOver kitchenLevel model.things then
                    Html.div
                        [ id "game-over"
                        , style
                            [ ( "position", "absolute" )
                            , ( "top", "0" )
                            , ( "width", "90%" )
                            , ( "height", "90%" )
                            , ( "padding", "5%" )
                            , ( "color", "darkred" )
                            , ( "text-align", "center" )
                            , ( "background-color", "white" )
                            , ( "opacity", "0.75" )
                            ]
                        ]
                        [ Html.h1 [ style [ ( "opacity", "1" ) ] ] [ text "Game over" ]
                        , Html.a
                            [ style [ ( "opacity", "1" ) ]
                            , Att.href "#restart"
                            , onClick RestartGame
                            ]
                            [ text "Try again?" ]
                        ]
                  else
                    text ""
                ]
            , Html.div
                [ class "debug"
                , style
                    [ ( "position", "absolute" )
                    , ( "right", "0" )
                    , ( "width", (4 * tileSide |> toString) ++ "px" )
                    , ( "height", (8 * tileSide |> toString) ++ "px" )
                    , ( "background-color", "lightgray" )
                    ]
                ]
                [ Html.button [ onClick Spawn ] [ text "Spawn!" ]
                , Html.button [ onClick Fall ] [ text "Fall!" ]
                , Html.button [ onClick Collect ] [ text "Collect" ]
                , Html.p [] [ "Move count: " ++ (model.moveCount |> toString) |> text ]
                , Html.p [] [ "Random seed: " ++ (toString model.seed) |> text ]
                , Html.p [] [ "Selected tile: " ++ (model.selectedTile |> toString) |> text ]
                , Html.p [] [ "Game over? " ++ ((isGameOver kitchenLevel model.things) |> toString) |> text ]
                ]
            ]


renderTile : Coords -> RenderableTile -> Html Msg
renderTile coords tile =
    Html.div
        [ style
            [ ( "width", toString (tileSide) ++ "px" )
            , ( "height", toString (tileSide) ++ "px" )
            , ( "background-color", getTileColor tile )
            , ( "border", "1px solid darkgray" )
            ]
        , onClick (SelectTile coords)
        ]
        [ tile.content |> Maybe.map renderThingy |> Maybe.withDefault (text "")
        , Html.span
            [ class "debug", style [ ( "font-size", "25%" ) ] ]
            [ Html.text (toString coords) ]
        ]


getTileColor : RenderableTile -> String
getTileColor tile =
    if tile.highlight then
        "aqua"
    else
        case tile.floor of
            PlainTile ->
                "lightgray"

            Spawner _ ->
                "antiquewhite"

            BunCollector ->
                "lawngreen"

            WallTile ->
                "darkgray"


{-| Render some ting insde tile
-}
renderThingy : Thingy -> Html msg
renderThingy thingy =
    case thingy of
        Bun flavour ->
            renderBun flavour

        Flour flavour ->
            renderFlour flavour

        Water flavour ->
            renderWater flavour

        Flavouring flavour ->
            renderFlavouring flavour

        Obstacle ->
            obstacleHtml


renderFlavouring : Flavour -> Html msg
renderFlavouring flavour =
    let
        ( cssClass, sprite ) =
            case flavour of
                Sugar ->
                    ( "sugar", sugarSprite )

                Chocolate ->
                    ( "chocolate", chocolateSprite )

                Chilli ->
                    ( "chilli", chilliSprite )
    in
        renderSprite cssClass sprite


{-| Render the most basic sprite
-}
renderSprite : String -> Sprite a -> Html msg
renderSprite cssClass sprite =
    Html.span
        [ class <| cssClass ++ "-sprite"
        , style <| Sprite.sprite sprite
        ]
        []


obstacleHtml : Html msg
obstacleHtml =
    Html.div
        [ style
            [ ( "width", "50px" )
            , ( "height", "50px" )
            , ( "margin", "4px 4px" )
            , ( "background-color", "black" )
            , ( "border", "2px dotted darkgray" )
            ]
        ]
        []


renderBun : Maybe Flavour -> Html msg
renderBun flavour =
    let
        sprite =
            getSpriteByFlavour bunSprites flavour

        ( primaryColor, secondaryColor ) =
            pickFlavourColors flavour

        debugName =
            (flavour |> Maybe.map toString |> Maybe.withDefault "") ++ " Bun"
    in
        renderBorderDecoratedSprite
            "bun"
            { primaryColor = primaryColor
            , secondaryColor = secondaryColor
            , borderRadius = 15
            , debugName = debugName
            }
            sprite


renderWater : Maybe Flavour -> Html msg
renderWater flavour =
    let
        sprite =
            getSpriteByFlavour waterSprites flavour

        ( primaryColor, secondaryColor ) =
            pickFlavourColors flavour

        debugName =
            (flavour |> Maybe.map toString |> Maybe.withDefault "") ++ " Water"
    in
        renderBorderDecoratedSprite
            "water"
            { primaryColor = primaryColor
            , secondaryColor = secondaryColor
            , borderRadius = (tileSide - 14) // 2
            , debugName = debugName
            }
            sprite


renderFlour : Maybe Flavour -> Html msg
renderFlour flavour =
    let
        sprite =
            getSpriteByFlavour flourSprites flavour

        ( primaryColor, secondaryColor ) =
            pickFlavourColors flavour

        debugName =
            (flavour |> Maybe.map toString |> Maybe.withDefault "") ++ " Flour"
    in
        renderBorderDecoratedSprite
            "flour"
            { primaryColor = primaryColor
            , secondaryColor = secondaryColor
            , borderRadius = 0
            , debugName = debugName
            }
            sprite


type alias BorderDecoratedSpriteStyle a =
    { a
        | borderRadius : Int
        , debugName : String
        , primaryColor : String
        , secondaryColor : String
    }


{-| Render a sprite surounded by a box border
-}
renderBorderDecoratedSprite : String -> BorderDecoratedSpriteStyle a -> Sprite {} -> Html msg
renderBorderDecoratedSprite cssClass { primaryColor, secondaryColor, borderRadius, debugName } sprite =
    let
        margin =
            7

        borderWidth =
            3

        -- Width & Height of borde box inside (i.e. excluding border)
        side =
            tileSide - (margin * 2) - (borderWidth * 2)
    in
        Html.div
            [ class cssClass
            , style
                ([ ( "position", "relative" )
                 , ( "overflow", "hide" )
                 , ( "text-align", "center" )
                 ]
                )
            ]
            [ Html.div
                [ class (cssClass ++ "-bg")
                , style
                    [ ( "position", "absolute" )
                    , ( "width", side ) |> px
                    , ( "height", side ) |> px
                    , ( "margin", margin ) |> px
                    , ( "border-radius", borderRadius ) |> px
                    , ( "border-width", borderWidth ) |> px
                    , ( "border-style", "dashed" )
                    , ( "border-color", primaryColor )
                    , ( "background-color", secondaryColor )
                    ]
                ]
                []
            , Html.span
                [ class ("sprite-container")
                , style <|
                    [ ( "position", "absolute" )
                    , ( "top", 0 ) |> px
                    , ( "left", 0 ) |> px
                    , ( "transform", "scale(0.5)" )
                    ]
                ]
                [ renderSprite cssClass sprite ]
            , Html.span
                [ class "debug"
                , style
                    [ ( "position", "absolute" )
                    , ( "width", "100%" )
                    , ( "top", "45px" )
                    , ( "left", "0" )
                    , ( "font-size", "40%" )
                    ]
                ]
                [ text debugName
                ]
            ]


px : ( String, Int ) -> ( String, String )
px ( name, value ) =
    ( name, (value |> toString) ++ "px" )


pickFlavourColors : Maybe Flavour -> ( String, String )
pickFlavourColors flavour =
    case flavour of
        Just Sugar ->
            ( "darkblue", "lightblue" )

        Just Chilli ->
            ( "darkred", "orange" )

        Just Chocolate ->
            ( "black", "brown" )

        Nothing ->
            ( "gray", "lightgray" )



-- SPRITES


chilliSprite : Sprite {}
chilliSprite =
    staticSprite ( 1, 0 )


sugarSprite : Sprite {}
sugarSprite =
    staticSprite ( 2, 0 )


chocolateSprite : Sprite {}
chocolateSprite =
    staticSprite ( 3, 0 )


type alias FlavouredSpriteKit =
    { sweet : Sprite {}
    , chilli : Sprite {}
    , coco : Sprite {}
    , basic : Sprite {}
    }


getSpriteByFlavour : FlavouredSpriteKit -> Maybe Flavour -> Sprite {}
getSpriteByFlavour kit flavour =
    case flavour of
        Just Sugar ->
            kit.sweet

        Just Chilli ->
            kit.chilli

        Just Chocolate ->
            kit.coco

        Nothing ->
            kit.basic


bunSprites : FlavouredSpriteKit
bunSprites =
    { chilli = staticSprite ( 1, 1 )
    , sweet = staticSprite ( 2, 1 )
    , coco = staticSprite ( 3, 1 )
    , basic = staticSprite ( 0, 1 )
    }


waterSprites : FlavouredSpriteKit
waterSprites =
    { chilli = staticSprite ( 1, 2 )
    , sweet = staticSprite ( 2, 2 )
    , coco = staticSprite ( 3, 2 )
    , basic = staticSprite ( 0, 2 )
    }


flourSprites : FlavouredSpriteKit
flourSprites =
    { chilli = staticSprite ( 1, 3 )
    , sweet = staticSprite ( 2, 3 )
    , coco = staticSprite ( 3, 3 )
    , basic = staticSprite ( 0, 3 )
    }


staticSprite : ( Int, Int ) -> Sprite {}
staticSprite pos =
    { baseSprite | dope = Array.fromList ([ pos ]) }


baseSprite : Sprite {}
baseSprite =
    { sheet = "SweetBuns--sprite-sheet.png"
    , rows = 4
    , columns = 4
    , size = ( 256, 256 )
    , frame = 0
    , dope = Array.fromList ([ ( 0, 0 ) ])
    }



-- LEVEL


tileSide : Int
tileSide =
    64


initialThings : Grid Thingy
initialThings =
    Grid.empty


kitchenLevel : Grid FloorTile
kitchenLevel =
    kitchenFloor
        |> Dict.union kitchenSpawners
        |> Dict.union kitchenCollectors
        |> Dict.union kitchenWalls


kitchenSpawners : Grid FloorTile
kitchenSpawners =
    Grid.drawBox (Spawner spawnables) { width = 6, height = 1 }
        |> Grid.translate ( 0, 0 )


{-| Spawnable things.
Weighted so that Flour, Water and Flavourings spawn 1/3 of the time each.
(Thus preventing an abundance of Flavourings)
-}
spawnables : List Thingy
spawnables =
    List.concat
        [ spawnableFlavours
        , List.repeat (List.length spawnableFlavours) (Water Nothing)
        , List.repeat (List.length spawnableFlavours) (Flour Nothing)
        ]


spawnableFlavours : List Thingy
spawnableFlavours =
    [ Flavouring Sugar, Flavouring Chilli, Flavouring Chocolate ]


kitchenCollectors : Grid FloorTile
kitchenCollectors =
    Grid.drawBox BunCollector { boardSize | height = 1 }
        |> Grid.translate ( 0, -5 )


kitchenFloor : Grid FloorTile
kitchenFloor =
    Grid.drawBox PlainTile { width = 6, height = 6 }
        |> Grid.translate ( 0, -5 )


kitchenWalls : Grid FloorTile
kitchenWalls =
    Grid.lineRect WallTile { width = 8, height = 8 }
        |> Grid.translate ( -1, -6 )


boardSize : Size Int
boardSize =
    Size 6 6
