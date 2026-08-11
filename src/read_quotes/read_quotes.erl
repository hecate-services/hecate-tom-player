%% @doc Ask both ports what things cost, over and over, so the page has prices
%% on it.
%%
%% THE GOODS ARE NAMED, NEVER LEFT EMPTY. `list_quotes' with an empty list
%% returns every good the port trades, which is sixty-seven rows for a page that
%% wants eight of them. The house knows which eight it is showing, so it says so.
%%
%% Prices are volatile by nature and nothing here is written to disk. A quote is
%% somebody else's fact with a timestamp on it, refetched in seconds, and the
%% page shows how old it is rather than pretending it is now.
%%
%% The ports are asked one after another in this process rather than in parallel
%% workers, and the next round is scheduled after the last answer rather than on
%% a fixed clock. Two ports that are both slow then cost one slow round instead
%% of an ever-growing pile of overlapping ones.
%% @end
-module(read_quotes).
-behaviour(gen_server).

-export([start_link/1, ask_now/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Config) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Config, []).

%% @doc One round of asking, synchronously. For a page that wants fresh prices
%% right now, and for a test that does not want to wait for a timer.
-spec ask_now() -> ok.
ask_now() -> gen_server:call(?MODULE, ask, 30_000).

%%% gen_server

init(Config) ->
    Names = maps:get(names, Config),
    self() ! ask,
    {ok, #{names    => Names,
           goods    => [MRI || {_Local, MRI} <- maps:get(goods, Names)],
           interval => maps:get(quote_interval_ms, Config)}}.

handle_call(ask, _From, S) ->
    ok = one_round(S),
    {reply, ok, S};
handle_call(_Msg, _From, S) ->
    {reply, {error, unknown_call}, S}.

handle_cast(_Msg, S) -> {noreply, S}.

handle_info(ask, #{interval := Interval} = S) ->
    ok = one_round(S),
    _ = erlang:send_after(Interval, self(), ask),
    {noreply, S};
handle_info(_Msg, S) ->
    {noreply, S}.

terminate(_Reason, _S) -> ok.

%%% Internal

one_round(#{names := Names, goods := Goods}) ->
    lists:foreach(fun({_Local, Harbour}) -> one_port(Harbour, Goods) end,
                  maps:get(harbours, Names)).

one_port(Harbour, Goods) ->
    posted(tom_wire:call(tom_names:procedure(Harbour, <<"list_quotes">>),
                         #{<<"goods">> => Goods}, read),
           Harbour).

posted({ok, Reply}, Harbour) ->
    ok = keep_house:note_quotes(Harbour,
                                #{quotes  => maps:get(<<"quotes">>, Reply, []),
                                  told_at => maps:get(<<"at">>, Reply, undefined),
                                  seen_at => erlang:system_time(millisecond)}),
    keep_house:note_all_well(read_quotes);
posted({refused, Why}, Harbour) ->
    keep_house:note_trouble(read_quotes, {Harbour, Why});
posted({unreachable, Why}, Harbour) ->
    keep_house:note_trouble(read_quotes, {Harbour, Why}).
