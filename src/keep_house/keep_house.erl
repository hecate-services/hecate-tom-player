%% @doc The one process that owns the house: its purse, its book of orders, its
%% picture of its ship, and the log that all three are folded from.
%%
%% This exists so that every act that moves money is serialised through one
%% place with one disk behind it. Two orders settling at once against a purse
%% held in two processes is a lost update, and a lost update in a purse is a
%% player who cannot tell whether the game cheated.
%%
%% WHAT IS DURABLE AND WHAT IS NOT is the whole design of this module.
%%
%%   durable    the purse, every order and how it concluded, and the last
%%              picture of the ship. Written and synced BEFORE anybody is told.
%%   volatile   prices, the news ticker, the last thing that went wrong. All of
%%              it is somebody else's fact, refetched in seconds, and none of it
%%              is worth a disk write every five seconds for the rest of time.
%%
%% GENESIS APPLIES ONCE. The configured purse enters the log only when the log
%% has no record of this house ever having opened. A house that re-seeded its
%% purse from a config file on every boot would mint money by crashing, which is
%% the same mistake as a harbour that re-seeds a ship and ends up with two of it.
%% @end
-module(keep_house).
-behaviour(gen_server).

-export([start_link/1]).
-export([names/0, house/0, snapshot/0, mint_order/0]).
-export([record/1, sight/1, note_quotes/2, note_news/2, note_trouble/2]).
-export([watch/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

%% How much of the ticker to keep. Long enough to see a voyage's whole story,
%% short enough that a house left running for a week does not grow a memory leak
%% shaped like a newspaper.
-define(NEWS_KEPT, 40).

-record(state, {
    names   :: tom_names:names(),
    ledger  :: tom_ledger:ledger(),
    house   :: tom_house:house(),
    quotes = #{} :: #{binary() => map()},
    news = []    :: [map()],
    trouble = #{} :: #{atom() => map()},
    watchers = #{} :: #{pid() => reference()}
}).

%%% API

-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Config) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Config, []).

%% @doc Every name this house uses. Read once at boot and never changes, so
%% every slice borrows it from here rather than re-deriving it.
-spec names() -> tom_names:names().
names() -> gen_server:call(?MODULE, names).

-spec house() -> tom_house:house().
house() -> gen_server:call(?MODULE, house).

%% @doc Everything the page shows, in one term.
-spec snapshot() -> map().
snapshot() -> gen_server:call(?MODULE, snapshot).

%% @doc A key for one order, unique to this house and this order.
%%
%% The harbour stores its receipt under this and replays it on a repeat call,
%% which is what makes a retry after a crash safe rather than a second purchase.
-spec mint_order() -> binary().
mint_order() -> binary:encode_hex(crypto:strong_rand_bytes(16), lowercase).

%% @doc Write one fact to the log and fold it in. Returns once it is on disk.
-spec record(tom_house:fact()) -> ok.
record(Fact) -> gen_server:call(?MODULE, {record, Fact}).

%% @doc Offer a new picture of the ship. Recorded only when it says something
%% the last one did not, because a poll every ten seconds for a week is sixty
%% thousand identical records and no new information.
-spec sight(map()) -> ok.
sight(Sight) -> gen_server:call(?MODULE, {sight, Sight}).

%% @doc What a port says things cost. Volatile.
-spec note_quotes(binary(), map()) -> ok.
note_quotes(HarbourMRI, Quotes) ->
    gen_server:cast(?MODULE, {quotes, HarbourMRI, Quotes}).

%% @doc Something happened out there. Volatile, and load-bearing for nothing:
%% the ticker exists so a player sees a voyage as it happens, and the house is
%% exactly as correct without it.
-spec note_news(atom(), map()) -> ok.
note_news(Fact, Payload) -> gen_server:cast(?MODULE, {news, Fact, Payload}).

%% @doc The last thing that went wrong in some corner, so the page can say so
%% instead of showing a stale number as though it were current.
-spec note_trouble(atom(), term()) -> ok.
note_trouble(Where, Reason) -> gen_server:cast(?MODULE, {trouble, Where, Reason}).

