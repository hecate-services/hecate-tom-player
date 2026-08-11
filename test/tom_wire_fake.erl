%% @doc A mesh made of a function, so the restart path can be exercised without
%% a station within a hundred kilometres.
%%
%% Install a fun of `(Procedure, Payload) -> tom_wire:answer()' and the house
%% talks to it exactly as it talks to two ports and an ocean. Every call is
%% recorded, which is how a test asserts the thing that matters most: that a
%% retried order goes out under the SAME key.
-module(tom_wire_fake).
-behaviour(tom_wire).

-export([install/1, calls/0, calls_to/1, forget/0]).
-export([call/3, subscribe/2]).

-define(TAB, tom_wire_fake_calls).
-define(ANSWER, {?MODULE, answer}).

%% @doc Point the house at this module and answer with `Fun'.
-spec install(fun((binary(), map()) -> tom_wire:answer())) -> ok.
install(Fun) when is_function(Fun, 2) ->
    forget(),
    ?TAB = ets:new(?TAB, [named_table, public, ordered_set]),
    persistent_term:put(?ANSWER, Fun),
    application:set_env(hecate_tom_house, wire, ?MODULE).

-spec forget() -> ok.
forget() ->
    _ = catch ets:delete(?TAB),
    _ = persistent_term:erase(?ANSWER),
    ok.

%% @doc Every call the house made, oldest first.
-spec calls() -> [{binary(), map()}].
calls() -> [{Procedure, Payload} || {_Seq, Procedure, Payload} <- ets:tab2list(?TAB)].

%% @doc Every call whose procedure ends in the given name.
-spec calls_to(binary()) -> [map()].
calls_to(Name) ->
    Size = byte_size(Name),
    [Payload || {Procedure, Payload} <- calls(),
                byte_size(Procedure) >= Size,
                binary:part(Procedure, byte_size(Procedure) - Size, Size) =:= Name].

%%% tom_wire

call(Procedure, Payload, _TimeoutMs) ->
    ets:insert(?TAB, {erlang:unique_integer([monotonic]), Procedure, Payload}),
    Fun = persistent_term:get(?ANSWER),
    Fun(Procedure, Payload).

subscribe(_Topic, _Subscriber) ->
    {error, no_mesh}.
