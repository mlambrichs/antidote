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
-module(antidote_hooks).

-include("antidote.hrl").

-include_lib("eunit/include/eunit.hrl").

-export([register_pre_hook/3,
         register_post_hook/3,
         get_hooks/2,
         unregister_hook/2
        ]).

-ifdef(TEST).
-export([test_commit_hook/1]).
-endif.

-define(PREFIX_PRE, {commit_hooks, pre}).
-define(PREFIX_POST, {commit_hooks, post}).

-type module_name() :: atom().
-type function_name() :: atom().

-spec register_post_hook(bucket(), module_name(), function_name()) -> ok | {error, reason()}.
register_post_hook(Bucket, Module, Function) ->
    register_hook(?PREFIX_POST, Bucket, Module, Function).

-spec register_pre_hook(bucket(), module_name(), function_name()) -> ok | {error, reason()}.
register_pre_hook(Bucket, Module, Function) ->
    register_hook(?PREFIX_PRE, Bucket, Module, Function).

%% Overwrites the previous commit hook
register_hook(Prefix, Bucket, Module, Function) ->
    case erlang:function_exported(Module, Function, 1) of
        true ->
            riak_core_metadata:put(Prefix, Bucket, {Module, Function}),
            ok;        
        false ->
            {error, function_not_exported}
    end.
            
unregister_hook(pre_commit, Bucket) ->
    riak_core_metadata:delete(?PREFIX_PRE, Bucket);

unregister_hook(post_commit, Bucket) ->
    riak_core_metadata:delete(?PREFIX_POST, Bucket).

get_hooks(pre_commit, Bucket) ->
    riak_core_metadata:get(?PREFIX_PRE, Bucket);

get_hooks(post_commit, Bucket) ->
    riak_core_metadata:get(?PREFIX_POST, Bucket).

-ifdef(TEST).
test_commit_hook(Object) ->
    lager:info("Executing test commit hook"),
    Object.

-endif.