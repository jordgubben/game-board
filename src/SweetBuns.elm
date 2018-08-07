module SweetBuns exposing (..)

import Dict
import Html exposing (Html, text)
import Html.Attributes as Att exposing (class, style)
import Html.Events as Ev exposing (onMouseEnter, onMouseLeave, onClick)
import Grid exposing (..)


main : Program Never Model Msg
main =
    Html.beginnerProgram { model = initialModel, update = update, view = view }


type alias Bun =
    String


type alias FullTile =
    { content : Maybe Bun
    , back : String
    }


type alias Model =
    { selectedTile : Coords
    , buns : Grid Bun
    }


type Msg
    = SelectColumn Coords
    | StepBuns


initialModel : Model
initialModel =
    { selectedTile = ( 0, 0 )
    , buns = initialBuns
    }


update : Msg -> Model -> Model
update msg model =
    case msg of
        SelectColumn coords ->
            { model | selectedTile = coords }

        StepBuns ->
            { model | buns = step model.buns }


step : Grid Bun -> Grid Bun
step buns =
    Dict.foldl (\( x, y ) b g -> Grid.put ( x, y - 1 ) b g) Grid.empty buns


view : Model -> Html Msg
view model =
    let
        ( selX, selY ) =
            model.selectedTile

        finalGrid : Grid FullTile
        finalGrid =
            back
                |> Dict.map
                    (\( x, y ) tile ->
                        if x == selX then
                            { tile | back = "pink" }
                        else
                            tile
                    )
                |> Dict.map
                    (\coords tile ->
                        { tile
                            | content = (Dict.get coords model.buns)
                        }
                    )
    in
        Html.div []
            [ Grid.toHtmlDiv ( tileSide, tileSide ) renderTile finalGrid
            , Html.p []
                [ (model.selectedTile |> toString |> Html.text)
                ]
            , Html.button [ onClick StepBuns ] [ text "Step" ]
            ]


renderTile : Coords -> FullTile -> Html Msg
renderTile coords tile =
    Html.div
        [ style
            [ ( "width", toString (tileSide) ++ "px" )
            , ( "height", toString (tileSide) ++ "px" )
            , ( "background-color", tile.back )
            , ( "border", "1px solid darkgray" )
            ]
        , onMouseEnter (SelectColumn coords)
        ]
        [ Html.text (Maybe.withDefault "" tile.content)
        , Html.span [ class "debug" ] [ Html.text (toString coords) ]
        ]


tileSide : Int
tileSide =
    32


initialBuns : Grid Bun
initialBuns =
    Grid.fromList
        [ ( ( 0, 0 ), "🍪" )
        , ( ( 1, 0 ), "🍪" )
        , ( ( 2, 0 ), "🍪" )
        , ( ( 3, 0 ), "🍪" )
        , ( ( 4, 0 ), "🍪" )
        , ( ( 5, 0 ), "🍪" )
        ]


back : Grid FullTile
back =
    Grid.drawBox { content = Nothing, back = "lightgray" } { width = 6, height = 12 }
        |> Grid.translate ( 0, -11 )
