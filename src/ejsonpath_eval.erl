-module(ejsonpath_eval).

-ifdef(TEST).
-compile([export_all, nowarn_export_all]).
-endif.

% -define(EJSONPATH_DEBUG, true).
-include("src/ejsonpath.hrl").

-export([eval/4,
         eval_step/3]).

eval({root, '$'}, Node, _, _) ->
    {[Node], ["$"]};
eval({root, Descendant}, Node, _, _) when is_atom(Descendant) ->
    Children = children(Descendant, [ejsonpath_common:argument(Node, "$")]),
    ejsonpath_common:unzip(Children);
eval({root, Predicates}, Node, Funcs, Options) ->
    EvalStep = fun (SubQuery, CurrNode, Ctx) -> eval_step(SubQuery, [CurrNode], Ctx) end,
    Context = #{root => Node,
                opts => Options,
                funcs => Funcs,
                eval_root => fun (SubQuery) -> eval(SubQuery, Node, Funcs, Options) end,
                eval_step => EvalStep},
    eval_step(Predicates, [ejsonpath_common:argument(Node, "$")], Context).

eval_step([{Children, {predicate, Predicate}} | Rest], Result, Cxt) ->
    ?EJSONPATH_LOG({enter, Predicate}),
    NewResult = lists:foldl(
                  fun (Arg, Acc) ->
                          Acc ++ apply_eval(Predicate, Arg, Cxt)
                  end, [], children(Children, Result)),
    eval_step(Rest, NewResult, Cxt);
eval_step([], Result, _) -> ejsonpath_common:unzip(Result);
eval_step(_, _, _) ->
    erlang:error(not_implemented).

