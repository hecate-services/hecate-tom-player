%% @doc Drive every order that never reached a conclusion to one.
%%
%% This is the second half of the reliability pattern, and the half that only
%% earns its keep after a crash. An order is written to disk before the call goes
%% out, so a house that dies between the write and the answer comes back with an
%% order and no conclusion. This sweeps those up, calls again with the ORIGINAL
%% key, and takes whatever the harbour replays.
%%
%% IT RETRIES FOREVER AND NEVER GIVES UP ON ITS OWN INITIATIVE. A harbour that is
%% down for an hour is an order that is open for an hour, which is the truth and
%% is visible on the page. The only things that close an order are a receipt and
%% a refusal, both of which come from the harbour, because the harbour is the one
%% that knows.
%% @end
-module(settle_orders).
-behaviour(gen_server).

-export([start_link/1, resume/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

%% The contract's cadence: every five seconds, forever, resuming at boot.
-define(SWEEP_MS, 5_000).

-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Config) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Config, []).

%% @doc One sweep, synchronously. Exported because it is the whole behaviour and
%% a test should be able to run it without waiting five seconds for a timer.
-spec resume() -> ok.
resume() ->
    lists:foreach(fun drive/1, tom_house:unsettled(keep_house:house())).

%%% gen_server

init(_Config) ->
    self() ! sweep,
    {ok, #{}}.

handle_call(_Msg, _From, S) -> {reply, {error, unknown_call}, S}.

handle_cast(_Msg, S) -> {noreply, S}.

handle_info(sweep, S) ->
    ok = resume(),
    _ = erlang:send_after(?SWEEP_MS, self(), sweep),
    {noreply, S};
handle_info(_Msg, S) ->
    {noreply, S}.

terminate(_Reason, _S) -> ok.

%%% Internal

%% The answer is deliberately dropped. A sweep is not a caller waiting on a
%% result: each slice writes its own conclusion to the log, and this only has to
%% make the call happen.
drive(#{kind := purchase} = Order) ->
    _ = buy_cargo:settle(Order),
    ok;
drive(#{kind := sale} = Order) ->
    _ = sell_cargo:settle(Order),
    ok.
