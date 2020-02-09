-module(ejsonpath_eval_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-compile(nowarn_export_all).
-compile(export_all).

-define(EMPTY_FUNCTIONS, #{}).
-define(EMPTY_OPTIONS, []).
-define(A_KEY, <<"key">>).
-define(A_VALUE, <<"value">>).

all() ->
    [
     can_return_root_element
    ].

init_per_testcase(_Name, Config) ->
    Config.

end_per_testcase(_Name, Config) ->
    Config.

can_return_root_element() ->
    [{doc, "Given a query for the root element, when evaluating, then returns the root element."}].
can_return_root_element(_Config) ->
    {ok, Query} = parse("$"),
    Element = a_json_object(),

    ?assertMatch({[Element], _},
                 ejsonpath_eval:eval(Query, Element, ?EMPTY_FUNCTIONS, ?EMPTY_OPTIONS)).

%%%===================================================================
%%% Internal functions
%%%===================================================================

parse(Raw) ->
    {ok, Tokens, _} = ejsonpath_scan:string(Raw),
    ejsonpath_parse:parse(Tokens).

a_json_object() ->
    #{?A_KEY => ?A_VALUE}.
