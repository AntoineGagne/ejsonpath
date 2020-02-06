-module(fixture_tests).

-compile([export_all, nowarn_export_all]).

-include_lib("eunit/include/eunit.hrl").

%% Helpers

get_file(FileName) ->
    Path = filename:join("./test/fixtures/", FileName),
    {ok, Bin} = file:read_file(Path),
    jsx:decode(Bin, [return_maps]).

-define(CHECK_DOC(Doc, Pattern, Expected),
    ?assertEqual(Expected, ejsonpath:q(Pattern, Doc))).

%% Tests

simple_test() ->
    Doc = get_file("simple.json"),
    ?CHECK_DOC(Doc, "$.hello", {[<<"world">>], ["$['hello']"]}).

simple_array_root_test() ->
    Doc = get_file("simple_array_root.json"),
    ?CHECK_DOC(Doc, "$.*", {[<<"hello">>, <<"work">>, 1, 2, 3], ["$[0]", "$[1]", "$[2]", "$[3]", "$[4]"]}).

complicated_test() ->
    Doc = get_file("complicated.json"),
    ?CHECK_DOC(Doc, "$.name", {[<<"Korg The Destroyer">>], ["$['name']"]}),
    ?CHECK_DOC(Doc, "$.class", {[<<"Fighter">>], ["$['class']"]}),
    ?CHECK_DOC(Doc, "$.awesome", {[true], ["$['awesome']"]}),

    ?CHECK_DOC(Doc, "$.nested.name", {[<<"Korgy Korg">>], ["$['nested']['name']"]}),
    ?CHECK_DOC(Doc, "$.nested.class", {[<<"Fighter">>], ["$['nested']['class']"]}),
    ?CHECK_DOC(Doc, "$.nested.specialization", {[<<"Champion">>], ["$['nested']['specialization']"]}),
    ?CHECK_DOC(Doc, "$.nested.awesome", {[true], ["$['nested']['awesome']"]}),
    ?CHECK_DOC(Doc, "$.nested['awesome levels']", {[<<"over 9000">>], ["$['nested']['awesome levels']"]}),

    ?CHECK_DOC(Doc, "$.stats.strength", {[22], ["$['stats']['strength']"]}),
    ?CHECK_DOC(Doc, "$.stats.dexterity", {[12], ["$['stats']['dexterity']"]}),
    ?CHECK_DOC(Doc, "$.stats.constitution", {[12], ["$['stats']['constitution']"]}),
    ?CHECK_DOC(Doc, "$.stats.resistance", {[12], ["$['stats']['resistance']"]}),
    ?CHECK_DOC(Doc, "$.stats.intelligence", {[8], ["$['stats']['intelligence']"]}),

    {BashOwnFace, _} = ejsonpath:q("$.skills['bash own face']", Doc),
    ?assertNotEqual([], BashOwnFace),
    ?CHECK_DOC(Doc, "$.skills['bash own face']['effects']['aoe buff']['area']",
                {[<<"tiles">>], ["$['skills']['bash own face']['effects']['aoe buff']['area']"]}),
    ?CHECK_DOC(Doc, "$.skills['cooking']['description']",
               {[<<"PC is able to cook tasty meals">>], ["$['skills']['cooking']['description']"]}),

    ?CHECK_DOC(Doc, "$['fallen enemies']", {[[<<"evil lord">>, <<"XXxx 3V1L L0RD xxXX">>, <<"reason">>,
                    <<"Greg the Evil Guy">>, <<"too many goblins">>, <<"imps">>,
                    <<"trolls">>, <<"beehive (it was a bad time)">>, 5, false,
                    <<"dignity">>]],
                  ["$['fallen enemies']"]}),
    ok.

stringified_inside_json_test() ->
    %% Testing in the odd case that your JSON contains JSON
    Doc = get_file("complicated.json"),
    ?CHECK_DOC(Doc, "$.metadata.game_difficulty", {[<<"ultra super permadeath hardcore">>],
                  ["$['metadata']['game_difficulty']"]}),

    {[Result], _} = ejsonpath:q("$.metadata.self", Doc),

    StringExistsIn =
        fun(Subject, String) ->
                case re:run(Subject, String) of
                    {match, _} -> ?assert(true);
                    nomatch -> ?assert(false, "could not find string")
                end
        end,

    StringExistsIn(Result, "name"),
    StringExistsIn(Result, "Korg The Destroyer"),
    StringExistsIn(Result, "cooking"),
    StringExistsIn(Result, "bash own face"),
    StringExistsIn(Result, "Fighter"),
    StringExistsIn(Result, "permadeath hardcore").

numbers_test() ->
    %% mainly jiffy concerns, but this is here for sanity and
    %% safeguarding against possible in between bad things (TM).
    Doc = get_file("numbers.json"),
    ?CHECK_DOC(Doc, "$.t_000", {[1], ["$['t_000']"]}),
    ?CHECK_DOC(Doc, "$.t_001", {[-0], ["$['t_001']"]}),
    ?CHECK_DOC(Doc, "$.t_002", {[-12], ["$['t_002']"]}),
    ?CHECK_DOC(Doc, "$.t_003", {[1.23e-7], ["$['t_003']"]}),
    ?CHECK_DOC(Doc, "$.t_004", {[-1.23e-7], ["$['t_004']"]}),
    ?CHECK_DOC(Doc, "$.t_005", {[1.123e10], ["$['t_005']"]}),
    ?CHECK_DOC(Doc, "$.t_006", {[1.123e-10], ["$['t_006']"]}),
    ?CHECK_DOC(Doc, "$.t_007", {[1.0e-5], ["$['t_007']"]}),
    ?CHECK_DOC(Doc, "$.t_008", {[1.0e-5], ["$['t_008']"]}),
    ?CHECK_DOC(Doc, "$.t_009", {[1.0e9], ["$['t_009']"]}).
