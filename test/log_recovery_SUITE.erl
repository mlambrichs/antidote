%% -------------------------------------------------------------------
%%
%% Copyright (c) 2014 SyncFree Consortium.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

-module(log_recovery_SUITE).

-compile({parse_transform, lager_transform}).

%% common_test callbacks
-export([
         init_per_suite/1,
         end_per_suite/1,
         init_per_testcase/2,
         end_per_testcase/2,
         all/0]).

%% tests
-export([read_pncounter_log_recovery_test/1]).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("kernel/include/inet.hrl").

init_per_suite(Config) ->
    lager_common_test_backend:bounce(debug),
    test_utils:at_init_testsuite(),
    Clusters = test_utils:set_up_clusters_common(Config),
    Nodes = hd(Clusters),
    [{nodes, Nodes}|Config].

end_per_suite(Config) ->
    Config.

init_per_testcase(_Case, Config) ->
    Config.

end_per_testcase(_, _) ->
    ok.

all() -> [read_pncounter_log_recovery_test].

%% First we remember the initial time of the counter (with value 0).
%% After 15 updates, we kill the nodes
%% We then restart the nodes, and read the value
%% being sure that all 15 updates were loaded from the log
read_pncounter_log_recovery_test(Config) ->    
    Nodes = proplists:get_value(nodes, Config),
    FirstNode = hd(Nodes),
    Type = antidote_crdt_counter,
    Key = log_value_test,
    
    {ok, TxId} = rpc:call(FirstNode, antidote, clocksi_istart_tx, []),
    increment_counter(FirstNode, Key, 15),
    %% value from old snapshot is 0
    {ok, ReadResult1} = rpc:call(FirstNode,
        antidote, clocksi_iread, [TxId, Key, Type]),
    ?assertEqual(0, ReadResult1),
    %% read value in txn is 15
    {ok, {_, [ReadResult2], _}} = rpc:call(FirstNode,
        antidote, clocksi_read, [Key, Type]),
    ?assertEqual(15, ReadResult2),

    lager:info("Killing and restarting the nodes"),
    %% Shut down the nodes
    Nodes = test_utils:kill_and_restart_nodes(Nodes,Config),
    lager:info("Vnodes are started up"),
    lager:info("Nodes: ~p", [Nodes]),

    %% Read the value again
    {ok, {_, [ReadResult3], _}} = rpc:call(FirstNode, antidote, clocksi_execute_tx,
             [[{read, {Key, Type}}]]),
    ?assertEqual(15, ReadResult3),
    lager:info("read_pncounter_log_recovery_test finished").

%% Auxiliary method to increment a counter N times.
increment_counter(_FirstNode, _Key, 0) ->
    ok;
increment_counter(FirstNode, Key, N) ->
    WriteResult = rpc:call(FirstNode, antidote, clocksi_execute_tx,
        [[{update, {Key, antidote_crdt_counter, {increment, 1}}}]]),
    ?assertMatch({ok, _}, WriteResult),
    increment_counter(FirstNode, Key, N - 1).
