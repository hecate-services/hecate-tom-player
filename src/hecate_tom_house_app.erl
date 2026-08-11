%% @doc The application. One call, and hecate_om does the rest.
%%
%% `hecate_om:boot/1' registers the service module, wires the capability
%% announcement and the /health endpoint, and then calls `start/1' on the service
%% module. The house exports no `store_id/0' and no `data_dir/0', so no reckon-db
%% store is started: this service keeps its own small append-only log and needs
%% nothing bigger.
%% @end
-module(hecate_tom_house_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) ->
    hecate_om:boot(hecate_tom_house_service).

stop(_State) ->
    ok.
