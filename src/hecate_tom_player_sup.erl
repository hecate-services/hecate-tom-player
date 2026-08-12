%% @doc The house's supervision tree.
%%
%% REST_FOR_ONE, AND THE ORDER IS THE DEPENDENCY ORDER. `keep_house' owns the
%% purse, the log and the book of orders, and every process after it calls into
%% it. If it dies they must all come back with it, because each of them holds a
%% conclusion about a house that no longer exists in that form. One_for_one would
%% leave four processes talking to a keeper that has forgotten them, which shows
%% up as a page that half updates.
%%
%% The listener is last. A page served before there is a house to describe is a
%% crash where a blank screen would do.
%%
%% INTENSITY IS DELIBERATELY LOW. A house whose disk will not take a write cannot
%% trade, and the correct behaviour then is to fall over so /health says so, not
%% to spin quietly forever refusing to remember anything.
%% @end
-module(hecate_tom_player_sup).
-behaviour(supervisor).

-export([start_link/1]).
-export([init/1]).

-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Config) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, Config).

init(Config) ->
    Flags = #{strategy  => rest_for_one,
              intensity => 3,
              period    => 10},
    Children = [worker(keep_house, Config),
                worker(watch_ports, Config),
                worker(read_quotes, Config),
                worker(find_ship, Config),
                worker(settle_orders, Config),
                page_listener(Config)],
    {ok, {Flags, Children}}.

%%% Internal

worker(Module, Config) ->
    #{id       => Module,
      start    => {Module, start_link, [Config]},
      restart  => permanent,
      shutdown => 5000,
      type     => worker,
      modules  => [Module]}.

page_listener(Config) ->
    Dispatch = cowboy_router:compile([{'_', show_house:routes()}]),
    ranch:child_spec(tom_house_page,
                     ranch_tcp, [{port, maps:get(web_port, Config)}],
                     cowboy_clear, #{env => #{dispatch => Dispatch}}).
