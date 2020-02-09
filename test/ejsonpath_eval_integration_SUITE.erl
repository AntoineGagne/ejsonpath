-module(ejsonpath_eval_integration_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-compile(nowarn_export_all).
-compile(export_all).

-define(AST(Query),
        element(2,
                ejsonpath_parse:parse(
                  element(2,
                          ejsonpath_scan:string(Query)
                         )
                 )
               )
       ).

-define(EMPTY_FUNCTIONS, #{}).
-define(EMPTY_OPTIONS, []).


all() ->
    [
     can_return_root_element,
     can_access_by_key,
     can_access_list_by_indice
    ].

init_per_suite(Config) ->
    Example = get_example(Config),
    [{example, Example} | Config].

end_per_suite(Config) ->
    Config.

init_per_testcase(_Name, Config) ->
    Config.

end_per_testcase(_Name, Config) ->
    Config.

can_return_root_element() ->
    [{doc, "Given a query for the root element, when evaluating, then returns the root element."}].
can_return_root_element(_Config) ->
    Element = #{},
    {ok, RootQuery} = parse("$"),
    ?assertEqual({[Element], ["$"]},
                 ejsonpath_eval:eval(RootQuery, Element, ?EMPTY_FUNCTIONS, ?EMPTY_OPTIONS)),

    AnotherElement = [],
    ?assertEqual({[AnotherElement], ["$"]},
                 ejsonpath_eval:eval(RootQuery, AnotherElement, ?EMPTY_FUNCTIONS, ?EMPTY_OPTIONS)),

    AThirdElement = #{
      <<"a">> => [1, 2, 3],
      <<"b">> => [#{ <<"id">> => 0}, #{ <<"id">> => 1}]
     },
    {ok, AnotherQuery} = parse("$."),
    ?assertEqual({[AThirdElement], ["$"]},
                 ejsonpath_eval:eval(AnotherQuery,
                                     AThirdElement,
                                     ?EMPTY_FUNCTIONS,
                                     ?EMPTY_OPTIONS)),

    {ok, AThirdQuery} = parse("$.."),
    ?assertEqual(
       { [ #{<<"a">> => [1, 2, 3], <<"b">> => [#{<<"id">> => 0}, #{<<"id">> => 1}]},
           [1, 2, 3],
           1, 2, 3,
           [#{<<"id">> => 0}, #{<<"id">> => 1}],
           #{<<"id">> => 0},
           0,
           #{<<"id">> => 1},
           1],
         [
          "$",
          "$['a']",
          "$['a'][0]",
          "$['a'][1]",
          "$['a'][2]",
          "$['b']",
          "$['b'][0]",
          "$['b'][0]['id']",
          "$['b'][1]",
          "$['b'][1]['id']"
         ]}, ejsonpath_eval:eval(AThirdQuery, AThirdElement, ?EMPTY_FUNCTIONS, ?EMPTY_OPTIONS)).

can_access_by_key() ->
    [{doc, "Given a query for a specific key, when evaluating, "
      "then returns the corresponding element."}].
can_access_by_key(Config) ->
    Example = ?config(example, Config),
    {ok, Query} = parse("$.none"),
    ?assertEqual({[], []}, ejsonpath_eval:eval(Query, Example, ?EMPTY_FUNCTIONS, ?EMPTY_OPTIONS)),
    ?assertEqual({[], []}, ejsonpath_eval:eval(Query, [1, 2, 3], ?EMPTY_FUNCTIONS, ?EMPTY_OPTIONS)),

    {ok, AnotherQuery} = parse("$.store"),
    ?assertEqual({[maps:get(<<"store">>, Example)], ["$['store']"]},
                 ejsonpath_eval:eval(AnotherQuery, Example, ?EMPTY_FUNCTIONS, ?EMPTY_OPTIONS)),

    {ok, AThirdQuery} = parse("$.store.bicycle.color"),
    ?assertEqual({[<<"red">>], ["$['store']['bicycle']['color']"]},
                 ejsonpath_eval:eval(AThirdQuery, Example, ?EMPTY_FUNCTIONS, ?EMPTY_OPTIONS)).

descendant_test() ->
    ?assertEqual(
       { [19.95, 8.95, 12.99, 8.99, 22.99],
         [
          "$['store']['bicycle']['price']",
          "$['store']['book'][0]['price']",
          "$['store']['book'][1]['price']",
          "$['store']['book'][2]['price']",
          "$['store']['book'][3]['price']"]
       },
       ejsonpath_eval:eval(?AST("$..price"), get_doc(), #{}, [])),

    ?assertEqual(
       { [0, 1, 2, 3],
         [
          "$['store']['book'][0]['id']",
          "$['store']['book'][1]['id']",
          "$['store']['book'][2]['id']",
          "$['store']['book'][3]['id']"]
       },
       ejsonpath_eval:eval(?AST("$..book..id"), get_doc(), #{}, [])),

    ok.

can_access_list_by_indice() ->
    [{doc, "Given a query with indices, when evaluating, "
      "then returns the element at the corresponding indice."}].
can_access_list_by_indice(Config) ->
    Example = ?config(example, Config),
    {ok, Query} = parse("$['none']"),
    ?assertEqual({[], []}, ejsonpath_eval:eval(Query, Example, ?EMPTY_FUNCTIONS, ?EMPTY_OPTIONS)),
    {ok, AnotherQuery} = parse("$['none']"),
    ?assertEqual({[], []},
                 ejsonpath_eval:eval(AnotherQuery, [1, 2, 3], ?EMPTY_FUNCTIONS, ?EMPTY_OPTIONS)),
    {ok, ThirdQuery} = parse("$[3]"),
    ?assertEqual({[], []},
                 ejsonpath_eval:eval(ThirdQuery, [1, 2, 3], ?EMPTY_FUNCTIONS, ?EMPTY_OPTIONS)),
    {ok, FourthQuery} = parse("$[-4]"),
    ?assertEqual({[], []},
                 ejsonpath_eval:eval(FourthQuery, [1, 2, 3], ?EMPTY_FUNCTIONS, ?EMPTY_OPTIONS)),

    ?assertEqual({[maps:get(<<"store">>, Example)], ["$['store']"]},
                 ejsonpath_eval:eval(?AST("$['store']"), Example, #{}, [])),

    ?assertEqual({[<<"red">>], ["$['store']['bicycle']['color']"]},
                 ejsonpath_eval:eval(?AST("$['store']['bicycle']['color']"), Example, #{}, [])),

    ?assertEqual(
       {[<<"red">>, 19.95], ["$['store']['bicycle']['color']", "$['store']['bicycle']['price']"]},
       ejsonpath_eval:eval(?AST("$['store']['bicycle']['color', 'price']"), Example, #{}, [])),
    ?assertEqual(
       {[<<"red">>, 19.95, <<"red">>],
        [
         "$['store']['bicycle']['color']",
         "$['store']['bicycle']['price']",
         "$['store']['bicycle']['color']"
        ]},
       ejsonpath_eval:eval(?AST("$['store']['bicycle']['color', 'price', 'noway', 0, 'color']"),
                           Example, #{}, [])),

    ?assertEqual({[1], ["$[0]"]}, ejsonpath_eval:eval(?AST("$[0]"), [1, 2, 3], #{}, [])),
    ?assertEqual({[1, 3], ["$[0]", "$[2]"]}, ejsonpath_eval:eval(?AST("$[0, 2]"), [1, 2, 3], #{}, [])),

    ?assertEqual({[3], ["$[2]"]}, ejsonpath_eval:eval(?AST("$[-1]"), [1, 2, 3], #{}, [])),
    ?assertEqual({[2], ["$[1]"]}, ejsonpath_eval:eval(?AST("$[-2]"), [1, 2, 3], #{}, [])),
    ?assertEqual({[1], ["$[0]"]}, ejsonpath_eval:eval(?AST("$[-3]"), [1, 2, 3], #{}, [])),
    ?assertEqual({[3, 2, 1], ["$[2]", "$[1]", "$[0]"]}, ejsonpath_eval:eval(?AST("$[-1, -2, -3]"), [1, 2, 3], #{}, [])),

    ?assertEqual({[3, 2, 1, 1], ["$[2]", "$[1]", "$[0]", "$[0]"]},
                 ejsonpath_eval:eval(?AST("$[-1, -2, -3, 'noway', 0]"), [1, 2, 3], #{}, [])),
    ?assertEqual(
       { [8.95, 12.99, 8.99, 22.99],
         [
          "$['store']['book'][0]['price']",
          "$['store']['book'][1]['price']",
          "$['store']['book'][2]['price']",
          "$['store']['book'][3]['price']"
         ]},
       ejsonpath_eval:eval(?AST("$.store.book.*.price"), Example, #{}, [])),
    ok.

slice_test() ->
    ?assertEqual({[], []}, ejsonpath_eval:eval(?AST("$[:]"), [], #{}, [])),
    ?assertEqual({[], []}, ejsonpath_eval:eval( ?AST("$[0:0]"), [x, y, z], #{}, [])),

    ?assertEqual({[x, y, z], ["$[0]", "$[1]", "$[2]"]}, ejsonpath_eval:eval(?AST("$[:]"), [x, y, z], #{}, [])),
    ?assertEqual({[], []}, ejsonpath_eval:eval( ?AST("$[0:0]"), [x, y, z], #{}, [])),
    ?assertEqual({[x], ["$[0]"]}, ejsonpath_eval:eval( ?AST("$[0:1]"), [x, y, z], #{}, [])),

    ?assertEqual({[y, z], ["$[1]", "$[2]"]}, ejsonpath_eval:eval( ?AST("$[1:]"), [x, y, z], #{}, [])),
    ?assertEqual({[x], ["$[0]"]}, ejsonpath_eval:eval( ?AST("$[:1]"), [x, y, z], #{}, [])),
    ok.

filter_expr_test() ->
    Subject = #{
      <<"name">> => <<"name">>,
      <<"name1">> => <<"name1">>,
      <<"lASTname">> => <<"lASTname">>,
      <<"items">> => [1, 2, 3, 4, 5]
     },
    Funcs = #{
      is_even => fun ({Curr, _}, []) ->
                         Curr rem 2 =:= 0
                 end,
      is_name => fun
                     ({<<"name">>, _}, []) -> true;
            ({_, _}, []) -> false
                 end
     },
    ?assertEqual({[2, 4], ["$['items'][1]", "$['items'][3]"]},
                 ejsonpath_eval:eval(?AST("$.items[?(is_even())]"), Subject, Funcs, [])),

    ?assertEqual({[<<"name">>], ["$['name']"]},
                 ejsonpath_eval:eval(?AST("$[ ?( is_name() ) ]"), Subject, Funcs, [])),

    ?assertEqual({ [8.95, 8.99],
                   [
                    "$['store']['book'][0]['price']",
                    "$['store']['book'][2]['price']"
                   ]},
                 ejsonpath_eval:eval(?AST("$.store.book.*.price[ ?( gt(8) && lt(10) ) ]"),
                                     get_doc(), #{gt => fun ({N, _}, [V]) -> N > V end,
                                                  lt => fun ({N, _}, [V]) -> N < V end}, [])),

    ?assertEqual(
       {[8.95], ["$['store']['book'][0]['price']"]},
       ejsonpath_eval:eval(?AST("$.store.book[?(@.id == 0)].price"), get_doc(), #{}, [])),

    ?assertEqual(
       {[3, 22.99],
        [
         "$['store']['book'][3]['id']",
         "$['store']['book'][3]['price']"]
       },
       ejsonpath_eval:eval(?AST("$.store.book[?(@.id == $.last_id)]['id', 'price']"), get_doc(), #{}, [])),

    ?assertEqual({[8.99, 22.99],
                  [
                   "$['store']['book'][2]['price']",
                   "$['store']['book'][3]['price']"
                  ]}, ejsonpath_eval:eval(?AST("$.store.book[?(@.isbn)].price"), get_doc(), #{}, [])),

    ok.

transform_expr_test() ->
    ?assertEqual({
       [89.5, 129.9, 89.9, 229.89999999999998],
       [
        "$['store']['book'][0]['price']",
        "$['store']['book'][1]['price']",
        "$['store']['book'][2]['price']",
        "$['store']['book'][3]['price']"
       ]},
                 ejsonpath_eval:eval(?AST("$..book..price[(mul(10))]"), get_doc(), #{
                                                                          mul => fun ({N, _}, [M]) -> N * M end
                                                                         }, [])),

    ok.

%%%===================================================================
%%% Internal functions
%%%===================================================================

parse(Raw) ->
    {ok, Tokens, _} = ejsonpath_scan:string(Raw),
    ejsonpath_parse:parse(Tokens).

get_example(Config) ->
    RootPath = ?config(data_dir, Config),
    FullPath = filename:join(RootPath, "doc.json"),
    {ok, Raw} = file:read_file(FullPath),
    jsx:decode(Raw, [return_maps]).

get_doc() ->
    {ok, Bin} = file:read_file("./test/doc.json"),
    jsx:decode(Bin, [return_maps]).