%% @doc Follow the house. The caller receives `{house_changed, Snapshot}' on
%% every change until it dies.
-spec watch(pid()) -> ok.
watch(Pid) -> gen_server:call(?MODULE, {watch, Pid}).

%%% gen_server

init(Config) ->
    process_flag(trap_exit, true),
    Names = maps:get(names, Config),
    {ok, Ledger, Facts} = tom_ledger:open(maps:get(ledger, Config)),
    House = tom_house:replay(Facts, tom_house:empty()),
    State = #state{names = Names, ledger = Ledger, house = House},
    {ok, opened(tom_house:opened(House), Config, State)}.

handle_call(names, _From, #state{names = N} = S) ->
    {reply, N, S};

handle_call(house, _From, #state{house = H} = S) ->
    {reply, H, S};

handle_call(snapshot, _From, S) ->
    {reply, view(S), S};

handle_call({record, Fact}, _From, S) ->
    {reply, ok, told(write(Fact, S))};

handle_call({sight, Sight}, _From, S) ->
    {reply, ok, resighted(worth_recording(Sight, S), Sight, S)};

handle_call({watch, Pid}, _From, #state{watchers = W} = S) ->
    Ref = erlang:monitor(process, Pid),
    {reply, ok, S#state{watchers = W#{Pid => Ref}}};

handle_call(_Other, _From, S) ->
    {reply, {error, unknown_call}, S}.

handle_cast({quotes, Harbour, Quotes}, #state{quotes = Q} = S) ->
    {noreply, told(S#state{quotes = Q#{Harbour => Quotes}})};

handle_cast({news, Fact, Payload}, #state{news = News} = S) ->
    Item = #{fact => Fact, at => erlang:system_time(millisecond), payload => Payload},
    {noreply, told(S#state{news = lists:sublist([Item | News], ?NEWS_KEPT)})};

handle_cast({trouble, Where, Reason}, #state{trouble = T} = S) ->
    Item = #{reason => Reason, at => erlang:system_time(millisecond)},
    {noreply, told(S#state{trouble = T#{Where => Item}})};

handle_cast(_Other, S) ->
    {noreply, S}.

handle_info({'DOWN', _Ref, process, Pid, _Reason}, #state{watchers = W} = S) ->
    {noreply, S#state{watchers = maps:remove(Pid, W)}};

handle_info(_Other, S) ->
    {noreply, S}.

terminate(_Reason, #state{ledger = L}) ->
    tom_ledger:close(L).

%%% Internal

%% The genesis clause. `false' means this log has never seen the house open, so
%% the configured purse applies now and never again.
opened(true, _Config, State) ->
    State;
opened(false, Config, #state{names = Names} = State) ->
    write({house_opened_v1, #{purse => maps:get(purse, Config),
                              ship  => maps:get(ship, Names),
                              at    => erlang:system_time(millisecond)}},
          State).

%% The write is synced before the fold, so a house that dies between the two
%% comes back with the fact and folds it then. The other order would let it
%% believe something it never wrote down.
write(Fact, #state{ledger = L, house = H} = S) ->
    ok = tom_ledger:append(L, Fact),
    S#state{house = tom_house:apply_fact(Fact, H)}.

%% A sighting is worth a disk write exactly when applying it would change the
%% picture. Asking the aggregate what it WOULD look like, rather than comparing
%% fields by hand, is what stops this drifting from `apply_fact/2': a poll that
%% offers no hull leaves the hull alone there, and must therefore count as no
%% change here, or the house writes a record every ten seconds forever.
worth_recording(Sight, #state{house = H}) ->
    picture(tom_house:apply_fact({ship_sighted_v1, Sight}, H)) =/= picture(H).

picture(H) ->
    {maps:without([sighted_at], tom_house:sight(H)), tom_house:hull(H)}.

resighted(false, _Sight, S) ->
    S;
resighted(true, Sight, S) ->
    told(write({ship_sighted_v1, Sight}, S)).

told(#state{watchers = W} = S) ->
    View = view(S),
    _ = [Pid ! {house_changed, View} || Pid <- maps:keys(W)],
    S.

view(#state{names = N, house = H, quotes = Q, news = News, trouble = T}) ->
    #{names     => N,
      purse     => tom_house:purse(H),
      hull      => tom_house:hull(H),
      cargo     => tom_house:cargo(H),
      hold      => tom_house:hold(H),
      free_hold => tom_house:free_hold(H),
      sight     => tom_house:sight(H),
      orders    => tom_house:orders(H),
      quotes    => Q,
      news      => News,
      trouble   => T,
      at        => erlang:system_time(millisecond)}.
