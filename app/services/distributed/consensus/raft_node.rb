# frozen_string_literal: true

module Distributed
  module Consensus
    # Production-grade Raft consensus node implementation
    # Implements the Raft paper: https://raft.github.io/raft.pdf
    class RaftNode
      include Singleton

      # Node states per Raft specification
      module State
        FOLLOWER = :follower
        CANDIDATE = :candidate
        LEADER = :leader
      end

      # Timing configuration (milliseconds)
      ELECTION_TIMEOUT_MIN = 150
      ELECTION_TIMEOUT_MAX = 300
      HEARTBEAT_INTERVAL = 50
      RPC_TIMEOUT = 100

      attr_reader :node_id, :state, :current_term, :voted_for, :current_leader
      attr_reader :commit_index, :last_applied, :log

      def initialize
        @lock = Mutex.new
        @state = State::FOLLOWER
        @current_term = 0
        @voted_for = nil
        @current_leader = nil
        @commit_index = 0
        @last_applied = 0
        @log = []

        # Leader-specific state (reinitialized after election)
        @next_index = {}
        @match_index = {}

        # Callbacks
        @callbacks = {
          state_change: [],
          leader_elected: [],
          log_committed: [],
          membership_changed: []
        }

        # Timers
        @election_timer = nil
        @heartbeat_timer = nil
        @running = false

        # Configuration
        @node_id = nil
        @peers = []
        @storage = nil
        @rpc = nil
      end

      # Initialize the Raft node with configuration
      def configure(node_id:, peers:, storage:, rpc:)
        @lock.synchronize do
          @node_id = node_id
          @peers = peers
          @storage = storage
          @rpc = rpc

          # Restore persistent state
          restore_persistent_state

          Rails.logger.info("[Raft:#{@node_id}] Configured with peers: #{@peers.join(', ')}")
        end
      end

      # Start the Raft node
      def start
        return if @running

        @lock.synchronize do
          return if @running
          @running = true

          # Start as follower with election timeout
          become_follower(nil)
          reset_election_timer

          Rails.logger.info("[Raft:#{@node_id}] Started as #{@state}")
        end
      end

      # Stop the Raft node gracefully
      def stop
        return unless @running

        @lock.synchronize do
          @running = false
          cancel_election_timer
          cancel_heartbeat_timer

          Rails.logger.info("[Raft:#{@node_id}] Stopped")
        end
      end

      # Submit a command to the Raft cluster (leader only)
      def submit_command(command, timeout: 5000)
        @lock.synchronize do
          unless @state == State::LEADER
            return {
              success: false,
              error: 'not_leader',
              leader_hint: @current_leader
            }
          end

          # Append entry to local log
          entry = LogEntry.new(
            term: @current_term,
            index: @log.length + 1,
            command: command,
            timestamp: Time.now.to_i
          )

          @log << entry
          persist_log_entry(entry)

          Rails.logger.debug("[Raft:#{@node_id}] Appended entry index=#{entry.index} term=#{entry.term}")

          # Replicate to followers (non-blocking)
          replicate_entry_async(entry)

          {
            success: true,
            index: entry.index,
            term: entry.term
          }
        end
      end

      # Handle RequestVote RPC from candidate
      def handle_request_vote(term:, candidate_id:, last_log_index:, last_log_term:)
        @lock.synchronize do
          Rails.logger.debug("[Raft:#{@node_id}] RequestVote from #{candidate_id} term=#{term}")

          # Rule 1: Reply false if term < currentTerm
          if term < @current_term
            return { term: @current_term, vote_granted: false }
          end

          # If RPC request contains term > currentTerm, update term
          if term > @current_term
            become_follower(nil)
            update_term(term)
          end

          # Rule 2: If votedFor is null or candidateId, and candidate's log is
          # at least as up-to-date as receiver's log, grant vote
          vote_granted = false

          if (@voted_for.nil? || @voted_for == candidate_id) && log_up_to_date?(last_log_index, last_log_term)
            @voted_for = candidate_id
            persist_vote(@voted_for)
            vote_granted = true
            reset_election_timer

            Rails.logger.info("[Raft:#{@node_id}] Granted vote to #{candidate_id} for term #{term}")
          end

          { term: @current_term, vote_granted: vote_granted }
        end
      end

      # Handle AppendEntries RPC from leader (heartbeat or log replication)
      def handle_append_entries(term:, leader_id:, prev_log_index:, prev_log_term:, entries:, leader_commit:)
        @lock.synchronize do
          Rails.logger.debug("[Raft:#{@node_id}] AppendEntries from #{leader_id} term=#{term} entries=#{entries.length}")

          # Rule 1: Reply false if term < currentTerm
          if term < @current_term
            return { term: @current_term, success: false, match_index: 0 }
          end

          # Valid leader heartbeat/append - reset election timer
          reset_election_timer

          # If RPC request contains term >= currentTerm, recognize leader
          if term >= @current_term
            if term > @current_term
              update_term(term)
            end

            if @state != State::FOLLOWER || @current_leader != leader_id
              become_follower(leader_id)
            end
          end

          # Rule 2: Reply false if log doesn't contain entry at prevLogIndex
          # whose term matches prevLogTerm
          if prev_log_index > 0
            if prev_log_index > @log.length
              return { term: @current_term, success: false, match_index: @log.length }
            end

            prev_entry = @log[prev_log_index - 1]
            if prev_entry.term != prev_log_term
              # Rule 3: Delete conflicting entries and all that follow
              @log = @log[0...prev_log_index - 1]
              persist_log_truncation(prev_log_index - 1)
              return { term: @current_term, success: false, match_index: @log.length }
            end
          end

          # Rule 4: Append any new entries not already in the log
          entries.each_with_index do |entry, i|
            entry_index = prev_log_index + 1 + i

            if entry_index <= @log.length
              existing = @log[entry_index - 1]
              if existing.term != entry.term
                # Conflict - delete this and all following entries
                @log = @log[0...entry_index - 1]
                persist_log_truncation(entry_index - 1)
              else
                # Entry already exists and matches
                next
              end
            end

            @log << entry
            persist_log_entry(entry)
          end

          # Rule 5: If leaderCommit > commitIndex, update commitIndex
          if leader_commit > @commit_index
            @commit_index = [leader_commit, @log.length].min
            apply_committed_entries
          end

          { term: @current_term, success: true, match_index: @log.length }
        end
      end

      # Register callback for events
      def on(event, &block)
        return unless block_given? && @callbacks.key?(event)
        @callbacks[event] << block
      end

      # Check if this node is the leader
      def leader?
        @state == State::LEADER
      end

      # Get cluster status
      def cluster_status
        @lock.synchronize do
          {
            node_id: @node_id,
            state: @state,
            current_term: @current_term,
            voted_for: @voted_for,
            current_leader: @current_leader,
            log_length: @log.length,
            commit_index: @commit_index,
            last_applied: @last_applied,
            peers: @peers.dup,
            next_index: @next_index.dup,
            match_index: @match_index.dup
          }
        end
      end

      private

      # State transitions

      def become_follower(leader_id)
        old_state = @state
        @state = State::FOLLOWER
        @current_leader = leader_id

        cancel_heartbeat_timer

        if old_state != State::FOLLOWER
          Rails.logger.info("[Raft:#{@node_id}] Became FOLLOWER, leader=#{leader_id || 'unknown'}")
          fire_callback(:state_change, old_state, @state)
        end
      end

      def become_candidate
        old_state = @state
        @state = State::CANDIDATE
        @current_term += 1
        @voted_for = @node_id
        @current_leader = nil

        persist_term(@current_term)
        persist_vote(@voted_for)

        Rails.logger.info("[Raft:#{@node_id}] Became CANDIDATE for term #{@current_term}")
        fire_callback(:state_change, old_state, @state)

        # Start election
        start_election
      end

      def become_leader
        old_state = @state
        @state = State::LEADER
        @current_leader = @node_id

        # Initialize leader state
        @peers.each do |peer|
          @next_index[peer] = @log.length + 1
          @match_index[peer] = 0
        end

        Rails.logger.info("[Raft:#{@node_id}] Became LEADER for term #{@current_term}")
        fire_callback(:state_change, old_state, @state)
        fire_callback(:leader_elected, @node_id, @current_term)

        # Send immediate heartbeat to establish authority
        cancel_election_timer
        send_heartbeats
        start_heartbeat_timer
      end

      # Election

      def start_election
        Rails.logger.info("[Raft:#{@node_id}] Starting election for term #{@current_term}")

        # Vote for self
        votes_received = 1
        votes_needed = (@peers.length + 1) / 2 + 1

        # If single node cluster, become leader immediately
        if @peers.empty?
          become_leader
          return
        end

        # Request votes from all peers in parallel
        last_log_index = @log.length
        last_log_term = @log.empty? ? 0 : @log.last.term

        vote_responses = Concurrent::Hash.new
        latch = Concurrent::CountDownLatch.new(@peers.length)

        @peers.each do |peer|
          Thread.new do
            begin
              response = @rpc.request_vote(
                peer,
                term: @current_term,
                candidate_id: @node_id,
                last_log_index: last_log_index,
                last_log_term: last_log_term
              )
              vote_responses[peer] = response
            rescue => e
              Rails.logger.warn("[Raft:#{@node_id}] RequestVote to #{peer} failed: #{e.message}")
              vote_responses[peer] = { error: e.message }
            ensure
              latch.count_down
            end
          end
        end

        # Wait for responses with timeout
        latch.wait(RPC_TIMEOUT / 1000.0)

        # Process responses (still holding lock from become_candidate)
        @lock.synchronize do
          return unless @state == State::CANDIDATE && @running

          vote_responses.each do |peer, response|
            next if response[:error]

            # If response term > currentTerm, step down
            if response[:term] && response[:term] > @current_term
              update_term(response[:term])
              become_follower(nil)
              return
            end

            votes_received += 1 if response[:vote_granted]
          end

          Rails.logger.info("[Raft:#{@node_id}] Election result: #{votes_received}/#{votes_needed} votes")

          if votes_received >= votes_needed
            become_leader
          else
            # Election failed, wait for next timeout
            reset_election_timer
          end
        end
      end

      # Log replication

      def replicate_entry_async(entry)
        @peers.each do |peer|
          Thread.new do
            replicate_to_peer(peer)
          end
        end
      end

      def replicate_to_peer(peer)
        return unless @state == State::LEADER && @running

        begin
          prev_log_index = @next_index[peer] - 1
          prev_log_term = prev_log_index > 0 ? @log[prev_log_index - 1].term : 0

          # Get entries to send
          entries = @log[@next_index[peer] - 1..-1] || []

          response = @rpc.append_entries(
            peer,
            term: @current_term,
            leader_id: @node_id,
            prev_log_index: prev_log_index,
            prev_log_term: prev_log_term,
            entries: entries,
            leader_commit: @commit_index
          )

          @lock.synchronize do
            return unless @state == State::LEADER

            # If response term > currentTerm, step down
            if response[:term] && response[:term] > @current_term
              update_term(response[:term])
              become_follower(nil)
              return
            end

            if response[:success]
              @next_index[peer] = response[:match_index] + 1
              @match_index[peer] = response[:match_index]

              # Check if we can advance commit index
              advance_commit_index
            else
              # Decrement nextIndex and retry
              @next_index[peer] = [1, @next_index[peer] - 1].max
            end
          end
        rescue => e
          Rails.logger.warn("[Raft:#{@node_id}] Replication to #{peer} failed: #{e.message}")
        end
      end

      def advance_commit_index
        # Find the highest index replicated on majority of servers
        sorted_match = @match_index.values.sort.reverse
        # Add our own log length as we've stored it locally
        sorted_match.unshift(@log.length)

        majority_index = sorted_match[sorted_match.length / 2]

        # Only commit if entry is from current term (Raft safety property)
        if majority_index > @commit_index && @log[majority_index - 1].term == @current_term
          @commit_index = majority_index
          Rails.logger.info("[Raft:#{@node_id}] Advanced commit_index to #{@commit_index}")
          apply_committed_entries
        end
      end

      def apply_committed_entries
        while @last_applied < @commit_index
          @last_applied += 1
          entry = @log[@last_applied - 1]

          Rails.logger.info("[Raft:#{@node_id}] Applying entry #{@last_applied}: #{entry.command[:type]}")

          # Apply to state machine
          Distributed::Consensus::StateAdapter.instance.apply_command(
            command_type: entry.command[:type],
            payload: entry.command[:data],
            organization_id: entry.command[:organization_id]
          )

          fire_callback(:log_committed, entry)
        end
      end

      # Heartbeats

      def send_heartbeats
        @peers.each do |peer|
          Thread.new do
            send_heartbeat_to_peer(peer)
          end
        end
      end

      def send_heartbeat_to_peer(peer)
        return unless @state == State::LEADER && @running

        begin
          prev_log_index = @next_index[peer] - 1
          prev_log_term = prev_log_index > 0 ? @log[prev_log_index - 1].term : 0

          response = @rpc.append_entries(
            peer,
            term: @current_term,
            leader_id: @node_id,
            prev_log_index: prev_log_index,
            prev_log_term: prev_log_term,
            entries: [],
            leader_commit: @commit_index
          )

          @lock.synchronize do
            return unless @state == State::LEADER

            if response[:term] && response[:term] > @current_term
              update_term(response[:term])
              become_follower(nil)
            elsif !response[:success]
              @next_index[peer] = [1, @next_index[peer] - 1].max
            end
          end
        rescue => e
          Rails.logger.debug("[Raft:#{@node_id}] Heartbeat to #{peer} failed: #{e.message}")
        end
      end

      # Timers

      def reset_election_timer
        cancel_election_timer

        timeout_ms = rand(ELECTION_TIMEOUT_MIN..ELECTION_TIMEOUT_MAX)
        @election_timer = Thread.new do
          sleep(timeout_ms / 1000.0)

          @lock.synchronize do
            next unless @running && @state != State::LEADER

            Rails.logger.info("[Raft:#{@node_id}] Election timeout")
            become_candidate
          end
        end
      end

      def cancel_election_timer
        @election_timer&.kill
        @election_timer = nil
      end

      def start_heartbeat_timer
        cancel_heartbeat_timer

        @heartbeat_timer = Thread.new do
          while @running && @state == State::LEADER
            sleep(HEARTBEAT_INTERVAL / 1000.0)
            send_heartbeats
          end
        end
      end

      def cancel_heartbeat_timer
        @heartbeat_timer&.kill
        @heartbeat_timer = nil
      end

      # Persistence

      def restore_persistent_state
        return unless @storage

        state = @storage.load_state
        return unless state

        @current_term = state[:term] || 0
        @voted_for = state[:voted_for]
        @log = state[:log] || []
        @commit_index = state[:commit_index] || 0
        @last_applied = 0  # Will be rebuilt by replaying committed entries

        Rails.logger.info("[Raft:#{@node_id}] Restored state: term=#{@current_term} log_length=#{@log.length}")
      end

      def persist_term(term)
        @storage&.save_term(term)
      end

      def persist_vote(vote)
        @storage&.save_voted_for(vote)
      end

      def persist_log_entry(entry)
        @storage&.append_log_entry(entry)
      end

      def persist_log_truncation(last_index)
        @storage&.truncate_log(last_index)
      end

      def update_term(new_term)
        @current_term = new_term
        @voted_for = nil
        persist_term(@current_term)
        persist_vote(nil)
      end

      # Helpers

      def log_up_to_date?(candidate_last_index, candidate_last_term)
        return true if @log.empty?

        my_last_term = @log.last.term
        my_last_index = @log.length

        # Candidate is up-to-date if their last term is greater,
        # or if terms are equal and their log is at least as long
        if candidate_last_term > my_last_term
          true
        elsif candidate_last_term == my_last_term
          candidate_last_index >= my_last_index
        else
          false
        end
      end

      def fire_callback(event, *args)
        @callbacks[event].each do |callback|
          begin
            callback.call(*args)
          rescue => e
            Rails.logger.error("[Raft:#{@node_id}] Callback error for #{event}: #{e.message}")
          end
        end
      end

      # Log entry structure
      class LogEntry
        attr_reader :term, :index, :command, :timestamp

        def initialize(term:, index:, command:, timestamp:)
          @term = term
          @index = index
          @command = command
          @timestamp = timestamp
        end

        def to_h
          {
            term: @term,
            index: @index,
            command: @command,
            timestamp: @timestamp
          }
        end

        def self.from_h(hash)
          new(
            term: hash[:term],
            index: hash[:index],
            command: hash[:command],
            timestamp: hash[:timestamp]
          )
        end
      end
    end
  end
end
