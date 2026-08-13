%% @doc Find out where the hull actually is, by asking.
%%
%% THIS IS THE POINT OF THE WHOLE ARCHITECTURE. A house can be shut down for an
%% entire voyage and know exactly where its ship is within one pass of this
%% module, because nothing it needs was ever pushed at it.
%%
%% ONE QUESTION NOW, ASKED OF EVERY PORT. It used to be two, because an ocean
%% held a hull in transit and no port could answer for her. Custody never leaves
%% the port she sailed from until the far port says held, so that port answers
%% for her the whole way across: moored, or in passage and due at this instant,
%% or not here.
%%
%% WHEN TWO PORTS BOTH CLAIM THE SHIP, THE HIGHER HOP WINS. That is the custody
%% rule verbatim: custody is held by whoever recorded taking the ship at the
%% highest hop, the counter is monotone, and only a durable acceptance advances
%% it. No vote, no quorum, no arbiter, and nothing here compares two machines'
%% clocks to decide anything.
%%
%% SILENCE AND not_here ARE NOT THE SAME ANSWER, and running them together is how
%% a house on a flaky link tells a player their ship never existed. A port that
%% says not_here has answered. A port that says nothing has not, and a pass where
%% nobody answered claims nothing: the last picture stays on the page with its
%% age showing, which is what an age is for.
%%
%% WHEN EVERY PORT ANSWERS AND NONE OF THEM HAS HER, THIS HOUSE DECIDES. There is
%% no archive left to ask: an ocean kept every crossing since the world began and
%% that was the archive of a party, which an ocean never was. A hull that no port
%% holds and that was due an hour ago did not arrive. That is the one inference
%% in the game and it is drawn from this house's own ledger, which is the only
%% record anywhere that she ever sailed.
%%
%% A FACT NEVER MOVES THE PICTURE, it only triggers a pass. That keeps the
%% house's own record ordered by one process asking in one order, instead of by
%% whichever of six publications happened to arrive first.
%% @end
-module(find_ship).
-behaviour(gen_server).

-export([start_link/1, look/0, look_around/1, look_around/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

%% A burst of facts arriving together is one thing happening, not six. Passes
%% closer together than this are folded into one that runs shortly.
-define(COALESCE_MS, 1_000).

%% @doc Where a pass ended up.
-type outcome() :: {sight, map()} | {no_news, term()}.

-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Config) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Config, []).

%% @doc Ask again, soon. Idempotent and safe to shout at.
-spec look() -> ok.
look() -> gen_server:cast(?MODULE, look).

%% @doc One pass, as a function of the names and whatever the mesh says.
%% Exported because this is the behaviour worth testing and it needs no process.
-spec look_around(tom_names:names()) -> outcome().
look_around(Names) -> look_around(Names, undefined).

%% @doc One pass, told what this house last believed, so that a hull nobody is
%% holding can be told apart from a hull nobody has ever had.
-spec look_around(tom_names:names(), map() | undefined) -> outcome().
look_around(Names, Last) -> ashore(asked(Names), Last).

%%% gen_server

init(Config) ->
    self() ! look,
    {ok, #{names    => maps:get(names, Config),
           interval => maps:get(locate_interval_ms, Config),
           timer    => undefined,
           last     => 0}}.

handle_call(_Msg, _From, S) -> {reply, {error, unknown_call}, S}.

handle_cast(look, S) -> {noreply, soon(S)};
handle_cast(_Msg, S)  -> {noreply, S}.

handle_info(look, S) -> {noreply, run(S)};
handle_info(_Msg, S) -> {noreply, S}.

terminate(_Reason, _S) -> ok.

%%% Internal

