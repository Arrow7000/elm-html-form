module Ui.Form exposing (..)

import Dict exposing (Dict)
import Html exposing (Html)
import Html.Attributes as Attr
import Html.Events
import Task


type Model editor
    = Model (Internals editor)


type alias Internals editor =
    { editors : Dict Int editor
    , focusedIndex : Maybe Int
    }


type Msg editor
    = UserUpdatedField Int editor
    | UserFocusedField Int
    | UserBlurredField
    | UserClickedSubmit


update :
    { onSubmit : record -> msg, toMsg : Msg editor -> msg, toRecord : List editor -> Maybe record }
    -> Msg editor
    -> Model editor
    -> ( Model editor, Cmd msg )
update { onSubmit, toMsg, toRecord } msg (Model model) =
    case msg of
        UserUpdatedField index editor ->
            ( Model { model | editors = Dict.insert index editor model.editors }
            , Cmd.none
            )

        UserFocusedField index ->
            ( Model { model | focusedIndex = Just index }
            , Cmd.none
            )

        UserBlurredField ->
            ( Model { model | focusedIndex = Nothing }
            , Cmd.none
            )

        UserClickedSubmit ->
            ( Model model
            , let
                call : msg -> Cmd msg
                call m =
                    Task.perform
                        (always m)
                        (Task.succeed identity)
              in
              Maybe.map
                (onSubmit >> call)
                (Dict.values model.editors |> toRecord)
                |> Maybe.withDefault Cmd.none
            )


type Init editor record model msg
    = Init
        { toModel : model -> Model editor -> model
        , fromModel : model -> Model editor
        , toMsg : Msg editor -> msg
        , toRecord : List editor -> Maybe record
        , onSubmit : record -> msg
        , fields : Dict Int (model -> Html msg)
        , initModel : Model editor -> Model editor
        }


init :
    { toModel : model -> Model editor -> model
    , fromModel : model -> Model editor
    , toMsg : Msg editor -> msg
    , toRecord : List editor -> Maybe record
    , onSubmit : record -> msg
    }
    -> Init editor record model msg
init { toModel, fromModel, toMsg, toRecord, onSubmit } =
    Init
        { toModel = toModel
        , fromModel = fromModel
        , toMsg = toMsg
        , toRecord = toRecord
        , fields = Dict.empty
        , initModel = identity
        , onSubmit = onSubmit
        }


withInput :
    { wrap : Maybe String -> editor
    , initialValue : Maybe String
    , attrs : List (Html.Attribute msg)
    }
    -> Init editor record model msg
    -> Init editor record model msg
withInput { wrap, initialValue, attrs } (Init init_) =
    let
        internals : model -> Internals editor
        internals =
            init_.fromModel >> (\(Model m) -> m)

        initEditor : editor
        initEditor =
            wrap initialValue

        nextIndex : Int
        nextIndex =
            Dict.size init_.fields

        withValueAttr : model -> List (Html.Attribute msg) -> List (Html.Attribute msg)
        withValueAttr model attrs_ =
            Maybe.andThen
                (\value ->
                    if value == initEditor then
                        Maybe.map (\v -> Attr.value v :: attrs_) initialValue

                    else
                        Nothing
                )
                ((internals model).editors |> Dict.get nextIndex)
                |> Maybe.withDefault attrs

        withEvents : List (Html.Attribute msg) -> List (Html.Attribute msg)
        withEvents attrs_ =
            Html.Events.onInput (Just >> wrap >> UserUpdatedField nextIndex >> init_.toMsg)
                :: Html.Events.onFocus (UserFocusedField nextIndex |> init_.toMsg)
                :: Html.Events.onBlur (init_.toMsg UserBlurredField)
                :: attrs_

        field =
            \model ->
                Html.input
                    (attrs |> withValueAttr model |> withEvents)
                    []
    in
    Init
        { init_
            | fields = Dict.insert nextIndex field init_.fields
            , initModel =
                init_.initModel
                    >> (\(Model m) -> Model { m | editors = Dict.insert nextIndex initEditor m.editors })
        }


type alias Module editor model msg =
    { init : ( Model editor -> model, Cmd msg ) -> ( model, Cmd msg )
    , elements : { fields : model -> List (Html msg), submitMsg : msg }
    , update : Msg editor -> model -> ( model, Cmd msg )
    }


build : Init editor record model msg -> Module editor model msg
build (Init init_) =
    { init =
        \( toModel, cmdMsg ) ->
            ( toModel <|
                Model
                    { editors = Dict.empty
                    , focusedIndex = Nothing
                    }
            , cmdMsg
            )
    , elements =
        { fields =
            \model ->
                Dict.values init_.fields
                    |> List.map ((|>) model)
        , submitMsg = init_.toMsg UserClickedSubmit
        }
    , update =
        \msg model ->
            update
                { onSubmit = init_.onSubmit
                , toRecord = init_.toRecord
                , toMsg = init_.toMsg
                }
                msg
                (init_.fromModel model)
                |> Tuple.mapFirst
                    (init_.toModel model)
    }