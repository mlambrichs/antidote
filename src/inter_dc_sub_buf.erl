-module(inter_dc_sub_buf).
-include("antidote.hrl").
-include("inter_dc_repl.hrl").

-export([new_state/1, process/2]).

-record(state, {
  state_name :: normal | buffering,
  pdcid :: pdcid(),
  last_observed_opid :: non_neg_integer(),
  queue :: queue()
}).

new_state(PDCID) -> #state{
  state_name = normal,
  pdcid = PDCID,
  last_observed_opid = 0,
  queue = queue:new()
}.

process({txn, Txn}, State = #state{state_name = normal}) -> process_queue(push(Txn, State));
process({txn, Txn}, State = #state{state_name = buffering}) -> push(Txn, State);

process({log_reader_resp, Txns}, State = #state{queue = Queue, state_name = buffering}) ->
  ok = lists:foreach(fun deliver/1, Txns),
  NewLast = case Txns of
    [] ->
      case queue:peek(Queue) of
        empty -> State#state.last_observed_opid;
        {value, Txn} ->
          {Min, _} = Txn#interdc_txn.logid_range,
          Min - 1
      end;
    _ ->
      {_, Max} = (lists:last(Txns))#interdc_txn.logid_range,
      Max
  end,
  NewState = State#state{last_observed_opid = NewLast},
  process_queue(NewState).

process_queue(State = #state{queue = Queue, last_observed_opid = Last}) ->
  case queue:peek(Queue) of
    empty -> State#state{state_name = normal};
    {value, Txn} ->
      {Min, Max} = Txn#interdc_txn.logid_range,
      %% assert Max >= Min
      case Last + 1 >= Min of
        true ->
          deliver(Txn),
          process_queue(State#state{queue = queue:drop(Queue), last_observed_opid = Max});
        false ->
          inter_dc_log_reader_query:query(State#state.pdcid, State#state.last_observed_opid, Min),
          State#state{state_name = buffering}
      end
  end.

deliver(Txn) -> inter_dc_dep_vnode:handle_transaction(Txn).
push(Txn, State) -> State#state{queue = queue:in(Txn, State#state.queue)}.