module GridTest exposing (..)

import Dict
import Html
import Grid exposing (Grid)
import Expect exposing (Expectation, equal)
import Test exposing (..)
import Fuzz exposing (..)
import Test.Html.Query as Query
import Test.Html.Selector exposing (tag, class, style, all)


-- # Test: Drawing


drawingSuite : Test
drawingSuite =
    describe "Drawing"
        [ describe "Grid.drawBox : t -> {w,h} -> Grid t"
            [ test "Draws a grid with the defined width and height" <|
                (\_ ->
                    Grid.drawBox "Tile" { width = 3, height = 4 }
                        |> Expect.all
                            [ Grid.numRows >> equal 4
                            , Grid.numCols >> equal 3
                            ]
                )
            ]
        , describe "Grid.lineRect : t -> {w,h} -> Grid t"
            [ test "Draws a grid with the defined width and height" <|
                (\_ ->
                    Grid.lineRect "Tile" { width = 5, height = 8 }
                        |> Expect.all
                            [ Grid.numRows >> equal 8
                            , Grid.numCols >> equal 5
                            , Dict.get ( 1, 1 ) >> equal Nothing
                            , Dict.get ( 4, 7 ) >> equal (Just "Tile")
                            , Dict.size >> equal (8 * 2 + 3 * 2)
                            ]
                )
            ]
        ]



-- # Test: Transformaton


transformationSuite : Test
transformationSuite =
    describe "Grid transformation"
        [ describe "Grid.translate"
            [ test "Moves grid content in the given direction" <|
                (\_ ->
                    let
                        original =
                            Grid.fromList [ ( ( 0, 0 ), True ), ( ( 1, -2 ), True ) ]

                        translated =
                            Grid.translate ( 3, 5 ) original

                        expected =
                            Grid.fromList [ ( ( 3, 5 ), True ), ( ( 4, 3 ), True ) ]
                    in
                        translated |> equal expected
                )
            , fuzz (tuple ( int, int )) "Translate one way and then the other returns the grid to it's original state" <|
                (\( x, y ) ->
                    exampleGrid |> Grid.translate ( x, y ) |> Grid.translate ( -x, -y ) |> equal exampleGrid
                )
            ]
        , describe "Grid.rotCv"
            [ test "Rotates clockwise" <|
                (\_ ->
                    let
                        original =
                            Grid.fromList [ ( ( -1, -1 ), 'n' ), ( ( 1, 3 ), 'P' ) ]

                        rot1 =
                            Grid.rotCv original

                        rot2 =
                            Grid.rotCv rot1

                        rot3 =
                            Grid.rotCv rot2

                        rot4 =
                            Grid.rotCv rot3
                    in
                        Expect.all
                            [ (\_ -> rot1 |> equal (Grid.fromList [ ( ( -1, 1 ), 'n' ), ( ( 3, -1 ), 'P' ) ]))
                            , (\_ -> rot2 |> equal (Grid.fromList [ ( ( 1, 1 ), 'n' ), ( ( -1, -3 ), 'P' ) ]))
                            , (\_ -> rot3 |> equal (Grid.fromList [ ( ( 1, -1 ), 'n' ), ( ( -3, 1 ), 'P' ) ]))
                            , (\_ -> rot4 |> equal original)
                            ]
                            never
                )
            ]
        , describe "Grid.rotCcv"
            [ test "Rotates counter clockwise" <|
                (\_ ->
                    let
                        original =
                            Grid.fromList [ ( ( -1, -1 ), 'n' ), ( ( 1, 3 ), 'P' ) ]

                        rot1 =
                            Grid.rotCcv original

                        rot2 =
                            Grid.rotCcv rot1

                        rot3 =
                            Grid.rotCcv rot2

                        rot4 =
                            Grid.rotCcv rot3
                    in
                        Expect.all
                            [ (\_ -> rot1 |> equal (Grid.fromList [ ( ( 1, -1 ), 'n' ), ( ( -3, 1 ), 'P' ) ]))
                            , (\_ -> rot2 |> equal (Grid.fromList [ ( ( 1, 1 ), 'n' ), ( ( -1, -3 ), 'P' ) ]))
                            , (\_ -> rot3 |> equal (Grid.fromList [ ( ( -1, 1 ), 'n' ), ( ( 3, -1 ), 'P' ) ]))
                            , (\_ -> rot4 |> equal original)
                            ]
                            never
                )
            ]
        ]



-- # Test: Rendering


renderingSuite : Test
renderingSuite =
    describe "Grid rendering"
        [ describe "Grid.toHtmlTable"
            [ test "Creates a table spanning all the cells" <|
                \() ->
                    exampleGrid
                        |> Grid.toHtmlTable (\_ _ -> (Html.text ""))
                        |> expectCellCountEquals
                            ((Grid.numRows exampleGrid) * (Grid.numCols exampleGrid))
            , test "If the grid is empty, then the table is empty" <|
                \() ->
                    Grid.empty
                        |> Grid.toHtmlTable (\_ _ -> (Html.text ""))
                        |> expectCellCountEquals 0
            ]
        , describe "Grid.toHtmlDiv"
            [ test "Creates a div containing a div for each grid tile " <|
                \() ->
                    exampleGrid
                        |> Grid.toHtmlDiv ( 16, 16 ) (\_ _ -> (Html.text ""))
                        |> expectTileDivCountEquals (Dict.size exampleGrid)
            , test "Creates an outer div large anough to house all tiles" <|
                \() ->
                    exampleGrid
                        |> Grid.toHtmlDiv ( 16, 16 ) (\_ _ -> (Html.text ""))
                        |> expectTileDivSize
                            ( 16 * Grid.numCols exampleGrid, 16 * Grid.numRows exampleGrid )
            , test "If the grid is empty, then there are no inner divs" <|
                \() ->
                    Grid.empty
                        |> Grid.toHtmlDiv ( 16, 16 ) (\_ _ -> (Html.text ""))
                        |> expectTileDivCountEquals 0
            ]
        ]



-- # Helpers


exampleGrid : Grid String
exampleGrid =
    Grid.empty
        |> Grid.put ( 0, 0 ) "a"
        |> Grid.put ( 0, -1 ) "down"
        |> Grid.put ( 0, 2 ) "up"
        |> Grid.put ( -3, 0 ) "left"
        |> Grid.put ( 4, 0 ) "right"


expectCellCountEquals : Int -> Html.Html msg -> Expectation
expectCellCountEquals expNumCells html =
    html
        |> Query.fromHtml
        |> Query.findAll [ tag "td" ]
        |> Query.count
            (\actualNumCells ->
                Expect.equal expNumCells actualNumCells
            )


expectTileDivCountEquals : Int -> Html.Html msg -> Expectation
expectTileDivCountEquals expNumCells html =
    html
        |> Query.fromHtml
        |> Query.children [ tag "div", class "grid-cell" ]
        |> Query.count
            (\actualNumCells ->
                Expect.equal expNumCells actualNumCells
            )


expectTileDivSize : ( Int, Int ) -> Html.Html msg -> Expectation
expectTileDivSize ( expWidth, expHeight ) html =
    html
        |> Query.fromHtml
        |> Query.has
            [ style
                [ ( "width", toString expWidth ++ "px" )
                , ( "height", toString expHeight ++ "px" )
                ]
            ]
