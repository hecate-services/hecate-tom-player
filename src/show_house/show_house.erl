%% @doc The page a human looks at, and the same thing as JSON for anyone who
%% would rather curl it.
%%
%% Five routes, and only one of them is for a browser:
%%
%%   GET  /          the page
%%   GET  /view      the same snapshot as JSON, for a shell
%%   GET  /stream    server-sent events, one rendered board per change
%%   GET  /coastline the shape of the earth, once
%%   POST /act       buy, sell, sail, price, or ask again
%%
%% THE COASTLINE IS NOT GAME DATA and does not come over the mesh. The world
%% service owns what EXISTS in the game: goods, ports, recipes, the routes
%% between them. Where the land is is not a fact anybody in this game owns, it
%% is the earth, and it is the same for every player for ever. So it ships with
%% this release as a file, is fetched once, and is the only thing here a browser
%% is allowed to cache.
%%
%% This listener is the house's OWN, on its own port, beside the one hecate_om
%% runs for /health. They are separate because they answer to different people:
%% /health answers to whatever supervises the container and must stay boring,
%% and this answers to a player.
%% @end
-module(show_house).

-export([routes/0, init/2]).

-spec routes() -> [{string(), module(), term()}].
routes() ->
    [{"/", ?MODULE, page},
     {"/view", ?MODULE, view},
     {"/coastline", ?MODULE, coastline},
     {"/stream", show_house_stream, []},
     {"/act", show_house_act, []}].

init(Req0, page) ->
    Body = show_house_page:page(keep_house:snapshot()),
    {ok, sent(<<"text/html; charset=utf-8">>, Body, Req0), page};
init(Req0, view) ->
    Body = json:encode(show_house_json:snapshot(keep_house:snapshot())),
    {ok, sent(<<"application/json">>, Body, Req0), view};
init(Req0, coastline) ->
    {ok, Body} = file:read_file(
                   filename:join([code:priv_dir(hecate_tom_player),
                                  "coastline.json"])),
    {ok, kept(<<"application/json">>, Body, Req0), coastline}.

%%% Internal

%% Nothing here is cacheable. A price four seconds old shown as though it were
%% now is worse than no price, and a browser that helpfully remembers a purse is
%% a browser lying to a player about their money.
sent(Type, Body, Req) ->
    cowboy_req:reply(200,
                     #{<<"content-type">>  => Type,
                       <<"cache-control">> => <<"no-store">>},
                     Body, Req).

%% The one exception, and it is not a game fact. Coastlines have not moved since
%% before this game is set and will not move before it is over.
kept(Type, Body, Req) ->
    cowboy_req:reply(200,
                     #{<<"content-type">>  => Type,
                       <<"cache-control">> => <<"public, max-age=604800">>},
                     Body, Req).
