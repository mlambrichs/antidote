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

%% This is a process running on each node, that is responsible for receiving
%% queries from other DCs, the types of messages that can be sent are found in
%% include/antidote_message_types.hrl
%% To handle new types, need to update the handle_info method below
%% As well as in the sender of the query at inter_dc_query

-module(inter_dc_query_receive_socket).
-behaviour(gen_server).
-include("antidote.hrl").
-include("inter_dc_repl.hrl").

%% API
-export([
  get_address/0,
  get_address_list/0,
  send_response/2]).

%% Server methods
-export([
  init/1,
  start_link/0,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

%% State
-record(state, {socket, id, next}). %% socket :: erlzmq_socket()

%%%% API --------------------------------------------------------------------+

%% Fetch the local address of a log_reader socket.
-spec get_address() -> socket_address().
get_address() ->
  {ok, List} = inet:getif(),
  {Ip, _, _} = hd(List),
  {ok, Port} = application:get_env(antidote, logreader_port),
  {Ip, Port}.

-spec get_address_list() -> {[partition_id()],[socket_address()]}.
get_address_list() ->
    PartitionList = dc_utilities:get_my_partitions(),
    {ok, List} = inet:getif(),
    {ok, Port} = application:get_env(antidote, logreader_port),
    AddressList = [{Ip1,Port} || {Ip1, _, _} <- List, Ip1 /= {127, 0, 0, 1}],
    {PartitionList, AddressList}.

-spec send_response(binary(), #inter_dc_query_state{}) -> ok.
send_response(BinaryResponse, QueryState = #inter_dc_query_state{local_pid=Sender}) ->
    ok = gen_server:cast(Sender, {send_response,BinaryResponse,QueryState}).

%%%% Server methods ---------------------------------------------------------+

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    {_, Port} = get_address(),
    Socket = zmq_utils:create_bind_socket(xrep, true, Port),
    _Res = random:seed(dc_utilities:now()),
    lager:info("Log reader started on port ~p", [Port]),
    {ok, #state{socket = Socket,next=getid}}.

%% Handle the remote request
%% ZMQ requests come in 3 parts
%% 1st the Id of the sender, 2nd an empty binary, 3rd the binary msg
handle_info({zmq, _Socket, Id, [rcvmore]}, State=#state{next=getid}) ->
    {noreply, State#state{next = blankmsg, id=Id}};
handle_info({zmq, _Socket, <<>>, [rcvmore]}, State=#state{next=blankmsg}) ->
    {noreply, State#state{next=getmsg}};
handle_info({zmq, Socket, BinaryMsg, _Flags}, State=#state{id=Id,next=getmsg}) ->
    %% Decode the message
    {ReqId,RestMsg} = binary_utilities:check_version_and_req_id(BinaryMsg),
    %% Create a response
    QueryState = #inter_dc_query_state{zmq_id = Id,
				       request_id_num_binary = ReqId,
				       local_pid = self()},
    case RestMsg of
	<<?LOG_READ_MSG,QueryBinary/binary>> ->
	    ok = inter_dc_query_response:get_entries(QueryBinary,QueryState#inter_dc_query_state{request_type=?LOG_READ_MSG});
	<<?CHECK_UP_MSG>> ->
	    ok = finish_send_response(<<?OK_MSG>>, Id, ReqId, Socket);
    <<?BCOUNTER_REQUEST,RequestBinary/binary>> ->
        ok = inter_dc_query_response:request_permissions(RequestBinary,QueryState#inter_dc_query_state{request_type=?BCOUNTER_REQUEST});
	%% TODO: Handle other types of requests
	_ ->
	    ErrorBinary = term_to_binary(bad_request),
	    ok = finish_send_response(<<?ERROR_MSG, ErrorBinary/binary>>, Id, ReqId, Socket)
    end,
    {noreply, State#state{next=getid}};
handle_info(Info, State) ->
    lager:info("got weird info ~p", [Info]),
    {noreply, State}.

handle_call(_Request, _From, State) -> {noreply, State}.
terminate(_Reason, State) -> erlzmq:close(State#state.socket).

handle_cast({send_response, BinaryResponse,
	     #inter_dc_query_state{request_type = ReqType, zmq_id = Id,
				   request_id_num_binary = ReqId}}, State=#state{socket = Socket}) ->
    finish_send_response(<<ReqType,BinaryResponse/binary>>, Id, ReqId, Socket),
    {noreply, State};

handle_cast(_Request, State) -> {noreply, State}.

code_change(_OldVsn, State, _Extra) -> {ok, State}.

%%%%%%%%%%%%%%%%%%%%%%%%%

-spec finish_send_response(<<_:8,_:_*8>>,binary(),binary(),erlzmq:erlzmq_socket()) -> ok.
finish_send_response(BinaryResponse, Id, ReqId, Socket) ->
    %% Must send a response in 3 parts with ZMQ
    %% 1st Id, 2nd empty binary, 3rd the binary message
    VersionBinary = ?MESSAGE_VERSION,
    Msg = <<VersionBinary/binary,ReqId/binary,BinaryResponse/binary>>,
    ok = erlzmq:send(Socket, Id, [sndmore]),
    ok = erlzmq:send(Socket, <<>>, [sndmore]),
    ok = erlzmq:send(Socket, Msg).


