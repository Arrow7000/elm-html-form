module Form exposing (..)

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


type Fieldset model fieldset
    = Fieldset (model -> fieldset)


type alias FieldEl msg =
    List (Html.Attribute msg) -> Html msg


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


type Init editor record fieldset model msg
    = Init
        { toModel : model -> Model editor -> model
        , fromModel : model -> Model editor
        , toMsg : Msg editor -> msg
        , toRecord : List editor -> Maybe record
        , onSubmit : record -> msg
        , fieldCount : Int
        , initModel : Model editor -> Model editor
        , fieldset : Fieldset model fieldset
        }


init :
    fieldset
    ->
        { toModel : model -> Model editor -> model
        , fromModel : model -> Model editor
        , toMsg : Msg editor -> msg
        , toRecord : List editor -> Maybe record
        , onSubmit : record -> msg
        }
    -> Init editor record fieldset model msg
init fieldset { toModel, fromModel, toMsg, toRecord, onSubmit } =
    Init
        { toModel = toModel
        , fromModel = fromModel
        , toMsg = toMsg
        , toRecord = toRecord
        , fieldCount = 0
        , initModel = identity
        , onSubmit = onSubmit
        , fieldset = Fieldset (always fieldset)
        }


type Field value editor msg
    = Field
        { initialValue : Maybe value
        , element : List (Html.Attribute msg) -> List (Html msg) -> Html msg
        , withValueAttr :
            { wrap : Maybe value -> editor
            , initialValue : Maybe value
            }
            -> editor
            -> List (Html.Attribute msg)
            -> List (Html.Attribute msg)
        , withOnInput : { wrap : Maybe value -> editor, index : Int, toMsg : Msg editor -> msg } -> List (Html.Attribute msg) -> List (Html.Attribute msg)
        }


input : Field String editor msg
input =
    Field
        { initialValue = Nothing
        , element = Html.input
        , withValueAttr =
            \{ wrap, initialValue } editor attrs ->
                (if wrap initialValue == editor then
                    initialValue

                 else
                    Nothing
                )
                    |> Maybe.map (\v -> Attr.value v :: attrs)
                    |> Maybe.withDefault attrs
        , withOnInput =
            \{ wrap, index, toMsg } ->
                (::) (Html.Events.onInput (Just >> wrap >> UserUpdatedField index >> toMsg))
        }


withInitialValue : Maybe value -> Field value editor msg -> Field value editor msg
withInitialValue value (Field field) =
    Field { field | initialValue = value }


type alias Module editor model fieldset msg =
    { init : ( Model editor -> model, Cmd msg ) -> ( model, Cmd msg )
    , submitMsg : msg
    , update : Msg editor -> model -> ( model, Cmd msg )
    , fieldset : model -> fieldset
    }


build : Init editor record fieldset model msg -> Module editor model fieldset msg
build (Init init_) =
    { init =
        \( toModel, cmdMsg ) ->
            ( toModel <|
                init_.initModel <|
                    Model
                        { editors = Dict.empty
                        , focusedIndex = Nothing
                        }
            , cmdMsg
            )
    , submitMsg = init_.toMsg UserClickedSubmit
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
    , fieldset =
        \model ->
            (\(Fieldset fs) -> fs model) init_.fieldset
    }


withField :
    (Maybe value -> editor)
    -> Field value editor msg
    -> Init editor record ((List (Html.Attribute msg) -> Html msg) -> fieldset) model msg
    -> Init editor record fieldset model msg
withField wrap (Field field) (Init init_) =
    let
        internals : model -> Internals editor
        internals =
            init_.fromModel >> (\(Model m) -> m)

        initEditor : editor
        initEditor =
            wrap field.initialValue

        withValueAttr : model -> List (Html.Attribute msg) -> List (Html.Attribute msg)
        withValueAttr model attrs_ =
            Maybe.map
                (\value ->
                    field.withValueAttr { wrap = wrap, initialValue = field.initialValue }
                        value
                        attrs_
                )
                -- syntax crimes
                ((internals model).editors |> Dict.get init_.fieldCount)
                |> Maybe.withDefault attrs_

        withEvents : List (Html.Attribute msg) -> List (Html.Attribute msg)
        withEvents attrs_ =
            Html.Events.onFocus (UserFocusedField init_.fieldCount |> init_.toMsg)
                :: Html.Events.onBlur (init_.toMsg UserBlurredField)
                :: attrs_
                |> field.withOnInput { wrap = wrap, index = init_.fieldCount, toMsg = init_.toMsg }

        element : model -> List (Html.Attribute msg) -> Html msg
        element model attrs =
            field.element
                (attrs |> withValueAttr model |> withEvents)
                []
    in
    Init
        { fieldCount = init_.fieldCount + 1
        , initModel =
            init_.initModel
                >> (\(Model m) -> Model { m | editors = Dict.insert init_.fieldCount initEditor m.editors })
        , toModel = init_.toModel
        , fromModel = init_.fromModel
        , toMsg = init_.toMsg
        , toRecord = init_.toRecord
        , onSubmit = init_.onSubmit
        , fieldset = Fieldset (\model -> (\(Fieldset fs) -> fs model (element model)) init_.fieldset)
        }