%% {key, _}
apply_eval({key, '*'}, #argument{type = hash, node = Node} = Arg, Ctx) ->
    ?EJSONPATH_LOG({key, hash, '*'}),
    Keys = maps:keys(Node),
    apply_eval({access_list, Keys}, Arg, Ctx);
apply_eval({key, '*'}, #argument{type = array, node = Node} = Arg, Ctx) ->
    ?EJSONPATH_LOG({key, array, '*'}),
    Idxs = lists:seq(0, erlang:length(Node)-1),
    apply_eval({access_list, Idxs}, Arg, Ctx);
apply_eval({key, Key}, #argument{type = hash} = Arg, Ctx) ->
    ?EJSONPATH_LOG({key, Key}),
    apply_eval({access_list, [Key]}, Arg, Ctx);
apply_eval({key, _}, _, _) ->
    [];
% {access_list, KeysOrIdxs}
apply_eval({access_list, Idxs}, #argument{type = array, node = Node, path = Path}, _) ->
    ?EJSONPATH_LOG({access_list, array, Idxs, Path}),
    Fun = fun (Idx0, Acc) ->
                  case ejsonpath_common:index(Idx0, erlang:length(Node)) of
                      {error, _} -> Acc;
                      {ok, Idx} ->
                          NodeAtIdx = lists:nth(Idx, Node),
                          Argument = ejsonpath_common:argument(NodeAtIdx, Path, Idx - 1),
                          [Argument | Acc]
                  end
          end,
    lists:reverse(lists:foldl(Fun, [], Idxs));
apply_eval({access_list, Keys}, #argument{type = hash, node = Node, path = Path}, _) ->
    ?EJSONPATH_LOG({access_list, hash, Keys, Path}),
    Fun = fun (Key, Acc) ->
                  case maps:get(Key, Node, '$undefined') of
                      '$undefined' -> Acc;
                      Child -> [ejsonpath_common:argument(Child, Path, Key)|Acc]
                  end
          end,
    lists:reverse(lists:foldl(Fun, [], Keys));

% {filter_expr, Script}
apply_eval({filter_expr, Script}, #argument{type = hash, node = Node, path = Path} = Arg, Ctx) ->
    ?EJSONPATH_LOG({filter_expr, hash, Script}),
    Fun = fun (Key, Value, Acc) ->
                  Argument = ejsonpath_common:argument(Value, Path, Key),
                  Evaluated = ejsonpath_common:script_eval(Script, Argument, Ctx),
                  case ejsonpath_common:to_boolean(Evaluated) of
                      false -> Acc;
                      _ -> [Key|Acc]
                  end
          end,
    Keys = lists:reverse(maps:fold(Fun, [], Node)),
    apply_eval({access_list, Keys}, Arg, Ctx);
apply_eval({filter_expr, Script}, #argument{type = array, node = Node, path = Path} = Arg, Ctx) ->
    ?EJSONPATH_LOG({filter_expr, array, Script}),
    Fun = fun (Item, {Idx, Acc}) ->
                  Argument = ejsonpath_common:argument(Item, Path, Idx),
                  Evaluated = ejsonpath_common:script_eval(Script, Argument, Ctx),
                  case ejsonpath_common:to_boolean(Evaluated) of
                      false -> {Idx+1, Acc};
                      _ -> {Idx+1, [Idx|Acc]}
                  end
          end,
    {_, Idxs} = lists:foldl(Fun, {0, []}, Node),
    apply_eval({access_list, lists:reverse(Idxs)}, Arg, Ctx);
apply_eval({filter_expr, Script}, #argument{} = Arg, Ctx) ->
    ?EJSONPATH_LOG({filter_expr, Script}),
    case ejsonpath_common:to_boolean(ejsonpath_common:script_eval(Script, Arg, Ctx)) of
        false -> [];
        _ -> [Arg]
    end;

%% {transform_expr, Script}
apply_eval({transform_expr, Script}, #argument{type = hash, node = Node, path = Path}, Ctx) ->
    ?EJSONPATH_LOG({transform_expr, hash, Path, Script}),
    Fun = fun (Key, Value, Acc) ->
                  Argument = ejsonpath_common:argument(Value, Path, Key),
                  Result = ejsonpath_common:script_eval(Script, Argument, Ctx),
                  [ejsonpath_common:argument(Result, Path, Key) | Acc]
          end,
    lists:reverse(maps:fold(Fun, [], Node));
apply_eval({transform_expr, Script}, #argument{type = array, node = Node, path = Path}, Ctx) ->
    ?EJSONPATH_LOG({transform_expr, array, Path, Script}),
    Fun = fun (Item, {Idx, Acc}) ->
                  Argument = ejsonpath_common:argument(Item, Path, Idx),
                  Result = ejsonpath_common:script_eval(Script, Argument, Ctx),
                  [ejsonpath_common:argument(Result, Path, Idx) | Acc ]
          end,
    {_, NewNode} = lists:foldl(Fun, {0, []}, Node),
    lists:reverse(NewNode);
apply_eval({transform_expr, Script}, #argument{path = Path} = Arg, Ctx) ->
    ?EJSONPATH_LOG({transform_expr, array, Path, Script}),
    Result = ejsonpath_common:script_eval(Script, Arg, Ctx),
    [#argument{type = ejsonpath_common:type(Result), node = Result, path = Path}];

%% {slice, S, E, Step}
apply_eval({slice, Start, End, Step}, #argument{type = array, node = Node} = Arg, Ctx) ->
    ?EJSONPATH_LOG({slice, array, Start, End, Step}),
    case ejsonpath_common:slice_seq(Start, End, Step, length(Node)) of
        {error, _} -> [];
        Seq ->
            apply_eval({access_list, Seq}, Arg, Ctx)
    end;
apply_eval(_P, _, _) ->
    ?EJSONPATH_LOG({not_implemented, _P}),
    erlang:error(not_implemented).

children(child, Nodes) -> Nodes;
children(descendant, Nodes) ->
    children_i(Nodes, []).

children_i([], Acc) ->
    Acc;
children_i([#argument{type = array, node = Node, path = Path } = Arg | Rest], Acc) ->
    Fun = fun (Child, {Idx, InnerAcc}) ->
                  Argument = ejsonpath_common:argument(Child, Path, Idx),
                  {Idx + 1, InnerAcc ++ children_i([Argument], [])}
          end,
    {_, AddAcc} = lists:foldl(Fun, {0, []}, Node),
    children_i(Rest, Acc ++ [Arg] ++ AddAcc);
children_i([#argument{type = hash, node = Node, path = Path} = Arg | Rest], Acc) ->
    Fun = fun (Key, Child, InnerAcc) ->
                  Argument = ejsonpath_common:argument(Child, Path, Key),
                  InnerAcc ++ children_i([Argument], [])
          end,
    AddAcc = maps:fold(Fun, [], Node),
    children_i(Rest, Acc ++ [Arg] ++ AddAcc);
children_i([Arg = #argument{}| Rest], Acc) ->
    children_i(Rest, Acc ++ [Arg]).