%% A poke that lands right after a pass waits a moment rather than starting a
%% second one, so six facts about one arrival cost one round of questions.
soon(#{last := Last} = S) ->
    due(erlang:system_time(millisecond) - Last < ?COALESCE_MS, S).

due(true, S)  -> armed(?COALESCE_MS, S);
due(false, S) -> run(S).

run(#{names := Names, interval := Interval} = S) ->
    ok = acted(look_around(Names, believed())),
    armed(Interval, S#{last => erlang:system_time(millisecond)}).

%% What this house currently thinks. Read fresh on each pass rather than carried
%% here, because keep_house owns it and a second copy would go stale.
believed() -> tom_house:sight(keep_house:house()).

armed(After, #{timer := Timer} = S) ->
    _ = cancelled(Timer),
    S#{timer => erlang:send_after(After, self(), look)}.

cancelled(undefined) -> ok;
cancelled(Timer)     -> erlang:cancel_timer(Timer).

acted({sight, Sight})   -> ok = keep_house:sight(Sight),
                           keep_house:note_all_well(find_ship);
acted({no_news, Why})   -> keep_house:note_trouble(find_ship, Why).

ship_of(Names) -> #{<<"ship">> => maps:get(ship, Names)}.

ask(Target, Procedure, Payload) ->
    tom_wire:call(tom_names:procedure(Target, Procedure), Payload, read).

%% Every port this house trades with, and what each of them said.
asked(Names) ->
    [{Harbour, ask(Harbour, <<"get_ship">>, ship_of(Names))}
     || {_Local, Harbour} <- maps:get(harbours, Names)].

ashore(Replies, Last) ->
    weighed([Held || {Harbour, Reply} <- Replies,
                     Held <- [holding(Harbour, Reply)],
                     Held =/= none],
            Replies, Last).

weighed([], Replies, Last)     -> nobody_holds_her(Replies, Last);
weighed(Holders, _Replies, _L) -> {sight, alongside(highest(Holders))}.

holding(Harbour, {ok, #{<<"state">> := <<"moored">>} = Reply}) ->
    {Harbour, moored, hull_of(Reply), Reply};
holding(Harbour, {ok, #{<<"state">> := <<"in_passage">>} = Reply}) ->
    {Harbour, in_passage, hull_of(Reply), Reply};
holding(_Harbour, _Anything_else) ->
    none.

hull_of(Reply) -> a_hull(maps:get(<<"ship">>, Reply, undefined)).

a_hull(Hull) when is_map(Hull) -> Hull;
a_hull(_NotAShip)              -> undefined.

%% The custody rule in one line.
highest(Holders) ->
    hd(lists:sort(fun(A, B) -> hop(A) >= hop(B) end, Holders)).

hop({_Harbour, _State, Hull, _Reply}) when is_map(Hull) ->
    maps:get(<<"hop">>, Hull, -1);
hop(_Held) ->
    -1.

%% A HULL IN PASSAGE IS NOT AT THE PORT THAT ANSWERS FOR HER. That port hosts her
%% passage and is her custodian on paper; where she IS is at sea. The reply
%% carries `due_at', an absolute instant, and never a duration: how long a
%% crossing takes is the sea's constant and this house has no business deriving
%% it.
alongside({Harbour, in_passage, Hull, Reply}) ->
    #{standing  => in_passage,
      where     => Harbour,
      hull      => Hull,
      bound_for => maps:get(<<"bound_for">>, Reply, undefined),
      sailed_at => maps:get(<<"sailed_at">>, Reply, undefined),
      due_at    => maps:get(<<"due_at">>, Reply, undefined),
      path      => maps:get(<<"path">>, Reply, []),
      at        => erlang:system_time(millisecond)};
alongside({Harbour, moored, Hull, _Reply}) ->
    #{standing  => moored,
      where     => Harbour,
      hull      => Hull,
      bound_for => undefined,
      at        => erlang:system_time(millisecond)}.

%% Nobody is holding her, and what that means depends entirely on who spoke.
nobody_holds_her(Replies, Last) ->
    concluded(strange(Replies), answered(Replies), Last).

answered(Replies) -> [Reply || {_Harbour, {ok, _} = Reply} <- Replies].

%% A port answering in a shape this house has never heard of is news rather than
%% a picture. Guessing at what a new state means is worse than saying it is new.
strange(Replies) ->
    [Reply || {_Harbour, {ok, Reply}} <- Replies,
              not lists:member(maps:get(<<"state">>, Reply, undefined),
                               [<<"moored">>, <<"in_passage">>, <<"not_here">>])].

concluded([Strange | _], _Answered, _Last) ->
    {no_news, {a_port_said_something_new, Strange}};
concluded([], [], _Last) ->
    {no_news, nobody_answered};
concluded([], _Answered, Last) ->
    unheld(Last, erlang:system_time(millisecond)).

%% THE ONE INFERENCE IN THE GAME. Every port has answered and none of them has
%% her. If this house never saw her sail she is a hull nobody has ever had; if it
%% saw her sail and her hour has come and gone, she is on the bottom. The cause is
%% known only to a house that was listening when the port said so, and a sight
%% without one says nothing rather than inventing weather.
unheld(#{standing := in_passage, due_at := Due} = Last, Now)
  when is_integer(Due), Now > Due ->
    {sight, #{standing  => was_lost,
              where     => undefined,
              bound_for => maps:get(bound_for, Last, undefined),
              sailed_at => maps:get(sailed_at, Last, undefined),
              cause     => maps:get(cause, Last, undefined),
              at        => Now}};
unheld(#{standing := in_passage}, _Now) ->
    {no_news, she_is_at_sea_and_not_yet_due};
unheld(_Last, Now) ->
    {sight, #{standing => never_sailed, where => undefined, at => Now}}.
